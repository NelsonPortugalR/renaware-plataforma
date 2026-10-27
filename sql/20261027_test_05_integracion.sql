-- =====================================================================
-- Test del Nivel 0 · integración con Nivel Cero, Bienvenida y cron
-- 1) n0_inscritos_json trae la llave "test" (estado del test de cada inscrito):
--    la leen Nivel Cero (n0_datos), Bienvenida (wa_bv_datos) y el propio test.
-- 2) Bienvenida recibe "test" y deja de arrastrar a quien no aprobó a tiempo.
-- 3) Cron diario: códigos nuevos y Empiece Ya entregados → Premios al día.
-- Los cambios a funciones existentes se hacen sobre su texto vigente
-- (pg_get_functiondef + replace), y fallan si no encuentran lo que cambian.
-- =====================================================================

create or replace function public.ts_con_test(j jsonb) returns jsonb
language sql stable set search_path = public as $$
  select j || jsonb_build_object('test',
    ts_resumen((j ->> 'id')::uuid, j ->> 'estado', (j ->> 'logro_fecha')::date, coalesce((j ->> 'excluido')::boolean, false)))
$$;
revoke all on function public.ts_con_test(jsonb) from public, anon, authenticated;

do $patch$
declare d text;
begin
  -- 1) n0_inscritos_json: cada fila pasa por ts_con_test
  d := pg_get_functiondef('public.n0_inscritos_json(uuid)'::regprocedure);
  if position('ts_con_test' in d) = 0 then
    if position($a$select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.id, 'origen', b.origen,$a$ in d) = 0 then raise exception 'n0_inscritos_json: inicio no encontrado'; end if;
    if position($a$      end
  ) order by b.fecha_inscripcion desc, b.nombre), '[]'::jsonb)$a$ in d) = 0 then raise exception 'n0_inscritos_json: cierre no encontrado'; end if;
    d := replace(d, $a$select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.id, 'origen', b.origen,$a$, $a$select coalesce(jsonb_agg(ts_con_test(jsonb_build_object(
    'id', b.id, 'origen', b.origen,$a$);
    d := replace(d, $a$      end
  ) order by b.fecha_inscripcion desc, b.nombre), '[]'::jsonb)$a$, $a$      end
  )) order by b.fecha_inscripcion desc, b.nombre), '[]'::jsonb)$a$);
    execute d;
  end if;

  -- 2a) Bienvenida: el estado del test viaja con cada asesor
  d := pg_get_functiondef('public.wa_bv_asesor_json(jsonb)'::regprocedure);
  if position($a$'test', x->'test'$a$ in d) = 0 then
    if position($a$    'mensajes', coalesce(x->'mensajes', '[]'::jsonb),$a$ in d) = 0 then raise exception 'wa_bv_asesor_json: mensajes no encontrado'; end if;
    d := replace(d, $a$    'mensajes', coalesce(x->'mensajes', '[]'::jsonb),$a$, $a$    'test', x->'test',
    'mensajes', coalesce(x->'mensajes', '[]'::jsonb),$a$);
    execute d;
  end if;

  -- 2b) Bienvenida: quien logró sus clases sigue en la lista mientras su botella esté en juego
  d := pg_get_functiondef('public.wa_bv_datos(uuid)'::regprocedure);
  if position($a$x->'test'->>'estado'$a$ in d) = 0 then
    if position($a$                and coalesce(jsonb_typeof(x->'ey'), 'null') <> 'object'));$a$ in d) = 0 then raise exception 'wa_bv_datos: filtro no encontrado'; end if;
    d := replace(d, $a$                and coalesce(jsonb_typeof(x->'ey'), 'null') <> 'object'));$a$, $a$                and coalesce(jsonb_typeof(x->'ey'), 'null') <> 'object'
                and coalesce(x->'test'->>'estado', '') not in ('vencido', 'excluido')));$a$);
    execute d;
  end if;
end $patch$;

-- 3) cron diario (06:07 de Lima)
select cron.schedule('ts_sync_diario', '7 11 * * *', $c$select public.ts_sync_todo()$c$);
