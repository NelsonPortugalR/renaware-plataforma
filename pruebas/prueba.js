// Pruebas del hub con un Supabase simulado. Correr: node pruebas/prueba.js
// (necesita jsdom: npm install jsdom)
const {JSDOM} = require('jsdom');
const fs = require('fs');
const path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', 'public', 'index.html'), 'utf8');
const SB = 'https://kiexpdaaoegbtesqmaff.supabase.co';
const K_STAFF = 'sb-kiexpdaaoegbtesqmaff-auth-token';
const CODIGO = '2f6d1d8e-0a9b-4c2e-9f1a-123456789abc';
const MODS = [
  {id:'cotizador',nombre:'Precios y promociones',descripcion:'Listas.',url:'https://renaware-peru.nelson1614.workers.dev',roles:['admin','asistente','gestor','asesor'],orden:1,grupo:'Ventas',traspaso_staff:true,traspaso_asesor:true},
  {id:'registro',nombre:'Registrar venta o afiliado',descripcion:'Formulario.',url:'https://renaware-registro.nelson1614.workers.dev',roles:['admin','asistente'],orden:2,grupo:'Ventas',traspaso_staff:false,traspaso_asesor:false},
  {id:'admin-registros',nombre:'Pedidos y afiliaciones',descripcion:'Revisar.',url:'https://renaware-registro.nelson1614.workers.dev/admin',roles:['admin','asistente'],orden:3,grupo:'Ventas',traspaso_staff:true,traspaso_asesor:false},
  {id:'importar-pedidos',nombre:'Subir reporte de Rena Ware',descripcion:'Carga.',url:'#importar',roles:['admin','asistente'],orden:5,grupo:'Ventas',traspaso_staff:false,traspaso_asesor:false},
  {id:'equipo',nombre:'Premios',descripcion:'Premios.',url:'https://panel-equipo.pages.dev',roles:['admin','asistente'],orden:7,grupo:'Equipo',traspaso_staff:true,traspaso_asesor:false},
  {id:'empiece-ya',nombre:'Ganadores Empiece Ya',descripcion:'Ganadores.',url:'https://empiece-ya.nelson1614.workers.dev',roles:['admin','asistente'],orden:8,grupo:'Equipo',traspaso_staff:false,traspaso_asesor:false},
  {id:'facturacion',nombre:'Facturación',descripcion:'Facturas.',url:'https://renaware-facturacion.pages.dev',roles:['admin','gestor'],orden:12,grupo:'Oficina',traspaso_staff:true,traspaso_asesor:false}];
const HOY = {rol:'admin', nombre:'Nelson Portugal Román',
  periodo:{numero:22,inicio:'2026-10-15',fin:'2026-10-28',hoy:'2026-10-21'}, oficial:{pb:19,puntos:5684,pedidos:14},
  items:[
    {id:'registros-sin-revisar',nivel:'alto',enlace:'admin-registros',modulo:'Pedidos',titulo:'82 registros sin revisar',detalle:'x'},
    {id:'reporte-rw',nivel:'alto',modulo:'Datos oficiales',titulo:'Faltan los reportes de pedidos del PB20 al PB21',detalle:'x',enlace:'importar-pedidos',boton:'Subir el reporte'},
    {id:'premios-declarados',nivel:'medio',enlace:'equipo',modulo:'Premios',titulo:'6 premios declarados sin confirmar',detalle:'x'}]};
const ASESOR = {nombre:'Elena Segunda Landázuri Mosquera', codigo:'1723832',
  periodo:{numero:22,inicio:'2026-10-15',fin:'2026-10-28',hoy:'2026-10-21'}, puntos:[{periodo:'2026-PB19 (03-16 sep)',pb:19,puntos:1213,pedidos:2}]};

let fallas = 0;
const ok = (c, t) => { console.log((c ? '✔ ' : '✗ ') + t); if (!c) fallas++; };
const espera = ms => new Promise(r => setTimeout(r, ms));

function crear(prep){
  const llamadas = [], idas = [];
  const dom = new JSDOM(html, {runScripts: 'dangerously', pretendToBeVisual: true, url: 'https://plataforma.nelson1614.workers.dev/',
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
        if (u.startsWith('/rest/v1/plataforma_modulos')) return r(auth.includes('jwt-') ? MODS : MODS.filter(m => m.roles.includes('asesor')));
        if (u.startsWith('/rest/v1/rpc/asesor_login')) return b.p_celular === '987654321' ? r({token:'tok-1', nombre:ASESOR.nombre, celular:'987654321'}) : r({message:'Ese numero no esta habilitado'}, 400);
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
const enviar = (w, d) => d.querySelector('form').dispatchEvent(new w.Event('submit', {bubbles: true, cancelable: true}));

(async () => {
  // ---- Staff: entra, Hoy, módulos agrupados, traspaso ----
  let {w, d, llamadas, idas} = crear();
  await espera(60);
  ok(d.querySelector('form.acceso'), 'Sin sesión muestra el acceso');
  escribir(w, d.getElementById('dato'), 'nelson1614@gmail.com'); d.getElementById('clave').value = 'clave'; enviar(w, d);
  await espera(150);
  ok(d.querySelector('h1').textContent === 'Hola, Nelson', 'Entra con correo y saluda');
  ok(d.querySelectorAll('.lista .item').length === 3, 'Muestra los pendientes de Hoy');
  const grupos = [...d.querySelectorAll('h3.grupo')].map(x => x.textContent);
  ok(grupos.join('|') === 'Ventas|Equipo|Oficina', 'Módulos agrupados en Ventas, Equipo y Oficina (' + grupos.join(', ') + ')');
  ok(d.querySelectorAll('.mod').length === 7, 'El admin ve sus 7 módulos');

  // Módulo con traspaso: crea código y navega con #traspaso
  const premios = [...d.querySelectorAll('a.mod')].find(a => a.textContent.includes('Premios'));
  premios.click(); await espera(120);
  const crear1 = llamadas.filter(c => c.u.startsWith('/rest/v1/rpc/traspaso_crear')).pop();
  ok(crear1 && JSON.parse(crear1.opts.body).p_destino === 'equipo' && crear1.opts.headers.Authorization.includes('jwt-1'), 'Crea el código de traspaso con la sesión del hub');
  ok(idas[0] === 'https://panel-equipo.pages.dev#traspaso=' + CODIGO, 'Abre Premios con #traspaso=<código> (' + idas[0] + ')');

  // Módulo sin traspaso: enlace normal
  const antes = llamadas.length;
  const registro = [...d.querySelectorAll('a.mod')].find(a => a.textContent.includes('Registrar venta'));
  const ev = new w.MouseEvent('click', {bubbles: true, cancelable: true}); registro.dispatchEvent(ev); await espera(60);
  ok(!ev.defaultPrevented && llamadas.length === antes, 'Módulo sin traspaso: el enlace navega solo, sin código');

  // Módulo con ruta (/admin): el código va después de la ruta
  const admin = [...d.querySelectorAll('a.mod')].find(a => a.textContent.includes('Pedidos y afiliaciones'));
  admin.click(); await espera(120);
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

  // ---- Asesor: solo precios acepta su traspaso ----
  ({w, d, llamadas, idas} = crear());
  await espera(60);
  escribir(w, d.getElementById('dato'), '987654321'); enviar(w, d); await espera(150);
  ok(d.querySelector('h1').textContent === 'Hola, Elena', 'Asesor entra con celular');
  ok(d.querySelectorAll('.mod').length === 1 && !d.querySelector('h3.grupo'), 'El asesor ve solo precios, sin agrupar');
  d.querySelector('a.mod').click(); await espera(120);
  const crear2 = llamadas.filter(c => c.u.startsWith('/rest/v1/rpc/traspaso_crear_asesor')).pop();
  ok(crear2 && JSON.parse(crear2.opts.body).p_token === 'tok-1', 'Crea el código con el token del asesor');
  ok(idas[0] === 'https://renaware-peru.nelson1614.workers.dev#traspaso=' + CODIGO, 'Abre precios con traspaso de asesor');

  console.log(fallas ? `\n${fallas} PRUEBA(S) FALLARON` : '\nTODAS LAS PRUEBAS PASARON');
  process.exit(fallas ? 1 : 0);
})();
