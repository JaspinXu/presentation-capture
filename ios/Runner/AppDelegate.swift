import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    BackgroundUploadManager.shared.backgroundCompletionHandler = completionHandler
  }
}

final class BackgroundUploadManager: NSObject, URLSessionTaskDelegate, URLSessionDelegate {
  static let shared = BackgroundUploadManager()
  private let identifier = "sg.edu.nus.presentation_capture.background_upload"
  private var channel: FlutterMethodChannel?
  var backgroundCompletionHandler: (() -> Void)?

  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = true
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  private override init() { super.init() }

  func restoreSession() { _ = session }

  func configure(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "sg.edu.nus.presentation_capture/background_upload",
      binaryMessenger: messenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "scheduleUpload":
        result(self.schedule(arguments: call.arguments))
      case "pendingEvents":
        let events = UserDefaults.standard.array(forKey: "backgroundUploadEvents") ?? []
        UserDefaults.standard.removeObject(forKey: "backgroundUploadEvents")
        result(events)
      case "activeTaskIds":
        self.session.getAllTasks { tasks in
          result(tasks.compactMap { $0.taskDescription })
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func schedule(arguments: Any?) -> Bool {
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
    emit([
      "type": "progress",
      "taskId": task.taskDescription ?? "",
      "progress": Double(totalBytesSent) / Double(totalBytesExpectedToSend)
    ])
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    let response = task.response as? HTTPURLResponse
    emit([
      "type": "completed",
      "taskId": task.taskDescription ?? "",
      "statusCode": response?.statusCode ?? 0,
      "error": error?.localizedDescription ?? ""
    ])
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      self.backgroundCompletionHandler?()
      self.backgroundCompletionHandler = nil
    }
  }

  private func emit(_ event: [String: Any]) {
    var events = UserDefaults.standard.array(forKey: "backgroundUploadEvents") as? [[String: Any]] ?? []
    events.append(event)
    UserDefaults.standard.set(events, forKey: "backgroundUploadEvents")
    DispatchQueue.main.async { self.channel?.invokeMethod("uploadEvent", arguments: event) }
  }
}
