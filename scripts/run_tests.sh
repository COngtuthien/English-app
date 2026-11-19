#!/usr/bin/env bash
# Runs analysis and all host tests; pass a device id to also run the integration test.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
flutter analyze
flutter test --reporter expanded
if [ "${1:-}" != "" ]; then flutter test integration_test/app_test.dart -d "$1"; fi
