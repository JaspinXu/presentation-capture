# NUS Presentation Capture

A Flutter app for iPhone and Android that records presentation videos as ordinary MP4 files with microphone audio and reliably uploads them to an NUS Lab Linux server.

This project borrows Stera's durable-session and reconciliation ideas, but deliberately does not include ARKit/ARCore, MCAP, pose, IMU, depth, point clouds, meshes, filters, or editing.

## Current feature set

- Rear-camera landscape recording with microphone audio
- 720p, 1080p, and 4K presets (the camera plugin chooses the best supported format at or below the requested preset)
- Pause and resume within one MP4 recording
- App-private local storage; recordings are not copied to the system photo gallery
- Local review and playback
- Experiment ID, participant ID, optional title, and notes
- Lab account/password login for demo and development
- Configurable Sign in with Apple and Google Sign-In
- Durable SQLite `upload_sessions` and `upload_parts` state
- Frozen 16 MiB multipart upload plan with a three-part staging window
- Native iOS background upload engine with SQLite/WAL journal and background URLSession
- Native Android WorkManager foreground service with network constraints, streaming multipart reads, restart persistence, and upload notifications
- Streaming server-side assembly so a large 4K upload is not loaded into memory during finalization
- English and Simplified Chinese UI

## Architecture

```text
Flutter camera (H.264/HEVC MP4 + microphone)
  -> app Documents/recordings/<video-id>.mp4
  -> SQLite videos + upload_sessions + upload_parts
  -> iOS background URLSession OR Android WorkManager foreground service
  -> NUS Linux Express API
  -> parts/<part-number>
  -> streamed final.mp4 assembly + whole-file SHA-256 verification
```

The server's completed-parts list is authoritative. After a restart or network interruption, the client compares durable local state and server state before scheduling missing parts again. iOS stages at most three 16 MiB chunks. Android streams each chunk directly from the original MP4 through WorkManager, so neither platform prepares a second full copy of a 4K video.

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

The Android emulator defaults to `http://10.0.2.2:8080`, Android's special address for the Windows host.

## Apple and Google login configuration

Both social-login buttons are implemented, but provider credentials cannot be committed to the repository. Until the following configuration is supplied, the lab account/password path remains usable.

### Apple

1. Use the bundle ID `sg.edu.nus.nusPresentationCapture`, or replace it consistently with the lab's App ID.
2. Enable **Sign in with Apple** for that App ID in the Apple Developer portal.
3. Keep `Runner/Runner.entitlements` attached to all Runner build configurations.
4. Set the server variable `APPLE_CLIENT_IDS` to the allowed bundle ID(s), comma-separated.

For Android, also create an Apple Services ID and HTTPS return URL, then run with:

```powershell
flutter run --dart-define=APPLE_SERVICE_ID=YOUR_SERVICE_ID `
  --dart-define=APPLE_REDIRECT_URI=https://YOUR_SERVER/auth/apple/callback
```

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

For Android, create an Android OAuth client for package `sg.edu.nus.nus_presentation_capture` and the SHA-1/SHA-256 fingerprints of the signing certificate. Pass the OAuth web client as `GOOGLE_SERVER_CLIENT_ID`. The demo account remains available before these external credentials are configured.

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

## Automated verification on Windows

The bundled Flutter SDK is not on the global `PATH`, so use its explicit path:

```powershell
cd G:\presentation-capture
& .\tool\verify_windows.ps1

# Also compile an APK after Android Studio/SDK is installed:
& .\tool\verify_windows.ps1 -BuildApk
```

The server test covers login, idempotent multipart initialization, per-part checksum validation, resume-state lookup, streamed assembly, and final SHA-256 verification.

## Android Studio UI validation on Windows

### One-time setup

1. Install Android Studio. In **Settings > Android SDK**, place the SDK on `G:\Android\Sdk` if you want to avoid using C:.
2. Install Android SDK Platform 37, Android SDK Build-Tools, Platform-Tools, Command-line Tools, and Android Emulator.
3. In **Device Manager**, create a Pixel 7/8 emulator using API 35 or newer. Enable a virtual-scene camera or webcam. The app compiles against SDK 37 but still runs on older supported Android versions.
4. To keep emulator images on G:, set the user environment variable `ANDROID_AVD_HOME=G:\Android\avd` before creating the emulator.
5. Configure Flutter and accept Android licences:

```powershell
& 'G:\flutter-sdk\bin\flutter.bat' config --android-sdk 'G:\Android\Sdk'
& 'G:\flutter-sdk\bin\flutter.bat' doctor --android-licenses
& 'G:\flutter-sdk\bin\flutter.bat' doctor -v
```

### Start the interactive demo

Open terminal 1 and start the upload server:

```powershell
cd G:\presentation-capture\server
docker compose up --build
```

Start the Pixel emulator from Android Studio. In terminal 2:

```powershell
cd G:\presentation-capture
& 'G:\flutter-sdk\bin\flutter.bat' devices
& 'G:\flutter-sdk\bin\flutter.bat' run
```

Flutter will install the debug app and open it in the emulator. Log in with `demo@nus.edu.sg` / `demo1234`; the default server URL is already correct for the emulator.

### UI acceptance checklist

1. Switch between English and 中文 on the login screen, then log in.
2. Open Settings, select 720p, 1080p, and 4K in turn, and verify the mobile-data switch persists.
3. Tap **Record presentation**, grant camera/microphone permission, rotate to landscape, and record with audio.
4. Pause for several seconds, resume, then stop. Play the preview and confirm the paused interval is absent while audio remains synchronized.
5. Enter Experiment ID and Participant ID, tap **Save and upload**, and allow upload notifications.
6. Put the app in the background. Confirm an Android upload notification appears, then reopen the app and confirm the status becomes **Uploaded**.
7. Inspect `G:\presentation-capture\server\data\<video-id>\final.mp4` and play it on Windows.
8. For resume testing, stop Docker during an upload, restart it, and confirm WorkManager retries and completes without recording again.

The emulator validates layout, navigation, form validation, pause/resume flow, API integration, and upload state. It cannot prove a phone's real 4K encoder, microphone quality, thermal limits, or manufacturer-specific background restrictions. Run those final checks on at least one physical Android phone that supports 4K.

### Physical Android phone

Enable Developer options and USB debugging, connect the phone, then either set the app server URL to the PC's LAN IP or use ADB forwarding:

```powershell
& 'G:\Android\Sdk\platform-tools\adb.exe' reverse tcp:8080 tcp:8080
& 'G:\flutter-sdk\bin\flutter.bat' run
```

With ADB forwarding, change the server URL in the app to `http://localhost:8080`. Windows Firewall must allow port 8080 when using the LAN-IP method.

## iPhone device validation

iOS compilation and real camera validation still require macOS/Xcode, either a borrowed Mac or a CI/macOS cloud runner. On the Mac:

```bash
flutter pub get
open ios/Runner.xcworkspace
```

Select an Apple team and a real iPhone. Test all resolution choices because 4K availability, encoding format, thermal behavior, and storage consumption depend on the phone model. Also verify pause/resume audio continuity and lock/background upload behavior on device; simulators cannot validate these reliably.

## Production notes

- The current Linux server writes to one filesystem. Before thousands of users, decide storage quota, retention, backup, monitoring, and whether object storage is preferable.
- iOS deliberately stops relaunching background work after the user force-quits the app; reopening it reconciles and resumes the durable upload session. Normal screen locking, app switching, suspension, network loss, and process reclamation use the native background engine.
- Remove `NSAllowsArbitraryLoads` after the lab HTTPS endpoint is available.
- Disable Android cleartext traffic after the lab HTTPS endpoint is available.
- Perform long 4K recordings on the oldest supported iPhone and monitor heat, battery, free space, resulting bitrate, audio, and app termination recovery.
- Add rate limiting, audit logs, database-backed users/roles, and a retention policy before a broader internal rollout.

## Project layout

```text
lib/                 Flutter application and SQLite upload state machine
ios/Runner/          iOS host, entitlements, and background URLSession bridge
android/app/         Android host, permissions, and WorkManager upload worker
server/              Node.js/Express multipart upload server
test/                Flutter model, localization, and widget/UI tests
tool/                Windows verification helpers
```
