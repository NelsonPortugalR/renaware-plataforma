# Pruebas de la página de Entrenamientos (public/entrenamientos/index.html) en un Chromium real
# con un Supabase simulado. Correr: python3 pruebas/prueba_entrenamientos.py [carpeta_capturas]
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
                       {'id': 'p2', 'dia': 4, 'hora': '10:00', 'titulo': 'Lanzamiento del nuevo concurso', 'descripcion': None, 'lugar': 'Oficina', 'modo': 'presencial', 'facilitador': None, 'enlace': None, 'tipo': 'evento', 'asistencia': True, 'solo_inicio_periodo': True, 'publico': True, 'orden': 2, 'activo': True}] if rol == 'admin' else None,
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
            if b['p_celular'] == '987654321': return route.fulfill(status=200, headers=m, body=json.dumps({'token': 'tok-ase', 'nombre': 'fley rojas', 'celular': '987654321'}))
            return route.fulfill(status=400, headers=m, body=json.dumps({'message': 'Ese numero no esta habilitado'}))
        if fn == 'admin_login':
            if b['p_clave'] == 'clave': return route.fulfill(status=200, headers=m, body=json.dumps('tok-adm'))
            return route.fulfill(status=400, headers=m, body=json.dumps({'message': 'Clave incorrecta'}))
        if tok not in ('tok-ase', 'tok-adm'): return route.fulfill(status=400, headers=m, body=json.dumps({'message': 'Sesion invalida'}))
        rol = 'admin' if tok == 'tok-adm' else 'asesor'
        if fn == 'ent_datos': return route.fulfill(status=200, headers=m, body=json.dumps(datos(rol)))
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
    return route.continue_()

def texto(p): return p.locator('#app').inner_text().replace('\u00a0', ' ')
def cap(p, n):
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
        p.goto(f'http://127.0.0.1:{PUERTO}/entrenamientos/' + hash)
        p.wait_for_timeout(250)
        return ctx, p

    # ---------- 1. Asesor sin sesión ----------
    ctx, p = nuevo()
    ok('Tu celular' in texto(p) and 'Soy de la oficina' in texto(p), 'Sin sesión pide el celular')
    cap(p, '01-entrar')
    p.fill('#celular', '911111111'); p.click('button.boton'); p.wait_for_timeout(200)
    ok('no está habilitado' in texto(p), 'Celular no habilitado: lo dice')
    p.fill('#celular', '987 654 321'); p.click('button.boton'); p.wait_for_timeout(400)
    ok(p.evaluate("JSON.parse(localStorage.getItem('rw_asesor_token'))") == 'tok-ase', 'Guarda la sesión de asesor en rw_asesor_token (la de la plataforma)')
    t = texto(p)
    ok('Fley' in t and 'Empieza bien' in t and 'Llevas 1 de 2 lecciones completadas' in t, 'Asesor ve los módulos con su progreso: ' + t[:80].replace('\n', ' '))
    ok('Lección oculta' not in t and 'Modo edición' not in t and 'Progreso del equipo' not in t, 'Asesor no ve lo oculto ni lo de la oficina')
    cap(p, '02-modulos')
    p.click('text=Empieza bien'); p.wait_for_timeout(150)
    t = texto(p)
    ok('Sesión de bienvenida' in t and 'Guía PDF' in t and 'Video' in t and 'Material en preparación' in t, 'Módulo: lecciones con sus materiales (solo lo que hay)')
    ok(p.url.endswith('#entrenamientos&modulo=m1'), 'El enlace recuerda el módulo: ' + p.url.split('/')[-1])
    cap(p, '03-modulo')
    p.click('text=Sesión de bienvenida'); p.wait_for_timeout(150)
    t = texto(p)
    ok('Guía' in t and 'Guía de la lección' in t and '6 páginas' in t and 'Cómo fue la primera sesión' in t and 'YouTube' in t, 'Lección: guía PDF con páginas y video de YouTube')
    ok('Completada · desmarcar' in t, 'Muestra la lección como completada')
    cap(p, '04-leccion')
    p.click('text=Completada · desmarcar'); p.wait_for_timeout(200)
    ok(('ent_progreso_marcar', {'p_token': 'tok-ase', 'p_leccion': 'l1', 'p_estado': 'nada'}) in llamadas and 'Marcar como completada' in texto(p), 'Desmarcar manda «nada» y repinta')
    p.click('text=Guía de la lección'); p.wait_for_timeout(600)
    ok(p.locator('.visor').count() == 1 and 'Descargar' in p.locator('.visor').inner_text(), 'Abre el visor con botón de descargar')
    ok('No se pudo mostrar aquí' in p.locator('.visor').inner_text(), 'Sin pdf.js (bloqueado en esta prueba) avisa y deja descargar')
    ok(p.locator('.visor .pie a').get_attribute('href') == SB + '/storage/v1/object/public/entrenamientos/t1/guia.pdf?download=guia.pdf', 'La descarga lleva el nombre del archivo')
    cap(p, '05-visor')
    p.click('.visor .x'); p.wait_for_timeout(200)
    ok(p.locator('.visor').count() == 0 and p.url.endswith('#entrenamientos&leccion=l1'), 'Cierra el visor y vuelve al enlace de la lección: ' + p.url.split('#')[-1])
    # Listas
    p.click('nav.pestanas >> text=Listas'); p.wait_for_timeout(150)
    t = texto(p)
    ok('Promociones del mes' in t and 'Vigente hasta el 30 nov' in t and 'Para el cliente' in t and 'Noviembre 2026' in t, 'Listas: la promo vigente con su vigencia y audiencia')
    ok('Precio regular · autocompra' not in t, 'Asesor no ve documentos sin archivo')
    ok('Venció el 20 oct' in t, 'Marca la foto vencida')
    ok(p.locator('.doc a.mini').first.get_attribute('href').endswith('?download=promos.pdf'), 'Descargar con nombre')
    cap(p, '06-listas')
    # Horario
    p.click('nav.pestanas >> text=Horario'); p.wait_for_timeout(150)
    t = texto(p)
    ok('Semana del 2 al 8 de noviembre' in t and 'Miércoles 4' in t and 'hoy' in t and 'Taller de cocina' in t and 'Entrar al Zoom' in t, 'Horario: semana con fechas, hoy y el Zoom')
    ok('Desayuno de líderes' not in t and 'Charla de la oportunidad' not in t, 'Asesor no ve lo apagado ni lo de la oficina')
    cap(p, '07-horario')
    p.click('button[aria-label="Semana siguiente"]'); p.wait_for_timeout(300)
    t = texto(p)
    ok('Semana del 9 al 15 de noviembre' in t and 'Inicia el PB24' in t and 'Lanzamiento del nuevo concurso' in t and 'Ir a esta semana' in t, 'Semana siguiente: inicio de período con el lanzamiento')
    ok(p.url.endswith('#horario&semana=2026-11-09'), 'El enlace recuerda la semana')
    cap(p, '08-horario-siguiente')
    p.click('text=Copiar para WhatsApp'); p.wait_for_timeout(200)
    txt = p.evaluate("navigator.clipboard.readText().catch(() => '')")
    ok(txt is None or txt == '' or ('*Semana del 9 al 15 de noviembre*' in txt and 'inicia el PB24' in txt and '• 10:00\u00a0a.\u00a0m. — Lanzamiento' in txt), 'Texto para WhatsApp (si hay portapapeles)')
    # Entrar por enlace directo con sesión
    ctx.close()
    ctx, p = nuevo('#listas')
    p.evaluate("localStorage.setItem('rw_asesor_token', JSON.stringify('tok-ase'))"); p.reload(); p.wait_for_timeout(400)
    ok(p.locator('nav.pestanas button[aria-selected="true"]').inner_text() == 'Listas', 'Con sesión guardada y #listas abre directo en Listas')
    ctx.close()

    # ---------- 2. Traspaso desde la plataforma (asesor) ----------
    ctx = br.new_context(viewport={'width': 390, 'height': 844}, is_mobile=True)
    ctx.route('**/*', lambda route, request: route.fulfill(status=200, headers={'content-type': 'application/json'}, body=json.dumps({'ok': True, 'tipo': 'asesor', 'token': 'tok-ase', 'nombre': 'fley rojas'})) if request.url.endswith('/functions/v1/traspaso') else manejar(route, request))
    p = ctx.new_page(); p.on('pageerror', lambda e: errores.append(str(e)))
    p.goto(f'http://127.0.0.1:{PUERTO}/entrenamientos/#horario&traspaso=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'); p.wait_for_timeout(500)
    ok('Semana del 2 al 8' in texto(p) and 'traspaso' not in p.url and p.evaluate("JSON.parse(localStorage.getItem('rw_asesor_token'))") == 'tok-ase', 'Traspaso de asesor: entra directo a Horario y limpia el código')
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
    ok('Lanzamiento del nuevo concurso' in p.locator('.hoja').inner_text() and 'Solo inicio de período' in p.locator('.hoja').inner_text(), 'Horario habitual con sus marcas')
    cap(p, '15-oficina-habitual')
    p.click('.hoja >> text=Editar >> nth=0'); p.wait_for_timeout(150)
    p.fill('#f_hora', '16:30'); p.click('.hoja button.boton[type=submit]'); p.wait_for_timeout(400)
    pl = [c for c in llamadas if c[0] == 'hor_plantilla_guardar']
    ok(pl and pl[-1][1]['p_id'] == 'p1' and pl[-1][1]['p_datos']['hora'] == '16:30' and pl[-1][1]['p_datos']['dia'] == 3, 'Edita la plantilla (día como número)')
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
    p.goto(f'http://127.0.0.1:{PUERTO}/entrenamientos/')
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
