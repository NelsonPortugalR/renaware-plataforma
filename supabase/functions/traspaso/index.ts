// Edge Function "traspaso": canjea un código de un solo uso creado por el hub
// por la credencial que usa cada módulo. Se despliega sin verificación de JWT
// (los módulos la llaman antes de tener sesión); la seguridad está en el
// código: uuid aleatorio, un solo uso, vence a los 3 minutos (traspaso_consumir).
//
// Respuesta:
//   asesor               → { ok, tipo:'asesor', token, nombre, celular }
//   staff → módulo clave → { ok, tipo:'staff', admin_token, (asesor opcional para el cotizador) }
//   staff → módulo correo→ { ok, tipo:'staff', sesion: {access_token, refresh_token, ...}, admin_token? }
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, motivo: "Método no permitido." }, 405);

  let codigo = "";
  try { codigo = String((await req.json())?.codigo ?? ""); } catch { /* sin cuerpo */ }
  if (!/^[0-9a-f-]{36}$/i.test(codigo)) return json({ ok: false, motivo: "Código inválido." }, 400);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const servicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, servicio, { auth: { persistSession: false, autoRefreshToken: false } });

  // 1) Qué módulo pide el código y con qué acceso entra
  const { data: t, error: e0 } = await admin.from("traspasos").select("modulo, rol, user_id, usado_en, creado_en").eq("codigo", codigo).maybeSingle();
  if (e0) return json({ ok: false, motivo: "No se pudo validar el enlace." }, 500);
  if (!t || t.usado_en) return json({ ok: false, motivo: "El enlace ya se usó o venció. Vuelve a abrirlo desde la plataforma." }, 401);
  const { data: mod } = await admin.from("plataforma_modulos").select("id, acceso").eq("id", t.modulo).maybeSingle();

  // 2) Asesor, o equipo hacia un módulo de clave (admin_sesion / cotizador): lo resuelve la base
  if (t.rol === "asesor" || !mod || mod.acceso !== "supabase") {
    const { data, error } = await admin.rpc("traspaso_canjear", { p_codigo: codigo });
    if (error) return json({ ok: false, motivo: limpiar(error.message) }, 401);
    if (t.rol === "asesor") {
      return json({ ok: true, tipo: "asesor", token: data?.asesor?.token, nombre: data?.asesor?.nombre, celular: data?.asesor?.celular, modulo: data?.modulo });
    }
    return json({ ok: true, tipo: "staff", admin_token: data?.admin_token ?? null, asesor: data?.asesor ?? null, modulo: data?.modulo, rol: data?.rol });
  }

  // 3) Equipo hacia un módulo con cuenta: una sesión de Supabase propia para ese módulo
  const { data: a, error: e1 } = await admin.rpc("traspaso_canjear_auth", { p_codigo: codigo });
  if (e1 || !a?.email) return json({ ok: false, motivo: limpiar(e1?.message ?? "Enlace inválido.") }, 401);

  const { data: enlace, error: e2 } = await admin.auth.admin.generateLink({ type: "magiclink", email: a.email });
  if (e2 || !enlace?.properties?.hashed_token) return json({ ok: false, motivo: "No se pudo crear la sesión." }, 500);
  const cliente = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: v, error: e3 } = await cliente.auth.verifyOtp({ token_hash: enlace.properties.hashed_token, type: "magiclink" });
  if (e3 || !v?.session) return json({ ok: false, motivo: "No se pudo abrir la sesión." }, 500);

  // Token de admin también, por si el módulo abre a su vez pantallas de clave (p. ej. el panel admin del cotizador)
  let adminToken: string | null = null;
  if (a.rol === "admin" || a.rol === "asistente") {
    const { data: s } = await admin.from("admin_sesion").insert({}).select("token").single();
    adminToken = s?.token ?? null;
  }
  return json({ ok: true, tipo: "staff", usuario: { email: a.email, rol: a.rol }, sesion: v.session, admin_token: adminToken, modulo: a.modulo });
});

function limpiar(m: string) {
  return m.replace(/^.*?:\s*/, "").trim() || "Enlace inválido.";
}
