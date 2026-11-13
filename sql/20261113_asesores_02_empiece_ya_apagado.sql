-- =====================================================================================================
-- «¿Ya ganó Empiece Ya?» apagado para las asesoras (13 de noviembre de 2026). Aplicado en la base; este archivo es la copia.
--
-- Nelson: «por ahora no; le voy a complicar a una persona con esa información. Yo como admin sí debería tener eso,
-- pero el asesor no necesariamente». La oficina no pierde nada: lo tiene en el hub, en «Ganadores Empiece Ya»
-- (Equipo), con su «Buscar persona».
--
-- No se quitó nada: quedó un interruptor. La fila «eya-buscar» de plataforma_modulos nace apagada, así que
-- plataforma_menu no se la manda a la asesora y /asesores/ no muestra el botón, ni la pantalla, ni la búsqueda;
-- y eya_buscar no le responde aunque llame a la función a mano. Para prenderlo, sin tocar la página:
--     update plataforma_modulos set activo = true where id = 'eya-buscar';
-- y para volver a apagarlo, lo mismo con false.
-- =====================================================================================================

-- El interruptor. Si la fila ya existe no se toca: volver a correr este archivo no cambia lo que Nelson haya decidido.
insert into plataforma_modulos (id, nombre, descripcion, url, grupo, orden, roles, acceso, activo)
values ('eya-buscar', '¿Ya ganó Empiece Ya?', 'Busca a una persona por su nombre.', '#empiece', 'Equipo', 27, array['asesor'], 'hub', false)
on conflict (id) do nothing;

-- La misma búsqueda del 11/11 (sql/20261111_asesores.sql), ahora mirando el interruptor cuando quien pregunta es una asesora.
create or replace function public.eya_buscar(p_token uuid, p_q text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_txt text := btrim(regexp_replace(unaccent_safe(coalesce(p_q, '')), '[^a-z0-9]+', ' ', 'g'));
  v_tok text[]; v_cod text; v_total int; v_res jsonb; v_ult record; v_q jsonb;
begin
  v_q := ent_quien(p_token);
  -- a la asesora solo le responde si la búsqueda está prendida en el menú (plataforma_modulos «eya-buscar»); a la oficina, siempre
  if v_q->>'rol' = 'asesor' and not exists (select 1 from plataforma_modulos m where m.id = 'eya-buscar' and m.activo and 'asesor' = any(m.roles)) then
    raise exception 'Esta búsqueda no está disponible.';
  end if;
  select p.anio, p.pb, p.fecha_cierre into v_ult from eya_periodos p order by p.fecha_cierre desc limit 1;
  if v_txt ~ '^[0-9]{4,}$' then
    v_cod := v_txt;
  else
    v_tok := array(select t from unnest(string_to_array(v_txt, ' ')) t where length(t) >= 2);
    if coalesce(cardinality(v_tok), 0) = 0 or length(replace(v_txt, ' ', '')) < 3 then
      return jsonb_build_object('ok', false, 'motivo', 'corto');
    end if;
  end if;
  with m as (
    select a.codigo, a.nombre, a.division, a.fecha_calificacion as fecha,
           row_number() over (order by (upper(a.division) = 'WV08') desc, a.fecha_calificacion desc, a.nombre) as rn
      from eya_asesores a
     where (v_cod is not null and a.codigo = v_cod)
        or (v_cod is null and (select bool_and(' ' || regexp_replace(unaccent_safe(a.nombre), '[^a-z0-9]+', ' ', 'g') like '% ' || t || '%') from unnest(v_tok) t))
  )
  select (select count(*) from m),
         coalesce(jsonb_agg(jsonb_build_object(
           'codigo', m.codigo, 'nombre', m.nombre, 'division', m.division, 'fecha', m.fecha,
           'mi_equipo', upper(m.division) = 'WV08',
           'pb', (select jsonb_build_object('anio', p.anio, 'pb', p.pb) from eya_periodos p where p.fecha_cierre = m.fecha),
           'premios', (select coalesce(jsonb_agg(jsonb_build_object('anio', pr.anio, 'pb', pr.pb, 'premio', pr.premio) order by pr.anio, pr.pb, pr.id), '[]'::jsonb)
                         from eya_premios pr where pr.codigo = m.codigo)) order by m.rn), '[]'::jsonb)
    into v_total, v_res
    from m where m.rn <= 30;
  return jsonb_build_object('ok', true, 'total', coalesce(v_total, 0), 'resultados', v_res,
    'cobertura', jsonb_build_object('desde', (select min(fecha_calificacion) from eya_historico),
                                    'hasta', v_ult.fecha_cierre, 'anio', v_ult.anio, 'pb', v_ult.pb));
end $fn$;
