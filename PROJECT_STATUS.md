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

## v1.0.2 (merged into main)
* Swipe the flashcard left/right/up/down to flip it (tap still works).
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
