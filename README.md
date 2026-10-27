# Plataforma · Equipo Arequipa

Un solo acceso para todo. El equipo de oficina entra con correo y contraseña;
los asesores, con su celular. Desde aquí se abre cada módulo ya con sesión.

## Archivos

- `public/index.html` — el hub: acceso único, pantalla **Hoy** (lo que hay que
  atender, ordenado por urgencia), módulos por grupo, carga del reporte de
  pedidos (`#importar`) y conciliación con Rena Ware (`#conciliar`).
- `public/test/index.html` — el **Test del Nivel 0** (`/test/`): el asesor lo
  rinde y la oficina ve resultados, prueba el test, apaga preguntas y ajusta
  (`/test/#oficina`). Ver más abajo.
- `public/_headers`, `public/404.html` — configuración.
- `wrangler.toml` — dice que el sitio son los archivos de `public/`.
- `sql/` — copia de las migraciones de la base aplicadas desde este chat (las demás están en el historial de Supabase).
- `supabase/functions/traspaso/` — la Edge Function que canjea los códigos de traspaso.
- `pruebas/prueba.js` — pruebas del hub con un Supabase simulado (`node pruebas/prueba.js`, necesita `npm install jsdom`).
- `pruebas/prueba_test.js` — pruebas del test (`node pruebas/prueba_test.js`), con
  `pruebas/simulador_test.js` (el Supabase simulado del test). `pruebas/capturas_test.js
  <carpeta>` saca capturas en un celular con Chromium (necesita playwright).
- `sql/pruebas/test_nivel0_simulacion.sql` — simulación completa en la base real:
  inscrito de prueba con 5 clases, rinde con 5 errores (aprueba igual), premio, sincronías (también
  al deshacer entregas), entrada solo con el Nivel Cero, doble inicio, anulación y
  bloqueado, todo con DNI. Termina con un error a propósito para que todo se deshaga.

## Cómo se publica

Sitio estático, sin build. Cloudflare está conectado a este repositorio:
**cada push a `main` publica**. En Cloudflare el proyecto es un Worker con
assets (como `renaware-registro`): *Build command* vacío, *Deploy command*
`npx wrangler deploy`.

## Cómo funciona el traspaso

1. El hub entra una sola vez (Supabase Auth para el equipo; `asesor_login` para asesores).
2. Al abrir un módulo externo, llama a `traspaso_crear(modulo)` (o
   `traspaso_crear_asesor(token, modulo)`) y recibe un código de un solo uso que vence en 3 minutos.
3. Navega a `https://modulo/...#traspaso=<código>`.
4. El módulo, al cargar, ve `#traspaso`, llama a la Edge Function `traspaso`
   (`POST /functions/v1/traspaso` con `{codigo}`) y recibe lo que necesita:
   - módulos con `acceso = 'supabase'` (pedidos, facturación, premios, admin de
     registros): `sesion`, una sesión de Supabase propia del módulo;
   - módulos con `acceso = 'admin_sesion'` o `'asesor'` (Nivel Cero, bienvenida,
     reparaciones, precios): `admin_token`, un token de `admin_sesion`;
   - asesores (solo precios): su `token` de `asesor_sesion`.
   La columna `plataforma_modulos.acceso` decide el camino.
5. Guarda la credencial en su propio almacenamiento, limpia el enlace y arranca.

Los módulos siguen aceptando su acceso directo de siempre; el traspaso es un
atajo, no una dependencia.

## Datos (Supabase `kiexpdaaoegbtesqmaff`)

Las reglas viven en la base, no en la página:

- `hoy()` / `hoy_items_v2(rol)` — pendientes por rol (admin, asistente, gestor),
  alimentados por registros, cargas pendientes, conciliación, clientes recién
  atendidos, bienvenida, premios, reparaciones, Nivel Cero y facturación
  (declaraciones, fraccionamientos, comisiones por facturar, reporte FPD).
- `asesor_inicio(token)` — inicio del asesor; solo sus propios datos.
- `perfiles` — quién es quién en el equipo de oficina y su rol.
- `plataforma_modulos` — qué módulos ve cada rol y con qué `acceso` entran. Se editan en la base; el hub agrupa por id (Ventas, Equipo, Oficina).
- `traspasos`, `traspaso_crear`, `traspaso_crear_asesor`, `traspaso_consumir`, `traspaso_canjear`, `traspaso_canjear_auth` — el traspaso.
- `importar_pedidos_rw(filas)`, `rw_pedidos`, `rw_importaciones` — carga del reporte oficial.
- `conciliacion_candidatos()`, `conciliar_confirmar`, `conciliar_seguras`, `conciliar_descartar` — conciliación.

El motor de concursos de agosto quedó apagado (sus disparadores están
deshabilitados; migración `archivar_motor_agosto_sin_drop`). Premios (`pr_*`) lo reemplaza.

## Test del Nivel 0 (`/test/`)

Quien completa sus **5 clases** del Nivel Cero tiene **15 días** (desde su 5.ª
clase) para hacer un test. **Por ahora aprueba todo el que lo termina** y su nota
queda registrada (`ts_config.exigir_nota = false`; prendido, pide `nota_minima`,
p. ej. el promedio que muestra la oficina). Al aprobar, su **botella de acero**
entra a Premios (`pr_premios`, programa «Nivel Cero», nivel «Nivel 0») como
recibida y por entregar. Pasado el plazo, el test ya no se puede rendir.

- **Mecánica** (la del quiz anterior): una pregunta por pantalla, 5 opciones; si
  falla, se le explica dónde encontrar la respuesta (sin decírsela) y sale otra
  del mismo tema hasta acertar. Nota = preguntas ÷ respuestas × 100. Intentos
  ilimitados dentro del plazo; si cierra la página, sigue donde quedó. Un solo
  intento abierto a la vez (índice `ts_intentos_uno_abierto`); si una pregunta no
  se puede armar con la data del día, ese paso sale del intento (`ts_generar_seguro`).
- **Que la correcta no se note**: en los montos (`ts_opc_soles`) la correcta cae en
  cualquier lugar de menor a mayor; en los textos no es la más larga ni la más
  corta; las de «marca todas» muestran una mezcla distinta en cada reintento.
- **Contenido**: 33 pasos en 7 bloques (`ts_pasos`): productos y precios,
  inicial/saldo/cuotas, crédito y zonas, cuentas y pagos, Empiece Ya, comisiones
  y autocompra, frase de oro y objeciones. Precios, promociones (con su foto y
  regalo), cuotas, zonas y Empiece Ya se arman en vivo (`ts_generar`) con la lista
  vigente, `reglas_credito`/`factores_credito`, `zc_*` y el Empiece Ya de Premios
  (`pr_catalogo`) que le toca por su fecha de ingreso. Las de texto viven en
  `ts_banco`, con variantes. La de cuentas sale cuando se cargan en Ajustes.
- **Entrar**: un solo enlace para todos (`/test/`), que la oficina copia desde
  Resultados o manda por WhatsApp desde la ficha de cada uno. El asesor pone su
  **DNI** una sola vez (también vale su celular): `ts_entrar` le da una sesión
  solo para el test (`ts_sesiones`, guardada como `rw_test_token`; no sirve para
  la plataforma) y su celular lo recuerda. Si llega desde la plataforma, entra
  con esa sesión. Cada respuesta se guarda al momento; el botón «atrás» del
  celular, dentro del test, vuelve a su estado sin perder nada. La oficina llega
  desde la plataforma (traspaso) o con la clave de admin.
- **Sin premios repetidos**: si su Empiece Ya (que trae botella) ya se entregó, la
  botella del Nivel 0 se cierra sola («Se entregó junto con su Empiece Ya»); si la
  del Nivel 0 se entregó primero, su Empiece Ya pendiente queda con la nota
  «Entregar sin botella» (también el que se carga después, al instante). Si se
  deshace una entrega, el cruce se deshace. Solo cuenta el Empiece Ya de su
  ingreso. Lo que se marque entregado en Premios se ve en Nivel Cero y al revés
  (disparadores `trg_ts_premios` y `trg_ts_n0_estado`). Cron diario
  `ts_sync_diario` (06:07 de Lima) como respaldo.
- **Datos**: `ts_config` (nota, días, premio, desde cuándo aplica, cuentas,
  enlaces de consulta), `ts_pasos`, `ts_banco`, `ts_personas` (plazo corregido o
  fuera del test), `ts_intentos`, `ts_sesiones`. Funciones web: `ts_entrar`, `ts_estado`,
  `ts_iniciar`, `ts_responder` (asesor) y `ts_admin_*` (oficina). El estado del
  test de cada inscrito viaja en `n0_inscritos_json` (llave `test`), que leen
  Nivel Cero y Bienvenida. En «Hoy» aparece quien tiene el test por vencer.
- SQL en `sql/20261027_test_*.sql` (el `10_revision` trae los ajustes tras la
  revisión independiente y reemplaza las versiones anteriores de esas funciones).
