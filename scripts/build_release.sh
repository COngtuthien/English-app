#!/usr/bin/env bash
# Release pipeline for Linux/macOS (equivalent of build_release.ps1).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release tools/data/out
echo "[1/6] dependencies";        flutter pub get
echo "[2/6] vocabulary";          python3 -I tools/data/validate_database.py assets/db/vocab.db tools/data/out/validation.json
echo "[3/6] analyze";             flutter analyze
echo "[4/6] tests";               flutter test
echo "[5/6] build";               flutter build apk --release
APK=build/app/outputs/flutter-apk/app-release.apk
echo "[6/6] verify + copy"
unzip -l "$APK" | grep -q "assets/flutter_assets/assets/db/vocab.db"
BT=$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/* | grep -v rc | sort -V | tail -1)
"$BT/aapt" dump permissions "$APK" | grep -q "android.permission.INTERNET" && { echo "INTERNET permission found"; exit 1; } || true
"$BT/apksigner" verify --print-certs "$APK"
cp "$APK" release/IELTS_Vocabulary_Master.apk
(cd release && sha256sum IELTS_Vocabulary_Master.apk > SHA256.txt && cat SHA256.txt)
