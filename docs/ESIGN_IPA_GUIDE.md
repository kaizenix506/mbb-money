# HƯỚNG DẪN BUILD FILE .IPA CÀI TRỰC TIẾP QUA ESIGN

Để cài app lên iPhone qua **ESign**, bạn cần file cài đặt định dạng `.ipa`.

---

## ⚠️ Vì sao không thể xuất trực tiếp file .ipa từ Windows?
Apple yêu cầu toàn bộ mã nguồn iOS (Objective-C/Swift/Frameworks của iPhone) phải được biên dịch bởi công cụ `clang` và bộ công cụ **Xcode SDK**, vốn chỉ chạy độc quyền trên hệ điều hành **macOS**. Vì máy tính hiện tại chạy Windows, hệ thống không có trình biên dịch của Apple.

Tuy nhiên, bạn có thể tạo file `.ipa` hoàn toàn **TỰ ĐỘNG & MIỄN PHÍ 100%** bằng 2 cách sau:

---

## CÁCH 1: Dùng GitHub Actions (Khuyến nghị — Nhanh & Tự động)
Dự án đã được cấu hình sẵn file workflow [`.github/workflows/build_ipa.yml`](file:///c:/Users/Hoang/Documents/Local/test/.github/workflows/build_ipa.yml).

### Các bước thực hiện:
1. Đăng nhập vào [GitHub](https://github.com) và tạo 1 repository mới (Private hoặc Public).
2. Tải toàn bộ thư mục code này lên GitHub repo đó:
   ```bash
   git init
   git add .
   git commit -m "Cyberpunk MBB Money app"
   git branch -M main
   git remote add origin <link_github_repo_cua_ban>
   git push -u origin main
   ```
3. Sau khi đẩy code lên:
   - Vào tab **Actions** trên GitHub repository.
   - Bạn sẽ thấy tiến trình **"Build Unsigned IPA for ESign"** tự động chạy trên máy Mac của GitHub.
   - Sau khoảng 3–5 phút khi hoàn thành, vào mục **Artifacts** và tải file `MBBMoney_Cyberpunk_ESign_IPA` về máy.
4. Mở ứng dụng **ESign** trên iPhone:
   - Nhập file `.ipa` vừa tải vào ESign.
   - Ký bằng chứng chỉ cá nhân của bạn trong ESign và cài đặt ngay lên màn hình chính.

---

## CÁCH 2: Dùng Codemagic (Miễn phí 500 phút build Mac/tháng)
1. Truy cập [codemagic.io](https://codemagic.io) và đăng ký tài khoản (đăng nhập bằng GitHub/GitLab).
2. Chọn repo dự án.
3. Trong phần **Build settings**, chọn nền tảng **iOS**.
4. Mục **Code signing**: chọn **Skip code signing** (để xuất file unsigned `.ipa` dành riêng cho ESign).
5. Bấm **Start new build**. Khi build xong, Codemagic sẽ gửi link tải trực tiếp file `.ipa` về điện thoại của bạn.

---

## CÁCH 3: Cài đặt ngay lập tức dưới dạng PWA (Không cần chứng chỉ ESign)
Nếu bạn muốn dùng thử ngay lập tức mà không cần đợi ký chứng chỉ:
1. Bạn có thể đưa thư mục `build/web` lên Vercel hoặc Netlify (miễn phí).
2. Mở trên Safari của iPhone → bấm **Chia sẻ** → chọn **Thêm vào Màn hình chính (Add to Home Screen)**.
3. App chạy mượt mà, đầy đủ giao diện Cyberpunk neon, kết nối SePay và chatbot AI như ứng dụng native.
