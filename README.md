# Sale Target — Kế hoạch kinh doanh

Web app quản lý & theo dõi **kế hoạch bán hàng** theo tháng, phân rã theo
Team → Miền → Phụ trách (PS) → Khách hàng → Sản phẩm.

Ứng dụng một trang (React qua CDN) + backend **Supabase** (Postgres + Edge Functions),
frontend host trên **GitHub Pages**.

> 📄 Tài liệu sản phẩm chi tiết: xem [PRD.md](PRD.md).

---

## Tính năng chính

- **3 màn hình:**
  - *Chi tiết kế hoạch* — bảng dạng bảng tính, sửa trực tiếp từng ô theo 12 tháng.
  - *Tổng hợp theo PS / Khách hàng* — phân cấp Miền → PS → Khách hàng.
  - *Tổng hợp theo Sản phẩm* — phân cấp Sản phẩm → Miền → Khách hàng.
- **Phân quyền theo 5 vai trò:** `admin`, `manager`, `product_manager`, `area_manager`, `ps`
  (chỉ `admin` và `ps` được sửa).
- **Thêm sản phẩm** (sinh 12 dòng/tháng cho năm tài chính).
- **Xuất Excel** giữ nguyên cấu trúc phân cấp (gộp/mở, header gộp).
- **Đồng bộ dữ liệu** qua cơ chế `rev` (phát hiện thay đổi).

---

## Kiến trúc

```
[Browser: index.html (React + Tailwind + SheetJS qua CDN)]
        │  POST { action, token, payload }
        ▼
[Edge Function: sale_target-api]    ← xác thực token HMAC, áp phạm vi quyền
[Edge Function: sale_target-login]  ← xác thực mật khẩu (SHA-256), phát token
        │  service role
        ▼
[Postgres: sale_target, catalog, dm_khach_hang, users]  (RLS bật)
```

---

## Cấu trúc thư mục

| Đường dẫn | Mô tả |
|---|---|
| `index.html` | Toàn bộ frontend (React + Tailwind + SheetJS qua CDN) |
| `schema.sql` | Định nghĩa schema Postgres |
| `supabase/functions/sale_target-api/` | Edge Function API (mọi action) |
| `supabase/functions/sale_target-login/` | Edge Function đăng nhập / đổi mật khẩu |
| `supabase/migrations/` | Migration (vd index hiệu năng) |
| `PRD.md` | Tài liệu yêu cầu sản phẩm |

---

## Phát triển & Triển khai

### Frontend
Là một file tĩnh `index.html`, deploy **tự động qua GitHub Pages** khi push lên `main`.
Chạy thử cục bộ chỉ cần mở file bằng một web server tĩnh bất kỳ.

### Edge Functions (Supabase)
> ⚠️ **Phải deploy tay riêng** — không đi theo pipeline GitHub Pages.

```bash
supabase functions deploy sale_target-api   --no-verify-jwt
supabase functions deploy sale_target-login --no-verify-jwt
```

Cần secret **giống nhau** cho cả hai function:

```bash
supabase secrets set SESSION_SECRET=<chuoi_bi_mat_dai>
```

### Biến môi trường
Xem `.env.example`. Frontend cần URL Supabase & endpoint Edge Function; Edge Function
dùng `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SESSION_SECRET`.

---

## Bảo mật

- Token phiên ký **HMAC-SHA256**, hết hạn sau 8 giờ.
- **RLS** bật trên mọi bảng; mọi truy cập dữ liệu đi qua Edge Function (service role).
- Mật khẩu lưu **SHA-256** (kế thừa hệ cũ — xem phần rủi ro trong [PRD.md](PRD.md)).
