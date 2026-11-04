-- =====================================================================
-- Entrenamientos · Listas · Horario  (módulo /entrenamientos/ de la plataforma)
--
-- Tres bases:
--   ent_*  entrenamientos: módulos → lecciones → recursos (guía PDF, video, libro, enlace)
--          y el progreso de cada asesor (visto / completado).
--   doc_*  documentos: una sola base de listas, fotos y PDF por categoría. Cada documento
--          tiene una `clave` estable (p. ej. lista-promo-cliente) para que otros sistemas
--          jalen el vigente, y acumula versiones (la última no borrada es la vigente).
--   hor_*  horario: plantillas semanales (el horario habitual) y eventos concretos por
--          fecha. La semana se materializa sola; cada evento se puede apagar o editar.
--          Lo que lleva asistencia se crea como clase en Nivel Cero (n0_clases).
--
-- Acceso: funciones RPC con p_token. Oficina = admin_sesion (es_admin); asesor =
-- asesor_sesion (asesor_sesion_valida). Sin RLS abierto: todo pasa por RPC.
-- Archivos: bucket `entrenamientos` (público para leer); subir exige un ticket
-- (ent_subidas) creado por la oficina, validado en la política de Storage.
-- =====================================================================

-- ---------------------------------------------------------------- tablas
create table if not exists public.doc_categorias (
  id            text primary key,
  nombre        text not null,
  descripcion   text,
  orden         integer not null default 0,
  roles         text[] not null default array['admin','asistente','asesor'],
  activo        boolean not null default true
);
comment on table public.doc_categorias is 'Categorías de la base de documentos (listas de precios, repuestos, concursos…)';

create table if not exists public.doc_documentos (
  id            uuid primary key default gen_random_uuid(),
  categoria_id  text not null references public.doc_categorias(id),
  clave         text unique,
  titulo        text not null,
  descripcion   text,
  audiencia     text not null default 'asesor' check (audiencia in ('cliente','asesor','oficina')),
  roles         text[] not null default array['admin','asistente','asesor'],
  orden         integer not null default 0,
  activo        boolean not null default true,
  borrado       boolean not null default false,
  creado_en     timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
comment on table public.doc_documentos is 'Documentos de la base compartida: listas de precios, repuestos, fotos de concursos. clave = llave estable; versiones en doc_versiones';
comment on column public.doc_documentos.clave is 'Llave estable que otros sistemas usan para jalar el vigente (p. ej. lista-promo-cliente). Null = documento suelto (un concurso)';
comment on column public.doc_documentos.audiencia is 'A quién se le muestra el documento: cliente (se le puede enviar), asesor (interno del equipo) u oficina';

create table if not exists public.doc_versiones (
  id            uuid primary key default gen_random_uuid(),
  documento_id  uuid not null references public.doc_documentos(id),
  version       integer not null,
  ruta          text not null,
  archivo       text not null,
  bytes         bigint,
  content_type  text,
  paginas       integer,
  portada       text,
  nota          text,
  vigente_desde date,
  vigente_hasta date,
  creado_en     timestamptz not null default now(),
  borrada       boolean not null default false,
  unique (documento_id, version)
);
comment on table public.doc_versiones is 'Versiones de cada documento (archivo en el bucket entrenamientos). La última no borrada es la vigente';

create table if not exists public.ent_modulos (
  id            uuid primary key default gen_random_uuid(),
  titulo        text not null,
  descripcion   text,
  orden         integer not null default 0,
  roles         text[] not null default array['admin','asistente','asesor'],
  activo        boolean not null default true,
  borrado       boolean not null default false,
  creado_en     timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
comment on table public.ent_modulos is 'Módulos del sistema de entrenamiento (3–4 lecciones cada uno)';

create table if not exists public.ent_lecciones (
  id            uuid primary key default gen_random_uuid(),
  modulo_id     uuid not null references public.ent_modulos(id),
  titulo        text not null,
  descripcion   text,
  orden         integer not null default 0,
  activo        boolean not null default true,
  borrada       boolean not null default false,
  creado_en     timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
comment on table public.ent_lecciones is 'Lecciones de cada módulo; sus materiales están en ent_recursos';

create table if not exists public.ent_recursos (
  id            uuid primary key default gen_random_uuid(),
  leccion_id    uuid not null references public.ent_lecciones(id),
  tipo          text not null check (tipo in ('guia','video','libro','enlace')),
  titulo        text,
  ruta          text,
  archivo       text,
  bytes         bigint,
  content_type  text,
  paginas       integer,
  portada       text,
  url           text,
  orden         integer not null default 0,
  activo        boolean not null default true,
  borrado       boolean not null default false,
  creado_en     timestamptz not null default now(),
  check (ruta is not null or url is not null)
);
comment on table public.ent_recursos is 'Materiales de una lección: guia (PDF), video (archivo o enlace), libro (PDF o enlace), enlace. Se muestra solo lo que existe';

create table if not exists public.ent_progreso (
  leccion_id    uuid not null references public.ent_lecciones(id),
  celular       text not null,
  visto_en      timestamptz,
  completado_en timestamptz,
  primary key (leccion_id, celular)
);
comment on table public.ent_progreso is 'Progreso de cada asesor (por celular) en cada lección';

create table if not exists public.ent_subidas (
  id            uuid primary key default gen_random_uuid(),
  creado_en     timestamptz not null default now(),
  usado         boolean not null default false
);
comment on table public.ent_subidas is 'Tickets de subida al bucket entrenamientos: la oficina pide uno (ent_subida_crear) y sube a <ticket>/<archivo>';

create table if not exists public.hor_plantillas (
  id            uuid primary key default gen_random_uuid(),
  dia           smallint not null check (dia between 0 and 6),
  hora          time not null,
  titulo        text not null,
  descripcion   text,
  lugar         text,
  modo          text not null default 'presencial' check (modo in ('presencial','zoom','otro')),
  facilitador   text,
  enlace        text,
  tipo          text not null default 'capacitacion' check (tipo in ('capacitacion','evento','reunion','reclutamiento')),
  asistencia    boolean not null default true,
  solo_inicio_periodo boolean not null default false,
  publico       boolean not null default true,
  orden         integer not null default 0,
  activo        boolean not null default true,
  borrada       boolean not null default false,
  creado_en     timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
comment on table public.hor_plantillas is 'Horario habitual de la semana (dia 0=domingo … 6=sábado). solo_inicio_periodo: solo el jueves que empieza un período (lanzamiento de concurso)';
comment on column public.hor_plantillas.asistencia is 'Si lleva asistencia, cada fecha se crea como clase en Nivel Cero';
comment on column public.hor_plantillas.publico is 'Si lo ven los asesores; apagado = solo la oficina (p. ej. desayuno de líderes)';

create table if not exists public.hor_eventos (
  id            uuid primary key default gen_random_uuid(),
  plantilla_id  uuid references public.hor_plantillas(id),
  fecha         date not null,
  hora          time not null,
  titulo        text not null,
  descripcion   text,
  lugar         text,
  modo          text not null default 'presencial' check (modo in ('presencial','zoom','otro')),
  facilitador   text,
  enlace        text,
  tipo          text not null default 'capacitacion' check (tipo in ('capacitacion','evento','reunion','reclutamiento')),
  asistencia    boolean not null default true,
  publico       boolean not null default true,
  activo        boolean not null default true,
  editado       boolean not null default false,
  nota          text,
  n0_clase_id   uuid,
  creado_en     timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
comment on table public.hor_eventos is 'Eventos concretos por fecha (una fila por plantilla y fecha, o sueltos). activo=false: esa semana no hay. n0_clase_id: la clase de Nivel Cero enlazada';
create unique index if not exists hor_eventos_plantilla_fecha on public.hor_eventos (plantilla_id, fecha) where plantilla_id is not null;
create index if not exists hor_eventos_fecha on public.hor_eventos (fecha);

alter table public.n0_clases add column if not exists evento_id uuid;
comment on column public.n0_clases.evento_id is 'Evento del horario (hor_eventos) del que salió esta clase, si vino de ahí';

-- Sin acceso directo: todo por RPC
alter table public.doc_categorias enable row level security;
alter table public.doc_documentos enable row level security;
alter table public.doc_versiones enable row level security;
alter table public.ent_modulos enable row level security;
alter table public.ent_lecciones enable row level security;
alter table public.ent_recursos enable row level security;
alter table public.ent_progreso enable row level security;
alter table public.ent_subidas enable row level security;
alter table public.hor_plantillas enable row level security;
alter table public.hor_eventos enable row level security;

-- ---------------------------------------------------------------- quién pregunta
create or replace function public.ent_quien(p_token uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v jsonb;
begin
  if p_token is null then raise exception 'Sesion invalida'; end if;
  if public.es_admin(p_token) then return jsonb_build_object('rol', 'admin'); end if;
  v := public.asesor_sesion_valida(p_token);
  if coalesce((v->>'ok')::boolean, false) then
    return jsonb_build_object('rol', 'asesor', 'celular', v->>'celular', 'nombre', v->>'nombre');
  end if;
  raise exception 'Sesion invalida';
end $$;
revoke all on function public.ent_quien(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- subidas
create or replace function public.ent_subida_crear(p_token uuid)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v uuid;
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  insert into ent_subidas default values returning id into v;
  return v;
end $$;

-- La política de Storage la usa: la ruta debe ser <ticket>/<archivo> con un ticket de menos de 30 minutos
create or replace function public.ent_ruta_ok(p_name text)
returns boolean language plpgsql stable security definer set search_path to 'public' as $$
declare v uuid;
begin
  if split_part(coalesce(p_name, ''), '/', 2) = '' or split_part(p_name, '/', 3) <> '' then return false; end if;
  begin v := split_part(p_name, '/', 1)::uuid; exception when others then return false; end;
  return exists (select 1 from ent_subidas where id = v and creado_en > now() - interval '30 minutes');
end $$;

-- Al guardar un archivo se comprueba que su ruta venga de un ticket válido
create or replace function public.ent_ruta_valida(p_ruta text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v uuid;
begin
  if p_ruta is null then return; end if;
  if split_part(p_ruta, '/', 2) = '' or split_part(p_ruta, '/', 3) <> '' then raise exception 'La ruta del archivo no es valida'; end if;
  begin v := split_part(p_ruta, '/', 1)::uuid; exception when others then raise exception 'La ruta del archivo no es valida'; end;
  if not exists (select 1 from ent_subidas where id = v) then raise exception 'El archivo no se subio por esta pagina'; end if;
  update ent_subidas set usado = true where id = v;
end $$;
revoke all on function public.ent_ruta_valida(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- horario: materializar
-- Crea los eventos de las plantillas activas para cada fecha del rango que aún no existan.
create or replace function public.hor_materializar(p_desde date, p_hasta date)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare v_n integer := 0; d date; t record;
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde then return 0; end if;
  d := greatest(p_desde, hoy_lima());                       -- el pasado no se inventa
  while d <= p_hasta loop
    for t in select * from hor_plantillas where activo and not borrada and dia = extract(dow from d)::int loop
      if t.solo_inicio_periodo and periodo_inicio(periodo_indice(d)) <> d then continue; end if;
      if not exists (select 1 from hor_eventos where plantilla_id = t.id and fecha = d) then
        insert into hor_eventos (plantilla_id, fecha, hora, titulo, descripcion, lugar, modo, facilitador, enlace, tipo, asistencia, publico)
        values (t.id, d, t.hora, t.titulo, t.descripcion, t.lugar, t.modo, t.facilitador, t.enlace, t.tipo, t.asistencia, t.publico);
        v_n := v_n + 1;
      end if;
    end loop;
    d := d + 1;
  end loop;
  return v_n;
end $$;
revoke all on function public.hor_materializar(date, date) from public, anon, authenticated;

-- ---------------------------------------------------------------- horario → Nivel Cero
-- Cada evento con asistencia y activo tiene su clase en n0_clases. Si se apaga o deja de
-- llevar asistencia, la clase se borra solo si nadie fue marcado.
create or replace function public.hor_evento_n0()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_tipo text; v_id uuid; v_pres integer;
begin
  v_tipo := case when new.tipo = 'capacitacion' then 'capacitacion' else 'evento' end;
  if new.asistencia and new.activo then
    if new.n0_clase_id is not null then
      begin
        update n0_clases set fecha = new.fecha, hora = new.hora, tema = new.titulo, tipo = v_tipo, borrada = false, evento_id = new.id
         where id = new.n0_clase_id;
        if found then return new; end if;
      exception when unique_violation then
        -- a esa fecha y hora ya hay otra clase: la vieja se suelta (se borra si nadie fue) y se enlaza la otra
        select count(*) into v_pres from n0_asistencias where clase_id = new.n0_clase_id and presente;
        if v_pres = 0 then update n0_clases set borrada = true, evento_id = null where id = new.n0_clase_id; end if;
      end;
      new.n0_clase_id := null;
    end if;
    select id into v_id from n0_clases where fecha = new.fecha and hora = new.hora and not borrada;
    if v_id is not null then
      update n0_clases set evento_id = new.id, tema = coalesce(tema, new.titulo) where id = v_id;
    else
      insert into n0_clases (fecha, hora, tema, tipo, evento_id) values (new.fecha, new.hora, new.titulo, v_tipo, new.id)
      on conflict (fecha, hora) do update set borrada = false, tema = excluded.tema, tipo = excluded.tipo, evento_id = excluded.evento_id
      returning id into v_id;
    end if;
    new.n0_clase_id := v_id;
  elsif new.n0_clase_id is not null then
    select count(*) into v_pres from n0_asistencias where clase_id = new.n0_clase_id and presente;
    if v_pres = 0 then
      update n0_clases set borrada = true, evento_id = null where id = new.n0_clase_id;
      new.n0_clase_id := null;
    end if;
  end if;
  return new;
end $$;
create or replace trigger trg_hor_evento_n0 before insert or update of fecha, hora, titulo, tipo, asistencia, activo on public.hor_eventos
  for each row execute function public.hor_evento_n0();

-- El horario habitual de Nivel Cero (n0_config.horarios) sale de las plantillas con asistencia
create or replace function public.hor_sync_n0_config()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  update n0_config set horarios = coalesce((
    select jsonb_agg(jsonb_build_object('dia', dia, 'hora', to_char(hora, 'HH24:MI')) order by dia, hora)
      from hor_plantillas where activo and not borrada and asistencia and not solo_inicio_periodo), '[]'::jsonb)
   where id = 'vigente';
  return null;
end $$;
create or replace trigger trg_hor_sync_n0_config after insert or update on public.hor_plantillas
  for each statement execute function public.hor_sync_n0_config();

-- ---------------------------------------------------------------- horario: lectura
create or replace function public.hor_semana_json(p_rol text, p_lunes date)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_hoy date := hoy_lima();
begin
  if p_lunes + 6 >= v_hoy then perform hor_materializar(greatest(p_lunes, v_hoy), p_lunes + 6); end if;
  return jsonb_build_object(
    'lunes', p_lunes, 'domingo', p_lunes + 6, 'hoy', v_hoy,
    'inicio_periodo', (select coalesce(array_agg(d::date), array[]::date[]) from generate_series(p_lunes, p_lunes + 6, '1 day'::interval) g(d)
                        where periodo_inicio(periodo_indice(d::date)) = d::date),
    'eventos', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'plantilla_id', e.plantilla_id, 'fecha', e.fecha, 'hora', to_char(e.hora, 'HH24:MI'),
        'titulo', e.titulo, 'descripcion', e.descripcion, 'lugar', e.lugar, 'modo', e.modo, 'facilitador', e.facilitador,
        'enlace', e.enlace, 'tipo', e.tipo, 'asistencia', e.asistencia, 'publico', e.publico, 'activo', e.activo,
        'editado', e.editado, 'nota', e.nota, 'n0_clase_id', e.n0_clase_id,
        'asistentes', (select count(*) from n0_asistencias a where a.clase_id = e.n0_clase_id and a.presente))
        order by e.fecha, e.hora, e.titulo)
      from hor_eventos e
      where e.fecha between p_lunes and p_lunes + 6
        and (p_rol = 'admin' or (e.activo and e.publico))), '[]'::jsonb));
end $$;
revoke all on function public.hor_semana_json(text, date) from public, anon, authenticated;

create or replace function public.hor_semana(p_token uuid, p_fecha date default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare q jsonb; v_f date; v_lunes date;
begin
  q := ent_quien(p_token);
  v_f := coalesce(p_fecha, hoy_lima());
  v_lunes := v_f - ((extract(dow from v_f)::int + 6) % 7);
  return hor_semana_json(q->>'rol', v_lunes);
end $$;

-- ---------------------------------------------------------------- lectura principal
create or replace function public.ent_datos(p_token uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare q jsonb; v_rol text; v_cel text; v_hoy date := hoy_lima(); v_lunes date; v_out jsonb;
begin
  q := ent_quien(p_token);
  v_rol := q->>'rol'; v_cel := q->>'celular';
  v_lunes := v_hoy - ((extract(dow from v_hoy)::int + 6) % 7);
  v_out := jsonb_build_object(
    'hoy', v_hoy, 'rol', v_rol, 'nombre', q->>'nombre', 'celular', v_cel,
    'modulos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'titulo', m.titulo, 'descripcion', m.descripcion, 'orden', m.orden, 'activo', m.activo,
        'lecciones', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', l.id, 'titulo', l.titulo, 'descripcion', l.descripcion, 'orden', l.orden, 'activo', l.activo,
            'recursos', coalesce((
              select jsonb_agg(jsonb_build_object(
                'id', r.id, 'tipo', r.tipo, 'titulo', r.titulo, 'ruta', r.ruta, 'archivo', r.archivo, 'bytes', r.bytes,
                'content_type', r.content_type, 'paginas', r.paginas, 'portada', r.portada, 'url', r.url, 'orden', r.orden, 'activo', r.activo)
                order by r.orden, r.creado_en)
              from ent_recursos r where r.leccion_id = l.id and not r.borrado and (v_rol = 'admin' or r.activo)), '[]'::jsonb),
            'progreso', case when v_cel is null then null else
              (select case when p.completado_en is not null then 'completado' when p.visto_en is not null then 'visto' end
                 from ent_progreso p where p.leccion_id = l.id and p.celular = v_cel) end,
            'n_vistos', case when v_rol = 'admin' then (select count(*) from ent_progreso p where p.leccion_id = l.id and p.visto_en is not null) end,
            'n_completados', case when v_rol = 'admin' then (select count(*) from ent_progreso p where p.leccion_id = l.id and p.completado_en is not null) end)
            order by l.orden, l.creado_en)
          from ent_lecciones l where l.modulo_id = m.id and not l.borrada and (v_rol = 'admin' or l.activo)), '[]'::jsonb))
        order by m.orden, m.creado_en)
      from ent_modulos m where not m.borrado and (v_rol = 'admin' or (m.activo and 'asesor' = any(m.roles)))), '[]'::jsonb),
    'categorias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'nombre', c.nombre, 'descripcion', c.descripcion, 'orden', c.orden, 'roles', to_jsonb(c.roles), 'activo', c.activo,
        'documentos', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', d.id, 'clave', d.clave, 'titulo', d.titulo, 'descripcion', d.descripcion, 'audiencia', d.audiencia,
            'roles', to_jsonb(d.roles), 'orden', d.orden, 'activo', d.activo,
            'vigente', (select jsonb_build_object('id', v.id, 'version', v.version, 'ruta', v.ruta, 'archivo', v.archivo, 'bytes', v.bytes,
                          'content_type', v.content_type, 'paginas', v.paginas, 'portada', v.portada, 'nota', v.nota,
                          'vigente_desde', v.vigente_desde, 'vigente_hasta', v.vigente_hasta, 'creado_en', v.creado_en)
                          from doc_versiones v where v.documento_id = d.id and not v.borrada order by v.version desc limit 1),
            'versiones', case when v_rol = 'admin' then coalesce((
                select jsonb_agg(jsonb_build_object('id', v.id, 'version', v.version, 'ruta', v.ruta, 'archivo', v.archivo, 'bytes', v.bytes,
                          'content_type', v.content_type, 'paginas', v.paginas, 'portada', v.portada, 'nota', v.nota,
                          'vigente_desde', v.vigente_desde, 'vigente_hasta', v.vigente_hasta, 'creado_en', v.creado_en) order by v.version desc)
                  from doc_versiones v where v.documento_id = d.id and not v.borrada), '[]'::jsonb) end)
            order by d.orden, d.creado_en)
          from doc_documentos d where d.categoria_id = c.id and not d.borrado and (v_rol = 'admin' or (d.activo and 'asesor' = any(d.roles)))), '[]'::jsonb))
        order by c.orden, c.id)
      from doc_categorias c where v_rol = 'admin' or (c.activo and 'asesor' = any(c.roles))), '[]'::jsonb),
    'semana', hor_semana_json(v_rol, v_lunes),
    'plantillas', case when v_rol = 'admin' then coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'dia', t.dia, 'hora', to_char(t.hora, 'HH24:MI'), 'titulo', t.titulo,
        'descripcion', t.descripcion, 'lugar', t.lugar, 'modo', t.modo, 'facilitador', t.facilitador, 'enlace', t.enlace, 'tipo', t.tipo,
        'asistencia', t.asistencia, 'solo_inicio_periodo', t.solo_inicio_periodo, 'publico', t.publico, 'orden', t.orden, 'activo', t.activo)
        order by t.dia, t.hora, t.orden)
      from hor_plantillas t where not t.borrada), '[]'::jsonb) end,
    'progreso', case when v_rol = 'admin' then coalesce((
      select jsonb_agg(jsonb_build_object('celular', x.celular, 'nombre', x.nombre, 'vistas', x.vistas, 'completadas', x.completadas, 'ultimo', x.ultimo)
                       order by x.ultimo desc nulls last)
      from (select p.celular,
                   coalesce((select e.nombre from eq_personas e where e.activo and cel_norm(e.celular) = p.celular order by e.actualizado_en desc limit 1),
                            (select a.nombre from asesores a where a.celular = p.celular limit 1)) as nombre,
                   count(*) filter (where p.visto_en is not null) as vistas,
                   count(*) filter (where p.completado_en is not null) as completadas,
                   max(greatest(p.visto_en, p.completado_en)) as ultimo
              from ent_progreso p join ent_lecciones l on l.id = p.leccion_id and not l.borrada
             group by p.celular) x), '[]'::jsonb) end,
    'archivos_base', 'https://kiexpdaaoegbtesqmaff.supabase.co/storage/v1/object/public/entrenamientos/'
  );
  return v_out;
end $$;

-- Lo vigente de un documento por su clave (para otros sistemas y el chat)
create or replace function public.doc_vigente(p_token uuid, p_clave text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare q jsonb;
begin
  q := ent_quien(p_token);
  return (select jsonb_build_object('id', d.id, 'clave', d.clave, 'titulo', d.titulo, 'descripcion', d.descripcion, 'audiencia', d.audiencia,
            'version', v.version, 'archivo', v.archivo, 'content_type', v.content_type, 'paginas', v.paginas, 'nota', v.nota,
            'vigente_desde', v.vigente_desde, 'vigente_hasta', v.vigente_hasta,
            'url', 'https://kiexpdaaoegbtesqmaff.supabase.co/storage/v1/object/public/entrenamientos/' || v.ruta,
            'portada', case when v.portada is null then null else 'https://kiexpdaaoegbtesqmaff.supabase.co/storage/v1/object/public/entrenamientos/' || v.portada end)
            from doc_documentos d
            join lateral (select * from doc_versiones x where x.documento_id = d.id and not x.borrada order by x.version desc limit 1) v on true
           where d.clave = p_clave and not d.borrado and d.activo
             and ((q->>'rol') = 'admin' or 'asesor' = any(d.roles)));
end $$;

-- ---------------------------------------------------------------- progreso (asesor)
create or replace function public.ent_progreso_marcar(p_token uuid, p_leccion uuid, p_estado text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare q jsonb; v_cel text;
begin
  q := ent_quien(p_token);
  v_cel := q->>'celular';
  if v_cel is null then return jsonb_build_object('ok', true, 'progreso', null); end if;   -- la oficina no lleva progreso
  if not exists (select 1 from ent_lecciones where id = p_leccion and not borrada) then raise exception 'La leccion no existe'; end if;
  if coalesce(p_estado, 'visto') = 'completado' then
    insert into ent_progreso (leccion_id, celular, visto_en, completado_en) values (p_leccion, v_cel, now(), now())
    on conflict (leccion_id, celular) do update set visto_en = coalesce(ent_progreso.visto_en, now()), completado_en = now();
  elsif p_estado = 'nada' then
    update ent_progreso set completado_en = null where leccion_id = p_leccion and celular = v_cel;
  else
    insert into ent_progreso (leccion_id, celular, visto_en) values (p_leccion, v_cel, now())
    on conflict (leccion_id, celular) do update set visto_en = coalesce(ent_progreso.visto_en, now());
  end if;
  return jsonb_build_object('ok', true, 'progreso',
    (select case when completado_en is not null then 'completado' when visto_en is not null then 'visto' end
       from ent_progreso where leccion_id = p_leccion and celular = v_cel));
end $$;

-- ---------------------------------------------------------------- oficina: entrenamientos
create or replace function public.ent_modulo_guardar(p_token uuid, p_id uuid, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r ent_modulos;
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Datos no validos'; end if;
  if p_id is null then
    if coalesce(btrim(p_datos->>'titulo'), '') = '' then raise exception 'Falta el titulo del modulo'; end if;
    insert into ent_modulos (titulo, descripcion, orden, activo)
    values (left(btrim(p_datos->>'titulo'), 120), nullif(btrim(coalesce(p_datos->>'descripcion', '')), ''),
            coalesce((p_datos->>'orden')::int, (select coalesce(max(orden), 0) + 1 from ent_modulos where not borrado)),
            coalesce((p_datos->>'activo')::boolean, true))
    returning * into r;
  else
    update ent_modulos m set
      titulo = case when p_datos ? 'titulo' then left(btrim(p_datos->>'titulo'), 120) else m.titulo end,
      descripcion = case when p_datos ? 'descripcion' then nullif(btrim(coalesce(p_datos->>'descripcion', '')), '') else m.descripcion end,
      orden = case when p_datos ? 'orden' then (p_datos->>'orden')::int else m.orden end,
      activo = case when p_datos ? 'activo' then (p_datos->>'activo')::boolean else m.activo end,
      actualizado_en = now()
    where m.id = p_id and not m.borrado returning * into r;
    if not found then raise exception 'El modulo no existe'; end if;
  end if;
  return jsonb_build_object('id', r.id, 'titulo', r.titulo, 'descripcion', r.descripcion, 'orden', r.orden, 'activo', r.activo);
end $$;

create or replace function public.ent_leccion_guardar(p_token uuid, p_id uuid, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r ent_lecciones; v_mod uuid;
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Datos no validos'; end if;
  if p_id is null then
    v_mod := (p_datos->>'modulo_id')::uuid;
    if v_mod is null or not exists (select 1 from ent_modulos where id = v_mod and not borrado) then raise exception 'El modulo no existe'; end if;
    if coalesce(btrim(p_datos->>'titulo'), '') = '' then raise exception 'Falta el titulo de la leccion'; end if;
    insert into ent_lecciones (modulo_id, titulo, descripcion, orden, activo)
    values (v_mod, left(btrim(p_datos->>'titulo'), 160), nullif(btrim(coalesce(p_datos->>'descripcion', '')), ''),
            coalesce((p_datos->>'orden')::int, (select coalesce(max(orden), 0) + 1 from ent_lecciones where modulo_id = v_mod and not borrada)),
            coalesce((p_datos->>'activo')::boolean, true))
    returning * into r;
  else
    update ent_lecciones l set
      modulo_id = case when p_datos ? 'modulo_id' then (p_datos->>'modulo_id')::uuid else l.modulo_id end,
      titulo = case when p_datos ? 'titulo' then left(btrim(p_datos->>'titulo'), 160) else l.titulo end,
      descripcion = case when p_datos ? 'descripcion' then nullif(btrim(coalesce(p_datos->>'descripcion', '')), '') else l.descripcion end,
      orden = case when p_datos ? 'orden' then (p_datos->>'orden')::int else l.orden end,
      activo = case when p_datos ? 'activo' then (p_datos->>'activo')::boolean else l.activo end,
      actualizado_en = now()
    where l.id = p_id and not l.borrada returning * into r;
    if not found then raise exception 'La leccion no existe'; end if;
  end if;
  return jsonb_build_object('id', r.id, 'modulo_id', r.modulo_id, 'titulo', r.titulo, 'descripcion', r.descripcion, 'orden', r.orden, 'activo', r.activo);
end $$;

create or replace function public.ent_recurso_guardar(p_token uuid, p_id uuid, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r ent_recursos; v_lec uuid;
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Datos no validos'; end if;
  if p_id is null then
    v_lec := (p_datos->>'leccion_id')::uuid;
    if v_lec is null or not exists (select 1 from ent_lecciones where id = v_lec and not borrada) then raise exception 'La leccion no existe'; end if;
    if coalesce(p_datos->>'tipo', '') not in ('guia', 'video', 'libro', 'enlace') then raise exception 'Tipo de material no valido'; end if;
    if nullif(p_datos->>'ruta', '') is null and nullif(p_datos->>'url', '') is null then raise exception 'Falta el archivo o el enlace'; end if;
    perform ent_ruta_valida(nullif(p_datos->>'ruta', ''));
    insert into ent_recursos (leccion_id, tipo, titulo, ruta, archivo, bytes, content_type, paginas, portada, url, orden, activo)
    values (v_lec, p_datos->>'tipo', nullif(left(btrim(coalesce(p_datos->>'titulo', '')), 160), ''),
            nullif(p_datos->>'ruta', ''), nullif(p_datos->>'archivo', ''), (p_datos->>'bytes')::bigint, nullif(p_datos->>'content_type', ''),
            (p_datos->>'paginas')::int, nullif(p_datos->>'portada', ''), nullif(btrim(coalesce(p_datos->>'url', '')), ''),
            coalesce((p_datos->>'orden')::int, (select coalesce(max(orden), 0) + 1 from ent_recursos where leccion_id = v_lec and not borrado)),
            coalesce((p_datos->>'activo')::boolean, true))
    returning * into r;
  else
    if p_datos ? 'ruta' then perform ent_ruta_valida(nullif(p_datos->>'ruta', '')); end if;
    update ent_recursos x set
      tipo = case when p_datos ? 'tipo' then p_datos->>'tipo' else x.tipo end,
      titulo = case when p_datos ? 'titulo' then nullif(left(btrim(coalesce(p_datos->>'titulo', '')), 160), '') else x.titulo end,
      ruta = case when p_datos ? 'ruta' then nullif(p_datos->>'ruta', '') else x.ruta end,
      archivo = case when p_datos ? 'archivo' then nullif(p_datos->>'archivo', '') else x.archivo end,
      bytes = case when p_datos ? 'bytes' then (p_datos->>'bytes')::bigint else x.bytes end,
      content_type = case when p_datos ? 'content_type' then nullif(p_datos->>'content_type', '') else x.content_type end,
      paginas = case when p_datos ? 'paginas' then (p_datos->>'paginas')::int else x.paginas end,
      portada = case when p_datos ? 'portada' then nullif(p_datos->>'portada', '') else x.portada end,
      url = case when p_datos ? 'url' then nullif(btrim(coalesce(p_datos->>'url', '')), '') else x.url end,
      orden = case when p_datos ? 'orden' then (p_datos->>'orden')::int else x.orden end,
      activo = case when p_datos ? 'activo' then (p_datos->>'activo')::boolean else x.activo end
    where x.id = p_id and not x.borrado returning * into r;
    if not found then raise exception 'El material no existe'; end if;
  end if;
  return jsonb_build_object('id', r.id, 'leccion_id', r.leccion_id, 'tipo', r.tipo, 'titulo', r.titulo, 'ruta', r.ruta, 'archivo', r.archivo,
                            'bytes', r.bytes, 'content_type', r.content_type, 'paginas', r.paginas, 'portada', r.portada, 'url', r.url,
                            'orden', r.orden, 'activo', r.activo);
end $$;

-- ---------------------------------------------------------------- oficina: documentos
create or replace function public.doc_categoria_guardar(p_token uuid, p_id text, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r doc_categorias; v_id text;
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Datos no validos'; end if;
  if p_id is null then
    if coalesce(btrim(p_datos->>'nombre'), '') = '' then raise exception 'Falta el nombre de la categoria'; end if;
    v_id := coalesce(nullif(p_datos->>'id', ''),
                     regexp_replace(lower(unaccent_safe(btrim(p_datos->>'nombre'))), '[^a-z0-9]+', '-', 'g'));
    v_id := btrim(v_id, '-');
    if exists (select 1 from doc_categorias where id = v_id) then v_id := v_id || '-' || to_char(now(), 'MMDDHH24MI'); end if;
    insert into doc_categorias (id, nombre, descripcion, orden, activo)
    values (v_id, left(btrim(p_datos->>'nombre'), 80), nullif(btrim(coalesce(p_datos->>'descripcion', '')), ''),
            coalesce((p_datos->>'orden')::int, (select coalesce(max(orden), 0) + 1 from doc_categorias)), coalesce((p_datos->>'activo')::boolean, true))
    returning * into r;
  else
    update doc_categorias c set
      nombre = case when p_datos ? 'nombre' then left(btrim(p_datos->>'nombre'), 80) else c.nombre end,
      descripcion = case when p_datos ? 'descripcion' then nullif(btrim(coalesce(p_datos->>'descripcion', '')), '') else c.descripcion end,
      orden = case when p_datos ? 'orden' then (p_datos->>'orden')::int else c.orden end,
      activo = case when p_datos ? 'activo' then (p_datos->>'activo')::boolean else c.activo end
    where c.id = p_id returning * into r;
    if not found then raise exception 'La categoria no existe'; end if;
  end if;
  return jsonb_build_object('id', r.id, 'nombre', r.nombre, 'descripcion', r.descripcion, 'orden', r.orden, 'activo', r.activo);
end $$;

create or replace function public.doc_documento_guardar(p_token uuid, p_id uuid, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r doc_documentos; v_cat text; v_roles text[];
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Datos no validos'; end if;
  if p_datos ? 'roles' and jsonb_typeof(p_datos->'roles') = 'array' then
    select array_agg(x) into v_roles from jsonb_array_elements_text(p_datos->'roles') x where x in ('admin', 'asistente', 'gestor', 'asesor');
  end if;
  if p_id is null then
    v_cat := p_datos->>'categoria_id';
    if v_cat is null or not exists (select 1 from doc_categorias where id = v_cat) then raise exception 'La categoria no existe'; end if;
    if coalesce(btrim(p_datos->>'titulo'), '') = '' then raise exception 'Falta el titulo del documento'; end if;
    insert into doc_documentos (categoria_id, clave, titulo, descripcion, audiencia, roles, orden, activo)
    values (v_cat, nullif(btrim(coalesce(p_datos->>'clave', '')), ''), left(btrim(p_datos->>'titulo'), 160),
            nullif(btrim(coalesce(p_datos->>'descripcion', '')), ''), coalesce(nullif(p_datos->>'audiencia', ''), 'asesor'),
            coalesce(v_roles, array['admin', 'asistente', 'asesor']),
            coalesce((p_datos->>'orden')::int, (select coalesce(max(orden), 0) + 1 from doc_documentos where categoria_id = v_cat and not borrado)),
            coalesce((p_datos->>'activo')::boolean, true))
    returning * into r;
  else
    update doc_documentos d set
      categoria_id = case when p_datos ? 'categoria_id' then p_datos->>'categoria_id' else d.categoria_id end,
      clave = case when p_datos ? 'clave' then nullif(btrim(coalesce(p_datos->>'clave', '')), '') else d.clave end,
      titulo = case when p_datos ? 'titulo' then left(btrim(p_datos->>'titulo'), 160) else d.titulo end,
      descripcion = case when p_datos ? 'descripcion' then nullif(btrim(coalesce(p_datos->>'descripcion', '')), '') else d.descripcion end,
      audiencia = case when p_datos ? 'audiencia' then p_datos->>'audiencia' else d.audiencia end,
      roles = coalesce(v_roles, d.roles),
      orden = case when p_datos ? 'orden' then (p_datos->>'orden')::int else d.orden end,
      activo = case when p_datos ? 'activo' then (p_datos->>'activo')::boolean else d.activo end,
      actualizado_en = now()
    where d.id = p_id and not d.borrado returning * into r;
    if not found then raise exception 'El documento no existe'; end if;
  end if;
  return jsonb_build_object('id', r.id, 'categoria_id', r.categoria_id, 'clave', r.clave, 'titulo', r.titulo, 'descripcion', r.descripcion,
                            'audiencia', r.audiencia, 'roles', to_jsonb(r.roles), 'orden', r.orden, 'activo', r.activo);
end $$;

create or replace function public.doc_version_guardar(p_token uuid, p_documento uuid, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r doc_versiones; v_id uuid;
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Datos no validos'; end if;
  v_id := (p_datos->>'id')::uuid;
  if v_id is not null then
    -- solo se corrigen la nota y la vigencia de una versión ya subida
    update doc_versiones v set
      nota = case when p_datos ? 'nota' then nullif(btrim(coalesce(p_datos->>'nota', '')), '') else v.nota end,
      vigente_desde = case when p_datos ? 'vigente_desde' then nullif(p_datos->>'vigente_desde', '')::date else v.vigente_desde end,
      vigente_hasta = case when p_datos ? 'vigente_hasta' then nullif(p_datos->>'vigente_hasta', '')::date else v.vigente_hasta end
    where v.id = v_id and v.documento_id = p_documento and not v.borrada returning * into r;
    if not found then raise exception 'La version no existe'; end if;
  else
    if not exists (select 1 from doc_documentos where id = p_documento and not borrado) then raise exception 'El documento no existe'; end if;
    if nullif(p_datos->>'ruta', '') is null then raise exception 'Falta el archivo'; end if;
    perform ent_ruta_valida(p_datos->>'ruta');
    insert into doc_versiones (documento_id, version, ruta, archivo, bytes, content_type, paginas, portada, nota, vigente_desde, vigente_hasta)
    values (p_documento, (select coalesce(max(version), 0) + 1 from doc_versiones where documento_id = p_documento),
            p_datos->>'ruta', coalesce(nullif(p_datos->>'archivo', ''), 'archivo'), (p_datos->>'bytes')::bigint, nullif(p_datos->>'content_type', ''),
            (p_datos->>'paginas')::int, nullif(p_datos->>'portada', ''), nullif(btrim(coalesce(p_datos->>'nota', '')), ''),
            nullif(p_datos->>'vigente_desde', '')::date, nullif(p_datos->>'vigente_hasta', '')::date)
    returning * into r;
    update doc_documentos set actualizado_en = now() where id = p_documento;
  end if;
  return jsonb_build_object('id', r.id, 'documento_id', r.documento_id, 'version', r.version, 'ruta', r.ruta, 'archivo', r.archivo, 'bytes', r.bytes,
                            'content_type', r.content_type, 'paginas', r.paginas, 'portada', r.portada, 'nota', r.nota,
                            'vigente_desde', r.vigente_desde, 'vigente_hasta', r.vigente_hasta, 'creado_en', r.creado_en);
end $$;

-- ---------------------------------------------------------------- oficina: horario
create or replace function public.hor_plantilla_guardar(p_token uuid, p_id uuid, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r hor_plantillas; v_hora time; v_hoy date := hoy_lima();
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Datos no validos'; end if;
  if p_datos ? 'hora' then
    begin v_hora := date_trunc('minute', nullif(btrim(p_datos->>'hora'), '')::time); exception when others then raise exception 'La hora no es valida'; end;
  end if;
  if p_id is null then
    if coalesce(btrim(p_datos->>'titulo'), '') = '' then raise exception 'Falta el nombre del evento'; end if;
    if v_hora is null then raise exception 'Falta la hora'; end if;
    if (p_datos->>'dia')::int is null then raise exception 'Falta el dia de la semana'; end if;
    insert into hor_plantillas (dia, hora, titulo, descripcion, lugar, modo, facilitador, enlace, tipo, asistencia, solo_inicio_periodo, publico, orden, activo)
    values ((p_datos->>'dia')::int, v_hora, left(btrim(p_datos->>'titulo'), 120), nullif(btrim(coalesce(p_datos->>'descripcion', '')), ''),
            nullif(btrim(coalesce(p_datos->>'lugar', '')), ''), coalesce(nullif(p_datos->>'modo', ''), 'presencial'),
            nullif(btrim(coalesce(p_datos->>'facilitador', '')), ''), nullif(btrim(coalesce(p_datos->>'enlace', '')), ''),
            coalesce(nullif(p_datos->>'tipo', ''), 'capacitacion'), coalesce((p_datos->>'asistencia')::boolean, true),
            coalesce((p_datos->>'solo_inicio_periodo')::boolean, false), coalesce((p_datos->>'publico')::boolean, true),
            coalesce((p_datos->>'orden')::int, 0), coalesce((p_datos->>'activo')::boolean, true))
    returning * into r;
  else
    update hor_plantillas t set
      dia = case when p_datos ? 'dia' then (p_datos->>'dia')::int else t.dia end,
      hora = coalesce(v_hora, t.hora),
      titulo = case when p_datos ? 'titulo' then left(btrim(p_datos->>'titulo'), 120) else t.titulo end,
      descripcion = case when p_datos ? 'descripcion' then nullif(btrim(coalesce(p_datos->>'descripcion', '')), '') else t.descripcion end,
      lugar = case when p_datos ? 'lugar' then nullif(btrim(coalesce(p_datos->>'lugar', '')), '') else t.lugar end,
      modo = case when p_datos ? 'modo' then p_datos->>'modo' else t.modo end,
      facilitador = case when p_datos ? 'facilitador' then nullif(btrim(coalesce(p_datos->>'facilitador', '')), '') else t.facilitador end,
      enlace = case when p_datos ? 'enlace' then nullif(btrim(coalesce(p_datos->>'enlace', '')), '') else t.enlace end,
      tipo = case when p_datos ? 'tipo' then p_datos->>'tipo' else t.tipo end,
      asistencia = case when p_datos ? 'asistencia' then (p_datos->>'asistencia')::boolean else t.asistencia end,
      solo_inicio_periodo = case when p_datos ? 'solo_inicio_periodo' then (p_datos->>'solo_inicio_periodo')::boolean else t.solo_inicio_periodo end,
      publico = case when p_datos ? 'publico' then (p_datos->>'publico')::boolean else t.publico end,
      orden = case when p_datos ? 'orden' then (p_datos->>'orden')::int else t.orden end,
      activo = case when p_datos ? 'activo' then (p_datos->>'activo')::boolean else t.activo end,
      actualizado_en = now()
    where t.id = p_id and not t.borrada returning * into r;
    if not found then raise exception 'El evento no existe'; end if;
    -- Lo que viene (sin editar a mano) sigue a la plantilla
    if r.activo then
      update hor_eventos e set hora = r.hora, titulo = r.titulo, descripcion = r.descripcion, lugar = r.lugar, modo = r.modo,
             facilitador = r.facilitador, enlace = r.enlace, tipo = r.tipo, asistencia = r.asistencia, publico = r.publico,
             activo = true, actualizado_en = now()
       where e.plantilla_id = r.id and e.fecha >= v_hoy and not e.editado;
      -- si cambió de día, las fechas futuras que ya no caen en ese día se apagan y se vuelven a crear
      update hor_eventos e set activo = false, actualizado_en = now()
       where e.plantilla_id = r.id and e.fecha >= v_hoy and not e.editado and extract(dow from e.fecha)::int <> r.dia;
      perform hor_materializar(v_hoy, v_hoy + 21);
    else
      update hor_eventos e set activo = false, actualizado_en = now() where e.plantilla_id = r.id and e.fecha >= v_hoy and not e.editado;
    end if;
  end if;
  if p_id is null then perform hor_materializar(v_hoy, v_hoy + 21); end if;
  return jsonb_build_object('id', r.id, 'dia', r.dia, 'hora', to_char(r.hora, 'HH24:MI'), 'titulo', r.titulo, 'descripcion', r.descripcion,
                            'lugar', r.lugar, 'modo', r.modo, 'facilitador', r.facilitador, 'enlace', r.enlace, 'tipo', r.tipo,
                            'asistencia', r.asistencia, 'solo_inicio_periodo', r.solo_inicio_periodo, 'publico', r.publico,
                            'orden', r.orden, 'activo', r.activo);
end $$;

create or replace function public.hor_evento_guardar(p_token uuid, p_id uuid, p_datos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r hor_eventos; v_hora time; v_solo_activo boolean;
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  if p_datos is null or jsonb_typeof(p_datos) <> 'object' then raise exception 'Datos no validos'; end if;
  if p_datos ? 'hora' then
    begin v_hora := date_trunc('minute', nullif(btrim(p_datos->>'hora'), '')::time); exception when others then raise exception 'La hora no es valida'; end;
  end if;
  if p_id is null then
    if coalesce(btrim(p_datos->>'titulo'), '') = '' then raise exception 'Falta el nombre del evento'; end if;
    if (p_datos->>'fecha')::date is null then raise exception 'Falta la fecha'; end if;
    if v_hora is null then raise exception 'Falta la hora'; end if;
    insert into hor_eventos (fecha, hora, titulo, descripcion, lugar, modo, facilitador, enlace, tipo, asistencia, publico, activo, editado, nota)
    values ((p_datos->>'fecha')::date, v_hora, left(btrim(p_datos->>'titulo'), 120), nullif(btrim(coalesce(p_datos->>'descripcion', '')), ''),
            nullif(btrim(coalesce(p_datos->>'lugar', '')), ''), coalesce(nullif(p_datos->>'modo', ''), 'presencial'),
            nullif(btrim(coalesce(p_datos->>'facilitador', '')), ''), nullif(btrim(coalesce(p_datos->>'enlace', '')), ''),
            coalesce(nullif(p_datos->>'tipo', ''), 'evento'), coalesce((p_datos->>'asistencia')::boolean, true),
            coalesce((p_datos->>'publico')::boolean, true), coalesce((p_datos->>'activo')::boolean, true), true,
            nullif(btrim(coalesce(p_datos->>'nota', '')), ''))
    returning * into r;
  else
    -- apagar/prender esa semana no cuenta como edición a mano; cambiar datos sí
    v_solo_activo := (select bool_and(k = 'activo') from jsonb_object_keys(p_datos) k);
    update hor_eventos e set
      fecha = case when p_datos ? 'fecha' then (p_datos->>'fecha')::date else e.fecha end,
      hora = coalesce(v_hora, e.hora),
      titulo = case when p_datos ? 'titulo' then left(btrim(p_datos->>'titulo'), 120) else e.titulo end,
      descripcion = case when p_datos ? 'descripcion' then nullif(btrim(coalesce(p_datos->>'descripcion', '')), '') else e.descripcion end,
      lugar = case when p_datos ? 'lugar' then nullif(btrim(coalesce(p_datos->>'lugar', '')), '') else e.lugar end,
      modo = case when p_datos ? 'modo' then p_datos->>'modo' else e.modo end,
      facilitador = case when p_datos ? 'facilitador' then nullif(btrim(coalesce(p_datos->>'facilitador', '')), '') else e.facilitador end,
      enlace = case when p_datos ? 'enlace' then nullif(btrim(coalesce(p_datos->>'enlace', '')), '') else e.enlace end,
      tipo = case when p_datos ? 'tipo' then p_datos->>'tipo' else e.tipo end,
      asistencia = case when p_datos ? 'asistencia' then (p_datos->>'asistencia')::boolean else e.asistencia end,
      publico = case when p_datos ? 'publico' then (p_datos->>'publico')::boolean else e.publico end,
      activo = case when p_datos ? 'activo' then (p_datos->>'activo')::boolean else e.activo end,
      nota = case when p_datos ? 'nota' then nullif(btrim(coalesce(p_datos->>'nota', '')), '') else e.nota end,
      editado = e.editado or not coalesce(v_solo_activo, false),
      actualizado_en = now()
    where e.id = p_id returning * into r;
    if not found then raise exception 'El evento no existe'; end if;
  end if;
  return jsonb_build_object('id', r.id, 'plantilla_id', r.plantilla_id, 'fecha', r.fecha, 'hora', to_char(r.hora, 'HH24:MI'), 'titulo', r.titulo,
                            'descripcion', r.descripcion, 'lugar', r.lugar, 'modo', r.modo, 'facilitador', r.facilitador, 'enlace', r.enlace,
                            'tipo', r.tipo, 'asistencia', r.asistencia, 'publico', r.publico, 'activo', r.activo, 'editado', r.editado,
                            'nota', r.nota, 'n0_clase_id', r.n0_clase_id,
                            'asistentes', (select count(*) from n0_asistencias a where a.clase_id = r.n0_clase_id and a.presente));
end $$;

-- ---------------------------------------------------------------- oficina: borrar y ordenar
create or replace function public.ent_borrar(p_token uuid, p_que text, p_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_n integer := 0;
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  if p_que = 'modulo' then
    update ent_modulos set borrado = true, actualizado_en = now() where id = p_id and not borrado; get diagnostics v_n = row_count;
    update ent_lecciones set borrada = true where modulo_id = p_id;
  elsif p_que = 'leccion' then
    update ent_lecciones set borrada = true, actualizado_en = now() where id = p_id and not borrada; get diagnostics v_n = row_count;
  elsif p_que = 'recurso' then
    update ent_recursos set borrado = true where id = p_id and not borrado; get diagnostics v_n = row_count;
  elsif p_que = 'documento' then
    update doc_documentos set borrado = true, actualizado_en = now() where id = p_id and not borrado; get diagnostics v_n = row_count;
  elsif p_que = 'version' then
    update doc_versiones set borrada = true where id = p_id and not borrada; get diagnostics v_n = row_count;
  elsif p_que = 'plantilla' then
    update hor_plantillas set borrada = true, activo = false, actualizado_en = now() where id = p_id and not borrada; get diagnostics v_n = row_count;
    update hor_eventos set activo = false, actualizado_en = now() where plantilla_id = p_id and fecha >= hoy_lima() and not editado;
  elsif p_que = 'evento' then
    -- un evento suelto se apaga (sus clases sin asistentes se borran); uno de plantilla también se apaga, no se borra
    update hor_eventos set activo = false, actualizado_en = now() where id = p_id and activo; get diagnostics v_n = row_count;
  else
    raise exception 'No se que borrar';
  end if;
  if v_n = 0 then raise exception 'Ya no existe'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.ent_ordenar(p_token uuid, p_que text, p_ids uuid[])
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i integer;
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  if p_ids is null then return jsonb_build_object('ok', true); end if;
  for i in 1..coalesce(array_length(p_ids, 1), 0) loop
    if p_que = 'modulo' then update ent_modulos set orden = i where id = p_ids[i];
    elsif p_que = 'leccion' then update ent_lecciones set orden = i where id = p_ids[i];
    elsif p_que = 'recurso' then update ent_recursos set orden = i where id = p_ids[i];
    elsif p_que = 'documento' then update doc_documentos set orden = i where id = p_ids[i];
    else raise exception 'No se que ordenar';
    end if;
  end loop;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.doc_categoria_ordenar(p_token uuid, p_ids text[])
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i integer;
begin
  if not public.es_admin(p_token) then raise exception 'Sesion invalida'; end if;
  for i in 1..coalesce(array_length(p_ids, 1), 0) loop
    update doc_categorias set orden = i where id = p_ids[i];
  end loop;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- permisos
grant execute on function public.ent_datos(uuid), public.hor_semana(uuid, date), public.doc_vigente(uuid, text),
  public.ent_progreso_marcar(uuid, uuid, text), public.ent_subida_crear(uuid),
  public.ent_modulo_guardar(uuid, uuid, jsonb), public.ent_leccion_guardar(uuid, uuid, jsonb), public.ent_recurso_guardar(uuid, uuid, jsonb),
  public.doc_categoria_guardar(uuid, text, jsonb), public.doc_documento_guardar(uuid, uuid, jsonb), public.doc_version_guardar(uuid, uuid, jsonb),
  public.hor_plantilla_guardar(uuid, uuid, jsonb), public.hor_evento_guardar(uuid, uuid, jsonb),
  public.ent_borrar(uuid, text, uuid), public.ent_ordenar(uuid, text, uuid[]), public.doc_categoria_ordenar(uuid, text[])
  to anon, authenticated;
grant execute on function public.ent_ruta_ok(text) to anon, authenticated;

-- ---------------------------------------------------------------- archivos (Storage)
insert into storage.buckets (id, name, public, file_size_limit)
values ('entrenamientos', 'entrenamientos', true, 52428800)
on conflict (id) do update set public = true, file_size_limit = 52428800;

create policy entrenamientos_sube on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'entrenamientos' and public.ent_ruta_ok(name));
create policy entrenamientos_reemplaza on storage.objects for update to anon, authenticated
  using (bucket_id = 'entrenamientos' and public.ent_ruta_ok(name)) with check (bucket_id = 'entrenamientos' and public.ent_ruta_ok(name));
create policy entrenamientos_lee on storage.objects for select to anon, authenticated using (bucket_id = 'entrenamientos');

-- ---------------------------------------------------------------- materialización diaria (00:15 de Lima)
select cron.schedule('hor_materializar_diario', '15 5 * * *', $$select public.hor_materializar(public.hoy_lima(), public.hoy_lima() + 21)$$);
