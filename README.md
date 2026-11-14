# Plataforma · Equipo Arequipa

Un solo acceso para todo. El equipo de oficina entra con correo y contraseña;
los asesores, con su DNI. Desde aquí se abre cada módulo ya con sesión.

**Los asesores entran con su DNI desde el 12/11/2026** (antes, con su celular; lo decidió Nelson: el
celular de un asesor lo tiene cualquier cliente). `asesor_login` recibe el DNI en su parámetro de
siempre y deja entrar a la persona activa de `eq_personas` que tiene ahí su DNI (el celular no hace
falta), o al invitado de `asesores` con DNI. La sesión guarda en `asesor_sesion.celular` la llave de
la persona: su celular o, si no tiene uno en la base, su DNI de 8 dígitos; `asesor_panel_de` la
reconoce por cualquiera de los dos. SQL: `renaware-peru/sql/20261112_06_ingreso_con_dni.sql` y
`20261112_07_basta_el_dni.sql`.

## Archivos

- `public/index.html` — el hub de la oficina: acceso único (a la asesora la manda a `/asesores/`), caja **Pregúntale** (abre `/chat/`
  con la pregunta), pantalla **Hoy** (lo que hay que atender, ordenado por
  urgencia; a la vista lo urgente y como mínimo 3, el resto con un toque),
  **Herramientas** por grupo con el globo de pendientes de cada una, carga del
  reporte de pedidos (`#importar`), conciliación con Rena Ware (`#conciliar`) y
  **Vigencia de los datos** (`#vigencia`: qué toca volver a subir y cuándo vence).
- `public/test/index.html` — el **Test del Nivel 0** (`/test/`): el asesor lo
  rinde y la oficina ve resultados, prueba el test, apaga preguntas y ajusta
  (`/test/#oficina`). Ver más abajo.
- `public/chat/index.html` — **Pregúntale** (`/chat/`): el chat en lenguaje
  natural sobre toda la base. Usa la misma sesión del hub. Ver más abajo.
- `public/asesores/index.html` — la **plataforma de asesores** (`/asesores/`): el inicio de la
  asesora con lo suyo, el buscador, precios, zonas de crédito, premios, Nivel Cero y puntos
  («¿ya ganó Empiece Ya?» está hecho pero apagado para las asesoras); y dentro, **Entrenamientos**, **Listas** (`#listas`) y **Horario**
  (`#horario`), que la oficina edita ahí mismo. Asesor con su DNI; oficina con la sesión
  de la plataforma o la clave. Ver más abajo.
- `public/entrenamientos/index.html` — solo redirige a `/asesores/` (enlaces viejos).
- `pruebas/prueba_asesores.py` — pruebas de la plataforma de asesores y del modo oficina en un
  Chromium real con un Supabase simulado (`python3 pruebas/prueba_asesores.py [carpeta_capturas]`).
- `pruebas/prueba_respaldo.py` — la descarga del respaldo en un Chromium real.
- `supabase/functions/chat/` — la Edge Function del chat (el ciclo con la API de Claude).
- `pruebas/prueba_chat.js` — pruebas del chat (`node pruebas/prueba_chat.js`).
- `public/_headers`, `public/404.html` — configuración.
- `wrangler.toml` — dice que el sitio son los archivos de `public/`.
- `sql/` — copia de las migraciones de la base aplicadas desde este chat (las demás están en el historial de Supabase).
- `supabase/functions/traspaso/` — la Edge Function que canjea los códigos de traspaso.
- `pruebas/prueba.js` — pruebas del hub con un Supabase simulado (`node pruebas/prueba.js`, necesita `npm install jsdom@24`: las versiones nuevas cambiaron la consola virtual).
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

## Cómo está armado el menú

De arriba abajo, en el celular:

1. **Hola + período**: el reloj de Rena Ware (día x de 14, cuándo cierra) y el
   último reporte oficial.
2. **Pregúntale**: una caja como buscador. Lo que se escriba se abre en `/chat/`
   ya preguntado. Es la entrada transversal: sirve cuando uno no sabe en qué
   herramienta está el dato.
3. **Hoy**: lo que hay que atender, ordenado por urgencia. A la vista lo urgente y
   como mínimo 3 cosas; «Ver los otros N pendientes» abre el resto, para que las
   herramientas no queden lejos.
4. **Herramientas**, agrupadas por lo que la persona está haciendo, no por el
   sistema: **Vender** (precios, zonas de crédito, registrar), **Pedidos**
   (revisar registros, pedidos y clientes, subir reporte, conciliar), **Equipo**
   (premios, Empiece Ya, Nivel Cero, test, bienvenida, local), **Oficina**
   (reparaciones, facturación). Cada tarjeta lleva un globo con cuántos
   pendientes de Hoy le tocan y de qué urgencia: el menú también es un tablero.
   Las asesoras ven solo lo suyo (precios y zonas; test si están en el Nivel
   Cero; local si son socias) y, con un solo grupo, sin encabezados.

Todo eso sale de `plataforma_modulos` + `plataforma_menu()` + `hoy()`; el hub no
tiene escrito ningún nombre de módulo salvo `chat` (la caja) y los dos internos
(`#importar`, `#conciliar`).

## Vigencia de los datos (`#vigencia`)

La plataforma se alimenta de cosas que alguien tiene que volver a subir: las
listas de precios cuando vencen, el reporte de pedidos al cerrar el período, el
reporte Aurora (montos y pendientes por facturar), las declaraciones del mes,
los resultados de premios y de Empiece Ya, el catálogo de premios, la lista de
zonas de crédito, el horario del local, las clases del Nivel Cero, las fichas
del chat, los premios por recibir. Todo eso está en un catálogo:

- `plataforma_fuentes` — una fila por fuente: `nombre`, `accion` (qué hacer y
  dónde), `modulo` (a dónde lleva), `roles`, `cadencia` (`vigencia`, `periodo`,
  `mensual`, `semanal`, `evento`), `dia` (días después del cierre / día del mes
  / tolerancia / espera máxima), `aviso_dias`, y tres `SELECT` de solo lectura:
  `ultima_sql` (última vez que se alimentó; en `periodo`, una fecha dentro del
  último período cubierto), `vence_sql` (hasta cuándo sirve lo cargado) y
  `pendientes_sql` (cuántos elementos esperan). Un disparador los valida con el
  mismo validador del chat (`chat_sql_valida`). `en_hoy = false` cuando el
  módulo ya avisa eso en Hoy por su cuenta (reporte de pedidos, FPD, Empiece
  Ya, premios por recibir): así no salen dos tarjetas.
- `plataforma_fuentes_estado(rol)` — evalúa cada fuente y devuelve `estado`
  (`al_dia`, `por_vencer`, `vencido`, `error`), `vence`, `dias`, `detalle`,
  `cadencia_texto`, `ultima_texto`. Un SQL roto sale como `error`, no se
  esconde.
- Hoy agrega una tarjeta **Vigencia** por cada fuente vencida o por vencer
  («Vencido: …», «Vence en 7 días: …»), que abre el módulo donde se sube.
- `#vigencia` muestra todas, por estado, con su cadencia y la última vez.

Agregar una fuente nueva es una fila. SQL en `sql/20261103_vigencia_de_los_datos.sql`.

## Respaldo (`#respaldo`, solo administrador)

El plan gratuito de Supabase no hace backups, así que la base se copia a sí misma:

- **Cada madrugada** (2:40 a. m., tarea `respaldo_diario`) `respaldo.correr()` guarda todas las tablas
  y el SQL para rehacer la estructura en el esquema `respaldo`, que no se expone por la API.
  Hay siete casilleros diarios (`dia-1`..`dia-7`, se pisan cada semana), tres mensuales
  (`mes-0`..`mes-2`) y uno `manual`. Una copia pesa unos 4 MB.
- **`respaldo.cambios`** guarda la historia de cada función, tabla, vista, política, disparador
  (también los de eventos propios, como la guardia de las vistas), índice y tarea: una fila cada
  vez que cambia su definición. Sirve para ver qué cambió y cuándo, y para recuperar la versión
  anterior de una función. Así se supo, el 13/11, que una vista cerrada se había vuelto a abrir.
- **La pantalla** (`pantallaRespaldo`) dice si la copia corrió, la descarga a este dispositivo
  (`respaldo-plataforma-AAAA-MM-DD.json.gz`: datos y estructura en un solo archivo) y baja los
  archivos de Storage por carpeta en `.zip`. Esa descarga es la única copia **fuera** de Supabase;
  Vigencia la pide una vez al mes (`respaldo-copia-fuera`) y avisa si la copia diaria deja de
  correr (`respaldo-diario`).
- **Recuperar un dato**: `select o from respaldo.objetos('dia-2', 'public.registros') o where …`
  devuelve las filas tal como estaban ese día. `respaldo.verificar('dia-3')` reconstruye cada tabla
  desde la copia y la compara con la viva (la prueba de restauración).

Todo el SQL está en `sql/20261111_respaldo.sql`. Pruebas: `node pruebas/prueba.js` (pantalla, archivo,
`.zip` validado con Python) y `python3 pruebas/prueba_respaldo.py` (la descarga comprimida en un
Chromium real).

## Seguridad de la base

- **`plataforma_salud()`** revisa la base, y lo que encuentra sale en Hoy para el administrador: tablas sin
  reglas, lo que se puede leer o escribir sin sesión, funciones públicas que escriben o leen personas sin pedir
  sesión, vistas que leen con el permiso de su dueño, archivos que cualquiera puede subir, módulos sin grupo o
  sin bloque en Hoy.
- **Las vistas quedan seguras solas.** La guardia `plataforma_vistas_seguras` (un disparador de eventos) le pone
  `security_invoker` a toda vista que se crea o se vuelve a crear en `public`. Nació el 13/11/2026: `fact_listos`
  (RUC, cuentas, CCI) se había cerrado el 10/11, se volvió a crear desde otra conversación y quedó abierta de
  nuevo; lo avisó la historia de cambios del respaldo. Regla: lo que haya que mostrar sin sesión se hace con una
  función, no con una vista.
- **Cerrar sin borrar.** Una política que sobra no se quita (eso pide una confirmación que desde un chat nadie
  alcanza a responder): se deja sin efecto con `alter policy … using (false) with check (false)`, se crea la de
  lectura si hace falta y se quitan los permisos de escritura. `plataforma_salud()` no cuenta las políticas sin
  efecto. Así se cerró el 13/11 la escritura directa del Local del equipo.
- SQL en `sql/20261110_seguridad_01_cierres.sql`, `sql/20261113_seguridad_02_vistas_seguras.sql` y
  `sql/20261113_seguridad_03_salud_politicas_sin_efecto.sql`. Lo que sigue abierto (el formulario de registro y
  las carpetas de archivos sin boleto) está en el documento del proyecto `claude/revision-plataforma-2026-11.md`.

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
- `plataforma_modulos` — el menú: qué ve cada rol, con qué `acceso` entra, bajo
  qué `grupo` se muestra (Vender, Pedidos, Equipo, Oficina) y, si hace falta,
  `visible_fn`: una función `(p_token uuid) returns boolean` que decide si se le
  muestra a esa asesora (`ts_visible`: solo en el Nivel Cero; `loc_visible`: solo
  socias del local). **El hub no lee la tabla: llama a `plataforma_menu()`**
  (equipo, con su sesión) o `plataforma_menu(p_token)` (asesora) y pinta lo que
  vuelve, en el orden de `orden`. Registrar una herramienta nueva es una fila;
  sin `grupo` cae en «Otros» y `plataforma_salud()` lo avisa en Hoy.
  `chat` es la única fila que el hub pinta distinto: como la caja Pregúntale.
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

## Pregúntale (`/chat/`)

Un chat que responde preguntas en lenguaje natural con lo que hay en la base:
precios y promociones, repuestos, zonas de crédito, períodos, puntos oficiales,
registro interno, pedidos, clientes, premios, Empiece Ya, Nivel Cero,
reparaciones, pendientes de Hoy, seguimientos, facturación, turnos del local.
Responde solo con datos de las herramientas y dice de dónde salió cada dato;
cuando no puede, lo marca (`sin_respuesta`) para que esa pregunta se vuelva
una herramienta o una ficha.

- **El catálogo vive en la base, no en el código.** `chat_herramientas`: una
  fila por herramienta (nombre, descripción para el modelo, parámetros en JSON
  Schema, el `SELECT` que la resuelve, roles). Agregar o cambiar una
  herramienta es editar una fila; apagarla, `activo = false`. En el SQL,
  `$1` son los argumentos (jsonb) y `$2` quién pregunta (jsonb con `rol`,
  `nombre`, `user_id`). Tipos integrados: `esquema` (tablas y columnas vivas),
  `sql_libre` (`sql_lectura`: solo SELECT, con validación) y `fichas`.
- **`chat_fichas`**: lo que no es tabla (reglas, programas, servicios,
  horarios), con búsqueda de texto en español; `vigente_hasta` apaga una ficha
  sola. Lo que cambia con el tiempo no va en fichas: lo dan las herramientas.
- **`chat_proyectos`**: un contexto por proyecto (prompt del sistema, modelo,
  pasos máximos). Hoy `renaware`; otro proyecto es otra fila con sus
  herramientas y fichas. El motor completo es una migración + una Edge
  Function: se instala igual en otra base.
- **Seguridad.** Misma identidad del hub (correo → `perfiles`). Cada
  herramienta corre en `chat_ejecutar`, `security definer`, que valida la
  sesión, el rol y pone la transacción en **solo lectura** con tiempo máximo:
  ni el modelo ni un SQL mal armado pueden escribir. `sql_lectura` además
  rechaza todo lo que no sea un SELECT y las tablas de credenciales y sesiones.
  Sin políticas RLS en las tablas `chat_*`: todo pasa por RPC.
- **Edge Function `chat`** (`POST /functions/v1/chat`, Bearer = sesión del
  hub): pide el catálogo (`chat_catalogo`), corre el ciclo pregunta →
  herramienta → respuesta con la API de Claude y guarda todo en
  `chat_conversaciones` / `chat_mensajes` (quién, qué consultó, tokens, tiempo).
  Secreto: `ANTHROPIC_API_KEY` en Supabase → Edge Functions → Secrets.
- SQL en `sql/20261031_chat_01..04_*.sql` (base, herramientas, fichas, módulo).

## Plataforma de asesores (`/asesores/`)

La página de la asesora: entra con su DNI y tiene **todo en un solo sitio**. Está pensada para
quien no es de tecnología: letra grande, botones grandes, una cosa por pantalla, un botón
«Volver» arriba y el «atrás» del teléfono que siempre regresa un paso.

- **Inicio**: saluda por su nombre, dice el día y cuándo cierra el período, y muestra solo lo
  que le toca a ella: *premios por recoger*, *su Nivel Cero* (clases, plazo y próxima clase;
  con las 5 clases, el botón de su test) y *lo que sigue en el horario*. Debajo, los botones
  en tres grupos: **Para vender** (Precios y promociones, Zonas de crédito, Listas y fotos),
  **Para aprender** (Entrenamientos, Horario) y **Lo tuyo** (Mi Nivel Cero, Mis premios, Mis
  puntos, y lo que `plataforma_menu` le sume, como el Local).
- **Buscador** (arriba del inicio): una sola caja busca secciones, listas, guías y distritos.
  Escribir «cayma» responde ahí mismo si hay crédito.
- **Precios y promociones**: sale al portal `renaware-peru` con su sesión (traspaso); con
  «atrás» vuelve.
- **Zonas de crédito**: la lista oficial (`zc_lista`, la misma del buscador de zonas). Abre con
  los distritos de Arequipa; al escribir busca distritos y zonas restringidas de todo el país.
  Cada distrito dice con palabras «Sí hay crédito», «Sí, con excepciones» o «No hay crédito»,
  cómo se entrega y sus zonas sin crédito por motivo. La lista se guarda 12 horas en el
  teléfono (`rw_zonas_v1`) y sirve sin señal.
- **¿Ya ganó Empiece Ya?** — **apagado para las asesoras desde el 13/11/2026** (Nelson: «por
  ahora no, le voy a complicar a una persona con esa información»; la oficina lo tiene en el
  hub, en «Ganadores Empiece Ya» → Buscar persona). Está hecho: un nombre (o un código) y dice
  si esa persona ya ganó, cuándo, en qué división y con qué premios, y hasta qué cierre llega
  la lista (`eya_buscar`). Es un interruptor en la base, sin tocar la página:
  `update plataforma_modulos set activo = true where id = 'eya-buscar';`. Con eso
  `plataforma_menu` se lo manda a la asesora y aparecen el botón (el grupo vuelve a llamarse
  «Para vender y afiliar»), la pantalla `#empiece` y la entrada del buscador; apagado, la
  dirección `#empiece` vuelve al inicio y `eya_buscar` no le responde a una sesión de asesor.
- **Mis premios** (`pr_premios` por su código): para recoger en la oficina, ganados que todavía
  no llegan (sin prometer de más: dice si es oficial, preliminar o anotado por la oficina) y
  entregados. **Mi Nivel Cero**: clases a las que fue, las próximas que cuentan y su test.
  **Mis puntos**: sus tres últimos períodos según Rena Ware.
- **Entrenamientos, Listas y Horario**: lo de abajo, sin pestañas (cada uno es una pantalla).

Lo personal llega en una sola llamada, `asesor_panel(p_token)`; si falla, el inicio lo dice y lo
demás sigue funcionando. El hub (`/`) ya no le arma un inicio a la asesora: la manda aquí, con la
misma sesión (`rw_asesor_token`, mismo dominio). La dirección vieja `/entrenamientos/` redirige
conservando la pantalla y el traspaso. SQL en `sql/20261111_asesores.sql` y
`sql/20261113_asesores_02_empiece_ya_apagado.sql`. Pruebas:
`python3 pruebas/prueba_asesores.py [carpeta_capturas]` (Chromium real, 156 comprobaciones; el
simulador responde por defecto como está la base, sin Empiece Ya, y un escenario aparte lo prende).

### Entrenamientos, Listas y Horario (dentro de `/asesores/`; la oficina los edita ahí mismo)

Para la oficina es la misma página con tres pestañas y el **modo edición** (entra por el hub
con traspaso, o con `#oficina` y la clave).

- **Entrenamientos**: módulos (3–4 lecciones cada uno) → lecciones → materiales. Son siete, en
  el orden del trabajo: Empieza bien, Consigue citas, La presentación, Cierra la venta,
  **Cómo cobrar** (abrir cuentas, facturar, declarar; desde el 13/11), Crece en el negocio y
  Trabaja en ti. El pedido y el crédito van en «Cierra la venta» (lección «Contratos: contado
  y crédito»); un módulo aparte, «Créditos y pedidos», se creó y se retiró ese mismo día.
  Cada lección muestra solo lo que tiene: **guía** (PDF), **video** (archivo o
  YouTube), **libro** (PDF o enlace), **enlace**. El asesor marca cada lección
  como completada; abrir un material la deja como vista. La oficina ve cuántos
  la vieron y completaron, y abajo el progreso del equipo por asesor.
- **Listas**: la base de documentos por categoría (listas de precios, repuestos
  y servicios, concursos y programas). Cada documento tiene una `clave` estable
  (p. ej. `lista-promo-cliente`) para que otros sistemas jalen el vigente, y
  **acumula versiones**: subir de nuevo crea la siguiente; la última es la
  vigente, con nota y vigencia (desde/hasta). Vista previa (primera página o
  foto, generada al subir), **Ver** (visor de PDF y fotos en la misma página),
  **Enviar** (hoja de compartir del celular: WhatsApp con el archivo) y
  **Descargar**. Lo marcado «para el cliente» es lo que se le puede mandar.
  Un PDF por concurso: la oficina crea un documento nuevo en Concursos.
- **Horario**: la semana con fechas reales (lunes a domingo), ‹ › para moverse,
  hoy resaltado y el jueves que inicia un período marcado («Inicia el PB24»,
  donde va el lanzamiento del concurso). La oficina apaga un evento para esa
  semana («Esta semana no hay»), lo edita, agrega uno suelto y mantiene el
  **horario habitual** (plantillas por día y hora, con «solo el día que
  inicia el período» para el lanzamiento y «solo cuando no inicia» para el
  Zoom del jueves con Juan Carlos Ezaine). «Copiar para WhatsApp» arma el
  texto de la semana. Lo presencial con asistencia se crea solo como clase en
  **Nivel Cero** (`n0_clases`, enlazada por `evento_id`); al apagarlo, la clase
  se borra si nadie fue marcado. **Por Zoom no se toma asistencia** (regla
  fija en `hor_plantilla_guardar` / `hor_evento_guardar`). El horario habitual
  de Nivel Cero (`n0_config.horarios`) también sale de aquí.

**Datos** (Supabase): `ent_modulos`, `ent_lecciones`, `ent_recursos`,
`ent_progreso` (por celular), `ent_subidas` (tickets de subida); `doc_categorias`,
`doc_documentos`, `doc_versiones`; `hor_plantillas`, `hor_eventos`. Todo por RPC
con `p_token` (sesión de admin o de asesor): `ent_datos`, `hor_semana`,
`doc_vigente`, `ent_progreso_marcar` y, para la oficina, `ent_subida_crear`,
`*_guardar`, `ent_borrar`, `ent_ordenar`, `doc_categoria_ordenar`. Las semanas se
materializan solas (`hor_materializar`: al consultar y con el cron diario
`hor_materializar_diario`). Archivos en el bucket público `entrenamientos`: subir
exige un ticket de la oficina (`ent_subida_crear`) y la ruta `<ticket>/<archivo>`
(política `ent_ruta_ok`); la vista previa va como `<ticket>/portada.jpg`.
Registrado en `plataforma_modulos` como `entrenamientos` (Equipo) y `listas`
(Vender, `#listas`), en Vigencia (`clases-nivel-cero`, `listas-digitales`) y en el
chat (`horario_semana`, `documentos_listas`, `entrenamientos_lecciones`).
SQL en `sql/20261104_entrenamientos_01_base.sql`, `_02_datos.sql`, `_03_zoom_sin_asistencia.sql`, `sql/20261106_entrenamientos_04_*.sql` y `sql/20261113_entrenamientos_05_como_cobrar.sql`.
