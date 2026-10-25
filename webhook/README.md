# SePay → MBB Money webhook (Cloudflare Worker)

## Vì sao cần cái này

iOS không cho app chạy nền lâu dài — kể cả khi bạn không tắt app, hệ thống vẫn
tạm ngưng nó sau ~30 giây. Nghĩa là **không có cách nào** để điện thoại tự nghe
tin nhắn ngân hàng khi app đã đóng.

Nhưng SePay thì *nhìn thấy* giao dịch từ phía server. Vậy để SePay **đẩy** dữ
liệu sang một endpoint luôn thức, rồi app chỉ việc kéo về khi mở lên:

```
MB Bank → SePay → POST /sepay (Worker này) → KV inbox
                                                  ↓
                          App mở lên → GET /pull → ghi vào SQLite
```

Kết quả: giao dịch vẫn được ghi nhận **ngay lúc phát sinh**, và app chỉ việc
đồng bộ bù khi bạn mở — không mất khoản nào.

## Cài đặt (5 phút)

```bash
cd webhook
npm install

# 1. Tạo storage cho inbox
npx wrangler kv namespace create INBOX
# → copy "id" trả về, dán vào wrangler.toml

# 2. Đặt hai khoá bí mật (mỗi cái là một chuỗi ngẫu nhiên dài)
npx wrangler secret put SEPAY_WEBHOOK_SECRET
npx wrangler secret put APP_PULL_TOKEN

# 3. Deploy
npx wrangler deploy
# → in ra https://mbb-money-webhook.<tên>.workers.dev
```

Sinh chuỗi ngẫu nhiên trên Windows (PowerShell):

```powershell
-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 48 | % {[char]$_})
```

## Nối vào SePay

Trong dashboard SePay → **Webhooks** → thêm webhook:

| Trường | Giá trị |
|---|---|
| URL | `https://mbb-money-webhook.<tên>.workers.dev/sepay` |
| Phương thức | `POST` |
| Xác thực | `Bearer` + chính giá trị `SEPAY_WEBHOOK_SECRET` |
| Loại giao dịch | Chuyển khoản / "Có mã giao dịch" |

Bấm **Gửi thử**. Nếu endpoint trả `{"ok":true,...}` là đã thông.

## Kiểm tra bằng tay

```bash
# Endpoint còn sống?
curl https://<worker>/health
# → {"ok":true,"ts":...}

# Webhook từ chối khi sai khoá (mong đợi 401)
curl -i -X POST https://<worker>/sepay -d '{}' -H 'Content-Type: application/json'

# Gửi một giao dịch thử
curl -X POST https://<worker>/sepay \
  -H "Authorization: Bearer $SEPAY_WEBHOOK_SECRET" \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "TEST-001",
    "transferAmount": 20000,
    "transferType": "out",
    "transactionDate": "2026-10-26 09:15:00",
    "content": "UONG NUOC 20K",
    "bankBrandName": "MB Bank"
  }'

# Kéo inbox về (dùng khi debug, app tự gọi)
curl "https://<worker>/pull?since=0" -H "Authorization: Bearer $APP_PULL_TOKEN"
```

## Thiết kế

- **Idempotent**: mỗi dòng mang khoá `sepay:<id>`. App đã dùng đúng khoá đó làm
  `reference_number`, nên gửi lại webhook bao nhiêu lần cũng không nhân đôi.
- **Chỉ ghi chi**: dòng thu nhập được trả `200` nhưng không vào inbox — đúng với
  yêu cầu "chỉ thu thập chi" của bạn.
- **Chịu được payload khác phiên bản**: SePay đã đổi tên trường vài lần
  (`id` / `transactionId` / `referenceCode`, số dạng chuỗi, kiểu không dấu), nên
  bộ chuẩn hoá xử lý tất cả thay vì giả định một dạng.
- **So sánh khoá theo thời gian hằng**: `===` thông thường rò rỉ độ dài/tiền tố
  qua timing, nên dùng phép so sánh không thoát sớm.
- **Tự dọn rác**: mỗi dòng có TTL 30 ngày; quá thời hạn đó thì API SePay thường
  đã phủ khoảng thời gian đó rồi.

## Giới hạn cần biết

- **Đồng bộ bù, không phải realtime.** Webhook giữ giao dịch an toàn khi app
  đóng, nhưng app chỉ *đọc* hộp thư khi được chạy (mở app, hoặc iOS cho phép cập
  nhật nền). Thông báo trên điện thoại vì thế có thể trễ — nội dung thì không
  mất, miễn là app mở lại trong 30 ngày.
- **Hộp thư có hạn 30 ngày.** Nếu bạn không mở app suốt quá 30 ngày, các dòng
  cũ bị dọn. Khi đó API SePay vẫn là lưới an toàn, nhưng chỉ với dữ liệu còn
  trên hệ thống SePay.
- Nếu SePay retry một webhook mà Worker đã nhận, chuông thông báo trên app có
  thể reo lại — nhưng **giao dịch không bị nhân đôi** (khoá `sepay:<id>`).
- Worker không giữ token SePay của bạn; nó chỉ nhận đúng payload SePay gửi.
- Inbox là "hộp thư tạm", không phải nguồn sự thật. Nguồn sự thật vẫn là SQLite
  trên máy + API SePay.
- **Chỉ ghi chi.** Dòng thu được trả `200` nhưng không xếp vào hộp thư, đúng với
  phạm vi "chuyên phụ trách chi tiêu".

