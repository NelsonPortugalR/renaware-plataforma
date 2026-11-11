# La descarga del respaldo en un Chromium real: el navegador comprime la copia (gzip) y la guarda como archivo.
# El resto de la pantalla se prueba en pruebas/prueba.js. Correr: python3 pruebas/prueba_respaldo.py
import gzip, json, os, sys, threading, http.server, socketserver, functools, tempfile, time, zipfile
from playwright.sync_api import sync_playwright

RAIZ = os.path.join(os.path.dirname(__file__), '..', 'public')
SB = 'https://kiexpdaaoegbtesqmaff.supabase.co'
fallas = 0
def ok(c, t):
    global fallas
    print(('✔ ' if c else '✗ ') + t)
    if not c: fallas += 1

class Silencioso(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
srv = socketserver.TCPServer(('127.0.0.1', 0), functools.partial(Silencioso, directory=RAIZ))
PUERTO = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()

TABLAS = {'(estructura)': {'columnas': ['script'], 'filas': 1, 'datos': [['create table public.clientes (id uuid);']]}}
for i in range(40):   # 40 tablas de 300 filas: suficiente para que comprimir valga la pena
    TABLAS['public.t%02d' % i] = {'columnas': ['id', 'nombre', 'monto'], 'filas': 300,
                                 'datos': [[k, 'Cliente número %d de Arequipa «ñ»' % k, k * 1.5] for k in range(300)]}
ESTADO = {'ultima': {'id': 1, 'ok': True, 'slot': 'dia-3', 'fin': '2026-11-11T07:40:02+00:00', 'tablas': 40, 'filas': 12000},
          'falla': None, 'copias': [{'slot': 'dia-3', 'tomado_en': '2026-11-11T07:40:00+00:00', 'tablas': 40, 'filas': 12000, 'bytes': 1}],
          'descarga': None, 'descarga_archivos': None, 'base': {'bytes': 48344211, 'limite': 524288000, 'respaldo_bytes': 8962048},
          'archivos': [{'carpeta': 'imagenes', 'publica': True, 'archivos': 3, 'bytes': 9}], 'cambios': [], 'hoy': '2026-11-11'}
ARCHIVOS = [{'nombre': 'lista/a.jpg', 'bytes': 3, 'fecha': '2026-10-01T15:00:00+00:00'}, {'nombre': 'lista/b ñ.png', 'bytes': 3, 'fecha': None},
            {'nombre': 'roto.jpg', 'bytes': 3, 'fecha': None}]
registradas = []

def simular(route):
    req = route.request
    u = req.url.replace(SB, '')
    cuerpo = json.loads(req.post_data) if req.post_data else {}
    def r(data, status=200): route.fulfill(status=status, content_type='application/json', body=json.dumps(data), headers={'access-control-allow-origin': '*'})
    if req.method == 'OPTIONS':
        return route.fulfill(status=204, headers={'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*'})
    if u.endswith('/rpc/respaldo_estado'): return r(ESTADO)
    if u.endswith('/rpc/respaldo_piezas'): return r({'slot': 'dia-3', 'tomado_en': '2026-11-11T07:40:00+00:00', 'piezas': [{'tabla': t, 'filas': v['filas'], 'bytes': 1} for t, v in TABLAS.items()]})
    if u.endswith('/rpc/respaldo_pieza'): return r(dict(tabla=cuerpo['p_tabla'], **TABLAS[cuerpo['p_tabla']]))
    if u.endswith('/rpc/respaldo_descargada'): registradas.append(cuerpo); return r({'ok': True})
    if u.endswith('/rpc/respaldo_archivos'): return r(ARCHIVOS)
    if u.endswith('/rpc/plataforma_menu'): return r([])
    if u.endswith('/rpc/hoy_items_v2') or '/rpc/hoy' in u: return r({'rol': 'admin', 'nombre': 'Nelson', 'periodo': {'numero': 23, 'inicio': '2026-10-29', 'fin': '2026-11-11', 'hoy': '2026-11-11'}, 'oficial': None, 'items': []})
    if u.startswith('/storage/v1/object/public/imagenes/'):
        if 'roto' in u: return route.fulfill(status=404, body='', headers={'access-control-allow-origin': '*'})
        return route.fulfill(status=200, content_type='image/jpeg', body=b'\xff\xd8\xff', headers={'access-control-allow-origin': '*'})
    return r({'message': 'sin mock ' + u}, 404)

with sync_playwright() as pw:
    try: nav = pw.chromium.launch()
    except Exception: nav = pw.chromium.launch(executable_path='/usr/bin/google-chrome')
    ctx = nav.new_context(viewport={'width': 412, 'height': 900}, accept_downloads=True, locale='es-PE', timezone_id='America/Lima')
    ctx.route(SB + '/**', simular)
    ctx.add_init_script("localStorage.setItem('sb-kiexpdaaoegbtesqmaff-auth-token', JSON.stringify({access_token: 'jwt-1', refresh_token: 'r1', expires_at: Math.floor(Date.now() / 1000) + 3600}))")
    errores = []
    pag = ctx.new_page()
    pag.on('pageerror', lambda e: errores.append(str(e)))
    pag.goto('http://127.0.0.1:%d/index.html#respaldo' % PUERTO)
    pag.wait_for_selector('button.boton')
    ok(pag.inner_text('h1') == 'Respaldo', 'Abre la pantalla de Respaldo')
    with pag.expect_download() as d:
        pag.click('button.boton')
    baja = d.value
    ruta = os.path.join(tempfile.mkdtemp(), baja.suggested_filename)
    baja.save_as(ruta)
    ok(baja.suggested_filename == 'respaldo-plataforma-2026-11-11.json.gz', 'El archivo sale comprimido y con la fecha de la copia (' + baja.suggested_filename + ')')
    crudo = open(ruta, 'rb').read()
    copia = json.loads(gzip.decompress(crudo).decode('utf-8'))
    ok(len(copia['piezas']) == 41 and copia['piezas']['public.t39'] == TABLAS['public.t39'], 'Se descomprime con gzip normal y trae las 41 piezas idénticas')
    ok(list(copia['piezas'].keys()) == list(TABLAS.keys()), 'Las piezas conservan su orden aunque se pidan de a cuatro')
    sin = len(json.dumps(copia, ensure_ascii=False).encode('utf-8'))
    ok(len(crudo) < sin / 5, 'Comprimido pesa %d KB en vez de %d KB' % (len(crudo) // 1024, sin // 1024))
    pag.wait_for_function("document.querySelector('[role=status]') && document.querySelector('[role=status]').textContent.includes('Listo')")
    ok(len(registradas) == 1 and registradas[0]['p_bytes'] == len(crudo) and registradas[0]['p_piezas'] == 41, 'Registra la descarga con el peso real del archivo')

    # una carpeta de archivos: baja lo que puede y avisa lo que no
    with pag.expect_download() as d2:
        pag.click('.lista .item .mini')
    z = d2.value
    ruta2 = os.path.join(tempfile.mkdtemp(), z.suggested_filename)
    z.save_as(ruta2)
    zf = zipfile.ZipFile(ruta2)
    ok(zf.testzip() is None and zf.namelist() == ['lista/a.jpg', 'lista/b ñ.png'] and zf.read('lista/a.jpg') == b'\xff\xd8\xff', 'El .zip de la carpeta abre bien y trae los archivos con su carpeta')
    pag.wait_for_function("[...document.querySelectorAll('.lista .item p')].some(p => p.textContent.includes('No se pudieron bajar 1'))")
    ok(True, 'Si un archivo no baja, lo dice y sigue con los demás')
    ok(not errores, 'Sin errores de JavaScript' + (': ' + '; '.join(errores) if errores else ''))
    nav.close()

print('\nTODO BIEN' if not fallas else '\n%d PRUEBA(S) FALLARON' % fallas)
sys.exit(1 if fallas else 0)
