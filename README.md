# Plataforma · Equipo Arequipa

Un solo acceso para todo. El equipo de oficina entra con correo y contraseña;
los asesores, con su celular. Desde aquí se abre cada módulo ya con sesión.

## Archivos

- `public/index.html` — el hub: acceso único, pantalla **Hoy** (lo que hay que
  atender, ordenado por urgencia), módulos por grupo, carga del reporte de
  pedidos (`#importar`) y conciliación con Rena Ware (`#conciliar`).
- `public/_headers`, `public/404.html` — configuración.
- `wrangler.toml` — dice que el sitio son los archivos de `public/`.
- `sql/` — copia de las migraciones de la base aplicadas desde este chat (las demás están en el historial de Supabase).
- `supabase/functions/traspaso/` — la Edge Function que canjea los códigos de traspaso.
- `pruebas/prueba.js` — pruebas del hub con un Supabase simulado (`node pruebas/prueba.js`, necesita `npm install jsdom`).

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
