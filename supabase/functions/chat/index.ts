// Edge Function "chat": el motor del chat de la plataforma ("Pregúntale").
//
// Recibe una pregunta con la sesión de correo de la plataforma (Bearer <jwt del usuario>),
// pide a la base el catálogo de herramientas que ese rol puede usar (chat_catalogo),
// corre el ciclo pregunta → herramienta → respuesta con la API de Claude y guarda
// la conversación (chat_mensaje_guardar). Cada herramienta se ejecuta en la base con
// chat_ejecutar, dentro de una transacción de solo lectura: el modelo nunca escribe.
//
// Se despliega sin verificación de JWT en la puerta porque la verificación la hace la
// base en cada llamada: todas las funciones chat_* exigen auth.uid() con un perfil activo
// (misma identidad que el hub). Secretos: ANTHROPIC_API_KEY (Edge Functions → Secrets).
//
// POST { proyecto?: "renaware", conversacion_id?: uuid, mensaje: string }
// → { ok, conversacion_id, respuesta, herramientas: [{nombre, args, filas, ms, error}], sin_datos, uso, ms, pasos }
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
const DIAS = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
function fechaLarga(iso: string) {
  const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number);
  const f = new Date(Date.UTC(y, m - 1, d));
  return `${DIAS[f.getUTCDay()]} ${d} de ${MESES[m - 1]} de ${y}`;
}
function limpiar(m: string) {
  return String(m || "").replace(/^.*?:\s*/, "").trim() || "Algo falló.";
}

type Msg = { role: "user" | "assistant"; content: unknown };
// La API pide turnos alternados que empiecen por el usuario: se unen seguidos del mismo rol.
function normalizar(msgs: Msg[]): Msg[] {
  const out: Msg[] = [];
  for (const m of msgs) {
    if (!out.length && m.role !== "user") continue;
    const u = out[out.length - 1];
    if (u && u.role === m.role && typeof u.content === "string" && typeof m.content === "string") {
      u.content = u.content + "\n\n" + m.content;
    } else out.push({ role: m.role, content: m.content });
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, motivo: "Método no permitido." }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";

  // 1) La sesión del hub viaja como Bearer; la base decide si vale.
  const jwt = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!jwt || jwt === anon) return json({ ok: false, motivo: "Entra a la plataforma para usar el chat." }, 401);
  const db = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 2) Qué pregunta
  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* sin cuerpo */ }
  const proyecto = String(body.proyecto || "renaware");
  const mensaje = String(body.mensaje || "").trim();
  let convId = typeof body.conversacion_id === "string" && /^[0-9a-f-]{36}$/i.test(body.conversacion_id) ? body.conversacion_id : null;
  if (!mensaje) return json({ ok: false, motivo: "Escribe una pregunta." }, 400);
  if (mensaje.length > 4000) return json({ ok: false, motivo: "La pregunta es muy larga (máximo 4000 caracteres)." }, 400);

  // 3) Catálogo: herramientas que este rol puede usar + prompt del proyecto (valida la sesión)
  const { data: cat, error: e0 } = await db.rpc("chat_catalogo", { p_proyecto: proyecto });
  if (e0 || !cat?.quien) {
    const m = e0?.message || "";
    const vencida = /Sin sesión|JWT|jwt|expired|invalid/i.test(m) || !cat?.quien;
    return json({ ok: false, motivo: vencida ? "Tu sesión venció. Vuelve a entrar a la plataforma." : limpiar(m) }, 401);
  }
  if (!apiKey) {
    return json({ ok: false, motivo: "Falta la clave de la API de Anthropic: en Supabase → Edge Functions → Secrets crea ANTHROPIC_API_KEY." }, 503);
  }

  // 4) Conversación: nueva o existente; se guarda la pregunta antes de responder.
  if (!convId) {
    const { data, error } = await db.rpc("chat_conversacion_iniciar", { p_proyecto: proyecto, p_titulo: mensaje.slice(0, 80) });
    if (error || !data) return json({ ok: false, motivo: "No se pudo abrir la conversación: " + limpiar(error?.message || "") }, 500);
    convId = data as string;
  }
  const { data: hist, error: e1 } = await db.rpc("chat_conversacion_mensajes", { p_conversacion: convId, p_limite: 20 });
  if (e1) return json({ ok: false, motivo: "No se pudo leer la conversación: " + limpiar(e1.message) }, 400);
  const { error: e2 } = await db.rpc("chat_mensaje_guardar", { p_conversacion: convId, p_rol: "user", p_contenido: mensaje });
  if (e2) return json({ ok: false, motivo: "No se pudo guardar la pregunta: " + limpiar(e2.message) }, 400);

  const previos: Msg[] = [];
  for (const m of (hist as Array<{ rol: string; contenido: string }>) ?? []) {
    if ((m.rol === "user" || m.rol === "assistant") && m.contenido) previos.push({ role: m.rol, content: m.contenido });
  }
  const messages = normalizar([...previos, { role: "user", content: mensaje }]);

  // 5) El mensaje del sistema: las reglas del proyecto + el contexto del momento.
  const p = cat.proyecto;
  const contexto = [
    `Hoy es ${fechaLarga(cat.hoy)}, ${cat.hora_lima} hora de Lima.`,
    `Período actual: PB${String(cat.periodo.pb).padStart(2, "0")}-${cat.periodo.anio}, del ${cat.periodo.inicio} al ${cat.periodo.fin}.`,
    `Quien pregunta: ${cat.quien.nombre} (rol ${cat.quien.rol}).`,
    Array.isArray(cat.fichas_temas) && cat.fichas_temas.length ? `Temas con fichas: ${cat.fichas_temas.join(", ")}.` : "",
  ].filter(Boolean).join(" ");
  const system = [
    { type: "text", text: String(p.instrucciones), cache_control: { type: "ephemeral" } },
    { type: "text", text: contexto },
  ];
  const tools = Array.isArray(cat.herramientas) ? cat.herramientas : [];
  const maxPasos = Math.max(1, Math.min(Number(p.max_pasos) || 8, 12));

  // 6) El ciclo: Claude pide herramientas, la base responde, hasta que Claude contesta.
  const t0 = Date.now();
  const trace: Array<Record<string, unknown>> = [];
  let tokensIn = 0, tokensOut = 0, pasos = 0, texto = "", stop = "";
  while (pasos < maxPasos) {
    pasos++;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 90_000);
    let r: Response, data: Record<string, any>;
    try {
      r = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: p.modelo, max_tokens: Number(p.max_tokens) || 1500, system, tools, messages }),
        signal: ctrl.signal,
      });
      data = await r.json();
    } catch (e) {
      clearTimeout(timer);
      return json({ ok: false, conversacion_id: convId, motivo: "No se pudo hablar con la API de Claude: " + String((e as Error)?.message || e) }, 502);
    }
    clearTimeout(timer);
    if (!r.ok) {
      const detalle = data?.error?.message || `HTTP ${r.status}`;
      return json({ ok: false, conversacion_id: convId, motivo: `La API de Claude respondió con error: ${detalle}` }, 502);
    }
    tokensIn += (data.usage?.input_tokens ?? 0) + (data.usage?.cache_creation_input_tokens ?? 0) + (data.usage?.cache_read_input_tokens ?? 0);
    tokensOut += data.usage?.output_tokens ?? 0;
    const content: Array<Record<string, any>> = Array.isArray(data.content) ? data.content : [];
    const usos = content.filter((b) => b.type === "tool_use");
    if (data.stop_reason === "tool_use" && usos.length) {
      messages.push({ role: "assistant", content });
      const resultados: Array<Record<string, unknown>> = [];
      for (const tu of usos) {
        const t1 = Date.now();
        const { data: res, error } = await db.rpc("chat_ejecutar", { p_proyecto: proyecto, p_herramienta: tu.name, p_args: tu.input ?? {} });
        const out = error ? { ok: false, error: limpiar(error.message) } : (res ?? { ok: false, error: "Sin respuesta de la base." });
        let txt = JSON.stringify(out);
        if (txt.length > 70_000) txt = txt.slice(0, 70_000) + "…(recortado: pide menos filas o columnas)";
        resultados.push({ type: "tool_result", tool_use_id: tu.id, content: txt, is_error: !out.ok });
        trace.push({ nombre: tu.name, args: tu.input ?? {}, filas: out.filas ?? null, ms: out.ms ?? (Date.now() - t1), error: out.ok ? null : (out.error || "error") });
      }
      messages.push({ role: "user", content: resultados });
      continue;
    }
    texto = content.filter((b) => b.type === "text").map((b) => String(b.text || "")).join("\n").trim();
    stop = String(data.stop_reason || "");
    break;
  }
  if (!texto) {
    texto = pasos >= maxPasos
      ? "Consulté la base varias veces y no llegué a una respuesta completa. Intenta precisar la pregunta (período, persona o lista)."
      : "No obtuve respuesta del modelo. Intenta de nuevo.";
  }
  if (stop === "max_tokens") texto += "\n\n(La respuesta se cortó por longitud; pide el detalle por partes.)";
  const sinDatos = /\[SIN_DATOS\]/.test(texto);
  texto = texto.replace(/\s*\[SIN_DATOS\]\s*/g, " ").trim();

  // 7) Guardar la respuesta con lo que consultó, para el historial y para la lista de preguntas sin respuesta.
  const ms = Date.now() - t0;
  await db.rpc("chat_mensaje_guardar", {
    p_conversacion: convId, p_rol: "assistant", p_contenido: texto, p_herramientas: trace,
    p_meta: { sin_respuesta: sinDatos, modelo: p.modelo, tokens_in: tokensIn, tokens_out: tokensOut, ms },
  });

  return json({ ok: true, conversacion_id: convId, respuesta: texto, herramientas: trace, sin_datos: sinDatos,
                uso: { entrada: tokensIn, salida: tokensOut }, ms, pasos, modelo: p.modelo });
});
