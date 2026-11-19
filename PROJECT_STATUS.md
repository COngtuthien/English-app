# Project status – IELTS Vocabulary Master

_Last updated: 2026-11-19_

## Summary
| Area | Status |
|---|---|
| Development environment | Ready: Flutter 3.41.4 (C:\flutter), Temurin JDK 21 (user-scoped), Android SDK 36, build-tools 35/36, NDK 28.2, emulator AVD `IELTS_Test_API36` |
| Vocabulary database | **10,657 validated entries**, validation PASSED (0 errors) – see release/VOCABULARY_REPORT.md |
| App features (25 screens) | Implemented – see TASKS.md for per-feature status and evidence |
| Automated tests | 67 passed, 1 skipped (host SQLite lacks FTS4; fallback verified) + integration test passed on emulator – see release/TEST_REPORT.md |
| Release APK | **Built & verified**: release/IELTS_Vocabulary_Master.apk, 78,397,944 bytes, SHA-256 89f49bc4…e414, signed (v2) with local release key |
| Device verification | Release APK installed & used offline (airplane mode) on Android 16 emulator; no physical phone available |

## GitHub Releases (published 2026-11-19)
* v1.0.0–v1.0.5 published on GitHub Releases with `IELTS_Vocabulary_Master_<tag>.apk` + `.sha256`;
  v1.0.5 is *Latest*. Every asset was re-downloaded anonymously and hash-checked.
* Process for future releases: RELEASING.md + `scripts/publish_release.ps1` (needs `gh auth login`).

## v1.0.5 (main) – iOS support
* `ios/` Runner project: bundle id `com.ieltsvocabulary.master`, iOS 14.0+ (required by
  file_picker_darwin), portrait, display name "IELTS Vocab", Files-app access for backups,
  icon + launch screen generated from the existing artwork, explicit Podfile.
* Notifications initialised for iOS (Darwin settings, permission on demand, AppDelegate delegate);
  TTS uses a playback audio session on iOS (audible with the silent switch on).
* CI: new `Build iOS` workflow (macOS) – unsigned release build + IPA artifact, integration test
  on an iPhone simulator. The Android workflow, which had been failing at `setup-android` since the
  first push, now passes.
* Topic header buttons no longer wrap; the card under the top card is hidden at rest.
* README rewritten in English with screenshots (`docs/screenshots/`).
* Android APK: `release/IELTS_Vocabulary_Master_v1.0.5.apk` (versionCode 6, same signing key).
* iOS cannot be built on this Windows machine; it is built and tested by GitHub Actions on macOS.
* Data note: the entry "project" (verb) mixes senses (Vietnamese "suy bụng ta ra bụng người",
  definition "To extend beyond a surface", noun example) – needs curation.

## v1.0.4
* Swipe direction corrected: swipe LEFT = next card, swipe RIGHT = previous card.
* Card-deck animation: the top card follows the finger with a slight tilt (pivot below the card),
  flies off with a light spin when released past ~22% of the width (or a fast fling); the next /
  previous card waits underneath and grows into place; short drags spring back (elastic); the first
  card rubber-bands to the right. Grading uses the same fly-off; the session advances immediately.
* APK: `release/IELTS_Vocabulary_Master_v1.0.4.apk` (versionCode 5, same signing key).

## v1.0.3
* Flashcards: tap the card or "Hiện đáp án" to show the answer; swipe = navigate (direction swapped
  in 1.0.4; vertical drags scroll). Swiping past a card does not grade it (counted as skipped);
  a revisited graded card shows "Đã chấm" and cannot be graded twice; summary has "Xem lại thẻ trước".
* APK: `release/IELTS_Vocabulary_Master_v1.0.3.apk` (versionCode 4, same signing key).

## v1.0.2
* (superseded) swipe in any direction flipped the card.
* Choose the number of cards/questions before: topic "Học chủ đề", topic Flashcard, topic Quiz,
  random flashcards, difficult-word review, favourites review (5/10/15/20/30/50, custom 1–200, or "Tất cả").
* APK: `release/IELTS_Vocabulary_Master_v1.0.2.apk` (versionCode 3, same signing key).

## Flashcard navigation fix – `fix/flashcard-next-navigation` (merged into main with v1.0.2)
* Version 1.0.1+2, APK `release/IELTS_Vocabulary_Master_flashcard_fix.apk` (same signing key as 1.0.0).
* Root cause: in-session requeue of learning-step cards inserted the card right after itself when
  ≤3 cards remained (always for 1-card sessions and at the end of every session), so grading showed
  the same word again; plus the UI only advanced after DB write + achievement queries finished.
* Fix: `FlashcardSession` controller (pure Dart, unit-tested) – immediate advance, card always
  face-down, never the same card twice in a row, duplicate-grade guard; background ordered save chain;
  outgoing card ignores taps; instruction "Chọn mức độ ghi nhớ để chuyển sang từ tiếp theo."
* Baseline is preserved: tag `v1.0.0-baseline` (commit d76af7f) on GitHub, original APK unchanged.

## How to resume
1. `scripts\setup_environment.ps1` (idempotent) – checks/installs toolchain and the signing key.
2. `scripts\run_tests.ps1 -Device emulator-5554` – analysis, host tests, integration test.
3. `scripts\build_release.ps1` – produces release/IELTS_Vocabulary_Master.apk + SHA256.txt.
4. Data changes: edit `tools/data/curated/*.json` → `scripts\validate_vocabulary.ps1 -Rebuild`
   (bump `CONTENT_VERSION` in build_database.py **and** `kContentVersion` in lib/data/db/app_database.dart).

## Next steps (optional improvements)
* Extend curated Vietnamese meanings for more B2–C1 words whose open-source first gloss is weak.
* More example sentences with Vietnamese translations (currently 42.7% of entries).
* Grow thin IELTS topics (Globalization, Migration, Population, Urbanization) with more curated seeds.
* Bundle licensed human pronunciation audio (currently device TTS only).
