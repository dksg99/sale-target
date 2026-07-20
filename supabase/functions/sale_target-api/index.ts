// Supabase Edge Function: api
// Endpoint duy nhất xử lý mọi action của web app.
// Body: { action, token, payload }
//
// Deploy:  supabase functions deploy api --no-verify-jwt
// Cần secret: supabase secrets set SESSION_SECRET=<chuoi_bi_mat_dai>  (GIỐNG login)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}
const enc = new TextEncoder();
function b64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function hmac(secret, msg) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(msg)));
}
async function verifyToken(token, secret) {
  if (!token || token.indexOf(".") < 0) return null;
  const [p, sig] = token.split(".");
  const expect = b64url(await hmac(secret, p));
  if (sig !== expect) return null;
  let payload;
  try {
    const bin = atob(p.replace(/-/g, "+").replace(/_/g, "/"));
    const bytes = Uint8Array.from(bin, (ch) => ch.charCodeAt(0));
    const jsonStr = new TextDecoder("utf-8").decode(bytes);
    payload = JSON.parse(jsonStr);
  } catch { return null; }
  if (!payload.exp || Date.now() > payload.exp) return null;
  return payload; // { u, r, s, b, exp }  -- b = bu (team)
}

// ---- Mapping field key (app) <-> cột Supabase ----
const COL = {
  fy: "nam_tai_chinh", mo: "thang_ke_hoach", region: "mien", ps: "ps",
  cust: "khach_hang", custId: "ma_khach_hang", grp: "nhom_san_pham",
  prod: "san_pham", mset: "bo_vat_tu", qOld: "quota_thau_cu_con_lai",
  mMain: "thang_thau_chinh", dMain: "thoi_gian_thau_chinh", qMain: "quota_thau_chinh",
  mAdd: "thang_thau_bo_sung", qAdd: "quota_bo_sung", rev: "sl_ke_hoach_dau_nam",
  revUpd: "sl_ke_hoach_update", price: "don_gia", note: "giai_trinh",
  act: "sl_thuc_hien", dt: "doanh_thu_kh_dau_nam",
};
// Thứ tự field khi trả getData (app đọc theo fields[])
const FIELDS = ["fy","mo","region","ps","cust","custId","grp","prod","mset",
  "qOld","mMain","dMain","qMain","mAdd","qAdd","rev","revUpd","price","note","act","dt"];
// Chỉ các cột này được phép sửa qua updateCells
const EDITABLE = new Set(["qOld","mMain","dMain","qMain","mAdd","qAdd","revUpd","note","price"]);

// Lọc dữ liệu theo quyền của user.
// - admin/manager: xem tất cả team (bu); nếu client gửi payload.bu cụ thể → lọc theo team đó.
// - Các role khác: LUÔN khoá theo bu trong token (không được ghi đè bằng payload).
// - Sau đó lọc tiếp theo phạm vi hẹp hơn: area_manager theo Miền, ps theo PS.
function applyScope(query, sess, payload = {}) {
  const role = String(sess.r || "").toLowerCase(); // phòng DB trả role viết HOA ("ADMIN"/"PS"...)
  let q = query;

  // --- Khoá theo team (bu) ---
  if (role === "admin" || role === "manager") {
    if (payload && payload.bu) q = q.eq("bu", payload.bu); // admin/manager chọn xem 1 team cụ thể
    // không chọn gì → xem tất cả team
  } else if (role === "product_manager") {
    // PM quản theo NGÀNH HÀNG, xuyên suốt các team → KHÔNG khoá theo bu.
    // (Muốn giới hạn PM trong 1 team thì bỏ comment dòng dưới.)
    // q = q.eq("bu", sess.b);
  } else {
    q = q.eq("bu", sess.b); // các role còn lại luôn khoá theo bu của chính họ (không tin payload)
  }

  // --- Phạm vi trong phạm vi trên ---
  if (role === "admin" || role === "manager") return q;
  if (role === "product_manager") {
    // sess.s = ngành hàng PM phụ trách; cho phép nhiều ngành, ngăn cách bởi dấu phẩy.
    const groups = String(sess.s || "").split(",").map((x) => x.trim()).filter(Boolean);
    if (groups.length === 0) return q.eq("nhom_san_pham", "__none__"); // chưa gán ngành → không thấy gì
    return groups.length > 1 ? q.in("nhom_san_pham", groups) : q.eq("nhom_san_pham", groups[0]);
  }
  if (role === "area_manager") return q.eq("mien", sess.s);
  if (role === "ps") return q.eq("ps", sess.s);
  return q.eq("ps", sess.s); // mặc định: hẹp nhất
}

function admin() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

async function getRev(db) {
  const { data } = await db.from("sale_target")
    .select("updated_at").order("updated_at", { ascending: false }).limit(1);
  if (data && data[0] && data[0].updated_at) return Date.parse(data[0].updated_at);
  return 0;
}

// Đọc TẤT CẢ dòng (PostgREST giới hạn 1000/lần → phân trang).
// Tối ưu: đếm tổng số dòng trước, rồi TẢI CÁC TRANG SONG SONG (thay vì tuần tự)
// để giảm mạnh thời gian chờ khi dữ liệu lớn (vd ~20k dòng = 21 trang).
const PAGE = 1000;      // = max_rows của PostgREST (config.toml) → không được vượt
const CONCURRENCY = 6;  // số trang tải đồng thời

async function fetchAll(db, sess, payload) {
  const cols = FIELDS.map((f) => COL[f]).join(",") + ",id";

  // 1) Đếm số dòng trong phạm vi quyền của user (head:true → không kéo data).
  let countQ = db.from("sale_target").select("id", { count: "exact", head: true });
  countQ = applyScope(countQ, sess, payload);
  const { count, error: cErr } = await countQ;
  if (cErr) throw new Error(cErr.message);
  const total = count || 0;
  if (total === 0) return [];

  const pages = Math.ceil(total / PAGE);
  const out = new Array(total);

  // 2) Tải các trang song song (có giới hạn CONCURRENCY). Sắp xếp theo id để
  //    phân trang ổn định (tránh trùng/thiếu dòng giữa các trang).
  let next = 0;
  async function worker() {
    for (let p = next++; p < pages; p = next++) {
      const from = p * PAGE;
      let q = db.from("sale_target").select(cols)
        .order("id", { ascending: true })
        .range(from, from + PAGE - 1);
      q = applyScope(q, sess, payload);
      const { data, error } = await q;
      if (error) throw new Error(error.message);
      for (let i = 0; i < data.length; i++) out[from + i] = data[i];
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(CONCURRENCY, pages) }, worker),
  );

  // Loại bỏ ô trống (phòng khi count lệch do dữ liệu thay đổi giữa chừng).
  return out.filter(Boolean);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);

  const secret = Deno.env.get("SESSION_SECRET");
  if (!secret) return json({ ok: false, error: "SESSION_SECRET chua duoc set" }, 500);

  let body;
  try { body = await req.json(); } catch { return json({ ok: false, error: "bad_body" }, 400); }

  const { action, token, payload = {} } = body;
  const sess = await verifyToken(token, secret);
  if (!sess) return json({ ok: false, error: "unauthorized" }, 401);
  sess.r = String(sess.r || "").toLowerCase(); // chuẩn hoá role: "ADMIN" → "admin", "PS" → "ps"...

  const db = admin();
  const canEdit = sess.r === "admin" || sess.r === "ps"; // PM KHÔNG nằm trong đây → chỉ xem

  try {
    if (action === "ping") {
      return json({ ok: true, role: sess.r, scope: sess.s, bu: sess.b, username: sess.u });
    }

    if (action === "getData") {
      // fetchAll và getRev độc lập → chạy song song để tiết kiệm 1 lượt chờ.
      const [dbRows, rev] = await Promise.all([
        fetchAll(db, sess, payload),
        getRev(db),
      ]);
      const rows = dbRows.map((r) => FIELDS.map((f) => {
        const v = r[COL[f]];
        return v === null || v === undefined ? "" : v;
      }));
      const rowNums = dbRows.map((r) => r.id);
      return json({
        ok: true, fields: FIELDS, rows, rowNums, rev,
        role: sess.r, scope: sess.s, bu: sess.b, username: sess.u,
      });
    }

    if (action === "getRev") {
      return json({ ok: true, rev: await getRev(db) });
    }

    if (action === "getCatalog") {
      const { data, error } = await db.from("catalog")
        .select("nhom_san_pham, bo_vat_tu, san_pham, don_gia").range(0, 4999);
      if (error) throw new Error(error.message);
      const catalog = (data || []).map((c) => ({
        grp: c.nhom_san_pham, mset: c.bo_vat_tu, prod: c.san_pham, price: c.don_gia,
      }));
      return json({ ok: true, catalog });
    }

    if (action === "getCustomers") {
      // Danh mục khách hàng ĐẦY ĐỦ từ dm_khach_hang (không giới hạn theo dữ liệu sale_target).
      // Phân trang vì PostgREST giới hạn 1000 dòng/lần.
      const out = [];
      for (let from = 0; ; from += PAGE) {
        const { data, error } = await db.from("dm_khach_hang")
          .select("customer_id, customer_name")
          .order("customer_id", { ascending: true })
          .range(from, from + PAGE - 1);
        if (error) throw new Error(error.message);
        if (!data || data.length === 0) break;
        for (const c of data) out.push({ custId: c.customer_id ?? "", cust: c.customer_name ?? "" });
        if (data.length < PAGE) break;
      }
      const customers = out.filter((c) => c.cust || c.custId);
      return json({ ok: true, customers });
    }

    if (action === "updateCells") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const updates = payload.updates || [];
      for (const u of updates) {
        if (!EDITABLE.has(u.key)) continue; // bỏ qua cột không cho sửa
        const col = COL[u.key];
        const patch = {};
        patch[col] = u.value === "" ? null : u.value;
        const { error } = await db.from("sale_target").update(patch).eq("id", Number(u.row));
        if (error) throw new Error(error.message);
      }
      return json({ ok: true, rev: await getRev(db) });
    }

    if (action === "addProduct") {
      if (!canEdit) return json({ ok: false, error: "forbidden" }, 403);
      const s = payload;
      // Lấy fy (năm tài chính) từ 1 dòng có sẵn
      const { data: any1 } = await db.from("sale_target").select("nam_tai_chinh").limit(1);
      const fy = any1 && any1[0] ? any1[0].nam_tai_chinh : "FY26";
      const MONTHS = ["2026-04","2026-05","2026-06","2026-07","2026-08","2026-09",
        "2026-10","2026-11","2026-12","2027-01","2027-02","2027-03"];
      const rowsIns = MONTHS.map((mo) => ({
        nam_tai_chinh: fy, thang_ke_hoach: mo, mien: s.region, ps: s.ps,
        khach_hang: s.cust, ma_khach_hang: s.custId, nhom_san_pham: s.grp,
        san_pham: s.prod, bo_vat_tu: s.mset, don_gia: s.price,
        bu: sess.b, // sản phẩm mới thêm luôn gắn theo bu của người tạo (kể cả admin/manager)
        sl_ke_hoach_dau_nam: 0, sl_thuc_hien: 0,
      }));
      const { error } = await db.from("sale_target").insert(rowsIns);
      if (error) throw new Error(error.message);
      return json({ ok: true });
    }

    return json({ ok: false, error: "unknown_action" }, 400);
  } catch (err) {
    return json({ ok: false, error: String(err && err.message || err) }, 500);
  }
});