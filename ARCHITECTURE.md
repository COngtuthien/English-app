# Architecture – IELTS Vocabulary Master

## Overview
```
Flutter app (Dart, Material 3, Riverpod, GoRouter)
 ├─ lib/main.dart            BootstrapApp: in-app splash → opens DB → ProviderScope
 ├─ lib/app.dart             MaterialApp.router, theme, routes, bottom-nav shell
 ├─ lib/providers.dart       repositories/services/state providers
 ├─ lib/core/                theme tokens, shared widgets, Vietnamese text utils, dates
 ├─ lib/data/
 │   ├─ db/app_database.dart content DB (asset copy) + user DB (migrations) ATTACHed as schema `c`
 │   ├─ models/              plain Dart models
 │   ├─ repositories/        vocabulary, learning (FSRS), stats, achievements, settings
 │   └─ services/            backup/restore, offline TTS, local notifications
 ├─ lib/domain/
 │   ├─ srs/                 FSRS-6 wrapper (package:fsrs, MIT)
 │   └─ quiz/                quiz engine (9 question types + mixed), typed-answer checker
 └─ lib/features/            25 screens (see TASKS.md)
```

## Two databases
| File | Content | Lifetime |
|---|---|---|
| `vocab_v<N>.db` | Read-only vocabulary content copied from `assets/db/vocab.db` on first launch (or when `kContentVersion` changes) | Replaced by app updates |
| `user.db` | Learning cards, review history, quizzes, favourites, study queue, achievements, settings, daily activity | Never touched by content updates; backup/restore |

Entry ids are stable 48-bit hashes of `headword|pos`, so progress stays linked to the same words
after a content update. The user DB attaches the content DB (`ATTACH … AS c`) so queries can join
progress with vocabulary. Migrations: `userMigrations` map in `app_database.dart` (schema version 1).

### Content schema (normalised)
`vocabulary_entries` (headword, POS, CEFR + source, difficulty, frequency rank, IPA UK/US + source,
primary Vietnamese meaning + source, primary English definition + source, register, skills, usage
note, common mistake) → `vocabulary_senses` (numbered English senses, labels, aligned Vietnamese
meaning) · `translations` (all Vietnamese meanings with English context and source) · `examples`
(sentence/phrase, Vietnamese translation, highlighted form, source + reference) · `collocations` ·
`lexical_relations` (synonym/antonym/family/confusable, optional target id) · `topics` +
`vocabulary_topics` (with assignment method) · `source_provenance` · `writing_exercises` ·
`speaking_packs` · `search_index` (FTS4) · `meta`.

Indexes: `headword_norm`, `cefr`, `pos`, `(difficulty, freq_rank)`, `freq_rank`, child `entry_id`s.

### Search
1. English prefix: range scan on `headword_norm` (`>= q AND < q||'￿'`), exact match first.
2. Full text: FTS4 over headword variants, Vietnamese meanings normalised without diacritics
   (`stripVietnamese` in Dart ≡ `strip_vi` in Python) and English definitions; prefix tokens.
3. Fallback when FTS4 is unavailable: `LIKE` on the normalised `vi_norm` column.

## Spaced repetition
`package:fsrs` (official open-spaced-repetition Dart port, FSRS-6 default weights), desired
retention 0.9, learning steps 1 min/10 min, relearning 10 min, max interval 10 years, fuzzing on.
All timestamps are stored in UTC; the local calendar day (for streaks and daily goals) is derived
from the device time zone. A clock that moved backwards is clamped to the last review time.
Cards due again within 15 minutes are re-queued inside the current session (max 3 times).
"Mastered" = review state with stability ≥ 21 days. Retention estimate = mean FSRS
retrievability of all reviewed cards.

## State management
Riverpod 2: repositories as `Provider`s; screens read async data through `FutureProvider`s that
watch `dataVersionProvider`; every learning activity calls `afterLearningActivity()` which
re-evaluates achievements and bumps the version so the dashboard, lists and stats refresh.

## Offline guarantees
* No `INTERNET` permission in the release manifest (verified with `aapt dump permissions`).
* Fonts (Be Vietnam Pro) and all images are bundled; no `google_fonts` runtime fetching.
* TTS only uses voices the Android engine reports as `network_required = 0` and installed;
  otherwise the UI falls back to IPA/text.
* No analytics, crash reporting, ads or remote config dependencies.

## Data pipeline
```
data_sources/raw  ──extract_sources.py──▶ data_sources/work/*.jsonl
                  ──build_database.py───▶ assets/db/vocab.db + tools/data/out/build_stats.json
                  ──validate_database.py▶ tools/data/out/validation.json (fails build on errors)
```
