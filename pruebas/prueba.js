// Pruebas del hub con un Supabase simulado. Correr: node pruebas/prueba.js
// (necesita jsdom: npm install jsdom)
const {JSDOM, VirtualConsole} = require('jsdom');
// jsdom no sabe navegar a otra página: ese aviso no es una falla (el enlace libre sí navega en el navegador)
const consola = new VirtualConsole(); consola.sendTo(console, {omitJSDOMErrors: true});
consola.on('jsdomError', e => { if (!/navigation/i.test(e.message)) console.error(e); });
const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8');
const SB = 'https://kiexpdaaoegbtesqmaff.supabase.co';
const K_STAFF = 'sb-kiexpdaaoegbtesqmaff-auth-token';
const CODIGO = '2f6d1d8e-0a9b-4c2e-9f1a-123456789abc';
// Lo que devuelve plataforma_menu(): ya filtrado por rol y por condición (test solo en Nivel Cero, local solo socias)
const MODS = [
  {id:'chat',nombre:'Pregúntale',descripcion:'Pregunta en tus palabras.',url:'/chat/',roles:['admin'],orden:0,acceso:'hub',grupo:'Vender'},
  {id:'cotizador',nombre:'Precios y promociones',descripcion:'Listas.',url:'https://renaware-peru.nelson1614.workers.dev',roles:['admin','asistente','gestor','asesor'],orden:1,acceso:'asesor',grupo:'Vender'},
  {id:'zonas',nombre:'Zonas de crédito',descripcion:'Dónde sí hay crédito y dónde no.',url:'https://zonas-de-credito.nelson1614.workers.dev',roles:['admin','asistente','gestor','asesor'],orden:2,acceso:'libre',grupo:'Vender'},
  {id:'registro',nombre:'Registrar venta o afiliado',descripcion:'Formulario.',url:'https://renaware-registro.nelson1614.workers.dev',roles:['admin','asistente'],orden:3,acceso:'libre',grupo:'Vender'},
  {id:'admin-registros',nombre:'Pedidos y afiliaciones',descripcion:'Revisar.',url:'https://renaware-registro.nelson1614.workers.dev/admin',roles:['admin','asistente'],orden:11,acceso:'supabase',grupo:'Pedidos'},
  {id:'importar-pedidos',nombre:'Subir reporte de Rena Ware',descripcion:'Carga.',url:'#importar',roles:['admin','asistente'],orden:13,acceso:'hub',grupo:'Pedidos'},
  {id:'premios',nombre:'Premios',descripcion:'Premios.',url:'https://panel-equipo.pages.dev',roles:['admin','asistente'],orden:21,acceso:'supabase',grupo:'Equipo'},
  {id:'empiece-ya',nombre:'Ganadores Empiece Ya',descripcion:'Ganadores.',url:'https://empiece-ya.nelson1614.workers.dev',roles:['admin','asistente'],orden:22,acceso:'libre',grupo:'Equipo'},
  {id:'test',nombre:'Test del Nivel 0',descripcion:'Test.',url:'https://renaware-plataforma.nelson1614.workers.dev/test/',roles:['admin','asistente','asesor'],orden:24,acceso:'asesor',grupo:'Equipo'},
  {id:'local',nombre:'Local del equipo',descripcion:'Turnos.',url:'https://local-equipo-arequipa.nelson1614.workers.dev',roles:['admin','asistente','asesor'],orden:26,acceso:'libre',grupo:'Equipo'},
  {id:'vigencia',nombre:'Vigencia de los datos',descripcion:'Qué toca volver a subir y cuándo vence.',url:'#vigencia',roles:['admin','asistente'],orden:30,acceso:'hub',grupo:'Oficina'},
  {id:'facturacion',nombre:'Facturación',descripcion:'Facturas.',url:'https://renaware-facturacion.pages.dev',roles:['admin','gestor'],orden:32,acceso:'supabase',grupo:'Oficina'},
  {id:'sin-grupo',nombre:'Herramienta nueva',descripcion:'Recién registrada, sin grupo.',url:'https://nueva.nelson1614.workers.dev',roles:['admin'],orden:40,acceso:'libre',grupo:null}];
const MENU_STAFF = MODS.filter(m => m.roles.includes('admin'));
// Para la asesora, lo que la base decidió mostrarle (las pruebas lo cambian)
let MENU_ASESOR = MODS.filter(m => ['cotizador', 'zonas'].includes(m.id));
// Lo que devuelve plataforma_fuentes_estado(): el catálogo de lo que alimenta la plataforma, ya evaluado por la base
const FUENTES = [
  {id:'listas-precios',nombre:'Listas de precios y promociones',accion:'Sube las listas nuevas en Precios y promociones.',modulo:'cotizador',cadencia:'vigencia',cadencia_texto:'Mientras dure lo cargado',ultima_texto:'Última vez: 01/10/2026',vence:'2026-11-11',dias:8,estado:'al_dia',estado_texto:'Al día hasta el 11 de noviembre.',extra:null,detalle:'Al día hasta el 11 de noviembre.',en_hoy:true},
  {id:'reporte-aurora',nombre:'Reporte Aurora (montos y pendientes por facturar)',accion:'Sube en Facturación el reporte Aurora del período.',modulo:'facturacion',cadencia:'periodo',cadencia_texto:'Cada período, 3 días después del cierre',ultima_texto:'Último cargado: PB21',vence:'2026-10-31',dias:-3,estado:'vencido',estado_texto:'Venció el 31 de octubre (hace 3 días).',extra:'Falta el PB22.',detalle:'Venció el 31 de octubre (hace 3 días). Falta el PB22.',en_hoy:true},
  {id:'resultados-premios',nombre:'Resultados de los programas de premios',accion:'Descarga de RenaKit los resultados y súbelos en Premios.',modulo:'premios',cadencia:'periodo',cadencia_texto:'Cada período, 7 días después del cierre',ultima_texto:'Último cargado: PB21',vence:'2026-11-04',dias:1,estado:'por_vencer',estado_texto:'Vence mañana.',extra:'Falta el PB22.',detalle:'Vence mañana. Falta el PB22.',en_hoy:true},
  {id:'fichas-chat',nombre:'Fichas del chat con fecha de vigencia',accion:'Actualiza lo que venció.',modulo:'chat',cadencia:'vigencia',cadencia_texto:'Mientras dure lo cargado',ultima_texto:null,vence:null,dias:null,estado:'al_dia',estado_texto:'Al día.',extra:null,detalle:'Al día.',en_hoy:true},
  {id:'rota',nombre:'Fuente con SQL roto',accion:'Arregla el SQL.',modulo:'premios',cadencia:'vigencia',cadencia_texto:'Mientras dure lo cargado',ultima_texto:null,vence:null,dias:null,estado:'error',estado_texto:'No se pudo calcular: relation x',extra:null,detalle:'No se pudo calcular: relation x',en_hoy:true}];
// Lo que devuelve ts_estado al asesor (null = no responde, como hoy en las pruebas viejas)
let TEST = null;
const HOY = {rol:'admin', nombre:'Nelson Portugal Román',
  periodo:{numero:22,inicio:'2026-10-15',fin:'2026-10-28',hoy:'2026-10-21'}, oficial:{pb:19,puntos:5684,pedidos:14},
  items:[
    {id:'registros-sin-revisar',nivel:'alto',enlace:'admin-registros',modulo:'Pedidos',titulo:'82 registros sin revisar',detalle:'x'},
    {id:'reporte-rw',nivel:'alto',modulo:'Datos oficiales',titulo:'Faltan los reportes de pedidos del PB20 al PB21',detalle:'x',enlace:'importar-pedidos',boton:'Subir el reporte'},
    {id:'vigencia-reporte-aurora',nivel:'alto',modulo:'Vigencia',titulo:'Vencido: reporte Aurora (montos y pendientes por facturar)',detalle:'Falta el PB22. Sube en Facturación el reporte Aurora del período.',accion:'Último cargado: PB21',enlace:'facturacion'},
    {id:'premios-declarados',nivel:'medio',enlace:'premios',modulo:'Premios',titulo:'6 premios declarados sin confirmar',detalle:'x'},
    {id:'premios-entregar',nivel:'info',enlace:'premios',modulo:'Premios',titulo:'2 premios por entregar',detalle:'x'},
    {id:'plataforma-salud',nivel:'info',modulo:'Plataforma',titulo:'7 reglas de la plataforma sin cumplir',detalle:'x'}]};
const ASESOR = {nombre:'Elena Segunda Landázuri Mosquera', codigo:'1723832',
  periodo:{numero:22,inicio:'2026-10-15',fin:'2026-10-28',hoy:'2026-10-21'}, puntos:[{periodo:'2026-PB19 (03-16 sep)',pb:19,puntos:1213,pedidos:2}]};

let fallas = 0;
const ok = (c, t) => { console.log((c ? '✔ ' : '✗ ') + t); if (!c) fallas++; };
const espera = ms => new Promise(r => setTimeout(r, ms));

function crear(prep){
  const llamadas = [], idas = [];
  const dom = new JSDOM(html, {runScripts: 'dangerously', pretendToBeVisual: true, url: 'https://plataforma.nelson1614.workers.dev/', virtualConsole: consola,
    beforeParse(w){
      w.scrollTo = () => {};
      if (prep) prep(w);
      w.fetch = async (url, opts = {}) => {
        const u = String(url).replace(SB, ''); llamadas.push({u, opts});
        const r = (data, status = 200) => ({ok: status < 400, status, text: async () => data === undefined ? '' : JSON.stringify(data)});
        const auth = (opts.headers || {}).Authorization || '';
        const b = opts.body ? JSON.parse(opts.body) : {};
        if (u.startsWith('/auth/v1/token?grant_type=password')) return b.password === 'clave'
          ? r({access_token:'jwt-1', refresh_token:'r1', expires_in:3600, token_type:'bearer', user:{email:b.email}})
          : r({error:'invalid_grant', error_description:'Invalid login credentials'}, 400);
        if (u.startsWith('/auth/v1/logout')) return {ok:true, status:204, text: async () => ''};
        if (u.startsWith('/rest/v1/rpc/hoy')) return auth.includes('jwt-') ? r(HOY) : r({message:'JWT expired'}, 401);
        if (u.startsWith('/rest/v1/rpc/plataforma_menu')) {
          if (b.p_token) return b.p_token === 'tok-1' ? r(MENU_ASESOR) : r({message:'Tu sesión venció. Vuelve a entrar con tu celular.'}, 400);
          return auth.includes('jwt-') ? r(MENU_STAFF) : r({message:'JWT expired'}, 401);
        }
        if (u.startsWith('/rest/v1/plataforma_modulos')) return r({message:'el hub ya no lee la tabla: usa plataforma_menu'}, 401);
        if (u.startsWith('/rest/v1/rpc/plataforma_fuentes_estado')) return auth.includes('jwt-') ? r(FUENTES) : r({message:'JWT expired'}, 401);
        if (u.startsWith('/rest/v1/rpc/asesor_login')) return b.p_celular === '987654321' ? r({token:'tok-1', nombre:ASESOR.nombre, celular:'987654321'}) : r({message:'Ese numero no esta habilitado'}, 400);
        if (u.startsWith('/rest/v1/rpc/ts_estado')) return TEST ? r(TEST) : r({message:'sin mock'}, 404);
        if (u.startsWith('/rest/v1/rpc/asesor_inicio')) return b.p_token === 'tok-1' ? r(ASESOR) : r({message:'Tu sesión venció. Vuelve a entrar con tu celular.'}, 400);
        if (u.startsWith('/rest/v1/rpc/traspaso_crear_asesor')) return b.p_token === 'tok-1' ? r(CODIGO) : r({message:'Tu sesión venció.'}, 400);
        if (u.startsWith('/rest/v1/rpc/traspaso_crear')) return auth.includes('jwt-') ? r(CODIGO) : r({message:'JWT expired'}, 401);
        return r({message:'sin mock ' + u}, 404);
      };
    }});
  const w = dom.window;
  w.navegar = url => idas.push(url);
  return {w, d: w.document, llamadas, idas};
}
const escribir = (w, el, v) => { el.value = v; el.dispatchEvent(new w.Event('input', {bubbles: true})); };
const enviar = (w, d, sel = 'form') => d.querySelector(sel).dispatchEvent(new w.Event('submit', {bubbles: true, cancelable: true}));
const textos = (d, sel) => [...d.querySelectorAll(sel)].map(x => x.textContent);
const tarjeta0 = (d, n) => [...d.querySelectorAll('.mod')].find(a => a.querySelector('strong').textContent === n);

(async () => {
  // ---- Staff: entra, Hoy, herramientas agrupadas desde la base, traspaso ----
  let {w, d, llamadas, idas} = crear();
  await espera(60);
  ok(d.querySelector('form.acceso'), 'Sin sesión muestra el acceso');
  escribir(w, d.getElementById('dato'), 'nelson1614@gmail.com'); d.getElementById('clave').value = 'clave'; enviar(w, d);
  await espera(150);
  ok(d.querySelector('h1').textContent === 'Hola, Nelson', 'Entra con correo y saluda');
  ok(d.querySelectorAll('.lista .item').length === 6 && d.querySelectorAll('.lista .item:not(.oculto)').length === 3, 'Hoy muestra 3 pendientes a la vista y guarda el resto');
  const verMas = d.querySelector('.ver-mas');
  ok(verMas && verMas.textContent === 'Ver los otros 3 pendientes', 'Un botón dice cuántos faltan (' + (verMas && verMas.textContent) + ')');
  verMas.click();
  ok(d.querySelectorAll('.lista .item:not(.oculto)').length === 6 && !d.querySelector('.ver-mas'), 'Al tocarlo se ven los 6');
  const vig = [...d.querySelectorAll('.lista .item')].find(li => li.textContent.includes('Vencido: reporte Aurora'));
  ok(vig && vig.classList.contains('alto') && vig.querySelector('a.abrir').textContent === 'Abrir facturación', 'La tarjeta de vigencia de Hoy es urgente y abre el módulo donde se sube');
  ok(!llamadas.some(c => c.u.startsWith('/rest/v1/plataforma_modulos')), 'El menú sale de plataforma_menu(), no de leer la tabla');
  const grupos = textos(d, 'h3.grupo');
  ok(grupos.join('|') === 'Vender|Pedidos|Equipo|Oficina|Otros', 'Grupos en el orden de la base: ' + grupos.join(', '));
  ok(d.querySelectorAll('.mod').length === 12, 'El admin ve sus 12 herramientas (sin contar Pregúntale, que es la caja)');
  ok(textos(d, '.mod strong').indexOf('Zonas de crédito') === 1 && textos(d, '.mod strong').indexOf('Local del equipo') === 8, 'Zonas de crédito va en Vender y el Local en Equipo');
  ok(textos(d, '.mod strong').indexOf('Vigencia de los datos') === 9 && tarjeta0(d, 'Vigencia de los datos').getAttribute('href') === '#vigencia', 'Vigencia de los datos va en Oficina y es una pantalla del hub');
  const ultimo = [...d.querySelectorAll('h3.grupo')].pop();
  ok(ultimo.textContent === 'Otros' && ultimo.nextElementSibling.textContent.includes('Herramienta nueva'), 'Una herramienta registrada sin grupo aparece en «Otros», no desaparece');
  ok(textos(d, 'h2').join('|') === 'Hoy|Herramientas', 'Secciones: Hoy y Herramientas');

  // Nunca se esconde un pendiente urgente, aunque sean más de 3
  {
    const antesItems = HOY.items;
    HOY.items = [1, 2, 3, 4].map(i => ({id: 'u' + i, nivel: 'alto', modulo: 'x', titulo: 'Urgente ' + i})).concat([{id: 'i1', nivel: 'info', modulo: 'x', titulo: 'Info 1'}]);
    const t2 = crear(w => w.localStorage.setItem(K_STAFF, JSON.stringify({access_token: 'jwt-1', refresh_token: 'r1', expires_at: Math.floor(Date.now() / 1000) + 3600})));
    await espera(150);
    ok(t2.d.querySelectorAll('.lista .item:not(.oculto)').length === 4 && t2.d.querySelector('.ver-mas').textContent === 'Ver el otro pendiente', 'Con 4 urgentes se ven los 4 y solo se guarda el informativo');
    HOY.items = antesItems;
  }

  // El dato vivo de cada tarjeta: sus pendientes de Hoy
  const tarjeta = n => [...d.querySelectorAll('.mod')].find(a => a.querySelector('strong').textContent === n);
  const pAdmin = tarjeta('Pedidos y afiliaciones').querySelector('.pend');
  ok(pAdmin && pAdmin.textContent.endsWith('1 pendiente') && pAdmin.classList.contains('alto'), 'Pedidos y afiliaciones marca «1 pendiente» urgente');
  const pPremios = tarjeta('Premios').querySelector('.pend');
  ok(pPremios && pPremios.textContent.endsWith('2 pendientes') && pPremios.classList.contains('medio'), 'Premios marca «2 pendientes» con la urgencia más alta de los dos');
  ok(!tarjeta('Zonas de crédito').querySelector('.pend'), 'Sin pendientes no hay globo');
  ok(pAdmin.querySelector('.sr').textContent === 'Urgente: ', 'El globo dice la urgencia al lector de pantalla');

  // Pregúntale: la caja abre /chat/ con la pregunta
  const caja = d.querySelector('form.preguntar');
  ok(caja && d.querySelector('h1').nextElementSibling.classList.contains('periodo'), 'La caja Pregúntale está arriba, después del período');
  escribir(w, d.getElementById('q'), '¿Hay crédito en Cerro Colorado?'); enviar(w, d, 'form.preguntar'); await espera(20);
  ok(idas[0] === '/chat/#q=' + encodeURIComponent('¿Hay crédito en Cerro Colorado?'), 'Preguntar abre el chat con la pregunta en el enlace (' + idas[0] + ')');
  d.getElementById('q').value = ''; enviar(w, d, 'form.preguntar'); await espera(20);
  ok(idas[1] === '/chat/', 'Sin texto, Preguntar abre el chat vacío');
  idas.length = 0;

  // Módulo con traspaso: crea código y navega con #traspaso
  const premios = tarjeta('Premios');
  premios.click(); await espera(120);
  const crear1 = llamadas.filter(c => c.u.startsWith('/rest/v1/rpc/traspaso_crear')).pop();
  ok(crear1 && JSON.parse(crear1.opts.body).p_modulo === 'premios' && crear1.opts.headers.Authorization.includes('jwt-1'), 'Crea el código de traspaso con la sesión del hub');
  ok(idas[0] === 'https://panel-equipo.pages.dev#traspaso=' + CODIGO, 'Abre Premios con #traspaso=<código> (' + idas[0] + ')');

  // Módulo sin traspaso: enlace normal
  const antes = llamadas.length;
  const registro = tarjeta('Registrar venta o afiliado');
  const ev = new w.MouseEvent('click', {bubbles: true, cancelable: true}); registro.dispatchEvent(ev); await espera(60);
  ok(!ev.defaultPrevented && llamadas.length === antes, 'Módulo sin traspaso: el enlace navega solo, sin código');

  // Módulo con ruta (/admin): el código va después de la ruta
  tarjeta('Pedidos y afiliaciones').click(); await espera(120);
  ok(idas[1] === 'https://renaware-registro.nelson1614.workers.dev/admin#traspaso=' + CODIGO, 'Con ruta /admin el código va al final');

  // Pendiente de Hoy con módulo externo: también con traspaso
  const abrir = [...d.querySelectorAll('.lista .item a.abrir')].find(a => a.textContent === 'Abrir premios');
  abrir.click(); await espera(120);
  ok(idas[2] === 'https://panel-equipo.pages.dev#traspaso=' + CODIGO, 'El pendiente "6 premios declarados" abre Premios con traspaso');

  // Pendiente interno (#importar): sin traspaso
  const subir = [...d.querySelectorAll('.lista .item a.abrir')].find(a => a.textContent === 'Subir el reporte');
  ok(subir && subir.getAttribute('href') === '#importar', 'Los pendientes internos siguen siendo enlaces #');

  // Si falla la creación del código, navega igual sin traspaso
  w.fetch = async () => ({ok: false, status: 500, text: async () => '{"message":"caído"}'});
  premios.click(); await espera(120);
  ok(idas[3] === 'https://panel-equipo.pages.dev', 'Si no se puede crear el código, abre el módulo sin traspaso');

  // ---- Pantalla Vigencia de los datos ----
  ({w, d, llamadas, idas} = crear(w => w.localStorage.setItem(K_STAFF, JSON.stringify({access_token: 'jwt-1', refresh_token: 'r1', expires_at: Math.floor(Date.now() / 1000) + 3600}))));
  await espera(150);
  w.location.hash = '#vigencia'; await espera(200);
  ok(d.querySelector('h1').textContent === 'Vigencia de los datos', 'Abre la pantalla de vigencia desde #vigencia');
  ok(llamadas.some(c => c.u.startsWith('/rest/v1/rpc/plataforma_fuentes_estado') && c.opts.headers.Authorization.includes('jwt-1')), 'Pide el estado de las fuentes con la sesión');
  ok(d.querySelector('.resumen-vig').textContent === '1 vencido · 1 por vencer · 2 al día', 'Resume: ' + d.querySelector('.resumen-vig').textContent);
  ok(textos(d, 'h2').join('|') === 'Vencido (1)|Por vencer (1)|Sin calcular (1)|Al día (2)', 'Secciones por estado: ' + textos(d, 'h2').join(', '));
  const aurora = [...d.querySelectorAll('.lista .item')].find(li => li.textContent.includes('Reporte Aurora'));
  ok(aurora && aurora.classList.contains('alto') && aurora.textContent.includes('Venció el 31 de octubre (hace 3 días). Falta el PB22.'), 'La fuente vencida dice desde cuándo y qué falta');
  ok(aurora.textContent.includes('Cada período, 3 días después del cierre · Último cargado: PB21'), 'Muestra la cadencia y la última vez');
  ok(aurora.querySelector('.accion').textContent === 'Sube en Facturación el reporte Aurora del período.', 'Dice qué hacer');
  aurora.querySelector('a.abrir').click(); await espera(120);
  ok(idas[0] === 'https://renaware-facturacion.pages.dev#traspaso=' + CODIGO, 'Abrir facturación desde la fuente va con traspaso');
  const rota = [...d.querySelectorAll('.lista .item')].find(li => li.textContent.includes('Fuente con SQL roto'));
  ok(rota && rota.textContent.includes('No se pudo calcular'), 'Una fuente con SQL roto se ve como «Sin calcular», no desaparece');
  const alDia = [...d.querySelectorAll('.lista .item')].find(li => li.textContent.includes('Listas de precios'));
  ok(alDia && alDia.classList.contains('ok') && alDia.textContent.includes('Al día hasta el 11 de noviembre'), 'Lo al día dice hasta cuándo');

  // ---- Asesora: ve lo que la base le asignó (precios y zonas), sin caja de pregunta ----
  ({w, d, llamadas, idas} = crear());
  await espera(60);
  escribir(w, d.getElementById('dato'), '987654321'); enviar(w, d); await espera(150);
  ok(d.querySelector('h1').textContent === 'Hola, Elena', 'Asesora entra con celular');
  const menuAs = llamadas.find(c => c.u.startsWith('/rest/v1/rpc/plataforma_menu'));
  ok(menuAs && JSON.parse(menuAs.opts.body).p_token === 'tok-1', 'Pide su menú con su token');
  ok(d.querySelectorAll('.mod').length === 2 && !d.querySelector('h3.grupo'), 'La asesora ve precios y zonas, sin encabezados (un solo grupo)');
  ok(!d.querySelector('form.preguntar'), 'Sin Pregúntale en su menú no hay caja de pregunta');
  ok(!d.querySelector('.pend'), 'Sin pendientes de Hoy, sin globos');
  d.querySelector('a.mod').click(); await espera(120);
  const crear2 = llamadas.filter(c => c.u.startsWith('/rest/v1/rpc/traspaso_crear_asesor')).pop();
  ok(crear2 && JSON.parse(crear2.opts.body).p_token === 'tok-1', 'Crea el código con el token de la asesora');
  ok(idas[0] === 'https://renaware-peru.nelson1614.workers.dev#traspaso=' + CODIGO, 'Abre precios con traspaso de asesora');
  ok(!d.querySelector('.aviso-test'), 'Asesora fuera del Nivel Cero: sin aviso ni módulo del test');

  // ---- Asesora nueva con el test habilitado y socia del local: la base le suma test y local ----
  TEST = {nombre: 'ELENA', estado: 'habilitado', intento: null,
    ventana: {estado: 'habilitado', hasta: '2026-11-11', dias: 2, botella: null}};
  MENU_ASESOR = MODS.filter(m => ['cotizador', 'zonas', 'test', 'local'].includes(m.id));
  ({w, d, llamadas, idas} = crear());
  await espera(60);
  escribir(w, d.getElementById('dato'), '987654321'); enviar(w, d); await espera(150);
  const av = d.querySelector('.aviso-test');
  ok(av && av.textContent.includes('Tu test del Nivel 0 está habilitado') && av.textContent.includes('te quedan 2 días'), 'Aviso del test habilitado con sus días');
  ok(av.textContent.includes('Termínalo y ganas tu botella'), 'Sin nota mínima: «Termínalo y ganas tu botella»');
  ok(textos(d, 'h3.grupo').join('|') === 'Vender|Equipo' && d.querySelectorAll('.mod').length === 4, 'Ve Vender (precios, zonas) y Equipo (test, local)');
  av.querySelector('a.abrir').click(); await espera(120);
  ok(idas[0] === 'https://renaware-plataforma.nelson1614.workers.dev/test/#traspaso=' + CODIGO, 'El aviso abre el test con traspaso');
  MENU_ASESOR = MODS.filter(m => ['cotizador', 'zonas'].includes(m.id));

  // ---- Aprobó: su botella lo espera ----
  TEST = {nombre: 'ELENA', estado: 'aprobado', ventana: {estado: 'aprobado', nota: 94, botella: 'por_entregar'}};
  ({w, d, llamadas, idas} = crear());
  await espera(60);
  escribir(w, d.getElementById('dato'), '987654321'); enviar(w, d); await espera(150);
  ok(d.querySelector('.aviso-test') && d.querySelector('.aviso-test').textContent.includes('Terminaste tu test del Nivel 0 con 94'), 'Terminó: aviso de la botella por recoger');
  // con nota mínima (si la oficina la vuelve a pedir) dice «Aprobaste»
  TEST = {nombre: 'ELENA', estado: 'aprobado', ventana: {estado: 'aprobado', nota: 94, botella: 'por_entregar'}, config: {exigir_nota: true, nota_minima: 90}};
  ({w, d, llamadas, idas} = crear());
  await espera(60);
  escribir(w, d.getElementById('dato'), '987654321'); enviar(w, d); await espera(150);
  ok(d.querySelector('.aviso-test') && d.querySelector('.aviso-test').textContent.includes('Aprobaste tu test del Nivel 0 con 94'), 'Con nota mínima: «Aprobaste»');
  TEST = null;

  // ---- Sesión de asesora vencida según la base: vuelve al acceso ----
  ({w, d, llamadas, idas} = crear(w => w.localStorage.setItem('rw_asesor_token', JSON.stringify('tok-viejo'))));
  await espera(150);
  ok(d.querySelector('form.acceso') && d.getElementById('error').textContent.includes('venció'), 'Token vencido: la base lo dice y el hub pide entrar de nuevo');

  console.log(fallas ? `\n${fallas} PRUEBA(S) FALLARON` : '\nTODAS LAS PRUEBAS PASARON');
  process.exit(fallas ? 1 : 0);
})();
