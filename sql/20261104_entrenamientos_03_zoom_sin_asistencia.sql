-- =====================================================================
-- Entrenamientos · ajustes del horario (4 nov, noche):
--   1. Los jueves que NO inicia período (no hay lanzamiento en la oficina) hay
--      capacitación por Zoom a las 9:00 a. m. con Juan Carlos Ezaine.
--      → nueva marca en el horario habitual: `excepto_inicio_periodo`.
--   2. La asistencia del Nivel Cero se toma solo en lo presencial de la oficina:
--      lo que es por Zoom no lleva asistencia (regla fija, no una casilla).
-- =====================================================================

alter table public.hor_plantillas add column if not exists excepto_inicio_periodo boolean not null default false;
comment on column public.hor_plantillas.excepto_inicio_periodo is 'Solo los días que NO inician un período (p. ej. el Zoom del jueves cuando no hay lanzamiento)';

-- ---------------------------------------------------------------- materializar
create or replace function public.hor_materializar(p_desde date, p_hasta date)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare v_n integer := 0; d date; t record; v_inicio boolean;
begin
  if p_desde is null or p_hasta is null or p_hasta < p_desde then return 0; end if;
  d := greatest(p_desde, hoy_lima());                       -- el pasado no se inventa
  while d <= p_hasta loop
    v_inicio := periodo_inicio(periodo_indice(d)) = d;
    for t in select * from hor_plantillas where activo and not borrada and dia = extract(dow from d)::int loop
      if t.solo_inicio_periodo and not v_inicio then continue; end if;
      if t.excepto_inicio_periodo and v_inicio then continue; end if;
      if not exists (select 1 from hor_eventos where plantilla_id = t.id and fecha = d) then
        insert into hor_eventos (plantilla_id, fecha, hora, titulo, descripcion, lugar, modo, facilitador, enlace, tipo, asistencia, publico)
        values (t.id, d, t.hora, t.titulo, t.descripcion, t.lugar, t.modo, t.facilitador, t.enlace, t.tipo, t.asistencia and t.modo <> 'zoom', t.publico);
        v_n := v_n + 1;
      end if;
    end loop;
    d := d + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------- horario habitual
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
    insert into hor_plantillas (dia, hora, titulo, descripcion, lugar, modo, facilitador, enlace, tipo, asistencia, solo_inicio_periodo, excepto_inicio_periodo, publico, orden, activo)
    values ((p_datos->>'dia')::int, v_hora, left(btrim(p_datos->>'titulo'), 120), nullif(btrim(coalesce(p_datos->>'descripcion', '')), ''),
            nullif(btrim(coalesce(p_datos->>'lugar', '')), ''), coalesce(nullif(p_datos->>'modo', ''), 'presencial'),
            nullif(btrim(coalesce(p_datos->>'facilitador', '')), ''), nullif(btrim(coalesce(p_datos->>'enlace', '')), ''),
            coalesce(nullif(p_datos->>'tipo', ''), 'capacitacion'), coalesce((p_datos->>'asistencia')::boolean, true),
            coalesce((p_datos->>'solo_inicio_periodo')::boolean, false), coalesce((p_datos->>'excepto_inicio_periodo')::boolean, false),
            coalesce((p_datos->>'publico')::boolean, true), coalesce((p_datos->>'orden')::int, 0), coalesce((p_datos->>'activo')::boolean, true))
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
      excepto_inicio_periodo = case when p_datos ? 'excepto_inicio_periodo' then (p_datos->>'excepto_inicio_periodo')::boolean else t.excepto_inicio_periodo end,
      publico = case when p_datos ? 'publico' then (p_datos->>'publico')::boolean else t.publico end,
      orden = case when p_datos ? 'orden' then (p_datos->>'orden')::int else t.orden end,
      activo = case when p_datos ? 'activo' then (p_datos->>'activo')::boolean else t.activo end,
      actualizado_en = now()
    where t.id = p_id and not t.borrada returning * into r;
    if not found then raise exception 'El evento no existe'; end if;
  end if;
  -- Regla: por Zoom no se toma asistencia (la asistencia del Nivel Cero es solo presencial)
  if r.modo = 'zoom' and r.asistencia then
    update hor_plantillas set asistencia = false where id = r.id returning * into r;
  end if;
  if r.solo_inicio_periodo and r.excepto_inicio_periodo then raise exception 'No puede ser solo inicio de periodo y a la vez excepto inicio de periodo'; end if;
  if p_id is not null then
    -- Lo que viene (sin editar a mano) sigue a la plantilla
    if r.activo then
      update hor_eventos e set hora = r.hora, titulo = r.titulo, descripcion = r.descripcion, lugar = r.lugar, modo = r.modo,
             facilitador = r.facilitador, enlace = r.enlace, tipo = r.tipo, asistencia = r.asistencia, publico = r.publico,
             activo = true, actualizado_en = now()
       where e.plantilla_id = r.id and e.fecha >= v_hoy and not e.editado;
      -- fechas futuras que ya no le tocan (cambió de día, o la regla de inicio de período) se apagan
      update hor_eventos e set activo = false, actualizado_en = now()
       where e.plantilla_id = r.id and e.fecha >= v_hoy and not e.editado
         and (extract(dow from e.fecha)::int <> r.dia
              or (r.solo_inicio_periodo and periodo_inicio(periodo_indice(e.fecha)) <> e.fecha)
              or (r.excepto_inicio_periodo and periodo_inicio(periodo_indice(e.fecha)) = e.fecha));
    else
      update hor_eventos e set activo = false, actualizado_en = now() where e.plantilla_id = r.id and e.fecha >= v_hoy and not e.editado;
    end if;
  end if;
  perform hor_materializar(v_hoy, v_hoy + 21);
  return jsonb_build_object('id', r.id, 'dia', r.dia, 'hora', to_char(r.hora, 'HH24:MI'), 'titulo', r.titulo, 'descripcion', r.descripcion,
                            'lugar', r.lugar, 'modo', r.modo, 'facilitador', r.facilitador, 'enlace', r.enlace, 'tipo', r.tipo,
                            'asistencia', r.asistencia, 'solo_inicio_periodo', r.solo_inicio_periodo, 'excepto_inicio_periodo', r.excepto_inicio_periodo,
                            'publico', r.publico, 'orden', r.orden, 'activo', r.activo);
end $$;

-- ---------------------------------------------------------------- evento de una fecha
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
            coalesce(nullif(p_datos->>'tipo', ''), 'evento'),
            coalesce((p_datos->>'asistencia')::boolean, true) and coalesce(nullif(p_datos->>'modo', ''), 'presencial') <> 'zoom',
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
      asistencia = (case when p_datos ? 'asistencia' then (p_datos->>'asistencia')::boolean else e.asistencia end)
                   and (case when p_datos ? 'modo' then p_datos->>'modo' else e.modo end) <> 'zoom',
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

-- ---------------------------------------------------------------- lectura: las plantillas traen la marca nueva
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
        'asistencia', t.asistencia, 'solo_inicio_periodo', t.solo_inicio_periodo, 'excepto_inicio_periodo', t.excepto_inicio_periodo,
        'publico', t.publico, 'orden', t.orden, 'activo', t.activo)
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

-- ---------------------------------------------------------------- datos
-- Por Zoom no hay asistencia: plantillas y eventos futuros (el disparador borra sus clases si nadie fue marcado)
update public.hor_plantillas set asistencia = false, actualizado_en = now() where modo = 'zoom' and asistencia;
update public.hor_eventos set asistencia = false, actualizado_en = now() where modo = 'zoom' and asistencia and fecha >= public.hoy_lima();

-- Jueves sin lanzamiento: Zoom 9:00 a. m. con Juan Carlos Ezaine
insert into public.hor_plantillas (dia, hora, titulo, descripcion, lugar, modo, facilitador, tipo, asistencia, solo_inicio_periodo, excepto_inicio_periodo, publico, orden)
select 4, '09:00', 'Capacitación por Zoom', 'Los jueves que no hay lanzamiento en la oficina.', null, 'zoom', 'Juan Carlos Ezaine', 'capacitacion', false, false, true, true, 5
where not exists (select 1 from public.hor_plantillas where dia = 4 and hora = '09:00' and not borrada);
select public.hor_materializar(public.hoy_lima(), public.hoy_lima() + 21);

-- Ficha del chat
update public.chat_fichas set contenido = replace(replace(contenido,
  'jueves 9:00 p. m. capacitación por Zoom con Nelson Portugal, y el jueves que empieza el período, 10:00 a. m., lanzamiento del nuevo concurso en la oficina;',
  'jueves 9:00 p. m. capacitación por Zoom con Nelson Portugal; el jueves que empieza el período, 10:00 a. m., lanzamiento del nuevo concurso en la oficina, y los jueves que no hay lanzamiento, 9:00 a. m. capacitación por Zoom con Juan Carlos Ezaine;'),
  'Las guías, listas y el horario están en el módulo Entrenamientos de la plataforma.',
  'La asistencia del Nivel Cero se toma solo en lo presencial de la oficina: las sesiones por Zoom no cuentan. Las guías, listas y el horario están en el módulo Entrenamientos de la plataforma.'),
  actualizado_en = now()
where proyecto = 'renaware' and titulo = 'Nivel Cero y test del Nivel 0';
