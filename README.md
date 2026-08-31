# NUS Presentation Capture

An iPhone-first Flutter app for recording presentation videos as ordinary MP4 files with microphone audio and reliably uploading them to an NUS Lab Linux server.

This project borrows Stera's durable-session and reconciliation ideas, but deliberately does not include ARKit/ARCore, MCAP, pose, IMU, depth, point clouds, meshes, filters, or editing.

## Current feature set

- Rear-camera portrait or landscape recording with microphone audio and orientation fixed from the device position at recording start
- 720p, 1080p, and 4K presets (the camera plugin chooses the best supported format at or below the requested preset)
- Pause and resume within one MP4 recording
- App-private local storage; recordings are not copied to iPhone Photos
- Local review and playback
- Experiment ID, participant ID, optional title, and notes
- Lab account/password login for demo and development
- Google Sign-In as the only user-facing authentication method
- Required PPT, PPTX, or PDF selection for each uploaded recording
- Native iOS audio extraction to M4A without creating another full video copy
- Durable SQLite `upload_sessions` and `upload_parts` state
- Frozen 16 MiB multipart upload plan with a three-part staging window
- Native iOS background upload engine with SQLite/WAL journal, automatic sliding-window refill, server reconciliation, retry backoff, and SHA-256 checks
- Streaming server-side assembly so a large 4K upload is not loaded into memory during finalization
- English and Simplified Chinese UI

## Architecture

```text
Flutter camera (H.264/HEVC MP4 + microphone)
  -> app Documents/recordings/<video-id>.mp4
  -> app-private final.mp4 + audio.m4a + presentation.ppt/.pptx/.pdf
  -> SQLite videos + per-asset upload sessions and parts
  -> native iOS SQLite journal + at most 3 temporary 16 MiB chunks
  -> background URLSession with automatic window refill
  -> NUS Linux Express API
  -> per-asset parts/<part-number>
  -> streamed final.mp4, audio.m4a, and presentation assembly + SHA-256 verification
```

The server's completed-parts list is authoritative. After a restart or network interruption, the client compares local SQLite state, the native SQLite journal, active iOS tasks, and the server before scheduling missing parts again. While Flutter is suspended, Swift creates the next part only when a window slot becomes available and directly finalizes the upload after the last part. The app never prepares a second full copy of a 4K video.

## Run the server locally

Node.js 22 or later:

```powershell
cd G:\presentation-capture\server
npm install
npm start
```

Or with Docker:

```powershell
cd G:\presentation-capture\server
docker compose up --build
```

The password endpoint and these credentials are retained for automated server tests only; they are not shown in the app UI:

```text
Account:  demo@nus.edu.sg
Password: demo1234
```

For a physical iPhone, set the app's server URL to the computer's LAN address, such as `http://192.168.1.20:8080`. `localhost` on the phone means the phone itself.

## Google login configuration

Google Sign-In is the only user-facing authentication method. Its OAuth client IDs cannot be invented by the app and are not committed to the repository. The demo password endpoint remains server-side for automated development tests only.

1. Create an OAuth iOS client for the active bundle ID in Google Cloud Console. The current personal Debug ID is `com.jaspinxu.presentationcapture.dev`; the formal Release ID remains `sg.edu.nus.nusPresentationCapture`.
2. Copy `ios/Flutter/GoogleAuth.xcconfig.example` to `ios/Flutter/GoogleAuth.xcconfig` and fill the iOS client ID, backend/web client ID, and reversed iOS client ID. The real file is ignored by Git and is injected into `Info.plist` at build time.
3. Alternatively, build with Dart client IDs, but the reversed URL scheme must still be supplied to Xcode:

```bash
flutter run \
  --dart-define=GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_SERVER_CLIENT_ID
```

4. Set the server variable `GOOGLE_CLIENT_IDS` to the backend/web client ID and restart Docker. Google login cannot complete until both iOS and server configuration are present.

The server verifies Google ID-token signatures, issuer, expiry, and audience against Google's public keys before issuing its own 30-day signed session token.

## Server environment variables

```text
PORT=8080
DATA_DIR=/data
AUTH_SECRET=<long random secret>
GOOGLE_CLIENT_IDS=<comma-separated OAuth client IDs>
ENABLE_DEMO_LOGIN=true
DEMO_ACCOUNT=demo@nus.edu.sg
DEMO_PASSWORD=demo1234
DEMO_TOKEN=<development token>
```

For deployment, set `ENABLE_DEMO_LOGIN=false`, use HTTPS, and replace every default secret. Each completed bundle is written to `DATA_DIR/<video-id>/final.mp4`, `audio.m4a`, and `presentation.<ppt|pptx|pdf>`.

## Verification on this Windows computer

The bundled Flutter SDK is not on the global `PATH`, so use its explicit path:

```powershell
cd G:\presentation-capture
& 'G:\.codex-tools\flutter-sdk\bin\flutter.bat' pub get
& 'G:\.codex-tools\flutter-sdk\bin\flutter.bat' analyze
& 'G:\.codex-tools\flutter-sdk\bin\flutter.bat' test

cd G:\presentation-capture\server
npm test
```

The server test covers login, idempotent multipart initialization, per-part checksum validation, resume-state lookup, streamed assembly, and final SHA-256 verification.

## iPhone device validation

If this is your first Mac, follow the complete Chinese walkthrough: [MacBook 上从零运行 iOS 版](docs/MAC_IOS_SETUP_ZH.md). It covers Xcode, Flutter, VS Code, Simulator, Docker, Xcode's UI, hot reload, signing, and physical-iPhone validation.

Quick start after the Mac is configured:

```bash
flutter pub get
./tool/verify_macos.sh
open ios/Runner.xcworkspace
```

Select an Apple team and a real iPhone. Test all resolution choices because 4K availability, encoding format, thermal behavior, and storage consumption depend on the phone model. Also verify pause/resume audio continuity and lock/background upload behavior on device; simulators cannot validate these reliably.

## Production notes

- The current Linux server writes to one filesystem. Before thousands of users, decide storage quota, retention, backup, monitoring, and whether object storage is preferable.
- iOS deliberately stops relaunching background work after the user force-quits the app; reopening it reconciles and resumes the durable upload session. Normal screen locking, app switching, suspension, network loss, and process reclamation use the native background engine.
- Remove `NSAllowsArbitraryLoads` after the lab HTTPS endpoint is available.
- Perform long 4K recordings on the oldest supported iPhone and monitor heat, battery, free space, resulting bitrate, audio, and app termination recovery.
- Add rate limiting, audit logs, database-backed users/roles, and a retention policy before a broader internal rollout.

## Project layout

```text
lib/                 Flutter application and SQLite upload state machine
ios/Runner/          iOS host, entitlements, and background URLSession bridge
server/              Node.js/Express multipart upload server
test/                Flutter localization tests
```
