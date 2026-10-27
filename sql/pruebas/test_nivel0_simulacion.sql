-- Simulación completa del Test del Nivel 0 (no deja rastro: termina con un error a propósito
-- para que todo se deshaga; el resultado sale en el mensaje "SIMULACION_OK {...}").
-- Crea un inscrito de prueba con 5 clases, rinde el test con 2 errores, verifica el premio
-- en Premios y la sincronía con Nivel Cero y con el Empiece Ya.
do $$
declare
  v_ins uuid := gen_random_uuid(); v_tok uuid := gen_random_uuid(); v_adm uuid := gen_random_uuid();
  cel text := '999000111';
  e jsonb; r jsonb; t ts_intentos; q jsonb; ans jsonb; out jsonb := '{}'::jsonb;
  n_resp int := 0; pasos_vistos text[] := '{}'; fallas jsonb := '[]'::jsonb;
  prev_id text; prev_paso text; v_ey uuid;
begin
  insert into asesores (celular, nombre, activo) values (cel, 'PRUEBA TEST', true);
  insert into asesor_sesion (token, celular) values (v_tok, cel);
  insert into admin_sesion (token) values (v_adm);
  insert into n0_inscritos_manual (id, nombre, celular, fecha_inscripcion)
  values (v_ins, 'Prueba Test Nivel Cero', cel, date '2026-10-15');
  insert into n0_clases (fecha, hora) values ('2026-10-21', '19:00'), ('2026-10-23', '19:00'), ('2026-10-27', '19:00');
  insert into n0_asistencias (clase_id, inscrito_id, presente)
  select id, v_ins, true from n0_clases where not borrada and fecha between '2026-10-15' and '2026-10-27';

  e := ts_estado(v_tok);
  out := out || jsonb_build_object('estado_inicial', e -> 'estado', 'ventana_inicial', e -> 'ventana');
  r := ts_iniciar(v_tok);
  out := out || jsonb_build_object('total_pasos', r -> 'total', 'bloques', r -> 'bloques');

  loop
    select * into t from ts_intentos where id = (r ->> 'id')::uuid;
    exit when t.terminado_en is not null;
    q := t.pregunta;
    if (r -> 'pregunta') ? 'clave' or (r -> 'pregunta') ? 'logica' or (r -> 'pregunta') ? 'dato' then
      raise exception 'la pregunta pública trae la respuesta (%)', q ->> 'paso';
    end if;
    n_resp := n_resp + 1;
    if n_resp > 90 then raise exception 'bucle sin fin'; end if;
    if n_resp in (3, 12) then
      ans := case q ->> 'tipo' when 'single' then to_jsonb('zz'::text) when 'multi' then '["zz"]'::jsonb else '{}'::jsonb end;
      prev_id := q ->> 'id'; prev_paso := q ->> 'paso';
      r := ts_responder(v_tok, t.id, q ->> 'id', ans);
      if (r ->> 'ok')::boolean then raise exception 'respuesta mala marcada como buena (%)', prev_paso; end if;
      if r ->> 'logica' is null then raise exception 'sin lógica al fallar (%)', prev_paso; end if;
      if r -> 'intento' -> 'pregunta' ->> 'id' = prev_id then raise exception 'no cambió la pregunta (%)', prev_paso; end if;
      if r -> 'intento' -> 'pregunta' ->> 'paso' <> prev_paso then raise exception 'cambió de paso al fallar (%)', prev_paso; end if;
      fallas := fallas || jsonb_build_object('paso', prev_paso, 'logica', r ->> 'logica',
                                             'nueva', r -> 'intento' -> 'pregunta' ->> 'texto');
      r := r -> 'intento';
      continue;
    end if;
    ans := case q ->> 'tipo'
      when 'single' then q -> 'clave' -> 0
      when 'multi' then q -> 'clave'
      when 'emparejar' then q -> 'clave'
      when 'escribir' then (select jsonb_object_agg(key, value -> 0) from jsonb_each(q -> 'clave'))
    end;
    r := ts_responder(v_tok, t.id, q ->> 'id', ans);
    if not (r ->> 'ok')::boolean then raise exception 'respuesta buena marcada como mala (%)', q ->> 'paso'; end if;
    pasos_vistos := pasos_vistos || (q ->> 'paso');
    r := r -> 'intento';
  end loop;

  out := out || jsonb_build_object('fin', r -> 'fin', 'respuestas', n_resp, 'pasos', cardinality(pasos_vistos), 'fallas', fallas);
  out := out || jsonb_build_object('premio', (select to_jsonb(p) - 'id' - 'creado_en' - 'actualizado_en' - 'carga_id'
                                                - 'catalogo_id' - 'foto_recibido' - 'foto_entregado'
                                                from pr_premios p where clave = 'n0-' || v_ins));
  e := ts_estado(v_tok);
  out := out || jsonb_build_object('estado_final', e -> 'estado', 'botella', e -> 'ventana' -> 'botella',
                                   'historial', e -> 'historial');
  begin
    perform ts_iniciar(v_tok);
    out := out || '{"reinicio":"PERMITIDO (mal)"}';
  exception when others then
    out := out || jsonb_build_object('reinicio', sqlerrm);
  end;

  -- A) Nivel Cero marca la botella entregada → Premios
  insert into n0_estado (inscrito_id, botella_entregada_en) values (v_ins, date '2026-10-28')
  on conflict (inscrito_id) do update set botella_entregada_en = excluded.botella_entregada_en;
  out := out || jsonb_build_object('A_premios_entregado', (select entregado_en from pr_premios where clave = 'n0-' || v_ins),
                                   'A_premios_avisado', (select avisado_en from pr_premios where clave = 'n0-' || v_ins));
  -- B) Premios la desmarca → Nivel Cero
  update pr_premios set entregado_en = null where clave = 'n0-' || v_ins;
  out := out || jsonb_build_object('B_n0_botella', coalesce((select botella_entregada_en::text from n0_estado where inscrito_id = v_ins), 'null'));

  -- C) Su Empiece Ya (con botella) se entrega → la botella del Nivel 0 se cierra sola
  update n0_estado set codigo_rw = '9999991' where inscrito_id = v_ins;
  perform ts_sync_persona(v_ins);
  insert into pr_premios (clave, programa, tipo, codigo, nombre, div, cantidad, premio, nivel, periodo_fin, origen, recibido_en)
  values ('test-ey-' || v_ins, 'Programa ¡Empiece Ya!', 'final', '9999991', 'PRUEBA', 'WV08', 1,
          'Utensilio de 1.5L + Botella de Acero Inoxidable', 'Nivel I', date '2026-11-25', 'resultado', date '2026-10-27')
  returning id into v_ey;
  update pr_premios set avisado_en = date '2026-10-29', entregado_en = date '2026-10-29' where id = v_ey;
  out := out || jsonb_build_object(
    'C_n0', (select jsonb_build_object('codigo', codigo, 'entregado', entregado_en, 'publicado', publicado_en, 'nota', nota)
               from pr_premios where clave = 'n0-' || v_ins),
    'C_n0_estado', (select botella_entregada_en from n0_estado where inscrito_id = v_ins));

  -- D) Al revés: la del Nivel 0 se entrega primero → el Empiece Ya pendiente va "sin botella"
  update pr_premios set entregado_en = null, publicado_en = null, nota = null where clave = 'n0-' || v_ins;
  update pr_premios set entregado_en = null, avisado_en = null, nota = null where id = v_ey;
  update pr_premios set entregado_en = date '2026-10-30' where clave = 'n0-' || v_ins;
  out := out || jsonb_build_object('D_ey_nota', (select nota from pr_premios where id = v_ey),
                                   'D_n0_estado', (select botella_entregada_en from n0_estado where inscrito_id = v_ins));

  -- E) vista de la oficina
  r := ts_admin_datos(v_adm);
  out := out || jsonb_build_object(
    'E_personas', (select count(*) from jsonb_array_elements(r -> 'personas')),
    'E_yo', (select x -> 'test' from jsonb_array_elements(r -> 'personas') x where x ->> 'id' = v_ins::text),
    'E_errores', r -> 'errores_bloque', 'E_plan', jsonb_array_length(r -> 'plan'));

  raise exception 'SIMULACION_OK %', out::text;
end $$;
