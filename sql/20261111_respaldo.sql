-- =====================================================================================================
-- Respaldo en el plan gratuito (11 de noviembre de 2026). Aplicado en la base; este archivo es la copia.
--
-- El plan gratuito de Supabase no hace backups. Esto guarda, dentro de la misma base y sin que nadie
-- haga nada, una copia de todos los datos y de la estructura cada madrugada:
--   · esquema «respaldo» (no se expone por la API; solo se llega por las funciones public.respaldo_*)
--   · casilleros que se pisan solos: dia-1..dia-7 (una por día de la semana), mes-0..mes-2 (la primera
--     copia de cada mes, tres meses dando la vuelta) y manual (la que se pide desde el hub)
--   · respaldo.cambios: la historia de cada función, tabla, vista, política, disparador, índice y tarea
--   · tarea respaldo_diario, 07:40 UTC (2:40 a. m. de Lima)
-- La copia dentro de la base cubre el daño accidental (un borrado, una carga mala). Si se pierde el
-- proyecto entero solo sirve la copia descargada: hub → Respaldo → «Descargar copia a este dispositivo».
-- Los archivos de Storage no entran en la copia de datos; se bajan aparte, por carpeta, en esa pantalla.
--
-- Recuperar un dato:
--   select o from respaldo.objetos('dia-2', 'public.registros') o where o->>'codigo' = 'R-0123';
--   insert into public.registros select (jsonb_populate_record(null::public.registros, o)).* from respaldo.objetos(...) o where ...;
-- Probar que la copia sirve (reconstruye cada tabla y la compara con la viva):
--   select * from respaldo.verificar('dia-3') where distintas <> 0;
-- La primera corrida (corrida 1, dia-3 y mes-2): 141 tablas, 29 143 filas, 2 segundos, 0 diferencias.
-- =====================================================================================================

create schema if not exists respaldo;
revoke all on schema respaldo from public, anon, authenticated;

create table if not exists respaldo.corridas (
  id bigint generated always as identity primary key,
  slot text not null,
  motivo text not null default 'diario',
  inicio timestamptz not null default now(),
  fin timestamptz,
  tablas int, filas bigint, bytes bigint, cambios int,
  copia_mes text,
  ok boolean not null default false,
  error text
);
create table if not exists respaldo.datos (
  slot text not null,
  tabla text not null,
  columnas text[] not null,
  filas bigint not null,
  datos jsonb not null,
  bytes bigint not null,
  tomado_en timestamptz not null default now(),
  corrida_id bigint not null,
  primary key (slot, tabla)
);
create table if not exists respaldo.cambios (
  id bigint generated always as identity primary key,
  tipo text not null,
  nombre text not null,
  que text not null,
  huella text not null,
  definicion text,
  visto_en timestamptz not null default now()
);
create index if not exists cambios_objeto on respaldo.cambios (tipo, nombre, id desc);
create table if not exists respaldo.descargas (
  id bigint generated always as identity primary key,
  creado_en timestamptz not null default now(),
  user_id uuid,
  slot text,
  que text not null default 'datos',
  piezas int,
  bytes bigint
);
revoke all on all tables in schema respaldo from public, anon, authenticated;

comment on schema respaldo is 'Copia diaria de los datos y de la estructura de la plataforma, dentro de la misma base (plan gratuito, sin backups de Supabase). No se expone por la API: solo se llega por las funciones public.respaldo_*.';
comment on table respaldo.datos is 'Una fila por tabla y por casillero (dia-1..7, mes-0..2, manual). datos = arreglo de filas; cada fila es un arreglo en el orden de «columnas». La pieza «(estructura)» lleva el SQL para rehacer la base.';
comment on table respaldo.cambios is 'Historia de cada función, vista, tabla, política, disparador, índice y tarea: una fila cada vez que su definición cambia. Sirve para ver qué cambió y recuperar una versión anterior.';

-- ---------- la estructura, objeto por objeto, en el orden en que hay que crearla ----------
create or replace function respaldo.definiciones()
returns table(orden int, pos bigint, tipo text, nombre text, sql text)
language sql stable security definer set search_path to 'public', 'pg_catalog' as $fn$
  select 10, 0::bigint, 'extension', e.extname::text,
         format('create extension if not exists %I with schema %I;', e.extname, n.nspname)
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname <> 'plpgsql'
  union all
  select 20, 0, 'tipo', t.typname::text,
         format('create type public.%I as enum (%s);', t.typname,
                (select string_agg(quote_literal(e.enumlabel), ', ' order by e.enumsortorder) from pg_enum e where e.enumtypid = t.oid))
    from pg_type t where t.typnamespace = 'public'::regnamespace and t.typtype = 'e'
  union all
  select 30, 0, 'secuencia', s.sequencename::text,
         format('create sequence if not exists public.%I as %s increment by %s minvalue %s maxvalue %s start with %s;',
                s.sequencename, s.data_type, s.increment_by, s.min_value, s.max_value, s.start_value)
    from pg_sequences s
   where s.schemaname = 'public'
     and not exists (select 1 from pg_depend d join pg_class c on c.oid = d.objid
                      where c.relname = s.sequencename and c.relnamespace = 'public'::regnamespace and d.deptype = 'i')
  union all
  -- las funciones van antes que las tablas (valores por defecto y columnas calculadas las usan); sus cuerpos no se revisan al crear
  select 40, p.oid::bigint, 'funcion', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', pg_get_functiondef(p.oid) || ';'
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
  union all
  select 50, c.oid::bigint, 'tabla', c.relname::text,
         format(E'create table public.%I (\n  %s\n);', c.relname,
           (select string_agg(
                     format('%I %s', a.attname, format_type(a.atttypid, a.atttypmod))
                     || case when a.attgenerated = 's' then ' generated always as (' || pg_get_expr(d.adbin, d.adrelid) || ') stored'
                             when a.attidentity = 'a' then ' generated always as identity'
                             when a.attidentity = 'd' then ' generated by default as identity'
                             when d.adbin is not null then ' default ' || pg_get_expr(d.adbin, d.adrelid)
                             else '' end
                     || case when a.attnotnull then ' not null' else '' end,
                     E',\n  ' order by a.attnum)
              from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped))
         || case when c.relrowsecurity then format(E'\nalter table public.%I enable row level security;', c.relname) else '' end
         || case when c.relforcerowsecurity then format(E'\nalter table public.%I force row level security;', c.relname) else '' end
    from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
  union all
  select case when k.contype = 'f' then 62 else 60 end, 0, 'restriccion', c.relname || '.' || k.conname,
         format('alter table public.%I add constraint %I %s;', c.relname, k.conname, pg_get_constraintdef(k.oid))
    from pg_constraint k join pg_class c on c.oid = k.conrelid
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and k.contype in ('p', 'u', 'c', 'f', 'x')
  union all
  select 64, 0, 'indice', ci.relname::text, pg_get_indexdef(i.indexrelid) || ';'
    from pg_index i join pg_class ci on ci.oid = i.indexrelid join pg_class ct on ct.oid = i.indrelid
   where ct.relnamespace = 'public'::regnamespace and ct.relkind = 'r'
     and not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid)
  union all
  select 70, c.oid::bigint, 'vista', c.relname::text,
         format('create or replace view public.%I%s as %s', c.relname,
                case when c.reloptions is not null then ' with (' || array_to_string(c.reloptions, ', ') || ')' else '' end,
                pg_get_viewdef(c.oid, true))
    from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'v'
  union all
  select 80, 0, 'disparador', c.relname || '.' || t.tgname, pg_get_triggerdef(t.oid, true) || ';'
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace
  union all
  -- disparadores de eventos propios (la guardia de las vistas, 13/11); los de Supabase viven en extensions y no se copian
  select 82, 0, 'disparador', 'evento.' || e.evtname,
         format('create event trigger %I on %s%s execute function public.%I();', e.evtname, e.evtevent,
                case when e.evttags is not null then ' when tag in (' || (select string_agg(quote_literal(t), ', ') from unnest(e.evttags) t) || ')' else '' end,
                p.proname)
         || case when e.evtenabled = 'D' then chr(10) || format('alter event trigger %I disable;', e.evtname) else '' end
    from pg_event_trigger e join pg_proc p on p.oid = e.evtfoid
   where p.pronamespace = 'public'::regnamespace
  union all
  select 90, 0, 'politica', p.schemaname || '.' || p.tablename || '.' || p.policyname,
         format('create policy %I on %I.%I as %s for %s to %s%s%s;', p.policyname, p.schemaname, p.tablename, p.permissive, p.cmd,
                array_to_string(p.roles, ', '),
                case when p.qual is not null then ' using (' || p.qual || ')' else '' end,
                case when p.with_check is not null then ' with check (' || p.with_check || ')' else '' end)
    from pg_policies p where p.schemaname = 'public' or (p.schemaname = 'storage' and p.tablename = 'objects')
  union all
  -- permisos: solo lo que se aparta de lo que Supabase da por defecto (todo abierto a anon y authenticated)
  select 100, 0, 'permiso', 'funcion ' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         format('revoke execute on function public.%I(%s) from public, anon, authenticated;', p.proname, pg_get_function_identity_arguments(p.oid))
         || coalesce((select string_agg(format(E'\ngrant execute on function public.%I(%s) to %s;', p.proname, pg_get_function_identity_arguments(p.oid), r), '')
                        from unnest(array['anon', 'authenticated']) r where has_function_privilege(r, p.oid, 'EXECUTE')), '')
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
     and not (has_function_privilege('anon', p.oid, 'EXECUTE') and has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  union all
  select 100, 0, 'permiso', 'tabla ' || c.relname,
         format('revoke all on public.%I from anon, authenticated;', c.relname)
         || coalesce((select string_agg(format(E'\ngrant %s on public.%I to %s;', lower(priv), c.relname, r), '' order by r, priv)
                        from unnest(array['anon', 'authenticated']) r, unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) priv
                       where has_table_privilege(r, c.oid, priv)), '')
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v')
     and exists (select 1 from unnest(array['anon', 'authenticated']) r, unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) priv
                  where not has_table_privilege(r, c.oid, priv))
  union all
  select 110, 0, 'carpeta', b.id::text,
         format('insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values (%L, %L, %L, %s, %L) on conflict (id) do nothing;',
                b.id, b.name, b.public, coalesce(b.file_size_limit::text, 'null'), b.allowed_mime_types)
    from storage.buckets b
  union all
  select 120, 0, 'tarea', j.jobname::text, format('select cron.schedule(%L, %L, %L);', j.jobname, j.schedule, j.command) from cron.job j
  union all
  select 130, 0, 'contador', s.sequencename::text, format('select setval(%L, %s, true);', 'public.' || quote_ident(s.sequencename), s.last_value)
    from pg_sequences s where s.schemaname = 'public' and s.last_value is not null
$fn$;

create or replace function respaldo.estructura_sql()
returns text language sql stable security definer set search_path to 'public', 'pg_catalog' as $fn$
  select format(E'-- Estructura de la base de la plataforma (Supabase %s), generada el %s.\n'
             || E'-- Para rehacer la base en un proyecto nuevo: correr este archivo completo y después cargar los datos de la copia.\n'
             || E'-- No incluye: cuentas de acceso (auth), secretos (vault) ni los archivos de Storage; el esquema «respaldo» se rehace con sql/20261111_respaldo.sql.\n'
             || E'-- %s\n\nset check_function_bodies = off;\n\n',
                current_database(), to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
                (select string_agg(n || ' ' || tipo, ', ' order by o) from (select d.tipo, count(*) n, min(d.orden) o from respaldo.definiciones() d group by d.tipo) z))
      || (select string_agg(d.sql, E'\n\n' order by d.orden, d.pos, d.nombre) from respaldo.definiciones() d)
$fn$;

-- ---------- leer una copia: las filas de una tabla, una por una y con nombre de columna ----------
create or replace function respaldo.objetos(p_slot text, p_tabla text)
returns setof jsonb language sql stable security definer set search_path to 'public', 'pg_catalog' as $fn$
  select case when cardinality(d.columnas) = 0 then f.fila
              else (select jsonb_object_agg(d.columnas[i], f.fila -> (i - 1)) from generate_subscripts(d.columnas, 1) i) end
    from respaldo.datos d, jsonb_array_elements(d.datos) as f(fila)
   where d.slot = p_slot and d.tabla = p_tabla
$fn$;
comment on function respaldo.objetos(text, text) is 'Las filas de una tabla tal como estaban en una copia, una por una y con nombre de columna. Ej.: select o from respaldo.objetos(''dia-3'', ''public.registros'') o where o->>''codigo'' = ''R-0123'';  y para volver a tabla: (jsonb_populate_record(null::public.registros, o)).*';

-- ---------- la historia de la estructura ----------
create or replace function respaldo.anotar_cambios()
returns int language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
declare n int := 0; m int := 0; v_primera boolean := not exists (select 1 from respaldo.cambios);
begin
  with ahora as (
    select d.tipo, d.nombre, md5(d.sql) as huella, d.sql from respaldo.definiciones() d where d.tipo <> 'contador'
  ), ultimo as (
    select distinct on (c.tipo, c.nombre) c.tipo, c.nombre, c.huella from respaldo.cambios c order by c.tipo, c.nombre, c.id desc
  )
  insert into respaldo.cambios (tipo, nombre, que, huella, definicion)
  select a.tipo, a.nombre,
         case when v_primera then 'inicial' when u.nombre is null or u.huella = '' then 'nuevo' else 'cambio' end,
         a.huella, a.sql
    from ahora a left join ultimo u on u.tipo = a.tipo and u.nombre = a.nombre
   where u.nombre is null or u.huella is distinct from a.huella;
  get diagnostics n = row_count;

  insert into respaldo.cambios (tipo, nombre, que, huella, definicion)
  select u.tipo, u.nombre, 'quitado', '', null
    from (select distinct on (c.tipo, c.nombre) c.tipo, c.nombre, c.huella from respaldo.cambios c order by c.tipo, c.nombre, c.id desc) u
   where u.huella <> ''
     and not exists (select 1 from respaldo.definiciones() d where d.tipo = u.tipo and d.nombre = u.nombre);
  get diagnostics m = row_count;
  return case when v_primera then 0 else n + m end;
end $fn$;

-- ---------- la copia ----------
create or replace function respaldo.correr(p_motivo text default 'diario')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
declare
  v_hoy date := public.hoy_lima();
  v_slot text := case when p_motivo = 'manual' then 'manual' else 'dia-' || extract(isodow from v_hoy)::int end;
  v_mes text; v_id bigint; r record; v_cols text[]; v_lista text; v_datos jsonb; v_n bigint;
  v_tablas int := 0; v_filas bigint := 0; v_bytes bigint := 0; v_cambios int := 0; v_script text; v_err text;
begin
  insert into respaldo.corridas (slot, motivo) values (v_slot, p_motivo) returning id into v_id;
  begin
    for r in
      select n.nspname::text as esquema, c.relname::text as tabla, c.oid
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where c.relkind = 'r'
         and (n.nspname = 'public'
              or (n.nspname = 'storage' and c.relname in ('buckets', 'objects'))
              or (n.nspname = 'supabase_migrations' and c.relname = 'schema_migrations'))
       order by 1, 2
    loop
      select array_agg(a.attname::text order by a.attnum), string_agg(quote_ident(a.attname), ', ' order by a.attnum)
        into v_cols, v_lista
        from pg_attribute a where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped;
      if cardinality(v_cols) <= 100 then
        execute format('select coalesce(jsonb_agg(jsonb_build_array(%s)), ''[]''::jsonb), count(*) from %I.%I', v_lista, r.esquema, r.tabla) into v_datos, v_n;
      else   -- una tabla con más de 100 columnas se guarda fila por fila con sus nombres
        v_cols := '{}';
        execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb), count(*) from %I.%I t', r.esquema, r.tabla) into v_datos, v_n;
      end if;
      insert into respaldo.datos (slot, tabla, columnas, filas, datos, bytes, tomado_en, corrida_id)
      values (v_slot, r.esquema || '.' || r.tabla, v_cols, v_n, v_datos, pg_column_size(v_datos), now(), v_id)
      on conflict (slot, tabla) do update
        set columnas = excluded.columnas, filas = excluded.filas, datos = excluded.datos, bytes = excluded.bytes,
            tomado_en = excluded.tomado_en, corrida_id = excluded.corrida_id;
      v_tablas := v_tablas + 1; v_filas := v_filas + v_n; v_bytes := v_bytes + pg_column_size(v_datos);
    end loop;

    -- la estructura viaja como una pieza más del mismo corte
    v_script := respaldo.estructura_sql();
    insert into respaldo.datos (slot, tabla, columnas, filas, datos, bytes, tomado_en, corrida_id)
    values (v_slot, '(estructura)', array['script'], 1, jsonb_build_array(jsonb_build_array(v_script)), length(v_script), now(), v_id)
    on conflict (slot, tabla) do update
      set columnas = excluded.columnas, filas = excluded.filas, datos = excluded.datos, bytes = excluded.bytes,
          tomado_en = excluded.tomado_en, corrida_id = excluded.corrida_id;

    v_cambios := respaldo.anotar_cambios();

    -- la primera copia diaria de cada mes se guarda aparte: tres meses que van dando la vuelta
    if p_motivo <> 'manual' and not exists (
         select 1 from respaldo.corridas c
          where c.ok and c.copia_mes is not null
            and to_char(c.inicio at time zone 'America/Lima', 'YYYY-MM') = to_char(v_hoy, 'YYYY-MM')) then
      v_mes := 'mes-' || (extract(month from v_hoy)::int % 3);
      insert into respaldo.datos (slot, tabla, columnas, filas, datos, bytes, tomado_en, corrida_id)
      select v_mes, d.tabla, d.columnas, d.filas, d.datos, d.bytes, d.tomado_en, d.corrida_id
        from respaldo.datos d where d.slot = v_slot and d.corrida_id = v_id
      on conflict (slot, tabla) do update
        set columnas = excluded.columnas, filas = excluded.filas, datos = excluded.datos, bytes = excluded.bytes,
            tomado_en = excluded.tomado_en, corrida_id = excluded.corrida_id;
    end if;
  exception when others then
    v_err := sqlerrm;   -- lo escrito en este intento se deshace solo: el casillero conserva su copia anterior
  end;

  update respaldo.corridas
     set fin = clock_timestamp(), ok = v_err is null, error = v_err,
         tablas = v_tablas, filas = v_filas, bytes = v_bytes, cambios = v_cambios, copia_mes = v_mes
   where id = v_id;
  return jsonb_build_object('ok', v_err is null, 'error', v_err, 'corrida', v_id, 'slot', v_slot, 'copia_mes', v_mes,
                            'tablas', v_tablas, 'filas', v_filas, 'bytes', v_bytes, 'cambios', v_cambios);
end $fn$;

-- ---------- prueba de restauración ----------
create or replace function respaldo.verificar(p_slot text)
returns table(tabla text, en_copia bigint, en_vivo bigint, distintas bigint)
language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
declare r record; v_rel text;
begin
  for r in
    select d.tabla as t, d.filas as f from respaldo.datos d
     where d.slot = p_slot and d.tabla !~ '^\('
       and d.corrida_id = (select max(d2.corrida_id) from respaldo.datos d2 where d2.slot = p_slot)
     order by 1
  loop
    tabla := r.t; en_copia := r.f; en_vivo := null; distintas := null;
    v_rel := format('%I.%I', split_part(r.t, '.', 1), split_part(r.t, '.', 2));
    begin
      execute format('select (select count(*) from %s), (select count(*) from (select (jsonb_populate_record(null::%s, o)).* from respaldo.objetos(%L, %L) o except all select * from %s) x)',
                     v_rel, v_rel, p_slot, r.t, v_rel) into en_vivo, distintas;
    exception when others then distintas := -1;   -- la tabla ya no existe o tiene un tipo que no se puede comparar
    end;
    return next;
  end loop;
end $fn$;
comment on function respaldo.verificar(text) is 'Prueba de restauración: reconstruye cada tabla desde la copia y la compara con la tabla viva. distintas = filas de la copia que hoy no están iguales (0 justo después de copiar).';

revoke all on all functions in schema respaldo from public, anon, authenticated;

-- ---------- lo que usa el hub (solo administrador) ----------
create or replace function public.respaldo_estado()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
begin
  if not tiene_rol('admin') then raise exception 'Solo el administrador puede ver el respaldo.'; end if;
  return jsonb_build_object(
    'ultima', (select to_jsonb(c) - 'error' from respaldo.corridas c where c.ok order by c.id desc limit 1),
    'falla', (select jsonb_build_object('inicio', c.inicio, 'error', c.error) from respaldo.corridas c
               where not c.ok and c.fin is not null and c.id > coalesce((select max(id) from respaldo.corridas where ok), 0) order by c.id desc limit 1),
    'copias', (select coalesce(jsonb_agg(x order by x->>'tomado_en' desc), '[]'::jsonb) from (
                 select jsonb_build_object('slot', d.slot, 'tomado_en', max(d.tomado_en),
                          'tablas', count(*) filter (where d.tabla !~ '^\('), 'filas', sum(d.filas) filter (where d.tabla !~ '^\('), 'bytes', sum(d.bytes)) as x
                   from respaldo.datos d
                  where d.corrida_id = (select max(d2.corrida_id) from respaldo.datos d2 where d2.slot = d.slot)
                  group by d.slot) z),
    'descarga', (select jsonb_build_object('creado_en', x.creado_en, 'slot', x.slot, 'bytes', x.bytes) from respaldo.descargas x where x.que = 'datos' order by x.id desc limit 1),
    'descarga_archivos', (select jsonb_build_object('creado_en', x.creado_en, 'bytes', x.bytes, 'piezas', x.piezas) from respaldo.descargas x where x.que = 'archivos' order by x.id desc limit 1),
    'base', jsonb_build_object('bytes', pg_database_size(current_database()), 'limite', 524288000,
              'respaldo_bytes', (select coalesce(sum(pg_total_relation_size(c.oid)), 0) from pg_class c where c.relnamespace = 'respaldo'::regnamespace and c.relkind = 'r')),
    'archivos', (select coalesce(jsonb_agg(jsonb_build_object('carpeta', z.bucket_id, 'publica', z.public, 'archivos', z.n, 'bytes', z.b) order by z.b desc), '[]'::jsonb)
                   from (select o.bucket_id, b.public, count(*) n, sum(coalesce((o.metadata->>'size')::bigint, 0)) b
                           from storage.objects o join storage.buckets b on b.id = o.bucket_id group by 1, 2) z),
    'cambios', (select coalesce(jsonb_agg(jsonb_build_object('tipo', c.tipo, 'nombre', c.nombre, 'que', c.que, 'visto_en', c.visto_en) order by c.id desc), '[]'::jsonb)
                  from (select * from respaldo.cambios where que <> 'inicial' order by id desc limit 30) c),
    'hoy', hoy_lima());
end $fn$;

create or replace function public.respaldo_piezas(p_slot text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
declare v_slot text := p_slot;
begin
  if not tiene_rol('admin') then raise exception 'Solo el administrador puede descargar el respaldo.'; end if;
  if v_slot is null then select c.slot into v_slot from respaldo.corridas c where c.ok order by c.id desc limit 1; end if;
  return jsonb_build_object('slot', v_slot,
    'tomado_en', (select max(d.tomado_en) from respaldo.datos d where d.slot = v_slot),
    'piezas', (select coalesce(jsonb_agg(jsonb_build_object('tabla', d.tabla, 'filas', d.filas, 'bytes', d.bytes) order by d.tabla), '[]'::jsonb)
                 from respaldo.datos d
                where d.slot = v_slot and d.corrida_id = (select max(d2.corrida_id) from respaldo.datos d2 where d2.slot = v_slot)));
end $fn$;

create or replace function public.respaldo_pieza(p_slot text, p_tabla text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
begin
  if not tiene_rol('admin') then raise exception 'Solo el administrador puede descargar el respaldo.'; end if;
  return (select jsonb_build_object('tabla', d.tabla, 'columnas', d.columnas, 'filas', d.filas, 'datos', d.datos, 'tomado_en', d.tomado_en)
            from respaldo.datos d where d.slot = p_slot and d.tabla = p_tabla);
end $fn$;

create or replace function public.respaldo_descargada(p_que text, p_slot text, p_piezas int, p_bytes bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
begin
  if not tiene_rol('admin') then raise exception 'Solo el administrador puede descargar el respaldo.'; end if;
  insert into respaldo.descargas (user_id, slot, que, piezas, bytes)
  values (auth.uid(), p_slot, case when p_que = 'archivos' then 'archivos' else 'datos' end, p_piezas, p_bytes);
  return jsonb_build_object('ok', true);
end $fn$;

create or replace function public.respaldo_ahora()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
begin
  if not tiene_rol('admin') then raise exception 'Solo el administrador puede hacer una copia.'; end if;
  if exists (select 1 from respaldo.corridas c where c.inicio > now() - interval '2 minutes') then
    raise exception 'Acabas de hacer una copia. Espera un par de minutos.';
  end if;
  return respaldo.correr('manual') - 'error';
end $fn$;

create or replace function public.respaldo_archivos(p_carpeta text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
begin
  if not tiene_rol('admin') then raise exception 'Solo el administrador puede descargar los archivos.'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('nombre', o.name, 'bytes', coalesce((o.metadata->>'size')::bigint, 0), 'fecha', o.updated_at) order by o.name), '[]'::jsonb)
            from storage.objects o where o.bucket_id = p_carpeta and o.metadata is not null);
end $fn$;

revoke execute on function public.respaldo_estado(), public.respaldo_piezas(text), public.respaldo_pieza(text, text),
  public.respaldo_descargada(text, text, int, bigint), public.respaldo_ahora(), public.respaldo_archivos(text) from public, anon;

-- ---------- tarea diaria, entrada en el menú y avisos en Vigencia ----------
select cron.schedule('respaldo_diario', '40 7 * * *', 'select respaldo.correr()');

insert into public.plataforma_modulos (id, nombre, descripcion, url, grupo, orden, roles, acceso, activo)
values ('respaldo', 'Respaldo', 'Copia diaria de los datos y descarga para guardarla fuera.', '#respaldo', 'Oficina', 33, array['admin'], 'hub', true)
on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, url = excluded.url, grupo = excluded.grupo,
  orden = excluded.orden, roles = excluded.roles, acceso = excluded.acceso, activo = excluded.activo;

insert into public.plataforma_fuentes (id, nombre, accion, modulo, roles, cadencia, dia, aviso_dias, ultima_sql, vence_sql, pendientes_sql, en_hoy, activo, orden, nota)
values
 ('respaldo-diario', 'Respaldo diario de la base',
  'La copia automática de la madrugada no está corriendo. Entra a Respaldo y haz una copia a mano; si vuelve a fallar, avísale a Claude.',
  'respaldo', array['admin'], 'vigencia', 0, 0,
  'select max(fin at time zone ''America/Lima'')::date from respaldo.corridas where ok',
  'select max(fin at time zone ''America/Lima'')::date + 2 from respaldo.corridas where ok',
  null, true, true, 90, 'Corre sola a las 2:40 a. m. (tarea respaldo_diario). Vence si pasan dos días sin una copia buena.'),
 ('respaldo-copia-fuera', 'Copia del respaldo fuera de Supabase',
  'Entra a Respaldo, descarga la copia y guárdala en tu Drive. Es la única que sirve si se pierde el proyecto de Supabase.',
  'respaldo', array['admin'], 'vigencia', 0, 5,
  'select max(creado_en at time zone ''America/Lima'')::date from respaldo.descargas where que = ''datos''',
  'select coalesce((select max(creado_en at time zone ''America/Lima'')::date + 30 from respaldo.descargas where que = ''datos''), (select min(inicio at time zone ''America/Lima'')::date + 5 from respaldo.corridas))',
  null, true, true, 91, 'Una descarga al mes. La primera vez da cinco días de plazo.')
on conflict (id) do update set nombre = excluded.nombre, accion = excluded.accion, modulo = excluded.modulo, roles = excluded.roles,
  cadencia = excluded.cadencia, dia = excluded.dia, aviso_dias = excluded.aviso_dias, ultima_sql = excluded.ultima_sql, vence_sql = excluded.vence_sql,
  en_hoy = excluded.en_hoy, activo = excluded.activo, orden = excluded.orden, nota = excluded.nota, actualizado_en = now();

-- la primera copia
select respaldo.correr('diario');
