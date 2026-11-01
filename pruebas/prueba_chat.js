// Pruebas del chat (/chat/) con un Supabase simulado. Correr: node pruebas/prueba_chat.js
// (necesita jsdom: npm install jsdom). El simulador rechaza toda escritura directa a tablas,
// igual que las políticas reales: el chat solo puede hablar por RPC y por la Edge Function.
const {JSDOM} = require('jsdom');
const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', 'public', 'chat', 'index.html'), 'utf8');
const SB = 'https://kiexpdaaoegbtesqmaff.supabase.co';
const K_STAFF = 'sb-kiexpdaaoegbtesqmaff-auth-token';
const CONV = '6b2a9e1c-3f4d-4a5b-8c6d-0123456789ab';

let fallas = 0;
const ok = (c, t) => { console.log((c ? '✔ ' : '✗ ') + t); if (!c) fallas++; };
const espera = ms => new Promise(r => setTimeout(r, ms));

const RESPUESTA = {
  ok: true, conversacion_id: CONV, pasos: 2, ms: 1800, modelo: 'claude-sonnet-5-5', uso: {entrada: 1200, salida: 90},
  respuesta: 'El **Especial #16** cuesta S/ 9,079 y da 1,457 puntos.\n\n- Lista: Especiales para Compartir (vigente hasta el 11 de nov)\n- Autocompra: S/ 7,992.67\n\nSegún la lista vigente del cotizador.',
  herramientas: [{nombre: 'precios_buscar', args: {q: 'especial 16'}, filas: 1, ms: 27, error: null}],
  sin_datos: false,
};

function crear({sesion = true, chat = () => [RESPUESTA, 200], guardada = []} = {}){
  const llamadas = [];
  const dom = new JSDOM(html, {runScripts: 'dangerously', pretendToBeVisual: true, url: 'https://plataforma.nelson1614.workers.dev/chat/',
    beforeParse(w){
      w.scrollTo = () => {};
      w.requestAnimationFrame = f => setTimeout(f, 0);
      if (sesion) w.localStorage.setItem(K_STAFF, JSON.stringify({access_token: 'jwt-1', refresh_token: 'r1', expires_at: Math.floor(Date.now() / 1000) + 3600}));
      w.fetch = async (url, opts = {}) => {
        const u = String(url).replace(SB, ''); llamadas.push({u, opts});
        const r = (data, status = 200) => ({ok: status < 400, status, text: async () => data === undefined ? '' : JSON.stringify(data)});
        const auth = (opts.headers || {}).Authorization || '';
        const b = opts.body ? JSON.parse(opts.body) : {};
        if (!auth.includes('jwt-')) return r({message: 'JWT expired'}, 401);
        if (u.startsWith('/rest/v1/rpc/mi_perfil')) return r({rol: 'admin', nombre: 'Nelson Portugal Román', activo: true});
        if (u.startsWith('/rest/v1/rpc/chat_conversacion_mensajes')) return r(b.p_conversacion === CONV ? guardada : []);
        if (u.startsWith('/rest/v1/rpc/chat_conversaciones_lista')) return r([{id: CONV, titulo: '¿Cuánto cuesta el Especial 16?', actualizado_en: '2026-10-31T21:00:00Z', mensajes: 2, rol: 'admin'}]);
        if (u.startsWith('/rest/v1/rpc/chat_conversacion_archivar')) return r(true);
        if (u.startsWith('/functions/v1/chat')) { await espera(60); const [data, status] = chat(b); return r(data, status); }   // tarda, como la real
        if (u.startsWith('/rest/v1/')) return r({message: 'escritura directa rechazada (RLS) ' + u}, 401);   // regla 3 de la plataforma
        return r({message: 'sin mock ' + u}, 404);
      };
    }});
  return {w: dom.window, d: dom.window.document, llamadas};
}
const escribir = (w, el, v) => { el.value = v; el.dispatchEvent(new w.Event('input', {bubbles: true})); };
const enviar = (w, d) => d.getElementById('form').dispatchEvent(new w.Event('submit', {bubbles: true, cancelable: true}));

(async () => {
  // ---- Sin sesión: no deja escribir y manda a la plataforma ----
  let t = crear({sesion: false});
  await espera(50);
  ok(t.d.querySelector('.acceso') && t.d.getElementById('redactar').classList.contains('oculto'), 'Sin sesión muestra el acceso y esconde la caja');
  ok(t.d.querySelector('.acceso a').getAttribute('href') === '../', 'El botón lleva al inicio de la plataforma');

  // ---- Con sesión: sugerencias, pregunta, respuesta con herramientas ----
  t = crear();
  await espera(60);
  ok(t.d.getElementById('quien').textContent === 'Nelson · admin', 'Saluda con el nombre y el rol de la sesión del hub');
  ok(t.d.querySelectorAll('.sugerencia').length === 6, 'Sin conversación muestra las sugerencias');
  escribir(t.w, t.d.getElementById('pregunta'), '¿Cuánto cuesta el Especial 16?'); enviar(t.w, t.d);
  await espera(30);
  ok(t.d.querySelector('.msg.yo') && t.d.querySelector('.pensando'), 'Muestra la pregunta y el estado "consultando"');
  await espera(80);
  const chat = t.llamadas.find(l => l.u.startsWith('/functions/v1/chat'));
  ok(chat && chat.opts.headers.Authorization === 'Bearer jwt-1' && JSON.parse(chat.opts.body).mensaje === '¿Cuánto cuesta el Especial 16?', 'Llama a la Edge Function con la sesión del hub');
  ok(JSON.parse(chat.opts.body).conversacion_id === null, 'La primera pregunta no manda conversación (la crea la función)');
  const resp = t.d.querySelector('.msg.chat:not(.pensando)');
  ok(resp && resp.querySelector('strong') && resp.querySelector('strong').textContent === 'Especial #16', 'Pinta la respuesta con negritas');
  ok(resp && resp.querySelectorAll('li').length === 2, 'Pinta la lista de la respuesta');
  ok(resp && resp.querySelector('.chip') && resp.querySelector('.chip').textContent === 'precios_buscar · 1', 'Muestra qué herramienta consultó y cuántas filas');
  resp.querySelector('.chip').click();
  ok(!resp.querySelector('.detalle').classList.contains('oculto') && resp.querySelector('.detalle').textContent.includes('"q":"especial 16"'), 'Al tocar el chip se ven los argumentos');
  ok(t.w.localStorage.getItem('rw_chat_conversacion') === JSON.stringify(CONV), 'Recuerda la conversación abierta');
  ok(!t.d.querySelector('.msg.chat script') && !t.d.querySelector('.msg.chat img'), 'No inyecta HTML');

  // Segunda pregunta en la misma conversación
  escribir(t.w, t.d.getElementById('pregunta'), '¿y el 17?'); enviar(t.w, t.d);
  await espera(100);
  const chat2 = t.llamadas.filter(l => l.u.startsWith('/functions/v1/chat'))[1];
  ok(chat2 && JSON.parse(chat2.opts.body).conversacion_id === CONV, 'La segunda pregunta sigue en la misma conversación');
  ok(t.d.querySelectorAll('.msg.yo').length === 2 && t.d.querySelectorAll('.msg.chat').length === 2, 'El hilo acumula preguntas y respuestas');

  // Nueva conversación
  t.d.getElementById('btn-nueva').click();
  await espera(20);
  ok(t.d.querySelectorAll('.sugerencia').length === 6 && t.w.localStorage.getItem('rw_chat_conversacion') === null, '"Nueva" vacía el hilo y olvida la conversación');

  // Lista de conversaciones y volver a abrir una guardada
  t.d.getElementById('btn-convs').click();
  await espera(60);
  ok(!t.d.getElementById('panel').classList.contains('oculto') && t.d.querySelector('.convs strong').textContent === '¿Cuánto cuesta el Especial 16?', 'Lista las conversaciones guardadas');

  // ---- Respuesta sin datos y respuesta con error ----
  t = crear({chat: b => [{...RESPUESTA, respuesta: 'No tengo esa información en la plataforma.', herramientas: [{nombre: 'sql_lectura', args: {consulta: 'select 1'}, filas: null, ms: 5, error: 'La consulta toca credenciales'}], sin_datos: true}, 200]});
  await espera(60);
  escribir(t.w, t.d.getElementById('pregunta'), 'algo raro'); enviar(t.w, t.d);
  await espera(100);
  ok(t.d.querySelector('.sin-datos') && t.d.querySelector('.chip.err'), 'Marca la respuesta sin datos y la herramienta que falló');

  t = crear({chat: () => [{ok: false, motivo: 'Falta la clave de la API de Anthropic: en Supabase → Edge Functions → Secrets crea ANTHROPIC_API_KEY.'}, 503]});
  await espera(60);
  escribir(t.w, t.d.getElementById('pregunta'), 'hola'); enviar(t.w, t.d);
  await espera(100);
  ok(t.d.querySelector('.msg.chat.error') && t.d.querySelector('.msg.chat.error').textContent.includes('ANTHROPIC_API_KEY'), 'Un error de la función se muestra tal cual');
  ok(!t.d.getElementById('enviar').disabled, 'Tras el error se puede volver a preguntar');

  // ---- Sesión vencida en medio: manda al acceso ----
  t = crear({chat: () => [{ok: false, motivo: 'Tu sesión venció. Vuelve a entrar a la plataforma.'}, 401]});
  await espera(60);
  escribir(t.w, t.d.getElementById('pregunta'), 'hola'); enviar(t.w, t.d);
  await espera(100);
  ok(t.d.querySelector('.acceso'), 'Si la sesión venció, vuelve a pedir entrar a la plataforma');

  // ---- Abre una conversación guardada al cargar ----
  t = crear({guardada: [
    {id: 1, rol: 'user', contenido: 'hola', herramientas: null, sin_respuesta: false, creado_en: '2026-10-31T20:00:00Z'},
    {id: 2, rol: 'assistant', contenido: 'Hola. ¿Qué necesitas?', herramientas: [], sin_respuesta: false, creado_en: '2026-10-31T20:00:03Z'}]});
  t.w.localStorage.setItem('rw_chat_conversacion', JSON.stringify(CONV));
  await espera(40);
  // (el arranque corre antes de poder poner el localStorage; se simula recargando la conversación)
  t.w.document.getElementById('btn-convs').click();
  await espera(60);
  t.d.querySelector('.convs button.abrir').click();
  await espera(80);
  ok(t.d.querySelectorAll('.msg').length === 2 && t.d.querySelector('.msg.chat .texto').textContent === 'Hola. ¿Qué necesitas?', 'Al abrir una conversación guardada pinta su historial');

  // ---- Ninguna escritura directa a tablas ----
  const directas = t.llamadas.filter(l => /^\/rest\/v1\/(?!rpc\/)/.test(l.u));
  ok(directas.length === 0, 'El chat nunca escribe ni lee tablas directo (todo por RPC o la función)');

  console.log(fallas ? `\n${fallas} prueba(s) fallaron` : '\nTodo en orden');
  process.exit(fallas ? 1 : 0);
})();
