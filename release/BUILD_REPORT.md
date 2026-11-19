# Build report – IELTS Vocabulary Master 1.0.0 (build 1)

Built 2026-11-19 on Windows 11 (26H2), 16 logical CPUs, 13.7 GB RAM, with `scripts\build_release.ps1` (exit code 0).

## Artifact
| Item | Value |
|---|---|
| File | `release/IELTS_Vocabulary_Master.apk` |
| Size | **78,397,944 bytes (74.8 MiB)** |
| SHA-256 | `89f49bc453659dd6e458e7e5e189c62194d631f26111ea5e53462a26af16e414` (also in `SHA256.txt`) |
| Type | Universal release APK (arm64-v8a, armeabi-v7a, x86_64), R8-minified, resources shrunk |
| Package | `com.ieltsvocabulary.master` |
| Version | versionName 1.0.0, versionCode 1 |
| Label | IELTS Vocabulary Master |
| minSdk / targetSdk / compileSdk | 24 (Android 7.0) / 36 / 36 |
| Permissions | POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, VIBRATE (from the notifications plugin), app-private DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION. **No INTERNET permission** (checked by the build script with `aapt dump permissions`). |
| Signing | APK Signature Scheme v2 verified by `apksigner verify`; certificate `CN=IELTS Vocabulary Master, OU=Personal, O=IELTS Vocabulary Master, C=VN`, SHA-256 `e7f0e58a4854d365fecf97fff7d82bfaee4739a0b8d6a6ac466e440ebccdc2b2`, RSA 4096, valid 10,000 days |
| Embedded data | `assets/flutter_assets/assets/db/vocab.db` (33.0 MB, 10,657 entries), fonts, images – presence checked by the build script |

AAB: not built (optional; run `scripts\build_release.ps1 -Aab`).

## Toolchain (verified versions)
* Flutter 3.41.4 stable (Dart 3.11.1) at `C:\flutter`
* Eclipse Temurin JDK 21.0.13+9 (installed user-scoped to `%LOCALAPPDATA%\Programs\temurin`, archive SHA-256 verified against Adoptium; configured with `flutter config --jdk-dir`). The JDK 26 on PATH is too new for Gradle 8.14, and the Android Studio JBR reported by `flutter doctor` no longer exists on disk.
* Android SDK at `%LOCALAPPDATA%\Android\Sdk`: platform 36/36.1, build-tools 35.0.0/36.1.0, NDK 28.2.13676358 (auto-installed by Gradle under the accepted SDK licence), platform-tools 37
* Gradle 8.14 wrapper, Android Gradle Plugin 8.11.1, Kotlin 2.2.20
* `kotlin.incremental=false` (project on D:, pub cache on C: – Kotlin incremental caches fail across drives; warnings only)

## Pipeline steps executed (`scripts\build_release.ps1`)
1. Environment check ✔ 2. Tool validation ✔ 3. `flutter pub get` ✔ 4. Vocabulary validation (0 errors) ✔
5. `flutter analyze` – No issues ✔ 6. `flutter test` – 67 passed, 1 skipped ✔ 7. `flutter build apk --release` ✔
8. APK structure, permissions and signature verification ✔ 9. Copy to `release/` ✔ 10. SHA-256 ✔

## Device verification (Android emulator – no physical phone was connected)
AVD `IELTS_Test_API36`: Pixel 6 profile, Android 16 (API 36.1) Google Play x86_64 image, WHPX acceleration.
* The **exact release APK** above was installed with `adb install` (fresh install) **with airplane mode enabled**, launched,
  onboarding completed, 2 words learned through flashcards, the app force-stopped and relaunched → progress (2 words,
  streak 1, today's activity) persisted; Vietnamese accent-free dictionary search and word details worked offline.
  Screenshots: `release/screenshots/`.
* `integration_test/app_test.dart` passed on the same emulator (debug build): first launch, DB copy, FTS4 on Android's
  system SQLite, onboarding, learning, search, restart persistence, 5-question quiz, backup → wipe → restore.
* Emulator note: with the SwiftShader GPU mode the emulator process (qemu) itself crashed repeatedly (Windows APPCRASH
  0xc0000005 in qemu-system-x86_64.exe); with `-gpu host` it was stable. These were emulator crashes, not app crashes.

**Not verified:** installation on a physical phone; Android versions other than 16; actual TTS audio output (the emulator
image's offline voice availability was not asserted); notification delivery.

## Signing key – keep it safe
`android/keystore/ielts-release.jks` and `android/key.properties` (password) are **not** in `release/` and are git-ignored.
Back both up privately; any future update must be signed with the same key, otherwise Android refuses to install it over
this version (users would have to uninstall and lose data unless they restore a backup).
