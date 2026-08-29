# NUS Presentation Capture

An iPhone-first Flutter app for recording presentation videos as ordinary MP4 files with microphone audio and reliably uploading them to an NUS Lab Linux server.

This project borrows Stera's durable-session and reconciliation ideas, but deliberately does not include ARKit/ARCore, MCAP, pose, IMU, depth, point clouds, meshes, filters, or editing.

## Current feature set

- Rear-camera landscape recording with microphone audio
- 720p, 1080p, and 4K presets (the camera plugin chooses the best supported format at or below the requested preset)
- Pause and resume within one MP4 recording
- App-private local storage; recordings are not copied to iPhone Photos
- Local review and playback
- Experiment ID, participant ID, optional title, and notes
- Lab account/password login for demo and development
- Configurable Sign in with Apple and Google Sign-In
- Durable SQLite `upload_sessions` and `upload_parts` state
- Frozen 16 MiB multipart upload plan with a three-part staging window
- Native iOS background upload engine with SQLite/WAL journal, automatic sliding-window refill, server reconciliation, retry backoff, and SHA-256 checks
- Streaming server-side assembly so a large 4K upload is not loaded into memory during finalization
- English and Simplified Chinese UI

## Architecture

```text
Flutter camera (H.264/HEVC MP4 + microphone)
  -> app Documents/recordings/<video-id>.mp4
  -> SQLite videos + upload_sessions + upload_parts
  -> native iOS SQLite journal + at most 3 temporary 16 MiB chunks
  -> background URLSession with automatic window refill
  -> NUS Linux Express API
  -> parts/<part-number>
  -> streamed final.mp4 assembly + whole-file SHA-256 verification
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

Demo credentials:

```text
Account:  demo@nus.edu.sg
Password: demo1234
```

For a physical iPhone, set the app's server URL to the computer's LAN address, such as `http://192.168.1.20:8080`. `localhost` on the phone means the phone itself.

## Apple and Google login configuration

Both social-login buttons are implemented, but provider credentials cannot be committed to the repository. Until the following configuration is supplied, the lab account/password path remains usable.

### Apple

1. Use the bundle ID `sg.edu.nus.nusPresentationCapture`, or replace it consistently with the lab's App ID.
2. Enable **Sign in with Apple** for that App ID in the Apple Developer portal.
3. Keep `Runner/Runner.entitlements` attached to all Runner build configurations.
4. Set the server variable `APPLE_CLIENT_IDS` to the allowed bundle ID(s), comma-separated.

### Google

1. Create an OAuth iOS client for the final bundle ID in Google Cloud Console.
2. Add its reversed client-ID URL scheme to the Runner target in Xcode. A downloaded `GoogleService-Info.plist` can be used for the same configuration, but do not commit secrets unintentionally.
3. Build with the IDs when the plist does not provide them:

```bash
flutter run \
  --dart-define=GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_SERVER_CLIENT_ID
```

4. Set the server variable `GOOGLE_CLIENT_IDS` to all accepted token audiences, comma-separated.

The server verifies Apple and Google ID-token signatures, issuer, expiry, and audience against the providers' remote public keys before issuing its own 30-day signed session token.

## Server environment variables

```text
PORT=8080
DATA_DIR=/data
AUTH_SECRET=<long random secret>
GOOGLE_CLIENT_IDS=<comma-separated OAuth client IDs>
APPLE_CLIENT_IDS=<comma-separated Apple bundle/service IDs>
ENABLE_DEMO_LOGIN=true
DEMO_ACCOUNT=demo@nus.edu.sg
DEMO_PASSWORD=demo1234
DEMO_TOKEN=<development token>
```

For deployment, set `ENABLE_DEMO_LOGIN=false`, use HTTPS, and replace every default secret. Uploaded files are written to `DATA_DIR/<video-id>/final.mp4` with metadata and parts beside them.

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
