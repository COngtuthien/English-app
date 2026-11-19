# Tasks & feature status

Status values: Not started · In progress · Implemented · Tested · Blocked
"Tested" = covered by an automated test that was actually executed and passed (see release/TEST_REPORT.md),
or verified on the Android emulator where stated.

| # | Feature / screen | Status | Evidence |
|---|---|---|---|
| 1 | Splash screen (native + in-app while DB is prepared) | Tested | integration test (device) |
| 2 | Onboarding | Tested | widget test, integration test |
| 3 | Goal configuration (name, level, band, daily words, topics) | Tested | widget test (persists) |
| 4 | Home dashboard (greeting, goal, due, studied, retention, streak, progress bar, 7-day chart, quick start, topics, milestone) | Tested | widget test + dashboard repo test |
| 5 | Topic browser (50 IELTS topics + 10 skill groups) | Tested | navigation widget test, DB test |
| 6 | Vocabulary list per topic (paging, status filter, sort) | Implemented | manual on emulator |
| 7 | Word detail (IPA UK/US, audio, VI meanings, EN senses, examples+VI, collocations, synonyms, antonyms, family, confusables, usage notes, mistakes, topics, status, favourite, add to study queue, sources) | Tested | widget test |
| 8 | Flashcards (EN→VI, VI→EN, definition→word, cloze; flip animation; Again/Hard/Good/Easy with interval preview; progress; transitions) | Tested | widget test, integration test |
| 9 | Review session (FSRS due cards, in-session relearning) | Tested | repo tests (due after interval) |
| 10 | Flashcard practice: random, topic, difficult, favourites | Implemented | shares tested session code |
| 11 | FSRS scheduling (state, steps, intervals, lapses, history, retention, UTC + local day, clock-skew guard) | Tested | srs_scheduler_test, learning tests |
| 12 | Quiz selection (types, 5/10/20/30/custom, topic) | Implemented | manual |
| 13 | Quiz gameplay – 9 types + mixed, feedback, explanation, definition | Tested | quiz engine tests (all types, unique answers), widget + integration tests |
| 14 | Quiz results + mistake review | Tested | widget test |
| 15 | Word matching game (timed/untimed, scoring, 3 difficulty levels, replay, summary) | Implemented | manual |
| 16 | Typing challenge (spelling, VI→EN recall, sentence completion, variants, typo feedback) | Tested (logic) | answer checker tests |
| 17 | Listening practice (identify word, meaning, type; speed; offline-voice detection + IPA fallback) | Implemented | manual (emulator voices vary) |
| 18 | IELTS Writing vocabulary (7 categories, 141 deterministic exercises) | Tested (data) | DB test validates every exercise |
| 19 | IELTS Speaking packs (Part 1/2/3, 24 packs, vocab, sample answers, tips, self-practice, favourite expressions) | Tested (data) | DB test |
| 20 | Favourites list | Tested | repo test |
| 21 | Difficult words / missed words / recently studied | Tested | repo test |
| 22 | Learning statistics (totals, mastered, pending, accuracy, streak, 30-day chart, ratings, topic mastery, quiz & review history) | Tested | stats repo test |
| 23 | Achievements (12, persisted) | Tested | achievement test |
| 24 | Study calendar (month heatmap, day details) | Implemented | manual |
| 25 | Settings (all preferences, theme, accent, speech rate, reminders, reset progress) | Tested | widget test (persistence) |
| 26 | Backup & restore (JSON, schema version, SHA-256, confirmation, transactional) | Tested | backup tests incl. corruption, integration test |
| 27 | About (sources, licences) | Implemented | manual |
| 28 | Dictionary search (EN prefix, VI accent-insensitive FTS, suggestions, family, topic, CEFR, POS, difficulty, favourites, sort, recent/missed links) | Tested | DB search tests, widget test |
| 29 | Daily reminder notifications | Implemented | not verifiable automatically (requires permission dialog) |
| 30 | Offline pronunciation (device TTS, offline voices only) | Implemented | depends on device voice data |
| 31 | Vocabulary database ≥ 10,000 validated entries | Tested | validate_database.py (0 errors), DB tests |
| 32 | Release APK build, signing, verification | Tested | see release/BUILD_REPORT.md |
| 33 | Scripts (setup/build/test/validate, .ps1 + .sh) & GitHub Actions workflow | Implemented | build_release.ps1 executed; CI file not executed |

## Not implemented (explicitly out of scope / honest limitations)
* Voice recording / pronunciation scoring in Speaking (no verified offline assessment engine).
* Open-ended essay grading (no offline evaluator).
* Bundled human audio recordings (licensed audio not bundled; device TTS used instead).
