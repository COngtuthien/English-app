# IELTS Vocabulary Master

Ứng dụng Android học từ vựng IELTS **hoàn toàn ngoại tuyến** cho người Việt (trình độ B2 → mục tiêu IELTS 7.5+).
Offline Android app (Flutter) for learning IELTS vocabulary with spaced repetition.

* **10.657 mục từ đã kiểm định** – từ đơn, cụm động từ, thành ngữ, collocation, cách diễn đạt Writing/Speaking –
  mỗi mục đều có nghĩa tiếng Việt, định nghĩa tiếng Anh, ít nhất một câu ví dụ, chủ đề và nguồn dữ liệu.
* FSRS spaced repetition, flashcards (4 kiểu), quiz 9 dạng + tổng hợp, ghép từ, gõ từ, luyện nghe,
  bài tập từ vựng Writing (141 câu), 24 gói Speaking Part 1–3, thống kê, thành tích, lịch học,
  sao lưu/khôi phục, chế độ tối.
* Không cần Internet, không tài khoản, không quảng cáo, không thu thập dữ liệu (APK không có quyền INTERNET).

## Cài đặt APK
Xem [`release/INSTALL_GUIDE_VI.md`](release/INSTALL_GUIDE_VI.md). File cài đặt: `release/IELTS_Vocabulary_Master.apk`.

## Build from source (Windows)
```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_environment.ps1   # Flutter, JDK 21, Android SDK, signing key
powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1       # validate → analyze → test → build → verify
```
Linux/macOS: `scripts/build_release.sh`. CI: `.github/workflows/android-apk.yml`.

Tests: `scripts\run_tests.ps1 [-Device emulator-5554]` (unit, database, widget; plus integration test on a device).

## Vocabulary data
Rebuild the database from the open datasets: `scripts\validate_vocabulary.ps1 -Rebuild`
(downloads ~3.7 GB of Wiktionary/Tatoeba data into `data_sources/`). Sources and licences: [`DATASET_SOURCES.md`](DATASET_SOURCES.md).
Quality report: [`release/VOCABULARY_REPORT.md`](release/VOCABULARY_REPORT.md).

## Docs
[`ARCHITECTURE.md`](ARCHITECTURE.md) · [`TASKS.md`](TASKS.md) · [`PROJECT_STATUS.md`](PROJECT_STATUS.md) ·
[`release/BUILD_REPORT.md`](release/BUILD_REPORT.md) · [`release/TEST_REPORT.md`](release/TEST_REPORT.md)

## Licence
App code: all rights reserved by the owner unless stated otherwise. Vocabulary database: CC BY-SA 4.0
(contains CC BY-SA material from Wiktionary, Octanove, NAWL/NGSL; CC BY 2.0 FR material from Tatoeba;
CEFR-J levels used with citation; ipa-dict MIT). Font: Be Vietnam Pro (SIL OFL 1.1).
