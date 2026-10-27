// Pruebas de la página del Test del Nivel 0 (public/test/index.html) con un Supabase simulado.
// Correr: node pruebas/prueba_test.js   (necesita jsdom: npm install jsdom)
const {JSDOM} = require('jsdom');
const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', 'public', 'test', 'index.html'), 'utf8');
const SB = 'https://kiexpdaaoegbtesqmaff.supabase.co';
const {servidor, CODIGO_ASESOR, CODIGO_STAFF} = require('./simulador_test');

let fallas = 0;
const ok = (c, t) => { console.log((c ? '✔ ' : '✗ ') + t); if (!c) fallas++; };
const espera = ms => new Promise(r => setTimeout(r, ms));

function crear({srv, hash = '', prep} = {}){
  srv = srv || servidor();
  const dom = new JSDOM(html, {runScripts: 'dangerously', pretendToBeVisual: true,
    url: 'https://renaware-plataforma.nelson1614.workers.dev/test/' + hash,
    beforeParse(w){
      w.scrollTo = () => {};
      w.HTMLElement.prototype.scrollIntoView = function () {};
      w.confirm = () => true;
      if (prep) prep(w);
      w.fetch = async (url, opts = {}) => {
        const u = String(url).replace(SB, '');
        const b = opts.body ? JSON.parse(opts.body) : {};
        const {st = 200, d} = await srv.manejar(u, b, opts.headers || {});
        const txt = d === undefined ? '' : JSON.stringify(d);
        return {ok: st < 400, status: st, text: async () => txt, json: async () => JSON.parse(txt)};
      };
    }});
  const w = dom.window;
  return {w, d: w.document, srv, S: srv.S};
}
const texto = d => d.getElementById('app').textContent;
const boton = (d, t) => [...d.querySelectorAll('button')].find(b => b.textContent.trim() === t);
const escribir = (w, el, v) => { el.value = v; el.dispatchEvent(new w.Event('input', {bubbles: true})); };
const elegir = (w, el, v) => { el.value = v; el.dispatchEvent(new w.Event('change', {bubbles: true})); };
const enviar = (w, d) => d.querySelector('form').dispatchEvent(new w.Event('submit', {bubbles: true, cancelable: true}));
const llamadas = (S, fn) => S.llamadas.filter(c => c.u === '/rest/v1/rpc/' + fn);

(async () => {
  // ---------- 1. Sin sesión: entra con el celular (solo test) ----------
  let {w, d, S} = crear();
  await espera(40);
  ok(d.querySelector('form.acceso') && texto(d).includes('Tu celular'), 'Sin sesión pide el celular');
  escribir(w, d.getElementById('cel'), '12345'); enviar(w, d); await espera(30);
  ok(texto(d).includes('9 dígitos'), 'Valida el celular de 9 dígitos');
  escribir(w, d.getElementById('cel'), '+51 900 947 503'); enviar(w, d); await espera(80);
  ok(llamadas(S, 'ts_login').pop().b.p_celular === '900947503', 'Normaliza el celular (+51 y espacios)');
  ok(JSON.parse(w.localStorage.getItem('rw_test_token')) === 'tok-test' && !w.localStorage.getItem('rw_asesor_token'),
    'Sesión solo para el test: va en rw_test_token, no toca la de la plataforma');
  ok(texto(d).includes('Hola, Fley') && texto(d).includes('¡Tu test está habilitado!'), 'Saluda y dice que su test está habilitado');
  ok(texto(d).includes('Tienes hasta el miércoles 11 de noviembre: quedan 15 días.'), 'Muestra el plazo con los días que quedan');
  ok(d.querySelector('.recursos a') && d.querySelector('.recursos a').href.startsWith('https://renaware-peru'), 'Muestra los enlaces para consultar');
  ok(boton(d, 'Salir'), 'Sin sesión de plataforma ofrece «Salir» (no «Inicio»)');

  // ---------- 2. Rinde el test: emparejar, falla una, multi, escribir ----------
  boton(d, 'Empezar el test').click(); await espera(60);
  ok(texto(d).includes('Pregunta 1 de 4') && texto(d).includes('Productos y precios'), 'Primera pregunta con su avance y bloque');
  const sels = d.querySelectorAll('.par select');
  ok(sels.length === 2 && d.querySelectorAll('.par img').length === 2, 'Emparejar: una foto y una lista por producto');
  const responder = () => boton(d, 'Responder');
  ok(responder().disabled, 'Responder empieza deshabilitado');
  elegir(w, sels[0], 'n2'); elegir(w, sels[1], 'n2');
  ok(responder().disabled && texto(d).includes('Cada nombre va con un solo producto'), 'No deja usar el mismo nombre dos veces');
  elegir(w, sels[1], 'n1');
  ok(!responder().disabled, 'Con todo elegido se puede responder');
  responder().click(); await espera(60);
  ok(texto(d).includes('¡Correcto!') && boton(d, 'Siguiente'), 'Acierta: ¡Correcto! y Siguiente');
  const env1 = llamadas(S, 'ts_responder').pop().b;
  ok(env1.p_respuesta.i1 === 'n2' && env1.p_respuesta.i2 === 'n1' && env1.p_token === 'tok-test', 'Envía el emparejamiento con su sesión');
  boton(d, 'Siguiente').click(); await espera(30);

  ok(texto(d).includes('Pregunta 2 de 4') && d.querySelector('.foto img') && texto(d).includes('Olla a Presión - 8 L'), 'Pregunta con foto y nombre del producto');
  const ops = () => [...d.querySelectorAll('.opcion')];
  ops()[0].click();
  ok(ops()[0].getAttribute('aria-checked') === 'true', 'Marca la opción elegida');
  responder().click(); await espera(60);
  ok(texto(d).includes('No es la respuesta.') && texto(d).includes('Cómo encontrarla: Búscalo en la lista de precio general.'), 'Falla: explica la lógica');
  ok(!texto(d).includes('S/ 3,229') || !ops().some(b => b.classList.contains('bien')), 'Al fallar no revela la correcta');
  ok(ops()[0].classList.contains('mal') && ops().every(b => b.disabled), 'Marca la elegida como incorrecta y bloquea las opciones');
  const idAntes = llamadas(S, 'ts_responder').pop().b.p_pregunta;
  boton(d, 'Otra pregunta').click(); await espera(30);
  ok(texto(d).includes('Pregunta 2 de 4') && texto(d).includes('1 de 2 bien'), 'Sale otra pregunta del mismo paso');
  ops()[1].click(); responder().click(); await espera(60);
  ok(llamadas(S, 'ts_responder').pop().b.p_pregunta !== idAntes, 'Responde la pregunta nueva, no la anterior');
  ok(texto(d).includes('¡Correcto!') && texto(d).includes('Dato curioso.'), 'Acierta y muestra el dato');
  boton(d, 'Siguiente').click(); await espera(30);

  ok(texto(d).includes('Marca todas las que correspondan.'), 'Multi: avisa que puede marcar varias');
  ops()[0].click(); ops()[2].click();
  ok(ops().filter(b => b.getAttribute('aria-checked') === 'true').length === 2, 'Multi: marca dos');
  responder().click(); await espera(60);
  ok(JSON.stringify(llamadas(S, 'ts_responder').pop().b.p_respuesta.sort()) === '["o1","o3"]', 'Multi: envía la lista de elegidas');
  boton(d, 'Siguiente').click(); await espera(30);

  const inp = d.querySelector('input[inputmode="numeric"]');
  ok(inp && texto(d).includes('Cuenta BCP'), 'Escribir: un campo por cuenta');
  escribir(w, inp, '194-1234567890'); responder().click(); await espera(60);
  ok(llamadas(S, 'ts_responder').pop().b.p_respuesta.c1 === '1941234567890', 'Escribir: envía solo los números');
  ok(boton(d, 'Ver mi nota'), 'La última pregunta lleva a «Ver mi nota»');
  boton(d, 'Ver mi nota').click(); await espera(30);
  ok(texto(d).includes('80') && texto(d).includes('Esta vez no llegaste') && texto(d).includes('apruebas con 90'), 'Final: nota 80, no aprueba');
  ok(texto(d).includes('Dónde fallaste') && boton(d, 'Intentar de nuevo'), 'Final: dónde falló y permite intentar de nuevo');

  // ---------- 3. Vuelve a intentar y aprueba sin errores ----------
  boton(d, 'Intentar de nuevo').click(); await espera(60);
  ok(texto(d).includes('Pregunta 1 de 4'), 'Nuevo intento desde la pregunta 1');
  async function bien(){
    const q = S.intento.q;
    if (q.tipo === 'emparejar') { const ss = d.querySelectorAll('.par select'); elegir(w, ss[0], 'n2'); elegir(w, ss[1], 'n1'); }
    if (q.tipo === 'single') ops().find(b => b.getAttribute('data-id') === q.clave[0]).click();
    if (q.tipo === 'multi') q.clave.forEach(id => ops().find(b => b.getAttribute('data-id') === id).click());
    if (q.tipo === 'escribir') escribir(w, d.querySelector('input[inputmode="numeric"]'), q.clave.c1[0]);
    responder().click(); await espera(50);
    (boton(d, 'Siguiente') || boton(d, 'Ver mi nota')).click(); await espera(30);
  }
  for (let i = 0; i < 4; i++) await bien();
  ok(texto(d).includes('¡Aprobaste!') && texto(d).includes('100') && texto(d).includes('botella de acero'), 'Aprueba con 100 y gana la botella');
  ok(!boton(d, 'Intentar de nuevo'), 'Aprobado: ya no ofrece intentar de nuevo');
  boton(d, 'Volver').click(); await espera(60);
  ok(texto(d).includes('¡Aprobaste tu test con 100! 🏆') && texto(d).includes('te espera en la oficina'), 'Estado aprobado: botella por recoger');
  ok(texto(d).includes('Tus intentos') && d.querySelectorAll('.historial li').length === 2, 'Historial con sus 2 intentos');

  // ---------- 3b. La oficina anula el intento mientras responde: vuelve a su estado con el aviso ----------
  {
    const s3 = servidor();
    const c3 = crear({srv: s3, prep: x => x.localStorage.setItem('rw_test_token', JSON.stringify('tok-test'))});
    await espera(50);
    boton(c3.d, 'Empezar el test').click(); await espera(60);
    await s3.manejar('/rest/v1/rpc/ts_admin_anular', {p_token: 'adm-1', p_intento: s3.S.intento.id}, {});
    const sl = c3.d.querySelectorAll('.par select'); elegir(c3.w, sl[0], 'n2'); elegir(c3.w, sl[1], 'n1');
    boton(c3.d, 'Responder').click(); await espera(80);
    ok(c3.d.getElementById('toast').textContent.includes('Ese intento se anuló') && boton(c3.d, 'Empezar el test'),
      'Intento anulado por la oficina: avisa y vuelve a su estado para empezar de nuevo');
  }

  // ---------- 3c. Enlaces de consulta: solo los http(s) ----------
  {
    const s4 = servidor({recursos: [{nombre: 'Malo', url: 'javascript:alert(1)'}, {nombre: 'Bueno', url: 'https://bien.example'}]});
    const c4 = crear({srv: s4, prep: x => x.localStorage.setItem('rw_test_token', JSON.stringify('tok-test'))});
    await espera(50);
    const as = c4.d.querySelectorAll('.recursos a');
    ok(as.length === 1 && as[0].textContent === 'Bueno', 'Enlaces de consulta: no muestra los que no son http(s)');
  }

  // ---------- 3d. Número bloqueado ----------
  {
    const c5 = crear();
    await espera(40);
    escribir(c5.w, c5.d.getElementById('cel'), '900000000'); enviar(c5.w, c5.d); await espera(60);
    ok(texto(c5.d).includes('Ese número está bloqueado') && !c5.w.localStorage.getItem('rw_test_token'), 'Número bloqueado: no entra');
  }

  // ---------- 4. Llega desde la plataforma con #traspaso y test a medias ----------
  const srv2 = servidor();
  srv2.S.intento = (() => { const it = {id: 'int-x', origen: 'asesor', plan: srv2.S.plan.slice(), idx: 1, intentos: 1, aciertos: 1, q: null, fin: null}; return it; })();
  srv2.S.intento.q = {id: 'q-99', paso: 'precio_general', tipo: 'single', texto: '¿Cuánto cuesta al contado?', opciones: [{id: 'o1', t: 'S/ 1'}], clave: ['o1'],
    bloque: 'productos', bloque_nombre: 'Productos y precios', logica: 'x'};
  ({w, d, S} = crear({srv: srv2, hash: '#traspaso=' + CODIGO_ASESOR}));
  await espera(80);
  ok(JSON.parse(w.localStorage.getItem('rw_asesor_token')) === 'tok-hub' && !w.location.hash.includes('traspaso'), 'Canjea el traspaso, guarda la sesión de la plataforma y limpia el enlace');
  ok(texto(d).includes('Tienes un test a medias') && texto(d).includes('Vas en la pregunta 2 de 4'), 'Ve su test a medias');
  ok(d.querySelector('a.lado') && d.querySelector('a.lado').getAttribute('href') === '/', 'Con sesión de plataforma ofrece volver al inicio');
  boton(d, 'Continuar mi test').click(); await espera(60);
  ok(texto(d).includes('Pregunta 2 de 4'), 'Continúa donde se quedó');
  boton(d, 'Salir y seguir después').click(); await espera(60);
  ok(texto(d).includes('Tienes un test a medias'), 'Sale y vuelve al estado sin perder el avance');

  // ---------- 5. Otros estados ----------
  for (const [estado, frase] of [['clases', 'Primero, tus 5 clases'], ['vencido', 'Tu plazo para el test venció'], ['no_inscrito', 'No encontramos tu inscripción'], ['excluido', 'no está habilitado']]) {
    const s = servidor({estado});
    ({w, d} = crear({srv: s, prep: x => x.localStorage.setItem('rw_test_token', JSON.stringify('tok-test'))}));
    await espera(50);
    ok(texto(d).includes(frase), `Estado ${estado}: «${frase}»`);
  }
  ({w, d} = crear({srv: servidor({estado: 'clases'}), prep: x => x.localStorage.setItem('rw_test_token', JSON.stringify('tok-test'))}));
  await espera(50);
  ok(texto(d).includes('Llevas 3 de 5 clases: te faltan 2.') && texto(d).includes('tendrás 15 días'), 'En clases: cuánto lleva y qué viene');

  // ---------- 6. Sesión vencida ----------
  ({w, d, S} = crear({prep: x => x.localStorage.setItem('rw_asesor_token', JSON.stringify('tok-viejo'))}));
  await espera(50);
  ok(d.querySelector('form.acceso') && texto(d).includes('Tu sesión venció'), 'Sesión vencida: pide entrar de nuevo');
  ok(!w.localStorage.getItem('rw_asesor_token'), 'Sesión vencida: borra el token');

  // ---------- 7. Oficina: traspaso de staff, resultados, persona, plazo ----------
  ({w, d, S} = crear({hash: '#traspaso=' + CODIGO_STAFF}));
  await espera(80);
  ok(JSON.parse(w.localStorage.getItem('rw_test_admin')) === 'adm-1', 'Staff: guarda la sesión de oficina del traspaso');
  ok(texto(d).includes('Test del Nivel 0 · Oficina') && d.querySelectorAll('.pestanas button').length === 4, 'Oficina con sus 4 pestañas');
  ok(texto(d).includes('con el test habilitado · 1 vence en 3 días o menos') && texto(d).includes('1 botella por entregar'), 'Cifras: habilitados que vencen y botellas por entregar');
  ok(texto(d).includes('Dónde fallan más') && texto(d).includes('30 % (3 de 10)'), 'Dónde fallan más, por bloque');
  ok(texto(d).includes('Fley Elvis Medina Soto') && texto(d).includes('hasta el 11/11 (quedan 2 días)'), 'Lista de personas con su plazo');
  const fila = [...d.querySelectorAll('.persona > button')].find(b => b.textContent.includes('Fley'));
  fila.click(); await espera(20);
  ok(texto(d).includes('Intentos') && texto(d).includes('80 · no aprobado') && texto(d).includes('Falló en Productos y precios: 1'), 'Detalle: intentos y dónde falló');
  ok(d.activeElement && d.activeElement.getAttribute('data-foco') === 'p-p1', 'Al abrir la ficha el foco se queda en la persona');
  boton(d, 'Ver respuestas').click(); await espera(40);
  ok(d.querySelectorAll('.respuestas li').length === 2, 'Ver respuestas de un intento');
  const fechaPlazo = d.querySelector('.detalle input[type="date"]');
  ok(texto(d).includes('Su plazo normal termina el 11/11'), 'Dice cuándo termina su plazo normal');
  const antes = llamadas(S, 'ts_admin_persona').length;
  fechaPlazo.value = '';
  boton(d, 'Guardar plazo').click(); await espera(40);
  ok(llamadas(S, 'ts_admin_persona').length === antes && d.getElementById('toast').textContent.includes('Elige la fecha'),
    'Plazo sin fecha: no lo guarda y pide la fecha');
  fechaPlazo.value = '2026-11-20';
  boton(d, 'Guardar plazo').click(); await espera(60);
  const cambio = llamadas(S, 'ts_admin_persona').pop().b;
  ok(cambio.p_inscrito === 'p1' && cambio.p_cambios.hasta === '2026-11-20' && cambio.p_token === 'adm-1', 'Cambia el plazo de la persona');

  // Preguntas: apagar un paso
  boton(d, 'Preguntas').click(); await espera(20);
  ok(texto(d).includes('sale cuando cargues las cuentas en Ajustes') && texto(d).includes('2 variantes'), 'Preguntas: notas de cada paso');
  d.querySelector('.interruptor[data-foco="sw-obj_caro"]').click(); await espera(60);
  const paso = llamadas(S, 'ts_admin_paso').pop().b;
  ok(paso.p_clave === 'obj_caro' && paso.p_activo === false, 'Apaga un paso');

  // Ajustes: cuentas y enlaces
  boton(d, 'Ajustes').click(); await espera(20);
  boton(d, 'Agregar cuenta').click(); await espera(10);
  const fe = d.querySelector('.fila-edit');
  escribir(w, fe.querySelector('input'), 'BCP');
  escribir(w, fe.querySelector('textarea'), '194-12345678-0-12\n002-194-012345678012-34\nx');
  boton(d, 'Agregar enlace').click(); await espera(10);
  const filas = d.querySelectorAll('.fila-edit'), fr = filas[filas.length - 1];
  escribir(w, fr.querySelectorAll('input')[0], 'Zonas de crédito'); escribir(w, fr.querySelectorAll('input')[1], 'https://zonas.example');
  escribir(w, d.getElementById('a-nota'), '91');
  boton(d, 'Guardar ajustes').click(); await espera(60);
  const aj = llamadas(S, 'ts_admin_config').pop().b.p_cambios;
  ok(aj.nota_minima === 91 && aj.cuentas.length === 1 && aj.cuentas[0].validos.join() === '19412345678012,00219401234567801234', 'Guarda nota y cuentas solo con números');
  ok(aj.recursos.length === 2 && aj.recursos[1].url === 'https://zonas.example', 'Guarda los enlaces de consulta');

  // Probar: práctica con las funciones de oficina
  boton(d, 'Probar').click(); await espera(20);
  boton(d, 'Empezar una práctica').click(); await espera(60);
  ok(texto(d).includes('Práctica de la oficina') && texto(d).includes('Pregunta 1 de 4'), 'Práctica: mismo test');
  const ss = d.querySelectorAll('.par select'); elegir(w, ss[0], 'n2'); elegir(w, ss[1], 'n1');
  responder().click(); await espera(60);
  ok(llamadas(S, 'ts_admin_responder').length === 1 && llamadas(S, 'ts_responder').length === 0, 'Práctica: responde por ts_admin_responder');
  boton(d, 'Siguiente').click(); await espera(20);
  boton(d, 'Volver a la oficina').click(); await espera(60);
  ok(texto(d).includes('Rinde el test como un asesor') && texto(d).includes('Prácticas hechas: 1'), 'Vuelve a la oficina');

  // ---------- 8. Oficina con la sesión de correo de la plataforma (mismo dominio) ----------
  ({w, d, S} = crear({hash: '#oficina', prep: x => x.localStorage.setItem('sb-kiexpdaaoegbtesqmaff-auth-token',
    JSON.stringify({access_token: 'jwt-1', refresh_token: 'r', expires_at: Math.floor(Date.now() / 1000) + 3600}))}));
  await espera(80);
  ok(llamadas(S, 'traspaso_crear').length === 1 && texto(d).includes('Test del Nivel 0 · Oficina'), 'Equipo con sesión de la plataforma entra sin clave');

  // ---------- 9. Oficina con clave ----------
  ({w, d, S} = crear({hash: '#oficina'}));
  await espera(40);
  ok(texto(d).includes('Test del Nivel 0 · Oficina') && d.getElementById('clave'), '#oficina sin sesión pide la clave');
  d.getElementById('clave').value = 'mala'; enviar(w, d); await espera(50);
  ok(texto(d).includes('Esa clave no es correcta.'), 'Clave mala: lo dice');
  d.getElementById('clave').value = 'clave'; enviar(w, d); await espera(80);
  ok(texto(d).includes('Dónde fallan más'), 'Clave buena: entra a la oficina');

  console.log(fallas ? `\n${fallas} prueba(s) fallaron` : '\nTodo bien');
  process.exit(fallas ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
