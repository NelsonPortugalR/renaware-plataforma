-- =====================================================================================================
-- Plataforma única de asesores (/asesores/), 11 de noviembre de 2026. Aplicado en la base; este archivo es la copia.
--
-- La asesora entra con su celular y tiene todo en una sola página: precios (sale al portal con su sesión),
-- zonas de crédito, listas, entrenamientos, horario, «¿ya ganó Empiece Ya?», sus premios, su Nivel Cero y sus puntos.
-- Entrenamientos, Listas y Horario ya existían (ent_datos, hor_semana…); aquí va lo nuevo:
--   · asesor_panel(p_token)      todo lo personal del inicio en una sola llamada
--   · asesor_panel_de(p_cel)     la parte que arma los datos; no se puede llamar desde fuera
--   · eya_buscar(p_token, p_q)   ¿ya ganó Empiece Ya? por nombre o código, entre los ganadores de todo el país
-- Las zonas salen de zc_lista(), la misma función del buscador de zonas (no pide sesión: es catálogo).
-- =====================================================================================================

-- ---------- ¿ya ganó Empiece Ya? ----------
-- Cada palabra escrita tiene que ser el comienzo de una palabra del nombre, en cualquier orden y sin tildes:
-- «quispe maria» encuentra a MARÍA QUISPE; «ana» no trae a SUSANA. Con solo dígitos busca por código.
-- Devuelve hasta 30, primero los de la división del equipo (WV08), con sus premios y hasta qué cierre llega la lista.
create or replace function public.eya_buscar(p_token uuid, p_q text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_txt text := btrim(regexp_replace(unaccent_safe(coalesce(p_q, '')), '[^a-z0-9]+', ' ', 'g'));
  v_tok text[]; v_cod text; v_total int; v_res jsonb; v_ult record;
begin
  perform ent_quien(p_token);
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

-- ---------- el panel de la asesora ----------
-- La parte que arma los datos, por celular. No se puede llamar desde fuera: solo la usa asesor_panel(), que valida la sesión.
--   nivel     su Nivel Cero (ts_persona_cel): estado, clases válidas, plazo, las clases a las que fue,
--             las próximas que cuentan (lo presencial con asistencia, dentro de su plazo) y el estado de su test
--   premios   de pr_premios por su código (y la botella del Nivel Cero, clave n0-<id>):
--             por_recoger = llegó a la oficina y no se entregó; por_llegar = ganado sin llegar; entregados
--   proximos  los tres eventos que siguen en el horario
--   puntos    sus tres últimos períodos según los pedidos de Rena Ware
create or replace function public.asesor_panel_de(p_cel text)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_cel text := cel_norm(p_cel); v_pid uuid; v_cod text; v_nombre text;
  v_hoy date := hoy_lima(); v_pi int := periodo_indice(v_hoy);
  v_ahora time := (now() at time zone 'America/Lima')::time;
  v_n0 jsonb; v_nivel jsonb; v_pts jsonb; v_premios jsonb; v_prox jsonb;
begin
  select p.id, p.codigo_asesor, p.nombre into v_pid, v_cod, v_nombre
    from eq_personas p
   where cel_norm(p.celular) = v_cel
   order by p.activo desc, (p.codigo_asesor is not null) desc, p.actualizado_en desc nulls last
   limit 1;

  if v_cod is not null then
    select coalesce(jsonb_agg(jsonb_build_object('periodo', periodo, 'pb', pb, 'puntos', pts, 'pedidos', n) order by anio desc, pb desc), '[]'::jsonb)
      into v_pts
      from (select split_part(periodo, '-', 1)::int as anio, substring(periodo from 'PB(\d+)')::int as pb,
                   periodo, sum(puntos) as pts, count(*) as n
              from crm_pedidos
             where id_vendedor::text = v_cod and coalesce(estatus, '') !~* '^(RECHAZ|CANCEL)'
             group by 1, 2, 3 order by 1 desc, 2 desc limit 3) s;
  end if;

  -- Nivel Cero y test: si algo falla ahí, el inicio sigue
  begin
    v_n0 := ts_persona_cel(v_cel);
    if v_n0 is not null then
      v_nivel := jsonb_build_object(
        'estado', v_n0->>'estado', 'inicio', v_n0->>'inicio', 'vence', v_n0->>'vence',
        'dias', greatest((v_n0->>'vence')::date - v_hoy, 0),
        'validas', coalesce((v_n0->>'validas')::int, 0),
        'meta', (select clases_meta from n0_config where id = 'vigente'),
        'premio', (select premio from n0_config where id = 'vigente'),
        'logro_fecha', v_n0->>'logro_fecha',
        'clases', (select coalesce(jsonb_agg(jsonb_build_object('fecha', k.fecha, 'hora', to_char(k.hora, 'HH24:MI'),
                            'tema', coalesce(nullif(e.titulo, ''), nullif(k.tema, ''), 'Clase en la oficina'), 'vale', coalesce((a->>'v')::boolean, false))
                            order by k.fecha, k.hora), '[]'::jsonb)
                     from jsonb_array_elements(coalesce(v_n0->'asistencias', '[]'::jsonb)) a
                     join n0_clases k on k.id = (a->>'c')::uuid
                     left join hor_eventos e on e.id = k.evento_id),
        'proximas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                       select jsonb_build_object('fecha', e.fecha, 'hora', to_char(e.hora, 'HH24:MI'), 'titulo', e.titulo, 'lugar', e.lugar) as x
                         from hor_eventos e
                        where e.activo and e.publico and e.asistencia
                          and (e.fecha > v_hoy or (e.fecha = v_hoy and e.hora >= v_ahora))
                          and e.fecha <= (v_n0->>'vence')::date
                        order by e.fecha, e.hora limit 6) z),
        'test', ts_ventana(v_n0) - 'nota_persona' - 'clases',
        'test_config', ts_config_publica());
    end if;
  exception when others then
    v_nivel := null;
  end;

  select jsonb_build_object(
           'por_recoger', coalesce(jsonb_agg(z.x order by z.recibido_en, z.premio) filter (where z.estado = 'oficina'), '[]'::jsonb),
           'por_llegar', coalesce(jsonb_agg(z.x order by z.periodo_fin desc nulls last, z.premio) filter (where z.estado = 'camino'), '[]'::jsonb),
           'entregados', coalesce(jsonb_agg(z.x order by z.entregado_en desc, z.premio) filter (where z.estado = 'entregado'), '[]'::jsonb))
    into v_premios
    from (select case when r.entregado_en is not null then 'entregado' when r.recibido_en is not null then 'oficina' else 'camino' end as estado,
                 r.recibido_en, r.entregado_en, r.periodo_fin, r.premio,
                 jsonb_build_object('premio', r.premio, 'cantidad', coalesce(r.cantidad, 1), 'programa', r.programa, 'nivel', r.nivel, 'pb', r.pb,
                                    'tipo', r.tipo, 'recibido_en', r.recibido_en, 'entregado_en', r.entregado_en, 'periodo_fin', r.periodo_fin) as x
            from pr_premios r
           where (v_cod is not null and r.codigo = v_cod)
              or (v_n0 is not null and r.clave = 'n0-' || (v_n0->>'id'))) z;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_prox from (
    select jsonb_build_object('fecha', e.fecha, 'hora', to_char(e.hora, 'HH24:MI'), 'titulo', e.titulo, 'modo', e.modo, 'lugar', e.lugar,
                              'facilitador', e.facilitador, 'enlace', e.enlace, 'asistencia', e.asistencia) as x
      from hor_eventos e
     where e.activo and e.publico
       and (e.fecha > v_hoy or (e.fecha = v_hoy and e.hora >= v_ahora - interval '1 hour'))
       and e.fecha <= v_hoy + 7
     order by e.fecha, e.hora limit 3) z;

  return jsonb_build_object(
    'nombre', v_nombre, 'codigo', v_cod, 'hoy', v_hoy,
    'periodo', jsonb_build_object('numero', periodo_numero(v_pi), 'inicio', periodo_inicio(v_pi), 'fin', periodo_inicio(v_pi) + 13),
    'puntos', coalesce(v_pts, '[]'::jsonb),
    'nivel', v_nivel,
    'premios', coalesce(v_premios, jsonb_build_object('por_recoger', '[]'::jsonb, 'por_llegar', '[]'::jsonb, 'entregados', '[]'::jsonb)),
    'proximos', v_prox);
end $fn$;
revoke execute on function public.asesor_panel_de(text) from public, anon, authenticated;

-- Lo que llama la página: valida la sesión de la asesora y le suma las herramientas que le tocan (plataforma_menu).
create or replace function public.asesor_panel(p_token uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare v_s jsonb; v_d jsonb; v_menu jsonb;
begin
  v_s := asesor_sesion_valida(p_token);
  if not coalesce((v_s->>'ok')::boolean, false) then raise exception 'Sesion invalida'; end if;
  v_d := asesor_panel_de(v_s->>'celular');
  if coalesce(v_d->>'nombre', '') = '' then v_d := v_d || jsonb_build_object('nombre', v_s->>'nombre'); end if;
  begin v_menu := plataforma_menu(p_token); exception when others then v_menu := '[]'::jsonb; end;
  return v_d || jsonb_build_object('menu', coalesce(v_menu, '[]'::jsonb));
end $fn$;

-- ---------- el menú: Entrenamientos y Listas ahora abren dentro de /asesores/ ----------
-- (la dirección vieja /entrenamientos/ sigue funcionando: redirige conservando la pantalla y el traspaso)
update public.plataforma_modulos set url = 'https://renaware-plataforma.nelson1614.workers.dev/asesores/#entrenamientos' where id = 'entrenamientos';
update public.plataforma_modulos set url = 'https://renaware-plataforma.nelson1614.workers.dev/asesores/#listas' where id = 'listas';
