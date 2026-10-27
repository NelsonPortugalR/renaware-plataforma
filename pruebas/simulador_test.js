// Supabase simulado para el Test del Nivel 0: mismo contrato que las funciones ts_* de la base.
// Lo usan pruebas/prueba_test.js (jsdom) y pruebas/capturas_test.js (Chromium).
const CODIGO_ASESOR = '11111111-2222-4333-8444-555555555555';
const CODIGO_STAFF = '99999999-2222-4333-8444-555555555555';
/* ---------- un "Supabase" de mentira con el mismo contrato que las funciones ts_* ---------- */
function servidor(cfg = {}){
  const S = {
    estado: cfg.estado || 'habilitado', qn: 0, intento: null, historial: [], plan: cfg.plan || ['identificar', 'precio_general', 'medios_inicial', 'cuentas'],
    exigir: !!cfg.exigir,   // como la base: por ahora no se pide nota mínima (aprueba al terminar)
    tokens: new Set(['tok-hub', 'tok-test']), admin: new Set(['adm-1']), pasosActivos: {}, practicas: 0, llamadas: [], anulados: new Set()
  };
  const BLOQUE = {identificar: 'productos', precio_general: 'productos', medios_inicial: 'credito', cuentas: 'pagos'};
  const NOMBRE = {productos: 'Productos y precios', credito: 'Inicial, saldo y cuotas', pagos: 'Cuentas y pagos'};
  function pregunta(paso){
    const id = 'q' + (++S.qn), b = BLOQUE[paso];
    const base = {id, paso, bloque: b, bloque_nombre: NOMBRE[b], logica: 'Búscalo en la lista de precio general.'};
    if (paso === 'identificar') return Object.assign(base, {tipo: 'emparejar', texto: 'Empareja cada producto con su nombre.',
      items: [{id: 'i1', foto: 'https://x/a.webp'}, {id: 'i2', foto: 'https://x/b.webp'}],
      nombres: [{id: 'n1', t: 'Multi Cooker'}, {id: 'n2', t: 'Parrilla Doble'}], clave: {i1: 'n2', i2: 'n1'}});
    if (paso === 'precio_general') return Object.assign(base, {tipo: 'single', texto: '¿Cuánto cuesta al contado?', foto: 'https://x/c.webp',
      sub: 'Olla a Presión - 8 L', opciones: [{id: 'o1', t: 'S/ 2,811'}, {id: 'o2', t: 'S/ 3,229'}, {id: 'o3', t: 'S/ 3,416'}],
      clave: ['o2'], dato: 'Dato curioso.'});
    if (paso === 'medios_inicial') return Object.assign(base, {tipo: 'multi', texto: '¿Por qué medios puede pagar la inicial?',
      opciones: [{id: 'o1', t: 'Yape'}, {id: 'o2', t: 'Cheque'}, {id: 'o3', t: 'Depósito'}], clave: ['o1', 'o3']});
    return Object.assign(base, {tipo: 'escribir', texto: 'Escribe los números de cuenta.', campos: [{id: 'c1', label: 'Cuenta BCP'}],
      clave: {c1: ['1941234567890']}});
  }
  const publico = q => { if (!q) return null; const c = Object.assign({}, q); delete c.clave; delete c.logica; delete c.dato; return c; };
  function vista(it){
    if (!it) return null;
    const bloques = [];
    it.plan.forEach((p, i) => {
      const b = BLOQUE[p]; let x = bloques.find(y => y.bloque === b);
      if (!x) { x = {bloque: b, nombre: NOMBRE[b], pasos: 0, hechos: 0}; bloques.push(x); }
      x.pasos++; if (i < it.idx) x.hechos++;
    });
    return {id: it.id, origen: it.origen, paso: Math.min(it.idx + 1, it.plan.length), total: it.plan.length,
      intentos: it.intentos, aciertos: it.aciertos, pregunta: it.fin ? null : publico(it.q), bloques, fin: it.fin || null};
  }
  function corregir(q, r){
    if (q.tipo === 'single') return r === q.clave[0];
    if (q.tipo === 'multi') return Array.isArray(r) && [...r].sort().join() === [...q.clave].sort().join();
    if (q.tipo === 'emparejar') return Object.entries(q.clave).every(([k, v]) => r && r[k] === v);
    return Object.entries(q.clave).every(([k, v]) => r && v.includes(String(r[k] || '').replace(/\D/g, '')));
  }
  function nuevo(origen){
    return {id: 'int-' + (++S.qn), origen, plan: S.plan.slice(), idx: 0, intentos: 0, aciertos: 0, q: pregunta(S.plan[0]), fin: null};
  }
  function responder(it, preg, resp){
    if (!it.q || it.q.id !== preg) return {desfase: true, intento: vista(it)};
    const q = it.q, bien = corregir(q, resp);
    it.intentos++; if (bien) it.aciertos++;
    if (bien) {
      it.idx++;
      if (it.idx >= it.plan.length) {
        const nota = Math.round(100 * it.plan.length / it.intentos);
        const aprobado = !S.exigir || nota >= 90;
        it.fin = {nota, aprobado, nota_minima: 90, exigir_nota: S.exigir, pasos: it.plan.length, intentos: it.intentos, errores: it.intentos - it.aciertos,
          minutos: 3, por_bloque: [{bloque: 'productos', nombre: 'Productos y precios', respuestas: 3, errores: it.intentos - it.aciertos}]};
        it.q = null;
        if (it.origen === 'asesor') { S.historial.unshift({fecha: '2026-10-27', nota, aprobado}); S.intento = null; if (aprobado) S.estado = 'aprobado'; }
      } else it.q = pregunta(it.plan[it.idx]);
      return {ok: true, dato: q.dato || null, logica: null, intento: vista(it)};
    }
    it.q = pregunta(q.paso);
    return {ok: false, dato: null, logica: q.logica, intento: vista(it)};
  }
  const ventana = () => ({estado: S.estado, desde: '2026-10-27', hasta: '2026-11-11', dias: 15, intentos: S.historial.length,
    mejor: S.historial.length ? Math.max(...S.historial.map(x => x.nota)) : null, abierto: S.intento ? S.intento.id : null,
    nota: S.estado === 'aprobado' ? S.historial[0].nota : null, aprobado_en: S.estado === 'aprobado' ? '2026-10-27' : null,
    botella: S.estado === 'aprobado' ? 'por_entregar' : null, botella_entregada_en: null, hasta_editado: false,
    clases: {validas: S.estado === 'clases' ? 3 : 5, meta: 5, vence: '2026-11-14', estado: S.estado === 'clases' ? 'en_curso' : 'logro'}});
  const config = {nota_minima: 90, exigir_nota: S.exigir, dias_ventana: 15, premio: 'Botella de acero inoxidable', pasos: 4,
    recursos: cfg.recursos || [{nombre: 'Precios y promociones', url: 'https://renaware-peru.nelson1614.workers.dev'}]};
  const PERSONAS = [
    {id: 'p1', nombre: 'FLEY ELVIS MEDINA SOTO', celular: '900947503', codigo: null, afiliador: 'Benilda Medina', inicio: '2026-10-15',
     logro_fecha: '2026-10-27', validas: 5, estado_n0: 'logro',
     test: {estado: 'habilitado', desde: '2026-10-27', hasta: '2026-11-11', dias: 2, intentos: 1, mejor: 80, abierto: null, hasta_editado: false},
     intentos: [{id: 'int-a', iniciado: '2026-10-27T15:00:00Z', terminado: '2026-10-27T15:20:00Z', nota: 80, aprobado: false, intentos: 5, pasos: 4, paso: 4,
                 por_bloque: [{bloque: 'productos', nombre: 'Productos y precios', respuestas: 3, errores: 1}]}]},
    {id: 'p2', nombre: 'ANA LUZ QUISPE', celular: '911111111', codigo: '1234567', afiliador: null, inicio: '2026-10-10',
     logro_fecha: '2026-10-25', validas: 5, estado_n0: 'logro',
     test: {estado: 'aprobado', nota: 94, aprobado_en: '2026-10-26', botella: 'por_entregar', intentos: 1, mejor: 94}, intentos: []}];
  function admDatos(){
    return {hoy: '2026-10-27', config: Object.assign({aplica_desde: '2026-10-27', cuentas: [], recursos: config.recursos}, config),
      plan: S.plan, personas: PERSONAS, en_clases: 12, practicas: S.practicas,
      errores_bloque: [{bloque: 'productos', nombre: 'Productos y precios', respuestas: 10, errores: 3}, {bloque: 'credito', nombre: 'Inicial, saldo y cuotas', respuestas: 6, errores: 0}],
      pasos: [{clave: 'identificar', bloque: 'productos', bloque_nombre: 'Productos y precios', titulo: 'Reconocer productos', activo: true, variantes: 0},
              {clave: 'cuentas', bloque: 'pagos', bloque_nombre: 'Cuentas y pagos', titulo: 'Cuentas de Rena Ware', activo: true, variantes: 0},
              {clave: 'obj_caro', bloque: 'objeciones', bloque_nombre: 'Frase de oro y objeciones', titulo: '«Es caro»', activo: true, variantes: 2}]};
  }
  async function manejar(u, b, headers){
    S.llamadas.push({u, b});
    const rpc = u.replace('/rest/v1/rpc/', '');
    const asesorOk = t => S.tokens.has(t);
    const error = (m, st = 400) => ({st, d: {message: m}});
    if (u === '/functions/v1/traspaso') {
      if (b.codigo === CODIGO_ASESOR) return {d: {ok: true, tipo: 'asesor', token: 'tok-hub', nombre: 'Fley', celular: '900947503'}};
      if (b.codigo === CODIGO_STAFF) return {d: {ok: true, tipo: 'staff', admin_token: 'adm-1'}};
      return {st: 401, d: {ok: false, motivo: 'El enlace ya se usó o venció.'}};
    }
    switch (rpc) {
      case 'ts_login':
        // como la base: no devuelve el nombre (no se puede averiguar de quién es un número)
        if (b.p_celular === '900947503') return {d: {token: 'tok-test', celular: '900947503', alcance: 'test'}};
        if (b.p_celular === '987654321') return {d: {token: 'tok-hub', celular: '987654321', alcance: 'plataforma'}};
        if (b.p_celular === '900000000') return error('Ese número está bloqueado. Habla con tu líder.');
        return error('No encontramos tu inscripción en el Nivel Cero con ese número. Avísale a tu líder.');
      case 'ts_entrar':
        // DNI (o su celular): siempre una sesión solo para el test
        if (b.p_doc === '12345678' || b.p_doc === '900947503') return {d: {token: 'tok-test', alcance: 'test'}};
        if (b.p_doc === '11111111') return error('Tu acceso está bloqueado. Habla con tu líder.');
        return error('No encontramos ese DNI en el Nivel Cero. Revísalo o avísale a tu líder.');
      case 'admin_login': return b.p_clave === 'clave' ? {d: 'adm-1'} : error('Clave incorrecta');
      case 'ts_estado':
        if (!asesorOk(b.p_token)) return error('Tu sesión venció. Vuelve a entrar con tu celular.');
        if (S.estado === 'no_inscrito') return {d: {nombre: 'X', estado: 'no_inscrito', config}};
        return {d: {nombre: 'FLEY ELVIS MEDINA SOTO', estado: S.estado, ventana: ventana(), intento: vista(S.intento), historial: S.historial, config}};
      case 'ts_iniciar':
        if (!asesorOk(b.p_token)) return error('Tu sesión venció. Vuelve a entrar con tu celular.');
        if (S.estado === 'aprobado') return error('Ya aprobaste tu test.');
        if (!S.intento) S.intento = nuevo('asesor');
        return {d: vista(S.intento)};
      case 'ts_responder':
        if (!asesorOk(b.p_token)) return error('Tu sesión venció. Vuelve a entrar con tu celular.');
        if (S.anulados.has(b.p_intento)) return error('Ese intento se anuló. Vuelve a empezar tu test.');
        if (!S.intento || S.intento.id !== b.p_intento) return error('Ese test no es tuyo.');
        return {d: responder(S.intento, b.p_pregunta, b.p_respuesta)};
      case 'ts_admin_datos': return S.admin.has(b.p_token) ? {d: admDatos()} : error('Sesion invalida');
      case 'ts_admin_persona': return {d: {estado: 'habilitado', hasta: b.p_cambios.hasta || '2026-11-11', hasta_editado: !!b.p_cambios.hasta}};
      case 'ts_admin_paso': return {d: null};
      case 'ts_admin_config': return {d: Object.assign({}, admDatos().config, b.p_cambios)};
      case 'ts_admin_intento': return {d: {id: b.p_id, detalle: [{paso: 'precio_general', titulo: 'Precio en la lista general', bloque: 'Productos y precios', ok: false},
                                                                {paso: 'precio_general', titulo: 'Precio en la lista general', bloque: 'Productos y precios', ok: true}]}};
      case 'ts_admin_practicar': S.practicas++; S.practica = nuevo('oficina'); return {d: vista(S.practica)};
      case 'ts_admin_responder': return {d: responder(S.practica, b.p_pregunta, b.p_respuesta)};
      case 'ts_admin_anular':
        S.anulados.add(b.p_intento);
        if (S.intento && S.intento.id === b.p_intento) S.intento = null;
        return {d: null};
      case 'traspaso_crear': return (headers.Authorization || '').includes('jwt-') ? {d: CODIGO_STAFF} : error('JWT expired', 401);
    }
    return {st: 404, d: {message: 'sin mock ' + u}};
  }
  return {S, manejar};
}


module.exports = {servidor, CODIGO_ASESOR, CODIGO_STAFF};
