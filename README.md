# Plataforma · Equipo Arequipa

Un solo acceso para todo. El equipo de oficina entra con correo y contraseña;
los asesores, con su celular. Desde aquí se abre cada módulo ya con sesión.

## Archivos

- `public/index.html` — el hub: acceso único, pantalla **Hoy** (lo que hay que
  atender, ordenado por urgencia), módulos por grupo, carga del reporte de
  pedidos (`#importar`) y conciliación con Rena Ware (`#conciliar`).
- `public/_headers`, `public/404.html` — configuración.
- `wrangler.toml` — dice que el sitio son los archivos de `public/`.
- `sql/` — las migraciones de la base que acompañan a cada versión, en orden.
- `supabase/functions/traspaso/` — la Edge Function que canjea los códigos de traspaso.
- `pruebas/prueba.js` — pruebas del hub con un Supabase simulado (`node pruebas/prueba.js`, necesita `npm install jsdom`).

## Cómo se publica

Sitio estático, sin build. Cloudflare está conectado a este repositorio:
**cada push a `main` publica**. En Cloudflare el proyecto es un Worker con
assets (como `renaware-registro`): *Build command* vacío, *Deploy command*
`npx wrangler deploy`.

## Cómo funciona el traspaso

1. El hub entra una sola vez (Supabase Auth para el equipo; `asesor_login` para asesores).
2. Al abrir un módulo externo, llama a `traspaso_crear(destino)` (o
   `traspaso_crear_asesor`) y recibe un código de un solo uso que vence en 2 minutos.
3. Navega a `https://modulo/...#traspaso=<código>`.
4. El módulo, al cargar, ve `#traspaso`, llama a la Edge Function `traspaso`
   (`POST /functions/v1/traspaso` con `{codigo}`) y recibe lo que necesita:
   - `sesion` — una sesión de Supabase propia (para los módulos con correo:
     pedidos, facturación, premios, admin de registros);
   - `admin_token` — un token de `admin_sesion` (para los que validan con
     `es_admin`: precios, Nivel Cero, bienvenida, reparaciones);
   - para asesores, su `token` de `asesor_sesion` (solo precios).
5. Guarda la credencial en su propio almacenamiento, limpia el enlace y arranca.

Los módulos siguen aceptando su acceso directo de siempre; el traspaso es un
atajo, no una dependencia.

## Datos (Supabase `kiexpdaaoegbtesqmaff`)

Las reglas viven en la base, no en la página:

- `hoy()` / `hoy_items(rol)` — pendientes por rol (admin, asistente, gestor),
  alimentados por registros, cargas pendientes, conciliación, seguimiento de
  clientes, premios, reparaciones, Nivel Cero y facturación.
- `asesor_inicio(token)` — inicio del asesor; solo sus propios datos.
- `perfiles` — quién es quién en el equipo de oficina y su rol.
- `plataforma_modulos` — qué módulos ve cada rol, en qué grupo y si aceptan traspaso. Se editan en la base.
- `traspasos`, `traspaso_crear*`, `traspaso_consumir`, `traspaso_canjear_asesor` — el traspaso.
- `importar_pedidos_rw(filas)`, `rw_pedidos`, `rw_importaciones` — carga del reporte oficial.
- `conciliacion_candidatos()`, `conciliar_confirmar`, `conciliar_seguras`, `conciliar_descartar` — conciliación.

El motor de concursos de agosto quedó archivado en el esquema `archivo`
(migración `20261021054500`). Premios (`pr_*`) lo reemplaza.
