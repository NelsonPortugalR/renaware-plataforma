// Edge Function "traspaso": canjea un código de un solo uso del hub por la
// credencial que usa cada módulo. Se despliega con verify_jwt = false (los
// módulos la llaman antes de tener sesión); la seguridad está en el código:
// uuid aleatorio, un solo uso, vence a los 2 minutos.
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

  const { data, error } = await admin.rpc("traspaso_consumir", { p_codigo: codigo });
  if (error) return json({ ok: false, motivo: "No se pudo validar el enlace." }, 500);
  if (!data?.ok) return json({ ok: false, motivo: data?.motivo ?? "Enlace inválido." }, 401);

  if (data.tipo === "asesor") {
    return json({ ok: true, tipo: "asesor", token: data.token, nombre: data.nombre, celular: data.celular });
  }

  // Staff: una sesión propia de Supabase para el módulo (su propia familia de
  // refresh tokens, así no se pisa con la del hub).
  const { data: enlace, error: e1 } = await admin.auth.admin.generateLink({ type: "magiclink", email: data.email });
  if (e1 || !enlace?.properties?.hashed_token) return json({ ok: false, motivo: "No se pudo crear la sesión." }, 500);
  const cliente = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: v, error: e2 } = await cliente.auth.verifyOtp({ token_hash: enlace.properties.hashed_token, type: "magiclink" });
  if (e2 || !v?.session) return json({ ok: false, motivo: "No se pudo abrir la sesión." }, 500);

  return json({
    ok: true,
    tipo: "staff",
    usuario: { email: data.email, nombre: data.nombre, rol: data.rol },
    sesion: v.session,            // access_token, refresh_token, expires_in, expires_at, token_type, user
    admin_token: data.admin_token, // para los módulos que validan con es_admin
    destino: data.destino,
  });
});
