-- Tối ưu tốc độ load danh sách (getData/getRev).
-- Tất cả đều idempotent (IF NOT EXISTS) → chạy lại nhiều lần vô hại.
-- Áp dụng: `supabase db push`, hoặc dán nội dung file này vào SQL Editor trên dashboard.

-- 1) getRev: SELECT updated_at ORDER BY updated_at DESC LIMIT 1.
--    Không index → quét + sort toàn bảng (~20k dòng) mỗi lần gọi.
--    Có index DESC → lấy 1 dòng đầu tức thì.
CREATE INDEX IF NOT EXISTS idx_sale_target_updated_at
  ON public.sale_target (updated_at DESC);

-- 2) applyScope lọc theo bu / mien / ps / nhom_san_pham tuỳ role.
--    Index từng cột giúp các role bị khoá phạm vi (ps, area_manager, PM, theo team)
--    không phải seq-scan toàn bảng.
CREATE INDEX IF NOT EXISTS idx_sale_target_bu
  ON public.sale_target (bu);

CREATE INDEX IF NOT EXISTS idx_sale_target_mien
  ON public.sale_target (mien);

CREATE INDEX IF NOT EXISTS idx_sale_target_ps
  ON public.sale_target (ps);

CREATE INDEX IF NOT EXISTS idx_sale_target_nhom_san_pham
  ON public.sale_target (nhom_san_pham);

-- 3) users: login tra cứu theo username (đã là PRIMARY KEY → có index sẵn, không cần thêm).

ANALYZE public.sale_target;
