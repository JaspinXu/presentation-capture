# NUS Presentation Capture Demo

An iPhone-first internal app for recording continuous presentation videos and uploading them reliably to an NUS Lab Linux server.

## Included in this demo

- Administrator-provisioned username/password sign-in
- Rear-camera recording in landscape orientation
- 720p default and optional 1080p recording
- Continuous MP4 recording with microphone audio (no pause, editing, filters, or beauty effects)
- Automatic copy to iPhone Photos
- Local recording library and playback
- Required experiment ID and participant ID metadata
- Optional title and notes
- 8 MiB multipart uploads with SHA-256 verification
- iOS background `URLSession` upload tasks
- Resume after network interruption or app restart
- Wi-Fi/mobile-data preference
- English and Simplified Chinese UI
- Docker-ready Linux upload server

## Project layout

```text
lib/                 Flutter application
ios/Runner/          iOS host and native background uploader
server/              Node.js multipart upload server
test/                Flutter tests
```

## Start the demo upload server

With Node.js 22 or later:

```bash
cd server
npm install
npm start
```

Or on Linux with Docker:

```bash
cd server
docker compose up --build
```

The demo credentials are:

```text
Account:  demo@nus.edu.sg
Password: demo1234
```

Uploaded videos are stored under `server/data/<video-id>/final.mp4`. Each directory also contains `metadata.json` and the uploaded parts.

For a physical iPhone, enter the server's LAN address on the login screen, for example `http://192.168.1.20:8080`. `localhost` on an iPhone refers to the iPhone itself.

## Run on iPhone

iOS builds require macOS with Xcode. On a Mac:

```bash
flutter pub get
open ios/Runner.xcworkspace
```

In Xcode:

1. Select the `Runner` target.
2. Choose an Apple development team under Signing & Capabilities.
3. Replace the bundle identifier if necessary.
4. Connect an iPhone running iOS 16 or later.
5. Build and run the `Runner` scheme.

The first recording requests Camera, Microphone, and Photos permissions. To test background transfer, record a video, start uploading, lock the phone, and verify the server's `parts` directory continues to receive files.

## Verification commands

```bash
flutter analyze
flutter test

cd server
npm test
```

The server test performs a complete login, multipart upload, resume-state query, assembly, and SHA-256 verification.

## Before an internal production deployment

The demo deliberately keeps infrastructure simple. Before serving thousands of users:

- Put the API behind a valid HTTPS certificate and remove the temporary arbitrary HTTP allowance from `Info.plist`.
- Replace the single environment-variable demo account with a real user database and password hashing.
- Store secrets outside `docker-compose.yml`.
- Add NUS authentication/SSO if required.
- Set storage quotas, retention, backups, monitoring, and disk-space alerts.
- Add rate limits and audit logs.
- Run long-duration tests on representative iPhone models.
- Configure TestFlight, MDM, or the NUS-approved internal distribution method.

## Current platform scope

Only the iOS host project is generated in this demo. The Flutter application logic is structured so an Android host and CameraX/background-upload implementation can be added later without rewriting the user flow.
