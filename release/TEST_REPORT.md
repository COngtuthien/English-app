# Test report – IELTS Vocabulary Master 1.0.0

All results below come from commands actually executed on 2026-11-19. Raw host-test output: `release/test_output.txt`.

## Static checks
| Command | Result |
|---|---|
| `dart format lib test integration_test` (page width 140) | 51 files, 0 changes on final run |
| `flutter analyze` | **No issues found** |
| `python tools/data/validate_database.py` | **PASSED** – 0 errors across 13 checks (see VOCABULARY_REPORT.md) |

## Host tests – `flutter test` → **67 passed, 1 skipped, 0 failed**
Run against the real bundled `assets/db/vocab.db` via sqflite_common_ffi.

| Suite | Tests | Covers |
|---|---|---|
| `test/unit/text_and_answers_test.dart` | 19 | Vietnamese normalisation & FTS query building, typed-answer checking (case, UK/US variants, hyphens, near-miss typos), Levenshtein, cloze blanking, streaks (incl. month boundary), longest streak, settings serialisation & corrupt-value fallback |
| `test/unit/srs_scheduler_test.dart` | 8 | FSRS learning steps, graduation, growing intervals, lapse → relearning, clock moved backwards, interval preview ordering, retrievability decay, interval formatting |
| `test/db/database_test.dart` | 22 (1 skipped) | seed DB version & ≥10,000 entries, minimum quality bar for every entry, foreign keys & unique keys, no placeholder headwords, 50 topics populated, licensed sources, EN prefix search, VI search with/without diacritics, VI phrase ranking, FTS (skipped – see below), CEFR/POS/topic filters & pagination, alphabetical sort, word family, suggestions, search speed, word details, writing exercises integrity, speaking packs, user schema/migration, transaction rollback, persistence across reopen |
| `test/db/learning_and_backup_test.dart` | 12 | learning a word (card + history + daily activity), due reviews after interval, study queue & favourites, B2 queue excludes function words, level/topic steering, difficult & missed words, dashboard/full statistics, achievements unlock once, backup round trip into a fresh DB, rejection of tampered/foreign/future-version/non-JSON backups without data change, quiz engine: all 9 types with exactly one valid answer, 20-question mixed quiz with no repeats, topic quiz scope |
| `test/widget/app_widgets_test.dart` | 8 | onboarding → goal setup → dashboard (persisted), home dashboard, dictionary search → word detail, flashcard flip/rate/persist, quiz gameplay → results persisted, quiz result mistake review, settings persistence (theme), bottom navigation to every tab |

**Skipped (1):** "FTS index answers queries" – the SQLite library bundled with sqflite_common_ffi on Windows is compiled
without the FTS4 module, so the test verifies the LIKE fallback instead and marks itself skipped. FTS4 itself was verified
on Android by the integration test.

## Integration test (Android emulator, API 36.1) – `flutter test integration_test/app_test.dart -d emulator-5554` → **1 passed**
Steps: first launch & content DB copy from APK → ≥10,000 entries → FTS4 `MATCH` on Android system SQLite →
onboarding → learn a word through the flashcard UI → Vietnamese search → app restart → progress & settings persisted →
5-question quiz → result saved → backup export → wipe → restore → progress restored.

## Manual verification of the release APK (emulator, airplane mode)
Fresh install of `release/IELTS_Vocabulary_Master.apk`, onboarding, home, 2 flashcards rated, force-stop + relaunch
(progress kept), dictionary search "moi truong", word detail. Screenshots in `release/screenshots/`.

## Bugs found by testing and fixed
* Home "Hoạt động 7 ngày" header overflowed on narrow widths/large fonts (widget test) → flexible layout.
* Topic chip labels invisible on Android (seen on device screenshot) → removed colourless chip label style.
* `setState()` after dispose when leaving the dictionary during the search debounce (integration test) → `mounted` guards
  (also added to typing, listening, writing and matching loaders).
* Vietnamese multi-word search ranked unrelated words first (device check) → FTS phrase query + relevance ordering.
* New-word queue started with function words such as "that" (adv.) (device check) → excluded function words and words
  already known at a much lower level.
* Re-opening the singleton DB connection could re-ATTACH the content DB → idempotent attach.

## Not covered by automated tests
Matching game, typing/listening screens' UI flows, calendar, notifications (OS permission dialog), real audio output, file
picker dialogs for backup (service logic is tested), behaviour on physical devices and other Android versions.
