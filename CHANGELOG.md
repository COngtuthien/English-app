# Changelog

All Android APKs are signed with the same release key
(certificate SHA-256 `e7f0e58a4854d365fecf97fff7d82bfaee4739a0b8d6a6ac466e440ebccdc2b2`),
so every version installs as an update over the previous one and keeps learning progress.

## [1.0.5] – 2026-11-19 · versionCode 6 · tag `v1.0.5`
### Added
- **iOS support** (iOS 14.0+): Xcode project (bundle id `com.ieltsvocabulary.master`), app icon and
  launch screen, local daily-reminder notifications, pronunciation audible with the silent switch on,
  backups visible in the Files app.
- GitHub Actions workflow **Build iOS**: unsigned release build + IPA artifact, integration test on an
  iPhone simulator.
- English README with screenshots.
### Fixed
- Android CI (failed at the SDK setup step since the first push) now builds and tests successfully.
- Topic page buttons ("Học chủ đề / Flashcard / Quiz") no longer wrap onto two lines.
- The next card no longer shows through behind a revealed (shorter) card.

APK `IELTS_Vocabulary_Master_v1.0.5.apk` – SHA-256 `865edf4eea36bb8131fa7a627cbca68a73fd86056bebd12f79df3fa059b22385`

## [1.0.4] – 2026-11-19 · versionCode 5 · tag `v1.0.4`
### Changed
- Flashcards: **swipe left = next card, swipe right = previous card**.
- Card-deck animation: the card follows the finger with a slight tilt and flies off with a light spin;
  the next card waits underneath and grows into place; short drags spring back.

APK `IELTS_Vocabulary_Master_v1.0.4.apk` – SHA-256 `f69026abf581efe38ae7f0477bd015d9db91dcf391d7a1702857943a4a778f2f`

## [1.0.3] – 2026-11-19 · versionCode 4 · tag `v1.0.3`
### Changed
- Flashcards: tap the card or "Hiện đáp án" to reveal; horizontal swipes move between cards.
- Swiping past a card does not grade it (shown as skipped in the summary); a graded card revisited
  cannot be graded twice; "Xem lại thẻ trước" on the summary screen.

APK `IELTS_Vocabulary_Master_v1.0.3.apk` – SHA-256 `88c966e153d8c999fb56d32d163feb10b96df5ca5352466707b0e96b2afeb6a7`

## [1.0.2] – 2026-11-19 · versionCode 3 · tag `v1.0.2`
### Added
- Choose the number of cards/questions before topic lessons, topic flashcards, topic quizzes,
  random flashcards, difficult-word and favourite reviews (presets, custom 1–200, or "Tất cả").
- Swipe the card to flip it (replaced in 1.0.3).

APK `IELTS_Vocabulary_Master_v1.0.2.apk` – SHA-256 `24b23abb058c6689879d2dab393ecdf87de0f782d70a7f7ba3aeb58eb988fafb`

## [1.0.1] – 2026-11-19 · versionCode 2 · tag `v1.0.1`
### Fixed
- Flashcards: grading always advances to the next card (a learning-step card could be re-queued
  directly after itself, so the same word appeared again); the UI no longer waits for the database.

APK `IELTS_Vocabulary_Master_flashcard_fix.apk` – SHA-256 `c6e7a8ffc8557453befaf43bf133ede6cc06cf0502e3d199c4279b8ecd01aa42`

## [1.0.0] – 2026-11-19 · versionCode 1 · tags `v1.0.0`, `v1.0.0-baseline`
- First offline Android release: 10,657 validated entries, FSRS spaced repetition, flashcards,
  9 quiz types, matching, typing, listening, Writing and Speaking practice, dictionary, statistics,
  achievements, backup/restore, dark mode.

APK `IELTS_Vocabulary_Master.apk` – SHA-256 `89f49bc453659dd6e458e7e5e189c62194d631f26111ea5e53462a26af16e414`

[1.0.5]: https://github.com/COngtuthien/English-app/releases/tag/v1.0.5
[1.0.4]: https://github.com/COngtuthien/English-app/releases/tag/v1.0.4
[1.0.3]: https://github.com/COngtuthien/English-app/releases/tag/v1.0.3
[1.0.2]: https://github.com/COngtuthien/English-app/releases/tag/v1.0.2
[1.0.1]: https://github.com/COngtuthien/English-app/releases/tag/v1.0.1
[1.0.0]: https://github.com/COngtuthien/English-app/releases/tag/v1.0.0
