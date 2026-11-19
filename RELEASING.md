# Release process

This document describes how changes reach `main` and how a version is published.
APK binaries are distributed through **GitHub Releases**, never committed to Git history.

## Rules

1. `main` always contains the latest stable, tested source code. Nobody commits directly to `main`.
2. Every change is developed on its own branch:
   `feat/<short-name>`, `fix/<short-name>`, `chore/<short-name>` or `docs/<short-name>`.
3. A branch is merged into `main` **only after** the tests pass and the owner has approved the change.
4. Existing history and tags are never rewritten: no force-push to `main`, and no moving or
   deleting tags (`v1.0.0` … `v1.0.5`, `v1.0.0-baseline`).
5. Signing keys, passwords and credentials are never committed. `android/key.properties`,
   `android/keystore/`, `*.jks`, `*.keystore`, `*.p12`, `.env` are git-ignored; keep an offline
   backup of the keystore, because it is the only key that can update installed apps.
6. A Release is only announced (README link, messages) **after** it has been published and its
   download links have been verified.

## Development flow

```powershell
git switch main
git pull --ff-only
git switch -c fix/<short-name>

# … make the change …
flutter analyze
flutter test
flutter test integration_test/app_test.dart -d <device>   # for UI / data changes

git push -u origin fix/<short-name>
```

After approval, merge with a fast-forward or merge commit (no history rewrite):

```powershell
git switch main
git pull --ff-only
git merge --ff-only fix/<short-name>     # or: git merge --no-ff fix/<short-name>
git push origin main
```

## Publishing an approved release

Prerequisites: the release keystore (`android/key.properties` + `android/keystore/`), and the
GitHub CLI authenticated once with `gh auth login`.

1. **Version**: on the release branch, bump `version:` in `pubspec.yaml` (e.g. `1.0.6+7`: the
   name *and* the build number) and the version strings in `lib/data/services/backup_service.dart`
   and `lib/features/about/about_screen.dart`.
2. **Changelog**: add a `## [1.0.6] – YYYY-MM-DD · versionCode 7 · tag v1.0.6` section to
   `CHANGELOG.md` (the Release notes are taken from it) and a link line at the bottom.
3. **Build and verify** (validate data → analyze → test → build → signature check → SHA-256):
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -ApkName IELTS_Vocabulary_Master_v1.0.6.apk
   ```
4. **Merge** the verified branch into `main` (after approval) and push.
5. **Tag** the merged commit and push the tag (annotated; never reuse an existing tag):
   ```powershell
   git tag -a v1.0.6 -m "IELTS Vocabulary Master 1.0.6 (versionCode 7)"
   git push origin v1.0.6
   ```
6. **Publish** the Release and update the README download link:
   ```powershell
   scripts\publish_release.ps1 -Tag v1.0.6 -Latest -UpdateReadme
   ```
   The script verifies the APK (version matches the tag, release certificate, no INTERNET
   permission), uploads `IELTS_Vocabulary_Master_v1.0.6.apk` and its `.sha256` file, re-downloads
   the published APK to compare the SHA-256, marks the Release as *Latest*, rewrites the
   `<!-- download:start -->` block of `README.md`, and checks every link (HTTP 200, and that
   `releases/latest` resolves to the new tag).
7. Commit the README change on a `docs/readme-download-v1.0.6` branch and merge it into `main`.

Use `-DryRun` to run every local check without contacting GitHub.

## Backlog publication (v1.0.0 – v1.0.5)

The tags already exist; publish their APKs in order, with v1.0.5 as *Latest*:

```powershell
scripts\publish_release.ps1 -All -UpdateReadme
```

| Tag | Commit | versionCode | Local APK | SHA-256 |
|---|---|---|---|---|
| v1.0.0 | d76af7f | 1 | `release/IELTS_Vocabulary_Master.apk` | `89f49bc4…e414` |
| v1.0.1 | ec6d4d2 | 2 | `release/IELTS_Vocabulary_Master_flashcard_fix.apk` | `c6e7a8ff…aa42` |
| v1.0.2 | be8fee4 | 3 | `release/IELTS_Vocabulary_Master_v1.0.2.apk` | `24b23abb…fafb` |
| v1.0.3 | e7bd379 | 4 | `release/IELTS_Vocabulary_Master_v1.0.3.apk` | `88c966e1…b6a7` |
| v1.0.4 | 86c82cb | 5 | `release/IELTS_Vocabulary_Master_v1.0.4.apk` | `f69026ab…8f2f` |
| v1.0.5 | 301fa01 | 6 | `release/IELTS_Vocabulary_Master_v1.0.5.apk` | `865edf4e…2385` |

All six are signed with certificate SHA-256
`e7f0e58a4854d365fecf97fff7d82bfaee4739a0b8d6a6ac466e440ebccdc2b2`.
Each Release asset is uploaded as `IELTS_Vocabulary_Master_<tag>.apk` (a renamed copy staged in
`release/dist/`, which is git-ignored).

## Recommended repository settings (owner, in GitHub → Settings)

- **Branches → Add branch ruleset for `main`**: require a pull request before merging, require the
  status checks *Build Android APK* and *Build iOS*, block force pushes and deletions.
- **Tags → ruleset for `v*`**: block updates and deletions, so published tags cannot be moved.
