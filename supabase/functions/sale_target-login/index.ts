// Supabase Edge Function: login
// Verify username/password bằng SHA-256 (khớp hashPasswords của Apps Script cũ),
// rồi phát hành token có CHỮ KÝ HMAC để các function khác xác thực được.
//
// Deploy:  supabase functions deploy login --no-verify-jwt
// Cần secret: supabase secrets set SESSION_SECRET=<chuoi_bi_mat_dai>

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

const enc = new TextEncoder();

async function sha256Hex(text) {
  const buf = await crypto.subtle.digest("SHA-256", enc.encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function b64url(bytes) {
  const s = btoa(String.fromCharCode(...bytes));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function hmac(secret, msg) {
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(msg));
  return new Uint8Array(sig);
}

// Token = base64url(payloadJSON) + "." + base64url(hmac)
async function signToken(payload, secret) {
  const p = b64url(enc.encode(JSON.stringify(payload)));
  const sig = b64url(await hmac(secret, p));
  return `${p}.${sig}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, 405);

  const secret = Deno.env.get("SESSION_SECRET");
  if (!secret) return json({ ok: false, error: "SESSION_SECRET chua duoc set" }, 500);

  let body;
  try { body = await req.json(); } catch { return json({ ok: false, error: "bad_body" }, 400); }

  const { username, password, newPassword } = body;
  if (!username || !password) return json({ ok: false, error: "missing_credentials" }, 400);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: user, error } = await admin
    .from("users")
    .select("username, password_hash, role, scope, bu")   // thêm bu
    .eq("username", username)
    .maybeSingle();

  if (error || !user) return json({ ok: false, error: "invalid" }, 401);

  const inputHash = await sha256Hex(password);
  if (inputHash.toLowerCase() !== String(user.password_hash).toLowerCase()) {
    return json({ ok: false, error: "invalid" }, 401);
  }

  // ---- Đổi mật khẩu ----
  // Nếu client gửi kèm newPassword: sau khi xác thực mật khẩu hiện tại ở trên là đúng,
  // ta cập nhật hash mới rồi trả về (KHÔNG phát hành token — người dùng đăng nhập lại).
  if (newPassword !== undefined && newPassword !== null && newPassword !== "") {
    if (String(newPassword).length < 6) {
      return json({ ok: false, error: "weak_password" }, 400);
    }
    if (String(newPassword) === String(password)) {
      return json({ ok: false, error: "same_password" }, 400);
    }
    const newHash = await sha256Hex(String(newPassword));
    const { error: upErr } = await admin
      .from("users")
      .update({ password_hash: newHash })
      .eq("username", user.username);
    if (upErr) return json({ ok: false, error: "update_failed" }, 500);
    return json({ ok: true, changed: true });
  }

  const exp = Date.now() + 8 * 60 * 60 * 1000;
  const token = await signToken(
    { u: user.username, r: user.role, s: user.scope ?? "", b: user.bu ?? "", exp },  // thêm b
    secret,
  );

  return json({
    ok: true,
    token,
    username: user.username,
    role: user.role,
    scope: user.scope,
    bu: user.bu,   // thêm bu vào response cho frontend dùng
  });
});
