# MBB Money — Cyberpunk 2077 Expense Tracker for iPhone (MB Bank)

Ứng dụng quản lý **chi tiêu cá nhân** phong cách viễn tưởng **Cyberpunk / Synthwave**, tự động đồng bộ biến động số dư tiền ra (chi tiêu) từ **MB Bank** thông qua **SePay API Token** và tích hợp trợ lý tài chính **AI (A.R.I.A 2077)**.

---

## ⚡ Các tính năng nổi bật

1. **Giao diện Cyberpunk 2077 Neon HUD**:
   - Tông màu đen sâu Carbon Void (`#05070D`), viền phát sáng Neon Cyan (`#00F0FF`), Neon Pink (`#FF0055`) và Laser Yellow.
   - Hiệu ứng phát sáng holographic, font số liệu công nghệ sci-fi.
2. **Tối ưu 100% cho CHI TIÊU (Expenses Only)**:
   - Toàn bộ dòng tiền vào / thu nhập đều được lọc bỏ, giao diện tập trung tuyệt đối vào việc kiểm soát dòng tiền chi tiêu và hạn mức ngân sách ngày.
3. **Chỉ dùng SePay API Token (Đơn giản nhất)**:
   - Không cần thiết lập Shortcut phức tạp. Chỉ cần dán 1 Token SePay tại `my.sepay.vn` vào app, hệ thống tự động kéo các khoản chuyển khoản tiền ra từ tài khoản MB Bank của bạn.
4. **Trợ lý ảo Cyber AI (A.R.I.A 2077)**:
   - Nút kích hoạt AI ngay trên thanh điều hướng dưới.
   - Trả lời thông minh về tổng chi tiêu, tiền ăn uống cafe, đưa ra chiến lược cắt giảm chi tiêu.
   - Chạy 100% offline với thuật toán tài chính tích hợp sẵn, hoặc hỗ trợ gắn Gemini API Key để trò chuyện tự do.
5. **Đã cấu hình tự động xuất file `.ipa` để cài qua ESign**:
   - Có sẵn GitHub Actions workflow [`.github/workflows/build_ipa.yml`](.github/workflows/build_ipa.yml) để đóng gói file `MBBMoney_Cyberpunk_ESign.ipa`.
   - Xem chi tiết tại [docs/ESIGN_IPA_GUIDE.md](docs/ESIGN_IPA_GUIDE.md).

---

## 🚀 Trải nghiệm ngay trên máy tính

Server cục bộ đang chạy tại:
👉 **http://localhost:8099**

(Mở Chrome/Edge, bấm `F12` và chọn giao diện iPhone để trải nghiệm).

---

## 📲 Cách tạo file .ipa để cài qua ESign

Vì máy tính chạy Windows không có trình biên dịch Xcode SDK độc quyền của Apple (macOS), Apple không cho phép biên dịch file `.ipa` trực tiếp trên Windows.

Bạn chỉ cần:
1. Đẩy code lên GitHub cá nhân (Private repo).
2. GitHub Actions sẽ tự động kích hoạt máy ảo macOS chạy workflow [build_ipa.yml](.github/workflows/build_ipa.yml) và tạo ra file `MBBMoney_Cyberpunk_ESign.ipa` trong mục **Artifacts**.
3. Tải file `.ipa` về iPhone và ký bằng **ESign** để dùng vĩnh viễn.

Hướng dẫn chi tiết từng bước xem tại: [docs/ESIGN_IPA_GUIDE.md](docs/ESIGN_IPA_GUIDE.md).
