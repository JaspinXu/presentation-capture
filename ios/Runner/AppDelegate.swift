import Flutter
import AVFoundation
import CryptoKit
import SQLite3
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var mediaChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    BackgroundUploadManager.shared.restoreSession()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    BackgroundUploadManager.shared.configure(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    mediaChannel = FlutterMethodChannel(
      name: "sg.edu.nus.presentation_capture/media_processing",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    mediaChannel?.setMethodCallHandler { call, result in
      guard call.method == "extractAudio",
            let arguments = call.arguments as? [String: Any],
            let videoPath = arguments["videoPath"] as? String,
            let outputPath = arguments["outputPath"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      Self.extractAudio(videoPath: videoPath, outputPath: outputPath, result: result)
    }
  }

  private static func extractAudio(
    videoPath: String,
    outputPath: String,
    result: @escaping FlutterResult
  ) {
    let source = URL(fileURLWithPath: videoPath)
    let destination = URL(fileURLWithPath: outputPath)
    try? FileManager.default.removeItem(at: destination)
    let asset = AVURLAsset(url: source)
    asset.loadTracks(withMediaType: .audio) { tracks, loadError in
      guard loadError == nil, let track = tracks?.first else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "audio_track_unavailable",
            message: loadError?.localizedDescription ?? "The recording has no audio track",
            details: nil
          ))
        }
        return
      }

      do {
        let reader = try AVAssetReader(asset: asset)
        let audioSettings: [String: Any] = [
          AVFormatIDKey: kAudioFormatLinearPCM,
          AVSampleRateKey: 48_000,
          AVNumberOfChannelsKey: 1,
          AVLinearPCMBitDepthKey: 16,
          AVLinearPCMIsBigEndianKey: false,
          AVLinearPCMIsFloatKey: false,
          AVLinearPCMIsNonInterleaved: false,
        ]
        let readerOutput = AVAssetReaderTrackOutput(
          track: track,
          outputSettings: audioSettings
        )
        guard reader.canAdd(readerOutput) else {
          throw MediaProcessingError.configuration("Cannot read the recording's audio track")
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .wav)
        let writerInput = AVAssetWriterInput(
          mediaType: .audio,
          outputSettings: audioSettings
        )
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
          throw MediaProcessingError.configuration("Cannot create a WAV audio file")
        }
        writer.add(writerInput)
        guard writer.startWriting(), reader.startReading() else {
          throw writer.error ?? reader.error ?? MediaProcessingError.configuration("Audio conversion could not start")
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "sg.edu.nus.presentation_capture.wav_export")
        var completed = false
        func finish(_ error: Error?) {
          guard !completed else { return }
          completed = true
          DispatchQueue.main.async {
            if let error {
              try? FileManager.default.removeItem(at: destination)
              result(FlutterError(
                code: "audio_export_failed",
                message: error.localizedDescription,
                details: nil
              ))
            } else {
              result(destination.path)
            }
          }
        }

        writerInput.requestMediaDataWhenReady(on: queue) {
          while writerInput.isReadyForMoreMediaData && !completed {
            if let sample = readerOutput.copyNextSampleBuffer() {
              if !writerInput.append(sample) {
                reader.cancelReading()
                writer.cancelWriting()
                finish(writer.error ?? MediaProcessingError.configuration("Could not write WAV audio"))
              }
              continue
            }

            writerInput.markAsFinished()
            if reader.status == .failed {
              writer.cancelWriting()
              finish(reader.error ?? MediaProcessingError.configuration("Could not decode recording audio"))
            } else {
              writer.finishWriting {
                finish(writer.status == .completed
                  ? nil
                  : writer.error ?? MediaProcessingError.configuration("Could not finish WAV audio"))
              }
            }
          }
        }
      } catch {
        DispatchQueue.main.async {
          try? FileManager.default.removeItem(at: destination)
          result(FlutterError(
            code: "audio_export_failed",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    BackgroundUploadManager.shared.backgroundCompletionHandler = completionHandler
  }
}

private enum MediaProcessingError: LocalizedError {
  case configuration(String)

  var errorDescription: String? {
    switch self {
    case .configuration(let message): message
    }
  }
}

private final class UploadJournal {
  private var database: OpaquePointer?
  private let lock = NSLock()
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init() {
    let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    try? FileManager.default.createDirectory(
      at: support,
      withIntermediateDirectories: true
    )
    let path = support.appendingPathComponent("background_upload.sqlite3").path
    guard sqlite3_open(path, &database) == SQLITE_OK else { return }
    execute("PRAGMA journal_mode=WAL")
    execute("PRAGMA synchronous=FULL")
    execute("""
      CREATE TABLE IF NOT EXISTS sessions(
        id TEXT PRIMARY KEY,
        source_path TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        part_size INTEGER NOT NULL,
        total_parts INTEGER NOT NULL,
        part_url_template TEXT NOT NULL,
        finalize_url TEXT NOT NULL,
        finalize_body TEXT NOT NULL,
        headers_json TEXT NOT NULL,
        allows_cellular INTEGER NOT NULL,
        finalize_attempts INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL,
        updated_at REAL NOT NULL
      )
    """)
    execute("""
      CREATE TABLE IF NOT EXISTS parts(
        session_id TEXT NOT NULL,
        part_number INTEGER NOT NULL,
        offset_bytes INTEGER NOT NULL,
        length_bytes INTEGER NOT NULL,
        state TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        temp_path TEXT,
        PRIMARY KEY(session_id, part_number)
      )
    """)
    execute("""
      CREATE TABLE IF NOT EXISTS events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payload_json TEXT NOT NULL,
        created_at REAL NOT NULL
      )
    """)
    // Version 3 uses one native session per asset: <video-id>:<asset-type>.
    // Stop legacy single-video sessions so they cannot retry obsolete endpoints.
    execute("UPDATE sessions SET state='failed' WHERE instr(id, ':')=0 AND state NOT IN ('completed', 'failed')")
  }

  deinit { sqlite3_close(database) }

  func upsertSession(_ values: [String: Any]) {
    execute(
      """
      INSERT INTO sessions(
        id, source_path, file_size, part_size, total_parts,
        part_url_template, finalize_url, finalize_body, headers_json,
        allows_cellular, state, updated_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'transferring', ?)
      ON CONFLICT(id) DO UPDATE SET
        source_path=excluded.source_path,
        file_size=excluded.file_size,
        part_size=excluded.part_size,
        total_parts=excluded.total_parts,
        part_url_template=excluded.part_url_template,
        finalize_url=excluded.finalize_url,
        finalize_body=excluded.finalize_body,
        headers_json=excluded.headers_json,
        allows_cellular=excluded.allows_cellular,
        state=CASE WHEN sessions.state IN ('completed', 'failed') THEN sessions.state ELSE 'transferring' END,
        updated_at=excluded.updated_at
      """,
      [
        values["sessionId"]!, values["sourcePath"]!, values["fileSize"]!,
        values["partSize"]!, values["totalParts"]!, values["partUrlTemplate"]!,
        values["finalizeUrl"]!, values["finalizeBody"]!, values["headersJson"]!,
        (values["allowsCellular"] as? Bool) == false ? 0 : 1,
        Date().timeIntervalSince1970,
      ]
    )
    let sessionId = values["sessionId"] as! String
    let fileSize = values["fileSize"] as! Int64
    let partSize = values["partSize"] as! Int64
    let totalParts = values["totalParts"] as! Int
    for number in 0..<totalParts {
      let offset = Int64(number) * partSize
      let length = min(partSize, fileSize - offset)
      execute(
        """
        INSERT OR IGNORE INTO parts(
          session_id, part_number, offset_bytes, length_bytes, state, attempts
        ) VALUES(?, ?, ?, ?, 'planned', 0)
        """,
        [sessionId, number, offset, length]
      )
    }
    if values["resetFailed"] as? Bool == true {
      execute(
        "UPDATE sessions SET state='transferring', finalize_attempts=0 WHERE id=? AND state!='completed'",
        [sessionId]
      )
      execute(
        "UPDATE parts SET state='planned', attempts=0, temp_path=NULL WHERE session_id=? AND state!='uploaded'",
        [sessionId]
      )
    }
  }

  func activeSessions() -> [[String: Any]] {
    query("SELECT * FROM sessions WHERE state IN ('transferring', 'finalizing')")
  }

  func session(_ id: String) -> [String: Any]? {
    query("SELECT * FROM sessions WHERE id=? LIMIT 1", [id]).first
  }

  func plannedParts(_ sessionId: String, limit: Int) -> [[String: Any]] {
    query(
      "SELECT * FROM parts WHERE session_id=? AND state='planned' AND attempts<15 ORDER BY part_number LIMIT ?",
      [sessionId, limit]
    )
  }

  func reclaimOrphans(_ sessionId: String, activeParts: Set<Int>) {
    let inflight = query(
      "SELECT part_number FROM parts WHERE session_id=? AND state='in_flight'",
      [sessionId]
    )
    for row in inflight {
      let number = row["part_number"] as! Int
      if !activeParts.contains(number) {
        execute(
          "UPDATE parts SET state='planned', temp_path=NULL WHERE session_id=? AND part_number=?",
          [sessionId, number]
        )
      }
    }
  }

  func markInFlight(_ sessionId: String, part: Int, tempPath: String) {
    execute(
      "UPDATE parts SET state='in_flight', attempts=attempts+1, temp_path=? WHERE session_id=? AND part_number=?",
      [tempPath, sessionId, part]
    )
  }

  func markUploaded(_ sessionId: String, part: Int) {
    execute(
      "UPDATE parts SET state='uploaded', temp_path=NULL WHERE session_id=? AND part_number=?",
      [sessionId, part]
    )
  }

  func markPlanned(_ sessionId: String, part: Int) {
    execute(
      "UPDATE parts SET state='planned', temp_path=NULL WHERE session_id=? AND part_number=?",
      [sessionId, part]
    )
  }

  func partAttempts(_ sessionId: String, part: Int) -> Int {
    query(
      "SELECT attempts FROM parts WHERE session_id=? AND part_number=? LIMIT 1",
      [sessionId, part]
    ).first?["attempts"] as? Int ?? 0
  }

  func uploadedCount(_ sessionId: String) -> Int {
    let row = query(
      "SELECT COUNT(*) AS count FROM parts WHERE session_id=? AND state='uploaded'",
      [sessionId]
    ).first
    return row?["count"] as? Int ?? 0
  }

  func setSessionState(_ sessionId: String, state: String) {
    execute(
      "UPDATE sessions SET state=?, updated_at=? WHERE id=?",
      [state, Date().timeIntervalSince1970, sessionId]
    )
  }

  func incrementFinalizeAttempts(_ sessionId: String) -> Int {
    execute(
      "UPDATE sessions SET finalize_attempts=finalize_attempts+1, updated_at=? WHERE id=?",
      [Date().timeIntervalSince1970, sessionId]
    )
    return query(
      "SELECT finalize_attempts FROM sessions WHERE id=? LIMIT 1",
      [sessionId]
    ).first?["finalize_attempts"] as? Int ?? 0
  }

  func appendEvent(_ event: [String: Any]) {
    guard
      JSONSerialization.isValidJSONObject(event),
      let data = try? JSONSerialization.data(withJSONObject: event),
      let json = String(data: data, encoding: .utf8)
    else { return }
    execute(
      "INSERT INTO events(payload_json, created_at) VALUES(?, ?)",
      [json, Date().timeIntervalSince1970]
    )
    execute(
      "DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT 1000)"
    )
  }

  func drainEvents() -> [[String: Any]] {
    let rows = query("SELECT id, payload_json FROM events ORDER BY id")
    var result: [[String: Any]] = []
    var ids: [Int] = []
    for row in rows {
      guard
        let id = row["id"] as? Int,
        let json = row["payload_json"] as? String,
        let data = json.data(using: .utf8),
        let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      ids.append(id)
      result.append(event)
    }
    if let maximum = ids.max() {
      execute("DELETE FROM events WHERE id<=?", [maximum])
    }
    return result
  }

  private func execute(_ sql: String, _ values: [Any] = []) {
    lock.lock()
    defer { lock.unlock() }
    guard let database else { return }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
    defer { sqlite3_finalize(statement) }
    bind(values, to: statement)
    sqlite3_step(statement)
  }

  private func query(_ sql: String, _ values: [Any] = []) -> [[String: Any]] {
    lock.lock()
    defer { lock.unlock() }
    guard let database else { return [] }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(statement) }
    bind(values, to: statement)
    var rows: [[String: Any]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      var row: [String: Any] = [:]
      for index in 0..<sqlite3_column_count(statement) {
        let name = String(cString: sqlite3_column_name(statement, index))
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
          row[name] = Int(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
          row[name] = sqlite3_column_double(statement, index)
        case SQLITE_TEXT:
          if let text = sqlite3_column_text(statement, index) {
            row[name] = String(cString: text)
          }
        default:
          break
        }
      }
      rows.append(row)
    }
    return rows
  }

  private func bind(_ values: [Any], to statement: OpaquePointer?) {
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      switch value {
      case let value as Int:
        sqlite3_bind_int64(statement, index, sqlite3_int64(value))
      case let value as Int64:
        sqlite3_bind_int64(statement, index, sqlite3_int64(value))
      case let value as Double:
        sqlite3_bind_double(statement, index, value)
      case let value as String:
        value.withCString {
          sqlite3_bind_text(statement, index, $0, -1, transient)
        }
      default:
        sqlite3_bind_null(statement, index)
      }
    }
  }
}

final class BackgroundUploadManager: NSObject, URLSessionTaskDelegate, URLSessionDelegate {
  static let shared = BackgroundUploadManager()
  private let identifier = "sg.edu.nus.presentation_capture.background_upload"
  private let journal = UploadJournal()
  private let workQueue = DispatchQueue(label: "sg.edu.nus.presentation_capture.upload_window")
  private let windowSize = 3
  private var channel: FlutterMethodChannel?
  var backgroundCompletionHandler: (() -> Void)?

  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = true
    configuration.httpMaximumConnectionsPerHost = 3
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  private override init() { super.init() }

  func restoreSession() {
    _ = session
    session.getAllTasks { tasks in
      for task in tasks {
        let sessionId = (task.taskDescription ?? "").split(separator: "#").first ?? ""
        if !sessionId.contains(":") { task.cancel() }
      }
      self.workQueue.async { self.fillAllWindows() }
    }
  }

  func configure(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "sg.edu.nus.presentation_capture/background_upload",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "startUploadSession":
        result(self.startUploadSession(arguments: call.arguments))
      case "scheduleUpload":
        result(self.scheduleLegacy(arguments: call.arguments))
      case "pendingEvents":
        result(self.journal.drainEvents())
      case "activeTaskIds":
        self.session.getAllTasks { tasks in
          result(tasks.compactMap { $0.taskDescription })
        }
      case "freeDiskBytes":
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        result(values?.volumeAvailableCapacityForImportantUsage)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startUploadSession(arguments: Any?) -> Bool {
    guard
      let arguments = arguments as? [String: Any],
      let sessionId = arguments["sessionId"] as? String,
      let sourcePath = arguments["sourcePath"] as? String,
      let fileSize = (arguments["fileSize"] as? NSNumber)?.int64Value,
      let partSize = (arguments["partSize"] as? NSNumber)?.int64Value,
      let totalParts = (arguments["totalParts"] as? NSNumber)?.intValue,
      let partUrlTemplate = arguments["partUrlTemplate"] as? String,
      let finalizeUrl = arguments["finalizeUrl"] as? String,
      let finalizeBody = arguments["finalizeBody"] as? String,
      let headers = arguments["headers"] as? [String: String],
      fileSize > 0, partSize > 0, totalParts > 0,
      let headersData = try? JSONSerialization.data(withJSONObject: headers),
      let headersJson = String(data: headersData, encoding: .utf8)
    else { return false }
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: sourcePath),
      let actualSize = attributes[.size] as? NSNumber,
      actualSize.int64Value == fileSize
    else { return false }

    journal.upsertSession([
      "sessionId": sessionId,
      "sourcePath": sourcePath,
      "fileSize": fileSize,
      "partSize": partSize,
      "totalParts": totalParts,
      "partUrlTemplate": partUrlTemplate,
      "finalizeUrl": finalizeUrl,
      "finalizeBody": finalizeBody,
      "headersJson": headersJson,
      "allowsCellular": arguments["allowsCellular"] as? Bool ?? true,
      "resetFailed": arguments["resetFailed"] as? Bool ?? false,
    ])
    workQueue.async { self.fillWindow(sessionId) }
    return true
  }

  private func fillAllWindows() {
    for session in journal.activeSessions() {
      if let id = session["id"] as? String { fillWindow(id) }
    }
  }

  private func fillWindow(_ sessionId: String) {
    session.getAllTasks { tasks in
      self.workQueue.async {
        guard let upload = self.journal.session(sessionId) else { return }
        guard upload["state"] as? String == "transferring" ||
                upload["state"] as? String == "finalizing"
        else { return }
        let activeDescriptions = Set(tasks.compactMap { $0.taskDescription })
        let prefix = "\(sessionId)#"
        let activeParts = Set(activeDescriptions.compactMap { description -> Int? in
          guard description.hasPrefix(prefix) else { return nil }
          return Int(description.dropFirst(prefix.count))
        })
        self.journal.reclaimOrphans(sessionId, activeParts: activeParts)
        let uploaded = self.journal.uploadedCount(sessionId)
        let total = upload["total_parts"] as! Int
        if uploaded == total {
          if !activeDescriptions.contains("\(sessionId)#finalize") {
            self.scheduleFinalization(upload)
          }
          return
        }
        let available = max(0, self.windowSize - activeParts.count)
        guard available > 0 else { return }
        for part in self.journal.plannedParts(sessionId, limit: available) {
          self.stageAndSchedule(upload: upload, part: part)
        }
      }
    }
  }

  private func stageAndSchedule(upload: [String: Any], part: [String: Any]) {
    let sessionId = upload["id"] as! String
    let partNumber = part["part_number"] as! Int
    let sourcePath = upload["source_path"] as! String
    let offset = UInt64(part["offset_bytes"] as! Int)
    let length = part["length_bytes"] as! Int
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let directory = support.appendingPathComponent("background_parts/\(sessionId)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = directory.appendingPathComponent("part_\(partNumber)")
    let data: Data
    do {
      let source = try FileHandle(forReadingFrom: URL(fileURLWithPath: sourcePath))
      try source.seek(toOffset: offset)
      data = try source.read(upToCount: length) ?? Data()
      try source.close()
      guard data.count == length else { throw CocoaError(.fileReadCorruptFile) }
      try data.write(to: temporary, options: .atomic)
    } catch {
      emit([
        "type": "completed", "taskId": "\(sessionId)#\(partNumber)",
        "statusCode": 0, "error": error.localizedDescription,
      ])
      workQueue.asyncAfter(deadline: .now() + 3) { self.fillWindow(sessionId) }
      return
    }

    let template = upload["part_url_template"] as! String
    guard let url = URL(string: template.replacingOccurrences(of: "__PART__", with: String(partNumber))) else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.allowsCellularAccess = (upload["allows_cellular"] as! Int) == 1
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    applyHeaders(upload, to: &request)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    request.setValue(digest, forHTTPHeaderField: "x-part-sha256")
    let task = session.uploadTask(with: request, fromFile: temporary)
    task.taskDescription = "\(sessionId)#\(partNumber)"
    journal.markInFlight(sessionId, part: partNumber, tempPath: temporary.path)
    task.resume()
  }

  private func scheduleFinalization(_ upload: [String: Any]) {
    let sessionId = upload["id"] as! String
    guard
      let url = URL(string: upload["finalize_url"] as! String),
      let data = (upload["finalize_body"] as! String).data(using: .utf8)
    else { return }
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let body = support.appendingPathComponent("background_parts/\(sessionId)_finalize.json")
    do { try data.write(to: body, options: .atomic) } catch { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allowsCellularAccess = (upload["allows_cellular"] as! Int) == 1
    applyHeaders(upload, to: &request)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let task = session.uploadTask(with: request, fromFile: body)
    task.taskDescription = "\(sessionId)#finalize"
    journal.setSessionState(sessionId, state: "finalizing")
    task.resume()
  }

  private func applyHeaders(_ upload: [String: Any], to request: inout URLRequest) {
    guard
      let json = upload["headers_json"] as? String,
      let data = json.data(using: .utf8),
      let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String]
    else { return }
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
  }

  private func scheduleLegacy(arguments: Any?) -> Bool {
    guard
      let arguments = arguments as? [String: Any],
      let taskId = arguments["taskId"] as? String,
      let filePath = arguments["filePath"] as? String,
      let urlString = arguments["url"] as? String,
      let url = URL(string: urlString),
      FileManager.default.fileExists(atPath: filePath)
    else { return false }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.allowsCellularAccess = arguments["allowsCellular"] as? Bool ?? true
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    if let headers = arguments["headers"] as? [String: String] {
      for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    }
    let task = session.uploadTask(with: request, fromFile: URL(fileURLWithPath: filePath))
    task.taskDescription = taskId
    task.resume()
    return true
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    guard totalBytesExpectedToSend > 0 else { return }
    let event: [String: Any] = [
      "type": "progress",
      "taskId": task.taskDescription ?? "",
      "progress": Double(totalBytesSent) / Double(totalBytesExpectedToSend),
    ]
    DispatchQueue.main.async {
      self.channel?.invokeMethod("uploadEvent", arguments: event)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    let description = task.taskDescription ?? ""
    let response = task.response as? HTTPURLResponse
    let statusCode = response?.statusCode ?? 0
    emit([
      "type": "completed", "taskId": description,
      "statusCode": statusCode, "error": error?.localizedDescription ?? "",
    ])
    guard let separator = description.lastIndex(of: "#") else { return }
    let sessionId = String(description[..<separator])
    let suffix = String(description[description.index(after: separator)...])
    workQueue.async {
      let success = error == nil && (200..<300).contains(statusCode)
      if suffix == "finalize" {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.removeItem(
          at: support.appendingPathComponent("background_parts/\(sessionId)_finalize.json")
        )
        self.journal.setSessionState(sessionId, state: success ? "completed" : "transferring")
        if !success {
          let attempts = self.journal.incrementFinalizeAttempts(sessionId)
          if attempts >= 8 {
            self.journal.setSessionState(sessionId, state: "failed")
          } else {
            let delay = min(300, 1 << min(attempts, 8))
            self.workQueue.asyncAfter(deadline: .now() + .seconds(delay)) {
              self.fillWindow(sessionId)
            }
          }
        }
        return
      }
      guard let partNumber = Int(suffix) else { return }
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      let staged = support.appendingPathComponent("background_parts/\(sessionId)/part_\(partNumber)")
      try? FileManager.default.removeItem(at: staged)
      if success {
        self.journal.markUploaded(sessionId, part: partNumber)
        self.fillWindow(sessionId)
      } else {
        self.journal.markPlanned(sessionId, part: partNumber)
        let attempts = self.journal.partAttempts(sessionId, part: partNumber)
        if attempts >= 15 {
          self.journal.setSessionState(sessionId, state: "failed")
        } else {
          let delay = min(300, 1 << min(attempts, 8))
          self.workQueue.asyncAfter(deadline: .now() + .seconds(delay)) {
            self.fillWindow(sessionId)
          }
        }
      }
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      self.backgroundCompletionHandler?()
      self.backgroundCompletionHandler = nil
    }
  }

  private func emit(_ event: [String: Any]) {
    journal.appendEvent(event)
    DispatchQueue.main.async {
      self.channel?.invokeMethod("uploadEvent", arguments: event)
    }
  }
}
