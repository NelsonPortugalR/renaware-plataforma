# Pruebas de la plataforma de asesores (public/asesores/index.html: inicio, buscador, zonas, Empiece Ya, premios,
# Nivel Cero, entrenamientos, listas y horario; y el modo oficina) en un Chromium real con un Supabase simulado.
# Correr: python3 pruebas/prueba_asesores.py [carpeta_capturas]
# Necesita playwright (pip install playwright && playwright install chromium) o un Chrome instalado.
import json, os, sys, threading, http.server, socketserver, functools, re
from playwright.sync_api import sync_playwright

RAIZ = os.path.join(os.path.dirname(__file__), '..', 'public')
SB = 'https://kiexpdaaoegbtesqmaff.supabase.co'
CAPTURAS = sys.argv[1] if len(sys.argv) > 1 else None
fallas = 0

def ok(c, t):
    global fallas
    print(('✔ ' if c else '✗ ') + t)
    if not c: fallas += 1

# ---------- servidor estático ----------
class Silencioso(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
handler = functools.partial(Silencioso, directory=RAIZ)
socketserver.TCPServer.allow_reuse_address = True
srv = socketserver.TCPServer(('127.0.0.1', 0), handler)
PUERTO = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()

# ---------- Supabase simulado ----------
PNG = bytes.fromhex('89504e470d0a1a0a0000000d4948445200000001000000010806000000' '1f15c4890000000d49444154789c636000020000050001e2' '26059b0000000049454e44ae426082')
def datos(rol):
    base = {
        'hoy': '2026-11-04', 'rol': rol, 'nombre': 'Fley Rojas' if rol == 'asesor' else None, 'celular': '987654321' if rol == 'asesor' else None,
        'archivos_base': SB + '/storage/v1/object/public/entrenamientos/',
        'modulos': [
            {'id': 'm1', 'titulo': 'Empieza bien', 'descripcion': 'Lo primero.', 'orden': 1, 'activo': True, 'lecciones': [
                {'id': 'l1', 'titulo': 'Sesión de bienvenida', 'descripcion': 'Tu primera sesión.', 'orden': 1, 'activo': True, 'progreso': 'completado' if rol == 'asesor' else None,
                 'n_vistos': 3, 'n_completados': 1, 'recursos': [
                    {'id': 'r1', 'tipo': 'guia', 'titulo': None, 'ruta': 't1/guia.pdf', 'archivo': 'guia.pdf', 'bytes': 240000, 'content_type': 'application/pdf', 'paginas': 6, 'portada': 't1/portada.jpg', 'url': None, 'orden': 1, 'activo': True},
                    {'id': 'r2', 'tipo': 'video', 'titulo': 'Cómo fue la primera sesión', 'ruta': None, 'archivo': None, 'bytes': None, 'content_type': None, 'paginas': None, 'portada': None, 'url': 'https://youtu.be/dQw4w9WgXcQ', 'orden': 2, 'activo': True}]},
                {'id': 'l2', 'titulo': 'Programa Empiece Ya', 'descripcion': None, 'orden': 2, 'activo': True, 'progreso': None, 'n_vistos': 0, 'n_completados': 0, 'recursos': []},
                {'id': 'l3', 'titulo': 'Lección oculta', 'descripcion': None, 'orden': 3, 'activo': False, 'progreso': None, 'n_vistos': 0, 'n_completados': 0, 'recursos': []}]},
            {'id': 'm2', 'titulo': 'Consigue citas', 'descripcion': None, 'orden': 2, 'activo': True, 'lecciones': []}],
        'categorias': [
            {'id': 'precios', 'nombre': 'Listas de precios', 'descripcion': 'Las listas.', 'orden': 1, 'roles': ['admin', 'asistente', 'asesor'], 'activo': True, 'documentos': [
                {'id': 'd1', 'clave': 'lista-promo-cliente', 'titulo': 'Promociones del mes · lista digital para el cliente', 'descripcion': 'Se le puede enviar al cliente.', 'audiencia': 'cliente',
                 'roles': ['admin', 'asistente', 'asesor'], 'orden': 1, 'activo': True,
                 'vigente': {'id': 'v2', 'version': 2, 'ruta': 't2/promos.pdf', 'archivo': 'promos.pdf', 'bytes': 1800000, 'content_type': 'application/pdf', 'paginas': 4, 'portada': 't2/portada.jpg', 'nota': 'Noviembre 2026', 'vigente_desde': '2026-11-01', 'vigente_hasta': '2026-11-30', 'creado_en': '2026-11-02T10:00:00Z'},
                 'versiones': [{'id': 'v2', 'version': 2, 'ruta': 't2/promos.pdf', 'archivo': 'promos.pdf', 'bytes': 1800000, 'content_type': 'application/pdf', 'paginas': 4, 'portada': 't2/portada.jpg', 'nota': 'Noviembre 2026', 'vigente_desde': '2026-11-01', 'vigente_hasta': '2026-11-30', 'creado_en': '2026-11-02T10:00:00Z'},
                               {'id': 'v1', 'version': 1, 'ruta': 't0/promos.pdf', 'archivo': 'promos.pdf', 'bytes': 1700000, 'content_type': 'application/pdf', 'paginas': 4, 'portada': None, 'nota': 'Octubre 2026', 'vigente_desde': '2026-10-01', 'vigente_hasta': '2026-10-31', 'creado_en': '2026-10-02T10:00:00Z'}]},
                {'id': 'd2', 'clave': 'lista-regular-asesor', 'titulo': 'Precio regular · autocompra', 'descripcion': None, 'audiencia': 'asesor', 'roles': ['admin', 'asistente', 'asesor'], 'orden': 2, 'activo': True, 'vigente': None, 'versiones': []}]},
            {'id': 'concursos', 'nombre': 'Concursos y programas', 'descripcion': None, 'orden': 3, 'roles': ['admin', 'asistente', 'asesor'], 'activo': True, 'documentos': [
                {'id': 'd3', 'clave': 'foto-empiece-ya', 'titulo': 'Programa Empiece Ya', 'descripcion': 'La foto.', 'audiencia': 'asesor', 'roles': ['admin', 'asistente', 'asesor'], 'orden': 1, 'activo': True,
                 'vigente': {'id': 'v3', 'version': 1, 'ruta': 't3/eya.png', 'archivo': 'eya.png', 'bytes': 300000, 'content_type': 'image/png', 'paginas': None, 'portada': 't3/portada.jpg', 'nota': None, 'vigente_desde': None, 'vigente_hasta': '2026-10-20', 'creado_en': '2026-09-02T10:00:00Z'}, 'versiones': []}]}],
        'semana': semana('2026-11-02', rol),
        'plantillas': [{'id': 'p1', 'dia': 3, 'hora': '16:00', 'titulo': 'Taller de cocina', 'descripcion': None, 'lugar': 'Oficina', 'modo': 'presencial', 'facilitador': None, 'enlace': None, 'tipo': 'capacitacion', 'asistencia': True, 'solo_inicio_periodo': False, 'publico': True, 'orden': 1, 'activo': True},
                       {'id': 'p2', 'dia': 4, 'hora': '10:00', 'titulo': 'Lanzamiento del nuevo concurso', 'descripcion': None, 'lugar': 'Oficina', 'modo': 'presencial', 'facilitador': None, 'enlace': None, 'tipo': 'evento', 'asistencia': True, 'solo_inicio_periodo': True, 'excepto_inicio_periodo': False, 'publico': True, 'orden': 2, 'activo': True},
                       {'id': 'p6', 'dia': 4, 'hora': '09:00', 'titulo': 'Capacitación por Zoom', 'descripcion': None, 'lugar': None, 'modo': 'zoom', 'facilitador': 'Juan Carlos Ezaine', 'enlace': None, 'tipo': 'capacitacion', 'asistencia': False, 'solo_inicio_periodo': False, 'excepto_inicio_periodo': True, 'publico': True, 'orden': 1, 'activo': True}] if rol == 'admin' else None,
        'progreso': [{'celular': '987654321', 'nombre': 'fley rojas', 'vistas': 2, 'completadas': 1, 'ultimo': '2026-11-03T15:00:00Z'}] if rol == 'admin' else None,
    }
    if rol != 'admin':   # la función real no manda lo oculto al asesor
        for m in base['modulos']: m['lecciones'] = [l for l in m['lecciones'] if l['activo']]
    return base
def semana(lunes, rol):
    import datetime
    l = datetime.date.fromisoformat(lunes)
    f = lambda n: (l + datetime.timedelta(days=n)).isoformat()
    evs = [
        {'id': 'e1', 'plantilla_id': 'p1', 'fecha': f(2), 'hora': '16:00', 'titulo': 'Taller de cocina', 'descripcion': None, 'lugar': 'Oficina · Av. Cayma 628', 'modo': 'presencial', 'facilitador': None, 'enlace': None, 'tipo': 'capacitacion', 'asistencia': True, 'publico': True, 'activo': True, 'editado': False, 'nota': None, 'n0_clase_id': 'k1', 'asistentes': 4},
        {'id': 'e2', 'plantilla_id': 'p3', 'fecha': f(3), 'hora': '21:00', 'titulo': 'Capacitación por Zoom', 'descripcion': None, 'lugar': None, 'modo': 'zoom', 'facilitador': 'Nelson Portugal', 'enlace': 'https://zoom.us/j/123', 'tipo': 'capacitacion', 'asistencia': True, 'publico': True, 'activo': True, 'editado': False, 'nota': 'Hoy a las 9 en punto', 'n0_clase_id': 'k2', 'asistentes': 0},
        {'id': 'e3', 'plantilla_id': 'p4', 'fecha': f(1), 'hora': '09:30', 'titulo': 'Desayuno de líderes', 'descripcion': None, 'lugar': 'Oficina', 'modo': 'presencial', 'facilitador': None, 'enlace': None, 'tipo': 'reunion', 'asistencia': False, 'publico': False, 'activo': True, 'editado': False, 'nota': None, 'n0_clase_id': None, 'asistentes': 0},
        {'id': 'e4', 'plantilla_id': 'p5', 'fecha': f(4), 'hora': '17:00', 'titulo': 'Charla de la oportunidad', 'descripcion': None, 'lugar': 'Oficina', 'modo': 'presencial', 'facilitador': None, 'enlace': None, 'tipo': 'reclutamiento', 'asistencia': False, 'publico': True, 'activo': False, 'editado': False, 'nota': None, 'n0_clase_id': None, 'asistentes': 0}]
    if lunes == '2026-11-09':
        evs.append({'id': 'e5', 'plantilla_id': 'p2', 'fecha': f(3), 'hora': '10:00', 'titulo': 'Lanzamiento del nuevo concurso', 'descripcion': None, 'lugar': 'Oficina', 'modo': 'presencial', 'facilitador': None, 'enlace': None, 'tipo': 'evento', 'asistencia': True, 'publico': True, 'activo': True, 'editado': False, 'nota': None, 'n0_clase_id': 'k5', 'asistentes': 0})
    if rol != 'admin': evs = [e for e in evs if e['activo'] and e['publico']]
    return {'lunes': lunes, 'domingo': f(6), 'hoy': '2026-11-04', 'inicio_periodo': ['2026-11-12'] if lunes == '2026-11-09' else [], 'eventos': evs}

MENU = [
    {'id': 'cotizador', 'nombre': 'Precios y promociones', 'descripcion': 'Listas.', 'url': 'https://renaware-peru.nelson1614.workers.dev', 'roles': ['asesor'], 'orden': 1, 'acceso': 'asesor', 'grupo': 'Vender'},
    {'id': 'zonas', 'nombre': 'Zonas de crédito', 'descripcion': 'Zonas.', 'url': 'https://zonas-de-credito.nelson1614.workers.dev', 'roles': ['asesor'], 'orden': 2, 'acceso': 'libre', 'grupo': 'Vender'},
    {'id': 'listas', 'nombre': 'Listas y fotos', 'descripcion': 'Listas.', 'url': '/asesores/#listas', 'roles': ['asesor'], 'orden': 4, 'acceso': 'asesor', 'grupo': 'Vender'},
    {'id': 'entrenamientos', 'nombre': 'Entrenamientos', 'descripcion': 'Guías.', 'url': '/asesores/#entrenamientos', 'roles': ['asesor'], 'orden': 20, 'acceso': 'asesor', 'grupo': 'Equipo'},
    {'id': 'test', 'nombre': 'Test del Nivel 0', 'descripcion': 'Test.', 'url': '/test/', 'roles': ['asesor'], 'orden': 24, 'acceso': 'asesor', 'grupo': 'Equipo'},
    {'id': 'local', 'nombre': 'Local del equipo', 'descripcion': 'Turnos del local.', 'url': 'https://local-equipo-arequipa.nelson1614.workers.dev', 'roles': ['asesor'], 'orden': 26, 'acceso': 'libre', 'grupo': 'Equipo'}]
def premio(nombre, programa, **k):
    return dict({'premio': nombre, 'cantidad': 1, 'programa': programa, 'nivel': None, 'pb': None, 'tipo': 'final', 'recibido_en': None, 'entregado_en': None, 'periodo_fin': None}, **k)
def panel():
    return {
        'nombre': 'FLEY ROJAS QUISPE', 'codigo': '1723832', 'hoy': '2026-11-04',
        'periodo': {'numero': 23, 'inicio': '2026-10-29', 'fin': '2026-11-11'},
        'puntos': [{'periodo': '2026-PB22 (15-28 oct)', 'pb': 22, 'puntos': 1213, 'pedidos': 2}, {'periodo': '2026-PB21 (01-14 oct)', 'pb': 21, 'puntos': 480, 'pedidos': 1}],
        'nivel': {'estado': 'en_curso', 'inicio': '2026-10-20', 'vence': '2026-11-19', 'dias': 15, 'validas': 2, 'meta': 5, 'premio': 'Botella de acero inoxidable', 'logro_fecha': None,
                  'clases': [{'fecha': '2026-10-21', 'hora': '16:00', 'tema': 'Taller de cocina', 'vale': True}, {'fecha': '2026-10-23', 'hora': '17:00', 'tema': 'Charla de la oportunidad', 'vale': True}],
                  'proximas': [{'fecha': '2026-11-04', 'hora': '16:00', 'titulo': 'Taller de cocina', 'lugar': 'Oficina · Av. Cayma 628, Of. 502'},
                               {'fecha': '2026-11-06', 'hora': '17:00', 'titulo': 'Charla de la oportunidad', 'lugar': 'Oficina'}],
                  'test': {'estado': 'clases', 'desde': None, 'hasta': None, 'dias': None, 'intentos': 0, 'mejor': None, 'abierto': None, 'aprobado_en': None, 'nota': None, 'botella': None},
                  'test_config': {'exigir_nota': False, 'nota_minima': 90, 'dias_ventana': 15, 'premio': 'Botella de acero inoxidable'}},
        'premios': {'por_recoger': [premio('Joyita 1 L', 'Impulsa tu Negocio con Rena Ware', nivel='Afiliaciones - Nivel I', pb='PB21', recibido_en='2026-10-30', periodo_fin='2026-10-14')],
                    'por_llegar': [premio('Set de Bowls 3 Piezas', 'Curazao · El Caribe te llama', tipo='declarado', periodo_fin='2026-10-28')],
                    'entregados': [premio('Mini Sartén 18cm', 'Programa Equípate', entregado_en='2026-09-10', recibido_en='2026-09-01')]},
        'proximos': [{'fecha': '2026-11-04', 'hora': '16:00', 'titulo': 'Taller de cocina', 'modo': 'presencial', 'lugar': 'Oficina', 'facilitador': None, 'enlace': None, 'asistencia': True},
                     {'fecha': '2026-11-05', 'hora': '21:00', 'titulo': 'Capacitación por Zoom', 'modo': 'zoom', 'lugar': None, 'facilitador': 'Nelson Portugal', 'enlace': None, 'asistencia': False}],
        'menu': MENU}
PANEL = {'modo': 'normal'}      # normal | logro | vacio | falla
def panel_segun():
    d = panel()
    if PANEL['modo'] == 'logro':
        d['nivel'].update({'estado': 'logro', 'validas': 5, 'logro_fecha': '2026-11-03', 'proximas': []})
        d['nivel']['test'].update({'estado': 'habilitado', 'desde': '2026-11-03', 'hasta': '2026-11-18', 'dias': 14})
    if PANEL['modo'] == 'vacio':
        d.update({'nombre': 'ANA NUEVA', 'codigo': None, 'puntos': [], 'nivel': None, 'premios': {'por_recoger': [], 'por_llegar': [], 'entregados': []}, 'proximos': [],
                  'menu': [m for m in MENU if m['id'] != 'local']})
    return d
ZONAS = {'meta': {'vigencia': 'Abril 2025', 'fuente': 'x.xlsx', 'carga_id': 1}, 'd': [
    {'dep': 'AREQUIPA', 'prov': 'AREQUIPA', 'nom': 'CAYMA', 'ali': None, 'pali': None, 'mod': 0, 'urb': False, 'todo': None, 'z': []},
    {'dep': 'AREQUIPA', 'prov': 'AREQUIPA', 'nom': 'CERRO COLORADO', 'ali': None, 'pali': None, 'mod': 0, 'urb': False, 'todo': None,
     'z': [['AA.HH. LAS FLORES', 'ZONA PELIGROSA'], ['URB. CIUDAD MUNICIPAL', 'ZONA PELIGROSA'], ['ASOC. VILLA PARAÍSO', 'DIFÍCIL ACCESO']]},
    {'dep': 'AREQUIPA', 'prov': 'AREQUIPA', 'nom': 'CHIGUATA', 'ali': None, 'pali': None, 'mod': 0, 'urb': False, 'todo': ['TODO EL DISTRITO', 'FUERA DE COBERTURA'], 'z': []},
    {'dep': 'AREQUIPA', 'prov': 'ISLAY', 'nom': 'MOLLENDO', 'ali': None, 'pali': None, 'mod': 1, 'urb': True, 'todo': None, 'z': []},
    {'dep': 'LIMA', 'prov': 'LIMA', 'nom': 'SANTIAGO DE SURCO', 'ali': ['SURCO'], 'pali': None, 'mod': 0, 'urb': False, 'todo': None, 'z': []}]}
def eya(q):
    cob = {'desde': '2024-01-10', 'hasta': '2026-10-14', 'anio': 2026, 'pb': 21}
    if 'quispe' in q.lower():
        return {'ok': True, 'total': 2, 'cobertura': cob, 'resultados': [
            {'codigo': '1700001', 'nombre': 'MARIA QUISPE DE LA CRUZ', 'division': 'WV08', 'fecha': '2026-10-14', 'mi_equipo': True, 'pb': {'anio': 2026, 'pb': 21},
             'premios': [{'anio': 2026, 'pb': 21, 'premio': 'Utensilio 1.5L + Botella Filtrante RW'}]},
            {'codigo': '1600002', 'nombre': 'MARIA ELENA QUISPE MAMANI', 'division': 'LK03', 'fecha': '2025-03-12', 'mi_equipo': False, 'pb': None, 'premios': []}]}
    return {'ok': True, 'total': 0, 'cobertura': cob, 'resultados': []}

llamadas = []
def manejar(route, request):
    u = request.url
    m = {'content-type': 'application/json'}
    if u.startswith(SB + '/rest/v1/rpc/'):
        fn = u.split('/rpc/')[1].split('?')[0]
        b = json.loads(request.post_data or '{}')
        llamadas.append((fn, b))
        tok = b.get('p_token')
        if fn == 'asesor_login':
            if b['p_celular'] == '40123456': return route.fulfill(status=200, headers=m, body=json.dumps({'token': 'tok-ase', 'nombre': 'fley rojas', 'celular': '987654321'}))
            return route.fulfill(status=400, headers=m, body=json.dumps({'message': 'Ese DNI no esta habilitado'}))
        if fn == 'admin_login':
            if b['p_clave'] == 'clave': return route.fulfill(status=200, headers=m, body=json.dumps('tok-adm'))
            return route.fulfill(status=400, headers=m, body=json.dumps({'message': 'Clave incorrecta'}))
        if fn == 'zc_lista': return route.fulfill(status=200, headers=m, body=json.dumps(ZONAS))
        if tok not in ('tok-ase', 'tok-adm'): return route.fulfill(status=400, headers=m, body=json.dumps({'message': 'Sesion invalida'}))
        rol = 'admin' if tok == 'tok-adm' else 'asesor'
        if fn == 'ent_datos': return route.fulfill(status=200, headers=m, body=json.dumps(datos(rol)))
        if fn == 'asesor_panel':
            if rol != 'asesor': return route.fulfill(status=400, headers=m, body=json.dumps({'message': 'Sesion invalida'}))
            if PANEL['modo'] == 'falla': return route.fulfill(status=500, headers=m, body=json.dumps({'message': 'se cayó algo'}))
            return route.fulfill(status=200, headers=m, body=json.dumps(panel_segun()))
        if fn == 'eya_buscar': return route.fulfill(status=200, headers=m, body=json.dumps(eya(b.get('p_q') or '')))
        if fn == 'traspaso_crear_asesor': return route.fulfill(status=200, headers=m, body=json.dumps('cccccccc-bbbb-4ccc-8ddd-eeeeeeeeeeee'))
        if fn == 'hor_semana':
            import datetime
            d = datetime.date.fromisoformat(b.get('p_fecha') or '2026-11-04'); l = d - datetime.timedelta(days=(d.weekday()))
            return route.fulfill(status=200, headers=m, body=json.dumps(semana(l.isoformat(), rol)))
        if fn == 'ent_progreso_marcar': return route.fulfill(status=200, headers=m, body=json.dumps({'ok': True, 'progreso': 'completado' if b['p_estado'] == 'completado' else ('visto' if b['p_estado'] == 'visto' else None)}))
        if fn == 'ent_subida_crear': return route.fulfill(status=200, headers=m, body=json.dumps('11111111-2222-4333-8444-555555555555'))
        if fn == 'traspaso_crear_admin': return route.fulfill(status=200, headers=m, body=json.dumps('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'))
        if fn.endswith('_guardar') or fn in ('ent_borrar', 'ent_ordenar', 'doc_categoria_ordenar'):
            return route.fulfill(status=200, headers=m, body=json.dumps({'id': 'nuevo', 'ok': True, 'fecha': b.get('p_datos', {}).get('fecha', '2026-11-04')}))
        return route.fulfill(status=404, headers=m, body=json.dumps({'message': 'sin simular: ' + fn}))
    if u.startswith(SB + '/storage/v1/object/entrenamientos/'):
        llamadas.append(('storage', u.split('/entrenamientos/')[1], request.headers.get('content-type')))
        return route.fulfill(status=200, headers=m, body=json.dumps({'Key': 'entrenamientos/x'}))
    if u.startswith(SB + '/storage/v1/object/public/'):
        return route.fulfill(status=200, headers={'content-type': 'image/png'}, body=PNG)
    if 'cdnjs' in u or 'fonts.g' in u:
        return route.abort()
    if 'renaware-peru.nelson1614.workers.dev' in u or 'local-equipo-arequipa' in u:      # los módulos de fuera: basta saber que se llegó
        return route.fulfill(status=200, headers={'content-type': 'text/html'}, body='<title>fuera</title><p id=app>modulo externo</p>')
    return route.continue_()

def texto(p): return p.locator('#app').inner_text().replace('\u00a0', ' ')
def cap(p, n):
    t = p.locator('body').inner_text()
    ok('null' not in t and 'undefined' not in t and 'NaN' not in t and '[object' not in t, 'Pantalla «' + n + '» sin textos rotos (null, undefined, NaN)')
    if CAPTURAS: p.screenshot(path=os.path.join(CAPTURAS, n + '.png'), full_page=True)

with sync_playwright() as pw:
    chrome = '/usr/bin/google-chrome' if os.path.exists('/usr/bin/google-chrome') else None
    br = pw.chromium.launch(executable_path=chrome) if chrome else pw.chromium.launch()
    errores = []
    def nuevo(hash=''):
        ctx = br.new_context(viewport={'width': 390, 'height': 844}, device_scale_factor=2, is_mobile=True, has_touch=True, locale='es-PE')
        ctx.route('**/*', manejar)
        p = ctx.new_page()
        p.on('pageerror', lambda e: errores.append(str(e)))
        p.goto(f'http://127.0.0.1:{PUERTO}/asesores/' + hash)
        p.wait_for_timeout(250)
        return ctx, p

    # ---------- 1. La asesora: entra y llega a su inicio ----------
    ctx, p = nuevo()
    ok('Tu DNI' in texto(p) and 'Soy de la oficina' in texto(p), 'Sin sesión pide el DNI')
    cap(p, '01-entrar')
    p.fill('#dni', '123'); p.click('button.boton'); p.wait_for_timeout(200)
    ok('8 dígitos' in texto(p), 'DNI incompleto: lo dice sin consultar la base')
    p.fill('#dni', '11111111'); p.click('button.boton'); p.wait_for_timeout(200)
    ok('no está registrado' in texto(p), 'DNI que no está en el equipo: lo dice')
    p.fill('#dni', '40 123 456'); p.click('button.boton'); p.wait_for_timeout(500)
    ok(p.evaluate("JSON.parse(localStorage.getItem('rw_asesor_token'))") == 'tok-ase', 'Guarda la sesión de asesor en rw_asesor_token (la de la plataforma)')
    t = texto(p)
    ok(p.locator('.hola h1').inner_text() == 'Hola, Fley' and 'Miércoles 4 de noviembre. El período 23 cierra el miércoles 11.' in t, 'Inicio: saluda por su nombre y dice el día y el cierre del período')
    ok(p.url.endswith('/asesores/#inicio') and p.locator('nav.pestanas').count() == 0, 'La asesora no tiene pestañas: tiene un inicio')
    ok(('asesor_panel', {'p_token': 'tok-ase'}) in llamadas and ('ent_datos', {'p_token': 'tok-ase'}) in llamadas, 'Lo suyo llega en una sola llamada (asesor_panel), junto con lo de todos')
    av = [x.replace('\u00a0', ' ') for x in p.locator('.avisos .tarj').all_inner_texts()]
    ok(len(av) == 3 and 'Tienes un premio por recoger' in av[0] and 'Joyita 1 L. Te espera en la oficina.' in av[0], 'Aviso 1: el premio por recoger, con su nombre')
    ok('Llevas 2 de 5 clases' in av[1] and 'Te quedan 15 días' in av[1] and 'hasta el jueves 19 de noviembre' in av[1] and av[1].rstrip(' \n›').endswith('Próxima clase: hoy, 4:00 p. m.'), 'Aviso 2: su Nivel Cero con clases, plazo y la próxima clase')
    ok(p.locator('.avisos .paso.hecho').count() == 2 and p.locator('.avisos .paso').count() == 5, 'Dibuja 5 círculos y 2 hechos')
    ok('Hoy, 4:00 p. m.' in av[2] and 'Taller de cocina · En la oficina' in av[2], 'Aviso 3: lo que sigue en el horario')
    ok(p.locator('h2').all_inner_texts() == ['Para vender y afiliar', 'Para aprender', 'Lo tuyo'], 'Los botones van en tres grupos: ' + ' / '.join(p.locator('h2').all_inner_texts()))
    losas = p.locator('.losa b').all_inner_texts()
    ok(losas == ['Precios y promociones', 'Zonas de crédito', 'Listas y fotos', '¿Ya ganó Empiece Ya?', 'Entrenamientos', 'Horario', 'Mi Nivel Cero', 'Mis premios', 'Mis puntos', 'Local del equipo'], 'Diez botones, cada uno con su nombre: ' + ', '.join(losas))
    ok(p.locator('.losa .globo').inner_text() == '1', 'Mis premios lleva la cuenta de lo que hay por recoger')
    med = p.evaluate("(() => { const l = [...document.querySelectorAll('.losa')].map(e => e.getBoundingClientRect()); const f = parseFloat(getComputedStyle(document.body).fontSize); const b = parseFloat(getComputedStyle(document.querySelector('.losa b')).fontSize); return {alto: Math.min(...l.map(r => r.height)), ancho: Math.min(...l.map(r => r.width)), letra: f, losa: b, desborda: document.documentElement.scrollWidth > innerWidth}; })()")
    ok(med['alto'] >= 120 and med['ancho'] >= 150 and med['letra'] >= 18 and med['losa'] >= 17.5 and not med['desborda'], 'Botones grandes y letra grande, sin desbordar el ancho del teléfono: ' + json.dumps(med))
    ok('Nelson Portugal, Representante Independiente de Rena Ware' in t and 'Rena Ware Arequipa' not in t, 'Lleva la marca correcta')
    # en teléfonos angostos nada se corta ni se parte con guiones
    for ancho in (360, 320):
        p.set_viewport_size({'width': ancho, 'height': 740}); p.wait_for_timeout(120)
        m = p.evaluate("(() => { const b = [...document.querySelectorAll('.losa b, .losa > span')]; return {cortados: b.filter(e => e.scrollWidth > e.clientWidth + 1).map(e => e.textContent), desborda: document.documentElement.scrollWidth > innerWidth, cols: getComputedStyle(document.querySelector('.losas')).gridTemplateColumns.split(' ').length, lineas: Math.round(document.querySelector('.losa:nth-child(1) b').getBoundingClientRect().height / parseFloat(getComputedStyle(document.querySelector('.losa b')).lineHeight)), entren: Math.round([...document.querySelectorAll('.losa b')].find(e => e.textContent === 'Entrenamientos').getBoundingClientRect().height / parseFloat(getComputedStyle(document.querySelector('.losa b')).lineHeight))}; })()")
        ok(not m['cortados'] and not m['desborda'] and m['entren'] == 1 and m['cols'] == (2 if ancho >= 351 else 1), f'A {ancho} px de ancho: nada cortado, «Entrenamientos» en una línea, {m["cols"]} columna(s): ' + json.dumps(m, ensure_ascii=False))
    p.set_viewport_size({'width': 390, 'height': 844}); p.wait_for_timeout(120)
    cap(p, '02-inicio')

    # --- el buscador del inicio ---
    p.fill('#buscar', 'promo'); p.wait_for_timeout(150)
    r = p.locator('.resultados .fila').all_inner_texts()
    ok(len(r) == 2 and 'SECCIÓN' in r[0].upper() and 'Precios y promociones' in r[0] and 'LISTA' in r[1].upper() and 'Promociones del mes' in r[1], 'Buscar «promo»: la sección de precios y la lista de promociones')
    ok(not p.locator('.losas').first.is_visible(), 'Mientras busca, los botones se apartan')
    cap(p, '03-buscar')
    p.fill('#buscar', 'bienvenida'); p.wait_for_timeout(150)
    ok('GUÍA' in p.locator('.resultados .fila').first.inner_text().upper() and 'Sesión de bienvenida' in p.locator('.resultados').inner_text(), 'Buscar una guía por su nombre')
    p.fill('#buscar', 'cayma'); p.wait_for_timeout(500)
    r = p.locator('.resultados .fila').all_inner_texts()
    ok(len(r) == 1 and 'DISTRITO' in r[0].upper() and 'Cayma' in r[0] and 'Sí hay crédito' in r[0], 'Buscar un distrito: trae la zona de crédito sin entrar a otra pantalla: ' + ' | '.join(r).replace('\n', ' '))
    ok(sum(1 for c in llamadas if c[0] == 'zc_lista') == 1, 'La lista de zonas se baja una sola vez, cuando hace falta')
    p.locator('.resultados .fila').first.click(); p.wait_for_timeout(200)
    ok(p.locator('h1').inner_text() == 'Cayma' and 'Sí hay crédito' in p.locator('.veredicto').inner_text() and 'En todo el distrito.' in texto(p), 'Abre el distrito con su veredicto')
    ok(p.url.endswith('#zonas&d=AREQUIPA%7CAREQUIPA%7CCAYMA'), 'La dirección recuerda el distrito')
    p.go_back(); p.wait_for_timeout(250)
    ok(p.locator('.hola h1').count() == 1 and p.input_value('#buscar') == 'cayma' and p.locator('.resultados .fila').count() == 1, 'Con «atrás» del teléfono vuelve al inicio, con su búsqueda tal cual')
    p.fill('#buscar', 'xyzq'); p.wait_for_timeout(150)
    ok('No encontré nada con «xyzq»' in texto(p), 'Si no hay nada, lo dice con sus palabras')
    p.click('text=Ver todas las secciones'); p.wait_for_timeout(100)
    ok(p.input_value('#buscar') == '' and p.locator('.losas').first.is_visible(), 'Y ofrece volver a ver todos los botones')

    # --- zonas de crédito ---
    p.click('.losa:has-text("Zonas de crédito")'); p.wait_for_timeout(250)
    t = texto(p)
    ok(p.locator('h1').inner_text() == 'Zonas de crédito' and 'Distritos de Arequipa' in t and p.locator('.filas .fila').count() == 3, 'Zonas: abre con los distritos de Arequipa')
    ok(p.locator('.tope .atras').inner_text().strip() == 'Volver' and p.locator('.tope .casa').count() == 0, 'Arriba, un solo botón grande: Volver')
    f = p.locator('.filas .fila').all_inner_texts()
    ok('Sí hay crédito' in f[0] and 'Sí, con excepciones' in f[1] and 'No hay crédito' in f[2], 'Cada distrito dice su respuesta con palabras, no solo con color')
    cap(p, '04-zonas')
    p.fill('#zona-q', 'las flores'); p.wait_for_timeout(150)
    t = texto(p)
    ok('Zonas sin crédito con ese nombre' in t and 'AA.HH. LAS FLORES' in t and 'No hay crédito · Cerro Colorado, Arequipa' in t and 'Si la que buscas no aparece, mira su distrito' in t, 'Buscar una urbanización restringida: dice que no hay crédito y explica cómo leer la lista')
    p.click('.fila:has-text("LAS FLORES")'); p.wait_for_timeout(200)
    t = texto(p)
    ok(p.locator('h1').inner_text() == 'Cerro Colorado' and 'Sí, con excepciones' in t and 'Menos en las 3 zonas de más abajo.' in t and 'Entrega directa, con servicio de entregador.' in t, 'El distrito: sí con excepciones, cuántas zonas y cómo se entrega')
    ok(p.input_value('#zona-f') == 'AA.HH. LAS FLORES' and p.locator('.zg li').count() == 1 and 'Zona peligrosa (1)' in t, 'Llega con la zona que buscó ya filtrada y su motivo')
    p.fill('#zona-f', ''); p.wait_for_timeout(100)
    ok(p.locator('.zg li').count() == 3 and p.locator('.zg h3').all_inner_texts() == ['Zona peligrosa (2)', 'Difícil acceso (1)'], 'Sin filtro salen las 3, agrupadas por motivo')
    ok(p.locator('.tope .casa').inner_text().strip() == 'Inicio', 'En una pantalla de segundo nivel aparece también «Inicio»')
    cap(p, '05-distrito')
    p.click('.tope .atras >> nth=0'); p.wait_for_timeout(250)
    ok(p.locator('h1').inner_text() == 'Zonas de crédito' and p.input_value('#zona-q') == 'las flores', '«Volver» regresa un paso: a la búsqueda de zonas')
    p.fill('#zona-q', 'chiguata'); p.wait_for_timeout(100); p.click('.fila:has-text("Chiguata")'); p.wait_for_timeout(200)
    ok('No hay crédito' in p.locator('.veredicto.none').inner_text() and 'En ningún punto de este distrito (fuera de cobertura).' in texto(p), 'Distrito sin crédito: lo dice claro y con el motivo')
    p.click('text=Buscar otro distrito'); p.wait_for_timeout(150)
    p.fill('#zona-q', 'surco'); p.wait_for_timeout(100)
    ok('Santiago de Surco' in texto(p) and 'Lima, Lima' in texto(p), 'Encuentra un distrito por su otro nombre (Surco) y dice de dónde es')
    p.fill('#zona-q', 'mollendo'); p.wait_for_timeout(100); p.click('.fila:has-text("Mollendo")'); p.wait_for_timeout(200)
    t = texto(p)
    ok('Solo dentro de la zona urbana.' in t and 'Courier. Si la venta es al contado, el cliente paga el COD por adelantado.' in t and 'Lista oficial de Rena Ware: Abril 2025' in t, 'Courier y solo zona urbana, con la vigencia de la lista')
    p.click('.tope .casa'); p.wait_for_timeout(200)
    ok(p.locator('.hola h1').count() == 1, '«Inicio» lleva al inicio desde cualquier parte')

    # --- ¿ya ganó Empiece Ya? ---
    p.click('.losa:has-text("Empiece Ya")'); p.wait_for_timeout(200)
    ok(p.locator('h1').inner_text() == '¿Ya ganó Empiece Ya?' and p.locator('#eya-q').count() == 1, 'Empiece Ya: solo pide un nombre')
    p.fill('#eya-q', 'ab'); p.click('button.boton'); p.wait_for_timeout(150)
    ok('Escribe al menos 3 letras' in texto(p) and not any(c[0] == 'eya_buscar' for c in llamadas), 'Con menos de 3 letras no busca y lo explica')
    p.fill('#eya-q', 'María Quispe'); p.press('#eya-q', 'Enter'); p.wait_for_timeout(300)
    t = texto(p)
    ok(('eya_buscar', {'p_token': 'tok-ase', 'p_q': 'María Quispe'}) in llamadas, 'Busca en la base con su sesión (también con Enter)')
    ok('Hay 2 personas con ese nombre que ya ganaron' in t and 'Maria Quispe de la Cruz' in t and 'Ganó Empiece Ya el 14 de octubre de 2026 (PB21 de 2026).' in t and 'División WV08 · nuestro equipo · código 1700001' in t, 'Sí ganó: quién, cuándo, su división y su código')
    ok('Premios: Utensilio 1.5L + Botella Filtrante RW (PB21)' in t and 'División LK03 · código 1600002' in t, 'Con sus premios, y distingue a la de otra división')
    ok('desde enero de 2024 hasta el cierre del 14 de octubre de 2026 (PB21)' in t, 'Dice hasta qué fecha llega la lista')
    cap(p, '06-empiece-si')
    p.fill('#eya-q', 'Zoila Zzzz'); p.click('button.boton'); p.wait_for_timeout(300)
    t = texto(p)
    ok('No aparece' in t and '«Zoila Zzzz» no figura entre los ganadores de Empiece Ya.' in t and 'Si ganó después de esa fecha, todavía no sale aquí.' in t, 'No ganó: lo dice, y avisa del límite de la lista')
    cap(p, '07-empiece-no')
    p.click('.tope .atras'); p.wait_for_timeout(250)

    # --- mis premios, mi Nivel Cero, mis puntos ---
    p.click('.avisos .tarj.ok'); p.wait_for_timeout(200)
    t = texto(p)
    ok(p.locator('h1').inner_text() == 'Mis premios' and 'Para recoger en la oficina' in t and 'Joyita 1 L' in t and 'Impulsa tu Negocio con Rena Ware · Afiliaciones - Nivel I · PB21' in t and 'Llegó el viernes 30 de octubre' in t and 'Av. Cayma 628, oficina 502' in t, 'Mis premios: lo que hay para recoger, de qué concurso, desde cuándo y dónde')
    ok('Ganados, todavía no llegan' in t and 'Set de Bowls 3 Piezas' in t and 'Anotado por la oficina: falta el resultado oficial' in t and 'Ya entregados (1)' in t and 'Mini Sartén 18cm' in t and 'entregado el 10 set' in t, 'También lo que viene en camino (sin prometer de más) y lo ya entregado')
    cap(p, '08-premios')
    p.go_back(); p.wait_for_timeout(250)
    p.click('.losa:has-text("Mi Nivel Cero")'); p.wait_for_timeout(200)
    t = texto(p)
    ok('Llevas 2 de 5 clases' in t and 'Te quedan 15 días: tienes hasta el jueves 19 de noviembre.' in t and 'Clases a las que fuiste' in t and 'Miércoles 21 de octubre, 4:00 p. m.' in t and 'Charla de la oportunidad' in t, 'Mi Nivel Cero: avance, plazo y las clases a las que fue')
    ok('Próximas clases que cuentan' in t and 'Hoy miércoles 4 de noviembre, 4:00 p. m.' in t and 'Viernes 6 de noviembre, 5:00 p. m.' in t and 'Las de Zoom no llevan asistencia' in t and 'aquí mismo se abre tu test' in t, 'Y las próximas que cuentan, con la regla del Zoom y lo del test')
    cap(p, '09-nivel')
    p.click('text=Ver el horario de la semana'); p.wait_for_timeout(200)
    ok(p.locator('h1').inner_text() == 'Horario' and 'Semana del 2 al 8 de noviembre' in texto(p), 'Desde ahí va al horario')
    p.go_back(); p.wait_for_timeout(200); p.go_back(); p.wait_for_timeout(250)
    p.click('.losa:has-text("Mis puntos")'); p.wait_for_timeout(200)
    t = texto(p)
    ok('2026-PB22 (15-28 oct)' in t and '1,213 puntos · 2 pedidos' in t and '480 puntos · 1 pedido' in t and 'Tu código de asesor: 1723832' in t, 'Mis puntos por período, con su código')
    p.click('.tope .atras'); p.wait_for_timeout(250)

    # --- precios: sale al portal con su sesión ---
    p.click('.losa:has-text("Precios y promociones")'); p.wait_for_timeout(600)
    ok(('traspaso_crear_asesor', {'p_token': 'tok-ase', 'p_modulo': 'cotizador'}) in llamadas and p.url == 'https://renaware-peru.nelson1614.workers.dev/#traspaso=cccccccc-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'Precios abre el portal ya con su sesión (traspaso): ' + p.url[:60])
    p.go_back(); p.wait_for_timeout(500)
    ok(p.locator('.hola h1').count() == 1 and p.locator('.losa[aria-busy]').count() == 0, 'Y con «atrás» vuelve a su inicio, listo para usarse')

    # --- entrenamientos: módulo, lección, visor, y volver paso a paso ---
    p.click('.losa:has-text("Entrenamientos")'); p.wait_for_timeout(200)
    t = texto(p)
    ok(p.locator('h1').inner_text() == 'Entrenamientos' and 'Empieza bien' in t and 'Llevas 1 de 2 lecciones completadas' in t, 'Entrenamientos: los módulos con su progreso')
    ok('Lección oculta' not in t and 'Modo edición' not in t and 'Progreso del equipo' not in t, 'Asesor no ve lo oculto ni lo de la oficina')
    p.click('text=Empieza bien'); p.wait_for_timeout(150)
    t = texto(p)
    ok('Sesión de bienvenida' in t and 'Guía PDF' in t and 'Video' in t and 'Material en preparación' in t, 'Módulo: lecciones con sus materiales (solo lo que hay)')
    ok(p.url.endswith('#entrenamientos&modulo=m1') and '← Módulos' not in t, 'El enlace recuerda el módulo y no hay dos formas de volver: ' + p.url.split('/')[-1])
    cap(p, '10-modulo')
    p.click('text=Sesión de bienvenida'); p.wait_for_timeout(150)
    t = texto(p)
    ok('Guía' in t and 'Guía de la lección' in t and '6 páginas' in t and 'Cómo fue la primera sesión' in t and 'YouTube' in t, 'Lección: guía PDF con páginas y video de YouTube')
    ok('Completada · desmarcar' in t, 'Muestra la lección como completada')
    cap(p, '11-leccion')
    p.click('text=Completada · desmarcar'); p.wait_for_timeout(200)
    ok(('ent_progreso_marcar', {'p_token': 'tok-ase', 'p_leccion': 'l1', 'p_estado': 'nada'}) in llamadas and 'Marcar como completada' in texto(p), 'Desmarcar manda «nada» y repinta')
    p.click('text=Guía de la lección'); p.wait_for_timeout(600)
    ok(p.locator('.visor').count() == 1 and 'Descargar' in p.locator('.visor').inner_text(), 'Abre el visor con botón de descargar')
    ok('No se pudo mostrar aquí' in p.locator('.visor').inner_text(), 'Sin pdf.js (bloqueado en esta prueba) avisa y deja descargar')
    ok(p.locator('.visor .pie a').get_attribute('href') == SB + '/storage/v1/object/public/entrenamientos/t1/guia.pdf?download=guia.pdf', 'La descarga lleva el nombre del archivo')
    p.go_back(); p.wait_for_timeout(250)
    ok(p.locator('.visor').count() == 0 and p.url.endswith('#entrenamientos&leccion=l1') and 'Guía de la lección' in texto(p), '«Atrás» del teléfono cierra el visor y deja la lección: ' + p.url.split('#')[-1])
    p.click('text=Guía de la lección'); p.wait_for_timeout(400); p.click('.visor .x'); p.wait_for_timeout(250)
    ok(p.locator('.visor').count() == 0 and p.url.endswith('#entrenamientos&leccion=l1'), 'La × también lo cierra')
    p.click('.tope .atras >> nth=0'); p.wait_for_timeout(250)
    ok(p.url.endswith('#entrenamientos&modulo=m1') and 'Programa Empiece Ya' in texto(p), '«Volver» desde la lección: al módulo')
    p.click('.tope .atras >> nth=0'); p.wait_for_timeout(250)
    ok(p.url.endswith('#entrenamientos') and 'Consigue citas' in texto(p), '«Volver» desde el módulo: a la lista de módulos')
    p.click('.tope .atras'); p.wait_for_timeout(250)
    ok(p.url.endswith('#inicio') and p.locator('.hola h1').count() == 1, '«Volver» desde la lista: al inicio')

    # --- listas y horario, desde sus botones ---
    p.click('.losa:has-text("Listas y fotos")'); p.wait_for_timeout(200)
    t = texto(p)
    ok('Promociones del mes' in t and 'Vigente hasta el 30 nov' in t and 'Para el cliente' in t and 'Noviembre 2026' in t, 'Listas: la promo vigente con su vigencia y audiencia')
    ok('Precio regular · autocompra' not in t, 'Asesor no ve documentos sin archivo')
    ok('Venció el 20 oct' in t, 'Marca la foto vencida')
    ok(p.locator('.doc a.mini').first.get_attribute('href').endswith('?download=promos.pdf'), 'Descargar con nombre')
    cap(p, '12-listas')
    p.click('.tope .atras'); p.wait_for_timeout(250)
    p.click('.avisos .tarj:has-text("Lo que sigue")'); p.wait_for_timeout(200)
    t = texto(p)
    ok('Semana del 2 al 8 de noviembre' in t and 'Miércoles 4' in t and 'hoy' in t and 'Taller de cocina' in t and 'Entrar al Zoom' in t, 'Horario (desde el aviso): semana con fechas, hoy y el Zoom')
    ok('Desayuno de líderes' not in t and 'Charla de la oportunidad' not in t, 'Asesor no ve lo apagado ni lo de la oficina')
    cap(p, '13-horario')
    p.click('button[aria-label="Semana siguiente"]'); p.wait_for_timeout(300)
    t = texto(p)
    ok('Semana del 9 al 15 de noviembre' in t and 'Inicia el PB24' in t and 'Lanzamiento del nuevo concurso' in t and 'Ir a esta semana' in t, 'Semana siguiente: inicio de período con el lanzamiento')
    ok(p.url.endswith('#horario&semana=2026-11-09'), 'El enlace recuerda la semana')
    p.click('text=Copiar para WhatsApp'); p.wait_for_timeout(200)
    txt = p.evaluate("navigator.clipboard.readText().catch(() => '')")
    ok(txt is None or txt == '' or ('*Semana del 9 al 15 de noviembre*' in txt and 'inicia el PB24' in txt and '• 10:00\u00a0a.\u00a0m. — Lanzamiento' in txt), 'Texto para WhatsApp (si hay portapapeles)')

    # --- salir ---
    p.click('.tope .atras'); p.wait_for_timeout(250)
    p.click('.pie-a >> text=Salir'); p.wait_for_timeout(150)
    ok('¿Salir de la plataforma en este teléfono?' in p.locator('.hoja').inner_text(), 'Salir pregunta antes (un toque sin querer no la saca)')
    p.click('.hoja >> text=Sí, adelante'); p.wait_for_timeout(200)
    ok('Tu DNI' in texto(p) and p.evaluate("localStorage.getItem('rw_asesor_token')") is None, 'Al salir vuelve a pedir el DNI y borra la sesión')
    ctx.close()

    # --- entrar por enlace directo con sesión; «Volver» sin historial ---
    ctx, p = nuevo('#listas')
    p.evaluate("localStorage.setItem('rw_asesor_token', JSON.stringify('tok-ase'))"); p.reload(); p.wait_for_timeout(500)
    ok(p.locator('h1').inner_text() == 'Listas y fotos' and 'Promociones del mes' in texto(p), 'Con sesión guardada y #listas abre directo en Listas')
    p.click('.tope .atras'); p.wait_for_timeout(250)
    ok(p.locator('.hola h1').count() == 1 and p.url.endswith('#inicio'), 'Si llegó por un enlace, «Volver» igual la lleva al inicio')
    ok(p.evaluate("JSON.parse(localStorage.getItem('rw_zonas_v1')) === null"), 'Sin haber buscado zonas no se bajó la lista')
    ctx.close()

    # --- quien completó sus clases: el test ---
    PANEL['modo'] = 'logro'
    ctx, p = nuevo()
    p.evaluate("localStorage.setItem('rw_asesor_token', JSON.stringify('tok-ase'))"); p.reload(); p.wait_for_timeout(500)
    a = p.locator('.avisos a.tarj')
    ok(a.count() == 1 and 'Completaste tus 5 clases: ya puedes rendir tu test' in a.inner_text() and 'Tienes hasta el miércoles 18 de noviembre' in a.inner_text() and a.get_attribute('href') == '/test/', 'Con las 5 clases, el inicio la manda a su test (/test/, misma sesión)')
    p.click('.losa:has-text("Mi Nivel Cero")'); p.wait_for_timeout(200)
    t = texto(p)
    ok('Completaste tus 5 clases el martes 3 de noviembre.' in t and 'Ya puedes rendirlo.' in t and p.locator('a.boton[href="/test/"]').inner_text() == 'Rendir mi test' and p.locator('.paso.hecho').count() == 5, 'Mi Nivel Cero: los 5 círculos llenos y el botón del test')
    cap(p, '14-nivel-test')
    ctx.close()

    # --- una asesora sin nada personal, y cuando lo personal falla ---
    PANEL['modo'] = 'vacio'
    ctx, p = nuevo()
    p.evaluate("localStorage.setItem('rw_asesor_token', JSON.stringify('tok-ase'))"); p.reload(); p.wait_for_timeout(500)
    ok(p.locator('.hola h1').inner_text() == 'Hola, Ana' and p.locator('.avisos').count() == 0 and p.locator('.losa b').all_inner_texts() == ['Precios y promociones', 'Zonas de crédito', 'Listas y fotos', '¿Ya ganó Empiece Ya?', 'Entrenamientos', 'Horario', 'Mis premios', 'Mis puntos'], 'Sin Nivel Cero, premios ni local: inicio limpio con sus 8 botones')
    p.click('.losa:has-text("Mis premios")'); p.wait_for_timeout(150)
    ok('Todavía no tienes premios registrados' in texto(p), 'Mis premios vacío lo dice sin alarmar')
    p.click('.tope .atras'); p.wait_for_timeout(200); p.click('.losa:has-text("Mis puntos")'); p.wait_for_timeout(150)
    ok('todavía no está enlazado a tu código de asesor' in texto(p), 'Mis puntos sin código: explica qué falta')
    ctx.close()
    PANEL['modo'] = 'falla'
    ctx, p = nuevo()
    p.evaluate("localStorage.setItem('rw_asesor_token', JSON.stringify('tok-ase'))"); p.reload(); p.wait_for_timeout(500)
    ok('No pude cargar tus datos' in texto(p) and p.locator('.losa').count() == 8, 'Si lo personal falla, lo avisa y lo demás sigue funcionando')
    PANEL['modo'] = 'normal'
    p.click('.avisos >> text=Reintentar'); p.wait_for_timeout(400)
    ok(p.locator('.hola h1').inner_text() == 'Hola, Fley' and 'Tienes un premio por recoger' in texto(p), '«Reintentar» lo trae sin recargar la página')
    ctx.close()

    # --- sesión vencida ---
    ctx, p = nuevo()
    p.evaluate("localStorage.setItem('rw_asesor_token', JSON.stringify('tok-viejo'))"); p.reload(); p.wait_for_timeout(500)
    ok('Tu sesión venció' in texto(p) and 'Tu DNI' in texto(p), 'Sesión vencida: vuelve a pedir el DNI y lo explica')
    ctx.close()

    # ---------- 2. Traspaso desde la plataforma (asesor) ----------
    ctx = br.new_context(viewport={'width': 390, 'height': 844}, is_mobile=True)
    ctx.route('**/*', lambda route, request: route.fulfill(status=200, headers={'content-type': 'application/json'}, body=json.dumps({'ok': True, 'tipo': 'asesor', 'token': 'tok-ase', 'nombre': 'fley rojas'})) if request.url.endswith('/functions/v1/traspaso') else manejar(route, request))
    p = ctx.new_page(); p.on('pageerror', lambda e: errores.append(str(e)))
    p.goto(f'http://127.0.0.1:{PUERTO}/entrenamientos/#horario&traspaso=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'); p.wait_for_timeout(700)
    ok('Semana del 2 al 8' in texto(p) and 'traspaso' not in p.url and p.evaluate("JSON.parse(localStorage.getItem('rw_asesor_token'))") == 'tok-ase', 'Traspaso de asesor (por la dirección vieja /entrenamientos/): entra directo a Horario y limpia el código')
    ok('/asesores/' in p.url and p.url.endswith('#horario'), 'La dirección vieja lleva a /asesores/ conservando la pantalla: ' + p.url.split('/', 3)[-1])
    ctx.close()

    # ---------- 3. Oficina ----------
    ctx, p = nuevo('#oficina')
    ok('Clave de la oficina' in texto(p), '#oficina pide la clave')
    p.fill('#clave', 'mala'); p.click('button.boton'); p.wait_for_timeout(200)
    ok('no es correcta' in texto(p), 'Clave incorrecta: lo dice')
    p.fill('#clave', 'clave'); p.click('button.boton'); p.wait_for_timeout(400)
    t = texto(p)
    ok('Modo edición' in t and 'Lección oculta' not in t and 'Nuevo módulo' in t and 'Progreso del equipo' in t and 'Fley Rojas' in t and '1/2' in t, 'Oficina: modo edición, nuevo módulo y progreso del equipo')
    cap(p, '10-oficina-modulos')
    p.click('text=+ Nuevo módulo'); p.wait_for_timeout(150)
    ok(p.locator('.hoja').count() == 1 and 'Nuevo módulo' in p.locator('.hoja').inner_text(), 'Abre la hoja de nuevo módulo')
    p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(150)
    ok('Falta: Nombre del módulo' in p.locator('.hoja').inner_text(), 'Valida el nombre')
    p.fill('#f_titulo', 'Trabaja en ti'); p.fill('#f_descripcion', 'Liderazgo'); p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(400)
    ok(('ent_modulo_guardar', {'p_token': 'tok-adm', 'p_id': None, 'p_datos': {'titulo': 'Trabaja en ti', 'descripcion': 'Liderazgo', 'activo': True}}) in llamadas, 'Guarda el módulo con sus datos')
    ok(p.locator('.hoja').count() == 0, 'Cierra la hoja al guardar')
    p.click('text=Empieza bien'); p.wait_for_timeout(150)
    t = texto(p)
    ok('Lección oculta' in t and 'oculta' in t and '3 la vieron · 1 la completaron' in t and 'Nueva lección' in t and 'Ordenar' in t, 'Oficina ve lecciones ocultas y los conteos')
    cap(p, '11-oficina-modulo')
    p.click('text=Ordenar'); p.wait_for_timeout(150)
    p.click('.hoja button[aria-label="Bajar"] >> nth=0'); p.click('.hoja >> text=Guardar orden'); p.wait_for_timeout(300)
    ok(('ent_ordenar', {'p_token': 'tok-adm', 'p_que': 'leccion', 'p_ids': ['l2', 'l1', 'l3']}) in llamadas, 'Ordenar manda el nuevo orden')
    p.click('text=Sesión de bienvenida'); p.wait_for_timeout(150)
    ok('Agregar material' in texto(p) and 'Marcar como completada' not in texto(p), 'Lección de oficina: agrega material, sin progreso propio')
    p.click('text=+ Agregar material'); p.wait_for_timeout(150)
    ok('Tipo de material' in p.locator('.hoja').inner_text() and p.locator('#f_archivo').count() == 1, 'Hoja de material con archivo y enlace')
    p.select_option('#f_tipo', 'video'); p.fill('#f_url', 'https://youtu.be/abc'); p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(400)
    ok(('ent_recurso_guardar', {'p_token': 'tok-adm', 'p_id': None, 'p_datos': {'tipo': 'video', 'titulo': '', 'url': 'https://youtu.be/abc', 'activo': True, 'leccion_id': 'l1'}}) in llamadas, 'Guarda un video por enlace')
    # Subida de archivo (imagen) con portada
    p.click('text=+ Agregar material'); p.wait_for_timeout(150)
    p.set_input_files('#f_archivo', {'name': 'Guía rápida.png', 'mimeType': 'image/png', 'buffer': PNG})
    p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(900)
    sub = [c for c in llamadas if c[0] == 'storage']
    ok(len(sub) >= 1 and sub[0][1] == '11111111-2222-4333-8444-555555555555/Guia-rapida.png' and sub[0][2] == 'image/png', 'Sube el archivo a <ticket>/<nombre limpio>: ' + str(sub[:1]))
    ok(any(c[0] == 'storage' and c[1].endswith('/portada.jpg') for c in llamadas), 'Sube también la vista previa (portada.jpg)')
    rec = [c for c in llamadas if c[0] == 'ent_recurso_guardar' and c[1]['p_datos'].get('ruta')]
    ok(rec and rec[-1][1]['p_datos']['ruta'] == '11111111-2222-4333-8444-555555555555/Guia-rapida.png' and rec[-1][1]['p_datos']['archivo'] == 'Guía rápida.png' and rec[-1][1]['p_datos'].get('portada') == '11111111-2222-4333-8444-555555555555/portada.jpg', 'Guarda el material con ruta, nombre original y portada')
    cap(p, '12-oficina-leccion')
    # Listas (oficina)
    p.click('nav.pestanas >> text=Listas'); p.wait_for_timeout(150)
    t = texto(p)
    ok('Precio regular · autocompra' in t and 'Todavía no se subió el archivo' in t and 'Subir archivo' in t and 'Subir nueva versión' in t and 'Ver las 2 versiones' in t and 'Nuevo documento' in t and 'Nueva categoría' in t, 'Listas de oficina: subir, versiones, nuevo documento y categoría')
    cap(p, '13-oficina-listas')
    p.click('text=Ver las 2 versiones'); p.wait_for_timeout(100)
    ok('Octubre 2026' in texto(p), 'Despliega las versiones anteriores')
    p.click('text=Subir nueva versión'); p.wait_for_timeout(150)
    ok('Nueva versión · Promociones del mes' in p.locator('.hoja').inner_text() and 'Vigente hasta' in p.locator('.hoja').inner_text(), 'Hoja de nueva versión con vigencia')
    p.set_input_files('#f_archivo', {'name': 'Promos Dic.png', 'mimeType': 'image/png', 'buffer': PNG})
    p.fill('#f_nota', 'Diciembre'); p.fill('#f_vigente_hasta', '2026-12-31'); p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(900)
    ver = [c for c in llamadas if c[0] == 'doc_version_guardar']
    ok(ver and ver[-1][1]['p_documento'] == 'd1' and ver[-1][1]['p_datos']['nota'] == 'Diciembre' and ver[-1][1]['p_datos']['vigente_hasta'] == '2026-12-31' and ver[-1][1]['p_datos']['ruta'].endswith('/Promos-Dic.png'), 'Guarda la versión con nota, vigencia y ruta')
    p.click('text=+ Nuevo documento >> nth=0'); p.wait_for_timeout(150)
    p.fill('#f_titulo', 'Concurso Tetera 3L'); p.select_option('#f_audiencia', 'cliente'); p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(400)
    doc = [c for c in llamadas if c[0] == 'doc_documento_guardar']
    ok(doc and doc[-1][1]['p_datos'] == {'titulo': 'Concurso Tetera 3L', 'descripcion': '', 'categoria_id': 'precios', 'audiencia': 'cliente', 'activo': True, 'clave': '', 'roles': ['admin', 'asistente', 'asesor']}, 'Guarda el documento nuevo')
    # Horario (oficina)
    p.click('nav.pestanas >> text=Horario'); p.wait_for_timeout(150)
    t = texto(p)
    ok('Desayuno de líderes' in t and 'Solo oficina' in t and 'No hay esta semana' in t and 'Sí hay esta semana' in t and 'Asistencia en Nivel Cero · 4 asistentes' in t and 'Horario habitual' in t and 'Tomar asistencia' in t, 'Horario de oficina: todo, con apagados y asistencia')
    cap(p, '14-oficina-horario')
    p.click('text=Sí hay esta semana'); p.wait_for_timeout(300)
    ok(('hor_evento_guardar', {'p_token': 'tok-adm', 'p_id': 'e4', 'p_datos': {'activo': True}}) in llamadas, 'Prender manda solo activo')
    p.click('text=Esta semana no hay >> nth=0'); p.wait_for_timeout(300)
    ok(any(c[0] == 'hor_evento_guardar' and c[1]['p_datos'] == {'activo': False} for c in llamadas), 'Apagar manda activo=false')
    p.click('text=+ Agregar algo este día >> nth=0'); p.wait_for_timeout(150)
    ok('Agregar evento · lunes 2 de noviembre' in p.locator('.hoja').inner_text(), 'Agregar evento en el día elegido')
    p.fill('#f_titulo', 'Clase extra'); p.fill('#f_hora', '18:30'); p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(400)
    ev = [c for c in llamadas if c[0] == 'hor_evento_guardar' and c[1]['p_id'] is None]
    ok(ev and ev[-1][1]['p_datos']['titulo'] == 'Clase extra' and ev[-1][1]['p_datos']['fecha'] == '2026-11-02' and ev[-1][1]['p_datos']['hora'] == '18:30' and ev[-1][1]['p_datos']['asistencia'] is True, 'Guarda el evento suelto con fecha, hora y asistencia')
    p.click('text=Horario habitual'); p.wait_for_timeout(150)
    ok('Lanzamiento del nuevo concurso' in p.locator('.hoja').inner_text() and 'Solo inicio de período' in p.locator('.hoja').inner_text() and 'Solo si no hay lanzamiento' in p.locator('.hoja').inner_text(), 'Horario habitual con sus marcas')
    cap(p, '15-oficina-habitual')
    p.click('.hoja >> text=Editar >> nth=0'); p.wait_for_timeout(150)
    p.fill('#f_hora', '16:30'); p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(400)
    pl = [c for c in llamadas if c[0] == 'hor_plantilla_guardar']
    ok(pl and pl[-1][1]['p_id'] == 'p1' and pl[-1][1]['p_datos']['hora'] == '16:30' and pl[-1][1]['p_datos']['dia'] == 3 and pl[-1][1]['p_datos']['excepto_inicio_periodo'] is False, 'Edita la plantilla (día como número, marca nueva)')
    # Zoom: la casilla de asistencia se apaga sola
    p.click('text=Horario habitual'); p.wait_for_timeout(150)
    p.click('.hoja >> text=+ Agregar al horario habitual'); p.wait_for_timeout(150)
    ok(p.locator('#f_asistencia').is_checked() and not p.locator('#f_asistencia').is_disabled(), 'Presencial: asistencia marcada y editable')
    p.select_option('#f_modo', 'zoom'); p.wait_for_timeout(100)
    ok(not p.locator('#f_asistencia').is_checked() and p.locator('#f_asistencia').is_disabled() and 'Por Zoom no se toma asistencia' in p.locator('.hoja').inner_text(), 'Zoom: asistencia apagada, bloqueada y explicada')
    p.fill('#f_titulo', 'Zoom extra'); p.fill('#f_hora', '08:00'); p.check('#f_solo_inicio_periodo'); p.check('#f_excepto_inicio_periodo'); p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(200)
    ok('Elige una sola' in p.locator('.hoja').inner_text(), 'No deja marcar «solo inicio» y «solo no inicio» a la vez')
    p.uncheck('#f_solo_inicio_periodo'); p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(400)
    pl = [c for c in llamadas if c[0] == 'hor_plantilla_guardar' and c[1]['p_id'] is None]
    ok(pl and pl[-1][1]['p_datos']['modo'] == 'zoom' and pl[-1][1]['p_datos']['asistencia'] is False and pl[-1][1]['p_datos']['excepto_inicio_periodo'] is True, 'Guarda la plantilla de Zoom sin asistencia y solo cuando no inicia período')
    # Modo edición apagado = vista de asesor
    p.click('.modo-ed button.interruptor'); p.wait_for_timeout(150)
    ok('Esta semana no hay' not in texto(p) and 'Desayuno de líderes' in texto(p), 'Con edición apagada no hay botones de editar')
    ctx.close()

    # ---------- 4. Oficina desde la plataforma (sesión de correo) ----------
    ctx = br.new_context(viewport={'width': 390, 'height': 844}, is_mobile=True)
    def manejar2(route, request):
        if request.url.endswith('/functions/v1/traspaso'):
            return route.fulfill(status=200, headers={'content-type': 'application/json'}, body=json.dumps({'ok': True, 'tipo': 'staff', 'admin_token': 'tok-adm'}))
        if '/rpc/traspaso_crear' in request.url:
            llamadas.append(('traspaso_crear', request.headers.get('authorization')))
            return route.fulfill(status=200, headers={'content-type': 'application/json'}, body=json.dumps('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'))
        return manejar(route, request)
    ctx.route('**/*', manejar2)
    p = ctx.new_page(); p.on('pageerror', lambda e: errores.append(str(e)))
    p.goto(f'http://127.0.0.1:{PUERTO}/asesores/')
    p.evaluate("localStorage.setItem('sb-kiexpdaaoegbtesqmaff-auth-token', JSON.stringify({access_token: 'jwt-staff', refresh_token: 'r', expires_at: Math.floor(Date.now()/1000) + 3600}))")
    p.reload(); p.wait_for_timeout(500)
    ok('Modo edición' in texto(p) and ('traspaso_crear', 'Bearer jwt-staff') in llamadas and p.evaluate("JSON.parse(localStorage.getItem('rw_ent_admin'))") == 'tok-adm', 'Con la sesión de la plataforma entra como oficina sin clave (traspaso con su JWT)')
    ok('Inicio' in texto(p), 'Ofrece volver al inicio de la plataforma')
    ctx.close()

    ok(not errores, 'Sin errores de JavaScript' + ('' if not errores else ': ' + '; '.join(errores[:3])))
    br.close()

srv.shutdown()
print('\n' + ('TODO BIEN' if not fallas else f'{fallas} FALLAS'))
sys.exit(1 if fallas else 0)
