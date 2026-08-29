#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter was not found on PATH. Add ~/Developer/flutter/bin to ~/.zshrc first." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode command-line tools were not found. Install and open Xcode first." >&2
  exit 1
fi

echo "== Flutter environment =="
flutter --version
flutter doctor -v

echo "== Dependencies =="
flutter pub get

echo "== Static analysis =="
flutter analyze

echo "== Flutter tests =="
flutter test

echo "== iOS Simulator compilation =="
flutter build ios --simulator --debug --no-codesign

echo "All macOS/iOS checks passed. Start Simulator with: open -a Simulator"
echo "Then run the app with: flutter run"
