# Hướng dẫn cài đặt IELTS Vocabulary Master

## 1. Tải file APK về điện thoại
**Cách nhanh nhất:** mở trình duyệt trên điện thoại và tải bản mới nhất từ GitHub Releases:
<https://github.com/COngtuthien/English-app/releases/latest>
(chạm vào file `IELTS_Vocabulary_Master_vX.Y.Z.apk` trong mục *Assets*). Các phiên bản cũ vẫn tải được tại
<https://github.com/COngtuthien/English-app/releases>. Mỗi bản có kèm file `.sha256` để kiểm tra file không bị hỏng.

Hoặc chép file APK từ máy tính sang điện thoại, chọn một cách:
* **Cáp USB:** cắm điện thoại vào máy tính → chọn chế độ *Truyền tệp (File transfer)* → chép file APK vào thư mục `Download` của điện thoại.
* **Zalo / Telegram / email gửi cho chính mình** rồi tải file về điện thoại.
* **Thẻ nhớ / USB OTG**.

Có thể kiểm tra file không bị hỏng bằng mã SHA-256 trong `SHA256.txt`.

## 2. Cho phép cài ứng dụng từ nguồn ngoài
Android chỉ hỏi một lần cho ứng dụng dùng để mở file (ví dụ *Files*, *Tệp của tôi*, *Chrome*, *Zalo*):
1. Mở ứng dụng quản lý tệp → vào `Download` → chạm vào file APK vừa tải (`IELTS_Vocabulary_Master_vX.Y.Z.apk`).
2. Nếu xuất hiện thông báo *"Vì lý do bảo mật, điện thoại không được phép cài đặt ứng dụng không rõ nguồn gốc"*:
   chạm **Cài đặt (Settings)** → bật **Cho phép từ nguồn này (Allow from this source)** → quay lại.
3. Chạm **Cài đặt (Install)**.
4. Nếu Google Play Protect hỏi *"Ứng dụng chưa được xác minh / Unsafe app blocked"*: chọn **Chi tiết khác → Vẫn cài đặt (Install anyway)**.
   Đây là cảnh báo chuẩn cho mọi ứng dụng không cài từ Play Store; ứng dụng này không có quyền Internet.

## 3. Mở ứng dụng lần đầu
* Lần mở đầu tiên mất vài giây để chuẩn bị cơ sở dữ liệu từ vựng (khoảng 33 MB) – **không cần Internet**.
* Nhập tên (không bắt buộc), trình độ, mục tiêu IELTS, số từ mới mỗi ngày và chủ đề yêu thích.
* Có thể bật **chế độ máy bay** – mọi tính năng học vẫn hoạt động.

## 4. Phát âm (tuỳ chọn)
Ứng dụng dùng giọng đọc **ngoại tuyến** có sẵn trên điện thoại. Nếu nút loa báo "chưa có giọng đọc":
*Cài đặt điện thoại → Hệ thống → Ngôn ngữ và phương thức nhập → Chuyển văn bản thành giọng nói →
Công cụ ưu tiên (Google) → Cài đặt → Cài đặt dữ liệu giọng nói → English (United Kingdom) và English (United States)*.
Việc tải giọng đọc này cần Internet **một lần**, sau đó dùng ngoại tuyến. Nếu không có giọng đọc, ứng dụng hiển thị phiên âm IPA thay thế.

## 5. Thông báo nhắc học (tuỳ chọn)
Bật trong *Cá nhân → Cài đặt → Nhắc học mỗi ngày*; Android 13+ sẽ hỏi quyền gửi thông báo.

## 6. Sao lưu tiến độ
*Cá nhân → Sao lưu & khôi phục → Tạo bản sao lưu* → chọn nơi lưu (ví dụ `Download`). Nên sao lưu trước khi đổi điện thoại hoặc gỡ ứng dụng.
Khôi phục: chọn file `.json` đã lưu → xác nhận.

## 7. Cập nhật ứng dụng sau này
Phiên bản mới phải được ký bằng **cùng khoá ký** (`android/keystore/ielts-release.jks` + `android/key.properties` trên máy tính build).
Hãy sao lưu hai file đó ở nơi an toàn (USB/ổ đám mây cá nhân, **không** chia sẻ công khai). Nếu mất khoá, phải gỡ bản cũ
(nhớ sao lưu tiến độ trước) rồi mới cài được bản ký bằng khoá mới.

## 8. Yêu cầu
* Android 7.0 (API 24) trở lên, ~120 MB dung lượng trống.
* Hỗ trợ điện thoại ARM 32/64-bit và x86_64.

## Gỡ lỗi nhanh
| Vấn đề | Cách xử lý |
|---|---|
| "Ứng dụng chưa được cài đặt" | Gỡ phiên bản cũ ký bằng khoá khác (sao lưu trước), kiểm tra dung lượng trống, tải lại file APK (so mã SHA-256). |
| "Lỗi phân tích cú pháp gói" | File APK bị hỏng khi chép – chép lại; kiểm tra Android ≥ 7.0. |
| Không có âm thanh | Xem mục 4; kiểm tra âm lượng phương tiện. |
