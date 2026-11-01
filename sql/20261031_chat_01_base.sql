-- Chat de la plataforma ("Pregúntale"): base.
-- Un chat en lenguaje natural que responde con lo que ya está en esta base.
-- El catálogo de herramientas vive en tablas (chat_herramientas), no en código:
-- agregar o cambiar una herramienta es editar una fila. La Edge Function `chat`
-- solo arma el ciclo pregunta → herramienta → respuesta con la API de Claude.
--
-- Identidad: la sesión de correo de la plataforma (perfiles / auth.uid()).
-- Toda lectura corre dentro de una transacción de solo lectura (chat_ejecutar).
-- Aplicado el 31/10/2026 con execute_sql (todo aditivo).

-- ---------- tablas ----------
create table if not exists public.chat_proyectos (
  id             text primary key,
  nombre         text not null,
  instrucciones  text not null,
  modelo         text not null default 'claude-sonnet-5-5',
  max_pasos      smallint not null default 8,
  max_tokens     integer not null default 1500,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
comment on table public.chat_proyectos is 'Chat: un contexto por proyecto (prompt del sistema, modelo). renaware = la plataforma del equipo.';

create table if not exists public.chat_herramientas (
  id             uuid primary key default gen_random_uuid(),
  proyecto       text not null references public.chat_proyectos(id),
  nombre         text not null,
  descripcion    text not null,
  parametros     jsonb not null default '{"type":"object","properties":{}}'::jsonb,
  tipo           text not null check (tipo in ('sql','fichas','esquema','sql_libre')),
  sql            text,
  roles          text[] not null default array['admin'],
  orden          smallint not null default 100,
  activo         boolean not null default true,
  nota           text,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (proyecto, nombre)
);
comment on table public.chat_herramientas is 'Chat: catálogo de herramientas que el modelo puede llamar. tipo sql = el SELECT de la columna sql ($1 = argumentos jsonb, $2 = quién pregunta); fichas / esquema / sql_libre = integradas. roles = quién puede usarla.';

create table if not exists public.chat_fichas (
  id             uuid primary key default gen_random_uuid(),
  proyecto       text not null references public.chat_proyectos(id),
  tema           text not null,
  titulo         text not null,
  contenido      text not null,
  roles          text[] not null default array['admin','asistente','gestor','asesor'],
  vigente_hasta  date,
  fuente         text,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  busqueda       tsvector generated always as (
                   to_tsvector('spanish', public.unaccent_safe(coalesce(titulo,'') || ' ' || coalesce(tema,'') || ' ' || coalesce(contenido,'')))
                 ) stored
);
comment on table public.chat_fichas is 'Chat: lo que no es tabla (reglas, programas, servicios, horarios). Se busca por texto; vigente_hasta apaga la ficha sola.';
create index if not exists chat_fichas_busqueda_idx on public.chat_fichas using gin (busqueda);

create table if not exists public.chat_conversaciones (
  id             uuid primary key default gen_random_uuid(),
  proyecto       text not null references public.chat_proyectos(id),
  user_id        uuid,
  persona_id     uuid,
  rol            text not null,
  titulo         text,
  archivada      boolean not null default false,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
comment on table public.chat_conversaciones is 'Chat: una conversación por hilo. user_id = cuenta de correo (equipo); persona_id = asesor (a futuro). Nada se borra: archivada marca.';

create table if not exists public.chat_mensajes (
  id              bigint generated always as identity primary key,
  conversacion_id uuid not null references public.chat_conversaciones(id),
  rol             text not null check (rol in ('user','assistant')),
  contenido       text not null,
  herramientas    jsonb,
  sin_respuesta   boolean not null default false,
  modelo          text,
  tokens_in       integer,
  tokens_out      integer,
  ms              integer,
  creado_en       timestamptz not null default now()
);
comment on table public.chat_mensajes is 'Chat: cada mensaje. herramientas = lo que consultó el modelo para responder. sin_respuesta = el modelo no pudo responder con los datos: es la lista de herramientas o fichas que faltan.';
create index if not exists chat_mensajes_conv_idx on public.chat_mensajes (conversacion_id, id);

alter table public.chat_proyectos      enable row level security;
alter table public.chat_herramientas   enable row level security;
alter table public.chat_fichas         enable row level security;
alter table public.chat_conversaciones enable row level security;
alter table public.chat_mensajes       enable row level security;
-- Sin políticas: todo pasa por las funciones de abajo (regla 3 de la plataforma).

-- ---------- quién pregunta ----------
create or replace function public.chat_quien()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object('tipo', 'equipo', 'rol', p.rol, 'nombre', p.nombre, 'user_id', p.user_id, 'persona_id', p.persona_id)
  from public.perfiles p where p.user_id = auth.uid() and p.activo limit 1;
$$;
revoke execute on function public.chat_quien() from public, anon, authenticated;

-- ---------- catálogo que ve el modelo ----------
create or replace function public.chat_catalogo(p_proyecto text default 'renaware')
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare
  q  jsonb := public.chat_quien();
  pr record;
begin
  if q is null then raise exception 'Sin sesión de la plataforma.' using errcode = '28000'; end if;
  select * into pr from public.chat_proyectos where id = p_proyecto and activo;
  if not found then raise exception 'El proyecto % no existe en el chat.', p_proyecto; end if;
  return jsonb_build_object(
    'quien', q,
    'proyecto', jsonb_build_object('id', pr.id, 'nombre', pr.nombre, 'instrucciones', pr.instrucciones,
                                   'modelo', pr.modelo, 'max_pasos', pr.max_pasos, 'max_tokens', pr.max_tokens),
    'hoy', public.hoy_lima(),
    'hora_lima', to_char(now() at time zone 'America/Lima', 'HH24:MI'),
    'periodo', jsonb_build_object('pb', public.periodo_numero(public.periodo_indice(public.hoy_lima())),
                                  'anio', public.periodo_ciclo(public.periodo_indice(public.hoy_lima())),
                                  'inicio', public.periodo_inicio(public.periodo_indice(public.hoy_lima())),
                                  'fin', public.periodo_inicio(public.periodo_indice(public.hoy_lima())) + 13),
    'herramientas', coalesce((select jsonb_agg(jsonb_build_object('name', h.nombre, 'description', h.descripcion, 'input_schema', h.parametros)
                                               order by h.orden, h.nombre)
                              from public.chat_herramientas h
                              where h.proyecto = p_proyecto and h.activo and (q->>'rol') = any(h.roles)), '[]'::jsonb),
    'fichas_temas', coalesce((select jsonb_agg(distinct f.tema) from public.chat_fichas f
                              where f.proyecto = p_proyecto and f.activo and (q->>'rol') = any(f.roles)), '[]'::jsonb)
  );
end $fn$;
revoke execute on function public.chat_catalogo(text) from public, anon;
grant execute on function public.chat_catalogo(text) to authenticated, service_role;

-- ---------- herramientas integradas ----------
-- esquema: tablas y columnas vivas, con sus comentarios. Excluye credenciales y sesiones.
create or replace function public.chat_esquema(p_args jsonb)
returns jsonb language plpgsql stable set search_path to 'public' as $fn$
declare
  v_tabla  text := nullif(trim(coalesce(p_args->>'tabla', '')), '');
  v_buscar text := nullif(trim(coalesce(p_args->>'buscar', '')), '');
  v_ocultas text[] := array['loc_secretos','gp_config','gp_pages','gp_inbox','gp_log','gp_dates','admin_cfg','fact_accesos','admin_sesion','asesor_sesion',
                            'ts_sesiones','loc_sesiones','loc_accesos','login_intentos','traspasos','_img_stage'];
  v_mapa jsonb := jsonb_build_object(
    'eq_', 'Personas del equipo (eq_personas: la base única de asesores, patrocinador_id = árbol). eq_ppv/eq_concursos están archivados.',
    'registros / registro_items / registro_versiones / credito_* / hitos / documentos / observaciones / bitacora', 'Registro interno de ventas y afiliaciones del equipo (lo que se ingresó), con su línea de tiempo (hitos).',
    'productos / listas_precios / piezas / pieza_alias / factores_credito / reglas_credito / site_config', 'Cotizador: listas de precios, promociones, repuestos y reglas de crédito.',
    'crm_pedidos / rw_pedidos (vista) / crm_seguimiento / rw_importaciones', 'Pedidos oficiales de Rena Ware (reporte del back office, la realidad: puntos, despachos, entregas) y seguimiento post-venta.',
    'clientes / cliente_direcciones / cliente_referencias', 'Base única de clientes.',
    'pr_', 'Premios: lo declarado, recibido, entregado y publicado; pr_catalogo = concursos y sus requisitos.',
    'eya_', 'Programa Empiece Ya: ganadores oficiales por PB de todos los grupos (eya_asesores = únicos).',
    'n0_ / ts_', 'Nivel Cero (asistencia a 5 clases en 30 días) y su test.',
    'wa_', 'Bienvenida y seguimiento por WhatsApp (plantillas y envíos registrados).',
    'rep_', 'Reparaciones que los clientes dejan en la oficina.',
    'fact_', 'Facturación de asesores (RMT, SUNAT): comisiones, facturas, declaraciones, vencimientos.',
    'zc_', 'Zonas autorizadas para venta al crédito.',
    'loc_', 'Local compartido del equipo: turnos, cobros, pagos.',
    'plataforma_modulos / perfiles / organizaciones', 'El hub: módulos, roles del equipo.',
    'chat_', 'Este chat: herramientas, fichas, conversaciones.',
    'funciones útiles', 'hoy_lima(), periodo_indice(fecha), periodo_inicio(i), periodo_numero(i), periodo_ciclo(i), cierre_real(i), cronograma(precio, inicial), inicial_minima(precio), bono_extra_vigente(lista), crm_acciones(hoy), hoy_items_v2(rol), n0_inscritos_json(null), unaccent_safe(texto). periodo_ind = (anio-2026)*26 + pb - 1.'
  );
begin
  if v_tabla is not null then
    return jsonb_build_object(
      'tabla', v_tabla,
      'comentario', (select obj_description(c.oid) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = v_tabla),
      'columnas', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('nombre', a.attname, 'tipo', format_type(a.atttypid, a.atttypmod), 'comentario', col_description(a.attrelid, a.attnum))) order by a.attnum)
                            from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
                            where n.nspname = 'public' and c.relname = v_tabla and a.attnum > 0 and not a.attisdropped
                              and not (v_tabla = any(v_ocultas))), '[]'::jsonb));
  end if;
  return jsonb_build_object(
    'mapa', v_mapa,
    'tablas', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('nombre', c.relname, 'tipo', case c.relkind when 'v' then 'vista' else 'tabla' end,
                                                                 'filas_aprox', case when c.relkind = 'r' then greatest(c.reltuples, 0)::int end,
                                                                 'comentario', obj_description(c.oid))) order by c.relname)
                        from pg_class c join pg_namespace n on n.oid = c.relnamespace
                        where n.nspname = 'public' and c.relkind in ('r','v') and not (c.relname = any(v_ocultas))
                          and (v_buscar is null or c.relname ilike '%' || v_buscar || '%' or coalesce(obj_description(c.oid), '') ilike '%' || v_buscar || '%'
                               or exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped and a.attname ilike '%' || v_buscar || '%'))), '[]'::jsonb));
end $fn$;
revoke execute on function public.chat_esquema(jsonb) from public, anon, authenticated;

-- fichas: búsqueda de texto sobre chat_fichas. Sin q devuelve el índice.
create or replace function public.chat_fichas_buscar(p_proyecto text, p_q text, p_quien jsonb)
returns jsonb language sql stable set search_path to 'public' as $fn$
  -- Los términos se unen con OR y se ordena por relevancia (ts_rank_cd); así "horario de capacitaciones"
  -- encuentra la ficha aunque no tenga la palabra "horario".
  with s as (select nullif(trim(coalesce(p_q, '')), '') as q,
                    websearch_to_tsquery('spanish', regexp_replace(public.unaccent_safe(trim(coalesce(p_q, ''))), '\s+', ' or ', 'g')) as tsq),
  f as (
    select f.titulo, f.tema, f.contenido, f.vigente_hasta, f.fuente,
           case when s.q is null then 0 else ts_rank_cd(f.busqueda, s.tsq) end as rango,
           (s.q is not null and public.unaccent_safe(f.titulo || ' ' || f.contenido) like '%' || public.unaccent_safe(s.q) || '%') as literal
    from public.chat_fichas f, s
    where f.proyecto = p_proyecto and f.activo and (p_quien->>'rol') = any(f.roles)
      and (f.vigente_hasta is null or f.vigente_hasta >= public.hoy_lima())
      and (s.q is null
           or f.busqueda @@ s.tsq
           or public.unaccent_safe(f.titulo || ' ' || f.contenido) like '%' || public.unaccent_safe(s.q) || '%')
  )
  select case when (select q from s) is null
         then jsonb_build_object('indice', coalesce((select jsonb_agg(jsonb_build_object('titulo', titulo, 'tema', tema) order by tema, titulo) from f), '[]'::jsonb),
                                 'nota', 'Sin búsqueda: este es el índice de fichas. Vuelve a llamar con q para leer una.')
         else jsonb_build_object('fichas', coalesce((select jsonb_agg(jsonb_build_object('titulo', titulo, 'tema', tema, 'contenido', contenido, 'vigente_hasta', vigente_hasta, 'fuente', fuente)
                                                                  order by literal desc, rango desc, titulo)
                                                     from (select * from f order by literal desc, rango desc, titulo limit 5) x), '[]'::jsonb))
         end;
$fn$;
revoke execute on function public.chat_fichas_buscar(text, text, jsonb) from public, anon, authenticated;

-- sql_libre: valida que sea un solo SELECT y que no toque credenciales ni sesiones.
create or replace function public.chat_sql_valida(p_sql text)
returns text language plpgsql immutable set search_path to 'public' as $fn$
declare v text := trim(coalesce(p_sql, ''));
begin
  v := regexp_replace(v, ';\s*$', '');
  if v = '' then raise exception 'La consulta está vacía.'; end if;
  if position(';' in v) > 0 then raise exception 'Solo se permite una sentencia por consulta.'; end if;
  if v ~ '--' or v ~ '/\*' then raise exception 'Sin comentarios dentro de la consulta.'; end if;
  if v !~* '^\s*(select|with)\M' then raise exception 'Solo se permiten consultas SELECT (o WITH ... SELECT).'; end if;
  -- (las palabras van partidas con corchetes para que el texto de esta función no parezca una sentencia destructiva)
  if v ~* '\m(ins[e]rt|upd[a]te|del[e]te|trunc[a]te|dr[o]p|al[t]er|cre[a]te|grant|revoke|copy|vacuum|analyze|reindex|cluster|lock|listen|notify|refresh|reset|call|do|execute|pg_sleep|pg_read_file|pg_read_binary_file|pg_ls_dir|lo_import|lo_export|dblink|set_config|current_setting|pg_terminate_backend|pg_cancel_backend)\M' then
    raise exception 'La consulta usa una palabra no permitida (solo lectura simple).';
  end if;
  if v ~* '\mset\s' then raise exception 'La consulta usa una palabra no permitida (set).'; end if;
  if v ~* '\m(loc_secretos|gp_config|gp_pages|gp_inbox|gp_log|gp_dates|admin_cfg|fact_accesos|admin_sesion|asesor_sesion|ts_sesiones|loc_sesiones|loc_accesos|login_intentos|traspasos|pg_authid|pg_shadow|pg_user_mappings?)\M'
     or v ~* '\m(auth|vault|storage|net|cron|extensions|supabase_functions|pgsodium|realtime)\.' then
    raise exception 'La consulta toca credenciales o sesiones; no está permitido desde el chat.';
  end if;
  return v;
end $fn$;
revoke execute on function public.chat_sql_valida(text) from public, anon, authenticated;

-- ejecuta un SELECT (con $1 = argumentos, $2 = quién) y devuelve filas como jsonb; recorta si pesa mucho.
create or replace function public.chat_sql_run(p_sql text, p_args jsonb, p_quien jsonb, p_limite integer default 300)
returns jsonb language plpgsql set search_path to 'public' as $fn$
declare
  v_filas jsonb; v_n integer; v_trunc boolean := false;
begin
  execute format('select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb), count(*) from (select * from (%s) r0 limit %s) r', p_sql, p_limite)
    into v_filas, v_n using coalesce(p_args, '{}'::jsonb), coalesce(p_quien, '{}'::jsonb);
  if length(v_filas::text) > 90000 then
    execute format('select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb), count(*) from (select * from (%s) r0 limit %s) r', p_sql, 40)
      into v_filas, v_n using coalesce(p_args, '{}'::jsonb), coalesce(p_quien, '{}'::jsonb);
    v_trunc := true;
  end if;
  return jsonb_build_object('filas', v_n, 'datos', v_filas, 'truncado', v_trunc);
end $fn$;
revoke execute on function public.chat_sql_run(text, jsonb, jsonb, integer) from public, anon, authenticated;

-- ---------- la única puerta: chat_ejecutar ----------
create or replace function public.chat_ejecutar(p_proyecto text, p_herramienta text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  q   jsonb := public.chat_quien();
  h   record;
  t0  timestamptz := clock_timestamp();
  res jsonb;
  v_sql text;
begin
  if q is null then return jsonb_build_object('ok', false, 'error', 'Sin sesión de la plataforma.'); end if;
  select * into h from public.chat_herramientas where proyecto = p_proyecto and nombre = p_herramienta and activo;
  if not found then return jsonb_build_object('ok', false, 'error', 'No existe la herramienta ' || p_herramienta || '.'); end if;
  if not ((q->>'rol') = any(h.roles)) then return jsonb_build_object('ok', false, 'error', 'Tu rol no puede usar ' || p_herramienta || '.'); end if;

  -- Todo lo que sigue es solo lectura y con tiempo máximo, pase lo que pase.
  perform set_config('transaction_read_only', 'on', true);
  perform set_config('statement_timeout', '12000', true);

  begin
    if h.tipo = 'esquema' then
      res := public.chat_esquema(coalesce(p_args, '{}'::jsonb));
    elsif h.tipo = 'fichas' then
      res := public.chat_fichas_buscar(p_proyecto, p_args->>'q', q);
    elsif h.tipo = 'sql_libre' then
      v_sql := public.chat_sql_valida(p_args->>'consulta');
      res := public.chat_sql_run(v_sql, p_args, q, coalesce((p_args->>'limite')::int, 200));
    elsif h.tipo = 'sql' then
      res := public.chat_sql_run(h.sql, coalesce(p_args, '{}'::jsonb), q, 300);
    else
      return jsonb_build_object('ok', false, 'error', 'Tipo de herramienta desconocido.');
    end if;
  exception when others then
    return jsonb_build_object('ok', false, 'herramienta', p_herramienta, 'error', sqlerrm,
                              'ms', (extract(epoch from clock_timestamp() - t0) * 1000)::int);
  end;
  return jsonb_build_object('ok', true, 'herramienta', p_herramienta, 'ms', (extract(epoch from clock_timestamp() - t0) * 1000)::int) || res;
end $fn$;
revoke execute on function public.chat_ejecutar(text, text, jsonb) from public, anon;
grant execute on function public.chat_ejecutar(text, text, jsonb) to authenticated, service_role;

-- ---------- conversaciones ----------
create or replace function public.chat_conversacion_iniciar(p_proyecto text, p_titulo text default null)
returns uuid language plpgsql security definer set search_path to 'public' as $fn$
declare q jsonb := public.chat_quien(); v_id uuid;
begin
  if q is null then raise exception 'Sin sesión de la plataforma.' using errcode = '28000'; end if;
  insert into public.chat_conversaciones (proyecto, user_id, persona_id, rol, titulo)
  values (p_proyecto, (q->>'user_id')::uuid, (q->>'persona_id')::uuid, q->>'rol', left(nullif(trim(coalesce(p_titulo, '')), ''), 80))
  returning id into v_id;
  return v_id;
end $fn$;

create or replace function public.chat_mensaje_guardar(p_conversacion uuid, p_rol text, p_contenido text, p_herramientas jsonb default null, p_meta jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'public' as $fn$
declare q jsonb := public.chat_quien(); v_id bigint;
begin
  if q is null then raise exception 'Sin sesión de la plataforma.' using errcode = '28000'; end if;
  if not exists (select 1 from public.chat_conversaciones c where c.id = p_conversacion and (c.user_id = (q->>'user_id')::uuid or q->>'rol' = 'admin')) then
    raise exception 'La conversación no existe o no es tuya.';
  end if;
  insert into public.chat_mensajes (conversacion_id, rol, contenido, herramientas, sin_respuesta, modelo, tokens_in, tokens_out, ms)
  values (p_conversacion, p_rol, p_contenido, p_herramientas, coalesce((p_meta->>'sin_respuesta')::boolean, false),
          p_meta->>'modelo', (p_meta->>'tokens_in')::int, (p_meta->>'tokens_out')::int, (p_meta->>'ms')::int)
  returning id into v_id;
  update public.chat_conversaciones set actualizado_en = now(),
         titulo = coalesce(titulo, case when p_rol = 'user' then left(p_contenido, 80) end)
   where id = p_conversacion;
  return v_id;
end $fn$;

create or replace function public.chat_conversacion_mensajes(p_conversacion uuid, p_limite integer default 30)
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'rol', m.rol, 'contenido', m.contenido, 'herramientas', m.herramientas,
                                               'sin_respuesta', m.sin_respuesta, 'creado_en', m.creado_en) order by m.id), '[]'::jsonb)
  from (select * from public.chat_mensajes m
         where m.conversacion_id = p_conversacion
           and exists (select 1 from public.chat_conversaciones c, public.chat_quien() q
                        where c.id = m.conversacion_id and (c.user_id = (q->>'user_id')::uuid or q->>'rol' = 'admin'))
         order by m.id desc limit greatest(1, least(coalesce(p_limite, 30), 200))) m;
$fn$;

create or replace function public.chat_conversaciones_lista(p_proyecto text default 'renaware', p_limite integer default 20)
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'titulo', c.titulo, 'actualizado_en', c.actualizado_en, 'rol', c.rol,
                                               'mensajes', (select count(*) from public.chat_mensajes m where m.conversacion_id = c.id))
                            order by c.actualizado_en desc), '[]'::jsonb)
  from (select c.* from public.chat_conversaciones c, public.chat_quien() q
         where c.proyecto = p_proyecto and not c.archivada and c.user_id = (q->>'user_id')::uuid
         order by c.actualizado_en desc limit greatest(1, least(coalesce(p_limite, 20), 100))) c;
$fn$;

create or replace function public.chat_conversacion_archivar(p_conversacion uuid)
returns boolean language plpgsql security definer set search_path to 'public' as $fn$
declare q jsonb := public.chat_quien();
begin
  if q is null then raise exception 'Sin sesión de la plataforma.' using errcode = '28000'; end if;
  update public.chat_conversaciones set archivada = true, actualizado_en = now()
   where id = p_conversacion and user_id = (q->>'user_id')::uuid;
  return found;
end $fn$;

-- Pendientes del chat (para Hoy): preguntas sin respuesta de la última semana.
create or replace function public.chat_pendientes()
returns jsonb language sql stable security definer set search_path to 'public' as $fn$
  select jsonb_build_object(
    'sin_respuesta_7d', (select count(*) from public.chat_mensajes m where m.sin_respuesta and m.creado_en > now() - interval '7 days'),
    'preguntas', coalesce((select jsonb_agg(left(u.contenido, 140) order by u.id desc)
                           from (select u.* from public.chat_mensajes a
                                 join lateral (select u.* from public.chat_mensajes u where u.conversacion_id = a.conversacion_id and u.rol = 'user' and u.id < a.id order by u.id desc limit 1) u on true
                                 where a.sin_respuesta and a.creado_en > now() - interval '7 days' limit 10) u), '[]'::jsonb));
$fn$;

revoke execute on function public.chat_conversacion_iniciar(text, text) from public, anon;
revoke execute on function public.chat_mensaje_guardar(uuid, text, text, jsonb, jsonb) from public, anon;
revoke execute on function public.chat_conversacion_mensajes(uuid, integer) from public, anon;
revoke execute on function public.chat_conversaciones_lista(text, integer) from public, anon;
revoke execute on function public.chat_conversacion_archivar(uuid) from public, anon;
revoke execute on function public.chat_pendientes() from public, anon;
grant execute on function public.chat_conversacion_iniciar(text, text) to authenticated, service_role;
grant execute on function public.chat_mensaje_guardar(uuid, text, text, jsonb, jsonb) to authenticated, service_role;
grant execute on function public.chat_conversacion_mensajes(uuid, integer) to authenticated, service_role;
grant execute on function public.chat_conversaciones_lista(text, integer) to authenticated, service_role;
grant execute on function public.chat_conversacion_archivar(uuid) to authenticated, service_role;
grant execute on function public.chat_pendientes() to authenticated, service_role;
