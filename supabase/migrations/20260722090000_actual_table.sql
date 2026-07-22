-- ════════════════════════════════════════════════════════════════════════
-- HƯỚNG HYBRID: actual đi vào bảng riêng (sv_bovattu_actual) làm NGUỒN SỰ THẬT,
-- rồi map sang sale_target.sl_thuc_hien bằng SQL (không phá huỷ, tra được).
--
-- Gồm:
--   1) Bảng sv_bovattu_actual        — chứa 100% actual (kể cả dòng chưa map)
--   2) Index hỗ trợ map              — thang_ke_hoach (raw) cho join theo tháng
--   3) Function map_actual_to_sale_target() — zero + set sl_thuc_hien theo khoá
--   4) View v_actual_unmatched       — các actual KHÔNG tìm thấy dòng plan
--
-- Idempotent: chạy lại nhiều lần vô hại.
-- Áp dụng: `supabase db push`, hoặc dán vào SQL Editor trên dashboard.
-- ════════════════════════════════════════════════════════════════════════

-- 1) Bảng actual ─────────────────────────────────────────────────────────
create table if not exists public.sv_bovattu_actual (
  id             bigint generated always as identity primary key,
  thang_ke_hoach text not null,            -- '2026-06' (khớp sale_target.thang_ke_hoach)
  mien           text,                     -- chỉ để hiển thị (không nằm trong khoá map)
  ps             text,                     -- khoá map
  ma_khach_hang  text,                     -- khoá map
  khach_hang     text,                     -- chỉ để hiển thị
  bo_vat_tu      text,                     -- khoá map
  san_pham       text,                     -- khoá map
  sl_thuc_hien   numeric,
  imported_at    timestamptz default now()
);

comment on table public.sv_bovattu_actual is
  'Actual (SL thực hiện) sau khi gán bộ vật tư — nguồn sự thật, giữ cả dòng chưa map. Map sang sale_target qua map_actual_to_sale_target().';

-- 2) Index cho map/lookup ────────────────────────────────────────────────
-- Join theo tháng (equality trên cột raw) để function không quét toàn bảng sale_target.
create index if not exists idx_sale_target_thang
  on public.sale_target (thang_ke_hoach);

create index if not exists idx_sv_actual_thang
  on public.sv_bovattu_actual (thang_ke_hoach);

-- 3) Function map: actual -> sale_target.sl_thuc_hien ─────────────────────
--    - Zero sl_thuc_hien cho MỌI tháng đang có trong bảng actual.
--    - Với mỗi khoá (thang|PS|maKH|boVT|sanPham, chuẩn hoá lower+trim), gộp SL và
--      ghi vào dòng plan có id NHỎ NHẤT (nhiều dòng cùng khoá do khác đơn giá →
--      dồn vào 1 dòng, các dòng còn lại = 0; giữ đúng hành vi cũ).
--    - Trả JSON thống kê để script in ra.
create or replace function public.map_actual_to_sale_target()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_months  text[];
  v_zeroed  int := 0;
  v_set     int := 0;
  v_matched int := 0;
  v_total   int := 0;
begin
  select array_agg(distinct thang_ke_hoach) into v_months from sv_bovattu_actual;
  if v_months is null then
    return jsonb_build_object('months', 0, 'zeroed', 0, 'set_rows', 0,
                              'matched_keys', 0, 'total_keys', 0, 'unmatched_keys', 0);
  end if;

  -- (1) Zero các tháng có actual
  update sale_target set sl_thuc_hien = 0
   where thang_ke_hoach = any(v_months)
     and sl_thuc_hien is distinct from 0;
  get diagnostics v_zeroed = row_count;

  -- (2) Gộp actual theo khoá chuẩn hoá + tìm dòng plan id nhỏ nhất.
  --     Dùng LEFT JOIN LATERAL (không UPDATE không-WHERE — DB bật safeupdate sẽ chặn).
  create temp table _agg on commit drop as
  with a as (
    select thang_ke_hoach,
           lower(btrim(ps))            as ps_n,
           lower(btrim(ma_khach_hang)) as kh_n,
           lower(btrim(bo_vat_tu))     as bo_n,
           lower(btrim(san_pham))      as sp_n,
           sum(sl_thuc_hien)           as sl
      from sv_bovattu_actual
     group by 1, 2, 3, 4, 5
  )
  select a.*, t.id as target_id
    from a
    left join lateral (
      select s.id from sale_target s
       where s.thang_ke_hoach                = a.thang_ke_hoach
         and lower(btrim(s.ps))            = a.ps_n
         and lower(btrim(s.ma_khach_hang)) = a.kh_n
         and lower(btrim(s.bo_vat_tu))     = a.bo_n
         and lower(btrim(s.san_pham))      = a.sp_n
       order by s.id
       limit 1
    ) t on true;

  -- (3) Ghi SL vào dòng khớp
  update sale_target s
     set sl_thuc_hien = a.sl
    from _agg a
   where a.target_id = s.id;
  get diagnostics v_set = row_count;

  select count(*), count(*) filter (where target_id is not null)
    into v_total, v_matched
    from _agg;

  return jsonb_build_object(
    'months',         array_length(v_months, 1),
    'zeroed',         v_zeroed,
    'set_rows',       v_set,
    'matched_keys',   v_matched,
    'total_keys',     v_total,
    'unmatched_keys', v_total - v_matched
  );
end;
$$;

grant execute on function public.map_actual_to_sale_target() to service_role;

-- 4) View: actual KHÔNG khớp dòng plan nào (để dò 28% đang rơi) ────────────
create or replace view public.v_actual_unmatched as
select a.thang_ke_hoach,
       a.mien,
       a.ps,
       a.ma_khach_hang,
       a.khach_hang,
       a.bo_vat_tu,
       a.san_pham,
       sum(a.sl_thuc_hien) as sl_thuc_hien
  from public.sv_bovattu_actual a
 where not exists (
   select 1 from public.sale_target s
    where s.thang_ke_hoach                = a.thang_ke_hoach
      and lower(btrim(s.ps))            = lower(btrim(a.ps))
      and lower(btrim(s.ma_khach_hang)) = lower(btrim(a.ma_khach_hang))
      and lower(btrim(s.bo_vat_tu))     = lower(btrim(a.bo_vat_tu))
      and lower(btrim(s.san_pham))      = lower(btrim(a.san_pham))
 )
 group by a.thang_ke_hoach, a.mien, a.ps, a.ma_khach_hang, a.khach_hang, a.bo_vat_tu, a.san_pham
 order by sum(a.sl_thuc_hien) desc;

grant select on public.v_actual_unmatched to service_role;

analyze public.sale_target;
