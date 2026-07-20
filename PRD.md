# PRD — Sale Target (Kế hoạch kinh doanh)


| Phiên bản tài liệu | Nội dung | Ngày | Thực hiện bởi |
|---|---|---|---|
| 1.0 | Khởi tạo tài liệu | 2026-06-20 | Đỗ Hoàng Giang |

---

## 1. Tổng quan (Overview)

**Sale Target** là ứng dụng web một trang (single-page app) giúp đội ngũ kinh doanh **lập, theo dõi và cập nhật kế hoạch bán hàng** theo từng tháng, phân rã theo Team → Miền → Phụ trách (PS) → Khách hàng → Bộ vật tư → Sản phẩm.

Ứng dụng cho phép:
- Nhập/sửa số lượng kế hoạch & thực hiện trực tiếp trên bảng theo 12 tháng của năm tài chính.
- Đối chiếu kế hoạch với quota thầu, thực hiện lũy kế (YTD) và quota khả dụng còn lại.
- Xem 3 góc nhìn tổng hợp và xuất Excel giữ nguyên cấu trúc phân cấp.
- Phân quyền dữ liệu chặt chẽ theo vai trò và phạm vi.

**Phạm vi:** Web app quản lý & theo dõi kế hoạch bán hàng năm tài chính.

**Product Owner:** Đỗ Hoàng Giang

---

## 2. Bối cảnh & Vấn đề (Background & Problem)

### 2.1 Hiện trạng trước đây
- Kế hoạch bán hàng trước đây chạy trên nhiều file Excel của từng PS.
- Dữ liệu phân tán, khó phân quyền theo vai trò, khó tổng hợp nhiều chiều, hiệu năng kém khi dữ liệu lớn.

### 2.2 Vấn đề cần giải quyết
1. **Một nguồn tin cậy (single source of truth):** nhiều cấp (admin, quản lý team, quản lý ngành hàng, quản lý miền, PS) cần cùng nhìn một bộ số nhất quán.
2. **Phân quyền dữ liệu:** mỗi vai trò chỉ được xem/sửa đúng phạm vi của mình.
3. **Cập nhật realtime & đồng bộ:** nhiều người sửa đồng thời, cần phát hiện thay đổi và làm mới.
4. **Tổng hợp đa chiều:** theo PS và theo Sản phẩm, kèm chỉ số quota & doanh thu.
5. **Hiệu năng ở quy mô ~20.000 dòng:** tải nhanh, sửa mượt.

### 2.3 Giải pháp đã chọn
Lựa chọn **Supabase** (Postgres + Edge Functions) làm backend, frontend tĩnh (React qua CDN) host trên **GitHub Pages**. Toàn bộ nghiệp vụ đi qua một Edge Function API duy nhất với token có chữ ký HMAC.

---

## 3. Mục tiêu & Phi mục tiêu (Goals / Non-goals)

### 3.1 Mục tiêu
| # | Mục tiêu | Loại |
|---|---|---|
| G1 | Cho phép PS/Admin sửa kế hoạch & thực hiện theo tháng ngay trên bảng | Sản phẩm |
| G2 | Phân quyền dữ liệu theo 5 vai trò × phạm vi (team/miền/PS/ngành hàng) | Sản phẩm |
| G3 | Cung cấp 3 màn hình: Chi tiết + 2 màn tổng hợp | Sản phẩm |
| G4 | Xuất Excel giữ cấu trúc phân cấp (gộp/mở, header gộp) | Sản phẩm |
| G5 | Tải & thao tác mượt ở quy mô ~20k dòng | Kỹ thuật |
| G6 | Giúp quản lý bám sát quota khả dụng còn lại và chênh lệch kế hoạch | Kinh doanh |

### 3.2 Phi mục tiêu (Non-goals)
- Không phải hệ CRM/quản lý cơ hội bán hàng; không quản lý đơn hàng/hợp đồng chi tiết.
- Không tự động tính hoa hồng/lương thưởng.
- Không có quy trình phê duyệt (approval workflow) nhiều bước ở phiên bản hiện tại.
- Không import dữ liệu thực hiện bằng tay qua UI (việc đẩy `sl_thuc_hien` do pipeline ngoài đảm nhiệm — xem §8).
- Không hỗ trợ đa ngôn ngữ (chỉ tiếng Việt).

---

## 4. Đối tượng người dùng & Phân quyền (Personas & Roles)

### 4.1 Khái niệm Team (bu / business unit)
Mỗi bản ghi kế hoạch gắn với một **Team** (`bu`). Các team hiện có: **CHCS, CTTM, THNK** (và TEST cho kiểm thử).

### 4.2 Năm vai trò & phạm vi

| Vai trò | Phạm vi dữ liệu | Quyền sửa | Chuyển team |
|---|---|---|---|
| **admin** | Tất cả team | ✅ Sửa & thêm SP | ✅ |
| **manager** | Tất cả team (hoặc chọn 1 team) | ❌ Chỉ xem | ✅ |
| **product_manager** | Theo **ngành hàng** (`nhom_san_pham`), xuyên suốt mọi team | ❌ Chỉ xem | — (không khoá theo team) |
| **area_manager** | Theo **Miền** (`mien`) trong team của mình | ❌ Chỉ xem | ❌ |
| **ps** | Theo **PS** (chính mình) trong team của mình | ✅ Sửa & thêm SP | ❌ |

**Quy tắc quan trọng:**
- Chỉ **admin** và **ps** có quyền chỉnh sửa (`canEdit`); các vai trò còn lại chỉ xem.
- Với các vai trò không phải admin/manager, phạm vi **luôn bị khoá theo token phía server** — client không thể ghi đè bằng payload (chống giả mạo).
- `product_manager` có thể phụ trách **nhiều ngành hàng**, ngăn cách bằng dấu phẩy trong `scope`; chưa gán ngành hàng → không thấy dữ liệu.

### 4.3 Persona tóm tắt
- **Admin (điều phối kế hoạch):** thiết lập & sửa dữ liệu cho toàn bộ team, thêm sản phẩm.
- **Ban giám đốc / Manager:** theo dõi toàn cảnh, so sánh giữa các team.
- **Product Manager:** theo dõi một/nhiều ngành hàng xuyên team.
- **Area Manager:** theo dõi địa bàn phụ trách.
- **PS (nhân viên phụ trách khách hàng):** nhập & cập nhật kế hoạch cho khách hàng của mình.

---

## 5. Luồng nghiệp vụ chính (User Flows)

### 5.1 Đăng nhập / đổi mật khẩu
1. Người dùng nhập `username` + `password`.
2. Edge Function `login` xác thực bằng SHA-256 (khớp hash hệ cũ), phát hành **token ký HMAC** có hạn **8 giờ** (`exp`).
3. Token chứa: `{ u: username, r: role, s: scope, b: bu, exp }`.
4. Đổi mật khẩu: gửi kèm `newPassword` (≥ 6 ký tự, khác mật khẩu cũ) → cập nhật hash, yêu cầu đăng nhập lại (không phát token).

### 5.2 Luồng làm việc chính
```
Đăng nhập → (admin/manager: chọn Team) → Chọn màn hình
   → Lọc (ngành hàng / miền / khách hàng)
   → [PS/Admin] Sửa ô theo tháng / Thêm sản phẩm
   → Xem tổng hợp → Xuất Excel
```

### 5.3 Đồng bộ dữ liệu
- Mỗi lần đọc, server trả `rev` = timestamp bản ghi mới nhất.
- Client có thể gọi `getRev` để phát hiện dữ liệu đã thay đổi và làm mới, tránh ghi đè lẫn nhau.

---

## 6. Yêu cầu chức năng (Functional Requirements)

Ứng dụng có **3 màn hình chính** (tab):

### 6.1 Màn "Chi tiết kế hoạch"
Bảng dạng bảng tính, mỗi dòng = một (Khách hàng × Sản phẩm × đơn giá) với 12 cột tháng.

- **Sửa trực tiếp từng ô**: Ô đang sửa có viền nhấn; ô chưa lưu (pending) tô màu hổ phách.
- Các cột **được phép sửa** (`EDITABLE`): `qOld` (quota thầu cũ còn lại), `mMain`/`dMain`/`qMain` (tháng/thời gian/quota thầu chính), `mAdd`/`qAdd` (tháng/quota thầu bổ sung), `revUpd` (SL kế hoạch update từng tháng), `note` (giải trình), `price` (đơn giá).
- Hiển thị: SL kế hoạch đầu năm, SL update theo tháng, doanh thu, chênh lệch (tô xanh/đỏ theo dấu), quota khả dụng còn lại.
- Tháng hiện tại được highlight.

### 6.2 Màn "Tổng hợp theo PS / Khách hàng"
Cấu trúc phân cấp: **Miền → PS → Khách hàng**, có thể gập/mở.
- Cột: Số KH, Số SP, Quota/Số lượng, Doanh thu (triệu VND), % Chênh lệch, Giải trình.
- Dòng tổng (grand total) ở cuối.

### 6.3 Màn "Tổng hợp theo Sản phẩm"
Cấu trúc phân cấp: **Sản phẩm → Miền → Khách hàng**, có thể gập/mở.
- Cột: SL KH update theo 12 tháng, Tổng Quota, Thực hiện YTD, KH còn lại YTD, Quota khả dụng còn lại.

### 6.4 Tính năng ngang (áp dụng nhiều màn)

| Tính năng | Mô tả |
|---|---|
| **Bộ lọc** | Lọc theo Ngành hàng, Miền, Khách hàng (hiển thị theo quyền — ví dụ PS không có bộ lọc miền/KH riêng). |
| **Chuyển team (TeamSwitcher)** | Chỉ admin/manager: chọn 1 team hoặc "Tất cả". |
| **Thêm sản phẩm** | Chọn Khách hàng (từ `dm_khach_hang`, có ô tìm kiếm gần đúng), Miền, PS, Nhóm SP, Sản phẩm, Bộ vật tư, đơn giá → sinh **12 dòng** (một dòng/tháng, 04/2026 → 03/2027), gắn `bu` của người tạo. |
| **Xuất Excel** | Xuất giữ nguyên cấu trúc phân cấp (gập/mở), header gộp (merge), dùng thư viện SheetJS (xlsx). |
| **Đồng bộ (rev)** | Phát hiện thay đổi dữ liệu qua `rev`/`getRev`. |
| **Đổi mật khẩu** | Ngay tại màn đăng nhập. |

---

## 7. Mô hình dữ liệu (Data Model)

### 7.1 Bảng chính

**`sale_target`** — bản ghi kế hoạch (một dòng / tháng / SP / KH):

| Cột DB | Field app | Ý nghĩa |
|---|---|---|
| `nam_tai_chinh` | fy | Năm tài chính (vd FY26) |
| `thang_ke_hoach` | mo | Tháng kế hoạch (YYYY-MM) |
| `mien` | region | Miền |
| `ps` | ps | Người phụ trách |
| `khach_hang` | cust | Tên khách hàng |
| `ma_khach_hang` | custId | Mã khách hàng |
| `nhom_san_pham` | grp | Nhóm/Ngành sản phẩm |
| `san_pham` | prod | Sản phẩm |
| `bo_vat_tu` | mset | Bộ vật tư |
| `quota_thau_cu_con_lai` | qOld | Quota thầu cũ còn lại |
| `thang_thau_chinh` / `thoi_gian_thau_chinh` / `quota_thau_chinh` | mMain/dMain/qMain | Thầu chính |
| `thang_thau_bo_sung` / `quota_bo_sung` | mAdd/qAdd | Thầu bổ sung |
| `sl_ke_hoach_dau_nam` | rev* | SL kế hoạch đầu năm |
| `sl_ke_hoach_update` | revUpd | SL kế hoạch update |
| `don_gia` | price | Đơn giá |
| `doanh_thu_kh_dau_nam` | dt | Doanh thu KH đầu năm |
| `sl_thuc_hien` | act | SL thực hiện (đẩy từ pipeline ngoài) |
| `giai_trinh` | note | Giải trình |
| `bu` | — | Team (business unit) |
| `updated_at` | — | Mốc cập nhật (nguồn của `rev`) |

**`catalog`** — danh mục sản phẩm chuẩn: `nhom_san_pham`, `bo_vat_tu`, `san_pham`, `don_gia` (unique theo `bo_vat_tu` + `san_pham`).

**`dm_khach_hang`** — danh mục khách hàng đầy đủ: `customer_id`, `customer_name` (RLS chặn anon; không chứa PS/Miền).

**`users`** — tài khoản: `username`, `password_hash` (SHA-256), `role`, `scope`, `bu`.

### 7.2 Chỉ số & công thức
- **Thực hiện YTD** = tổng `sl_thuc_hien` các tháng đã qua.
- **KH còn lại YTD** = tổng SL kế hoạch update từ tháng hiện tại trở đi (`sumFromNow`).
- **Tổng Quota** = quota thầu cũ còn lại + quota thầu chính + quota bổ sung (theo cấp tổng hợp).
- **Quota khả dụng còn lại** = Tổng Quota − (Thực hiện YTD + KH còn lại YTD).
- **Doanh thu** = SL × đơn giá (đầu năm vs update) → **chênh lệch doanh thu** (tô xanh nếu dương, đỏ nếu âm).
- **% Chênh lệch**: so sánh kế hoạch update với kế hoạch đầu năm.

---

## 8. Quy tắc nghiệp vụ (Business Rules)

1. **Một sản phẩm có thể có nhiều dòng** nếu **đơn giá khác nhau** giữa các khách hàng.
2. **Đẩy `sl_thuc_hien` khớp theo PS**: một khách hàng có thể do nhiều PS phụ trách; import thực hiện phải khớp đúng PS tương ứng (qua pipeline ngoài).
3. **Năm tài chính**: 12 tháng từ **Tháng 04 năm nay → Tháng 03 năm sau**.
4. **Chỉ các cột `EDITABLE`** được sửa qua `updateCells`; mọi cột khác bị bỏ qua ở server (kể cả nếu client gửi lên).
5. **Sản phẩm mới** luôn gắn `bu` của người tạo (kể cả admin), khởi tạo `sl_ke_hoach_dau_nam = 0`, `sl_thuc_hien = 0`.
6. **Phạm vi quyền khoá phía server**: role không phải admin/manager không thể mở rộng phạm vi bằng payload.

---

## 9. Yêu cầu phi chức năng (Non-functional Requirements)

### 9.1 Bảo mật
- Token phiên có **chữ ký HMAC-SHA256**; hết hạn sau 8 giờ; server verify chữ ký + `exp` trước mọi action.
- Mật khẩu lưu dạng **SHA-256**. *Ghi chú rủi ro: SHA-256 không salt — xem §12.*
- **RLS** bật trên mọi bảng; anon không đọc trực tiếp được `dm_khach_hang`. Mọi truy cập dữ liệu đi qua Edge Function dùng service role.
- CORS mở cho web app; API dùng `--no-verify-jwt` (tự xác thực bằng token nội bộ).

### 9.2 Hiệu năng
- Đọc toàn bộ dữ liệu theo phạm vi quyền, **phân trang 1000 dòng/lần** (giới hạn PostgREST), **tải song song 6 trang** để giảm thời gian chờ ở ~20k dòng (~21 trang).
- Đếm tổng số dòng trước (`head:true`) rồi tải trang song song, sắp xếp theo `id` để phân trang ổn định.
- Có index hiệu năng (migration `perf_indexes`).

### 9.3 Khả dụng & UX
- Giao diện tiếng Việt, phong cách bảng tính quen thuộc, highlight tháng hiện tại, màu sắc trực quan cho chênh lệch.
- Màn hình boot có spinner + báo lỗi rõ ràng.

### 9.4 Tương thích
- Frontend chỉ cần trình duyệt hiện đại; không cần cài đặt (React/Tailwind/xlsx nạp qua CDN).

---

## 10. Kiến trúc & Triển khai (Architecture & Deployment)

```
[Browser: index.html (React CDN + Tailwind + SheetJS)]
        │  POST { action, token, payload }
        ▼
[Supabase Edge Function: sale_target-api]  ← xác thực token HMAC, áp phạm vi quyền
[Supabase Edge Function: sale_target-login] ← xác thực mật khẩu, phát token
        │  service role
        ▼
[Postgres: sale_target, catalog, dm_khach_hang, users]  (RLS bật)
```

### 10.1 Điểm triển khai quan trọng
- **Frontend**: `index.html` deploy tự động qua **GitHub Pages** (GitHub Actions).
- **Edge Functions**: **phải deploy tay riêng** (`supabase functions deploy ... --no-verify-jwt`); **không** đi theo pipeline Pages. Cần secret `SESSION_SECRET` giống nhau cho cả login & api.
- **Endpoint API duy nhất** xử lý mọi action: `ping`, `getData`, `getRev`, `getCatalog`, `getCustomers`, `updateCells`, `addProduct`.

---

## 11. Chỉ số thành công (Success Metrics / KPIs)

| Nhóm | Chỉ số |
|---|---|
| **Áp dụng** | % PS đăng nhập & cập nhật kế hoạch hàng tháng; số bản ghi được sửa/tháng |
| **Chất lượng dữ liệu** | Tỷ lệ dòng có giải trình khi chênh lệch lớn; số lần dữ liệu lệch được phát hiện qua `rev` |
| **Hiệu năng** | Thời gian tải màn Chi tiết ở ~20k dòng (< X giây) |
| **Tin cậy** | Số lỗi 401/500 từ Edge Function; uptime |
| **Kinh doanh** | Mức độ bám sát Quota khả dụng còn lại theo thời gian |

*(Ngưỡng cụ thể cần chốt với chủ sở hữu sản phẩm.)*

---

## 12. Rủi ro, Giả định & Hướng phát triển

### 12.1 Rủi ro
- **Mật khẩu SHA-256 không salt** → yếu trước tấn công dò bảng băm. Cân nhắc chuyển bcrypt/argon2.
- **Không có khoá lạc quan (optimistic lock)** ở cấp ô: hai người sửa cùng dòng có thể ghi đè; hiện chỉ giảm nhẹ bằng `rev`.
- **CORS `*`** + API `--no-verify-jwt`: an toàn dựa hoàn toàn vào token HMAC; cần bảo vệ `SESSION_SECRET`.
- **`getCatalog` giới hạn 5000 dòng**; danh mục lớn hơn sẽ bị cắt.

### 12.2 Giả định
- `sl_thuc_hien` được đẩy đúng, đúng PS, bởi pipeline ngoài.
- Danh mục khách hàng/sản phẩm được quản trị ngoài UI.

### 12.3 Hướng phát triển (Future)
- Ghi log/audit trail cho `updateCells`.
- Quy trình phê duyệt kế hoạch.
- Khoá phiên bản ô (concurrency control) rõ ràng.
- Dashboard biểu đồ trực quan (xu hướng, so sánh team).
- Nâng cấp cơ chế lưu mật khẩu.

---

## 13. Phụ lục — Từ điển thuật ngữ & Ánh xạ field ↔ cột DB

### 13.1 Thuật ngữ
- **PS**: người phụ trách (sales phụ trách khách hàng).
- **bu**: business unit / Team.
- **Quota thầu**: hạn ngạch theo gói thầu (chính, bổ sung, thầu cũ còn lại).
- **YTD**: lũy kế từ đầu năm tới hiện tại.
- **Quota khả dụng còn lại**: phần quota chưa được tiêu bởi thực hiện + kế hoạch còn lại.

### 13.2 Ánh xạ field ↔ cột
Xem bảng đầy đủ ở §7.1. Thứ tự field khi trả `getData`:
`fy, mo, region, ps, cust, custId, grp, prod, mset, qOld, mMain, dMain, qMain, mAdd, qAdd, rev, revUpd, price, note, act, dt`

### 13.3 Danh sách action API
`ping` · `getData` · `getRev` · `getCatalog` · `getCustomers` · `updateCells` · `addProduct`

---
