-- Simulación completa del Test del Nivel 0 (no deja rastro: termina con un error a propósito
-- para que todo se deshaga; el resultado sale en el mensaje "SIMULACION_OK {...}").
-- Crea un inscrito de prueba con 5 clases, rinde el test con 5 errores (sin nota mínima
-- aprueba igual y la nota queda), verifica el premio en Premios y la sincronía con Nivel Cero
-- y con el Empiece Ya (en los dos sentidos y al deshacer entregas). Con un segundo inscrito
-- (solo del Nivel Cero) prueba la entrada con DNI, el doble inicio y la anulación; con un
-- tercero, que un bloqueado no entra.
do $$
declare
  v_ins uuid := gen_random_uuid(); v_tok uuid := gen_random_uuid(); v_adm uuid := gen_random_uuid();
  v_ins2 uuid := gen_random_uuid(); v_ins3 uuid := gen_random_uuid(); v_tok3 uuid := gen_random_uuid();
  cel text := '999000111'; cel2 text := '999000222'; cel3 text := '999000333';
  e jsonb; r jsonb; t ts_intentos; q jsonb; ans jsonb; out jsonb := '{}'::jsonb;
  n_resp int := 0; pasos_vistos text[] := '{}'; fallas jsonb := '[]'::jsonb;
  prev_id text; prev_paso text; v_ey uuid; v_ey2 uuid; v_tok2 uuid; a1 jsonb; a2 jsonb;
begin
  insert into asesores (celular, nombre, activo) values (cel, 'PRUEBA TEST', true);
  insert into asesor_sesion (token, celular) values (v_tok, cel);
  insert into admin_sesion (token) values (v_adm);
  insert into n0_inscritos_manual (id, nombre, celular, dni, fecha_inscripcion)
  values (v_ins, 'Prueba Test Nivel Cero', cel, '99999901', date '2026-10-15'),
         (v_ins2, 'Prueba Solo Nivel Cero', cel2, '99999902', date '2026-10-15'),
         (v_ins3, 'Prueba Bloqueada', cel3, '99999903', date '2026-10-15');
  insert into n0_clases (fecha, hora) values ('2026-10-21', '19:00'), ('2026-10-23', '19:00'), ('2026-10-27', '19:00');
  insert into n0_asistencias (clase_id, inscrito_id, presente)
  select c.id, i, true from n0_clases c, unnest(array[v_ins, v_ins2, v_ins3]) i
   where not c.borrada and c.fecha between '2026-10-15' and '2026-10-27';

  e := ts_estado(v_tok);
  out := out || jsonb_build_object('estado_inicial', e -> 'estado', 'ventana_inicial', e -> 'ventana',
                                   'nota_oficina_visible', (e -> 'ventana') ? 'nota_persona');
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
    if n_resp in (3, 6, 9, 12, 15) then
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

  -- C2) Ese Empiece Ya se desmarca en Premios → la botella del Nivel 0 vuelve a estar pendiente
  update pr_premios set entregado_en = null where id = v_ey;
  out := out || jsonb_build_object(
    'C2_n0', (select jsonb_build_object('entregado', entregado_en, 'publicado', publicado_en, 'nota', nota)
                from pr_premios where clave = 'n0-' || v_ins),
    'C2_n0_estado', coalesce((select botella_entregada_en::text from n0_estado where inscrito_id = v_ins), 'null'));

  -- D) Al revés: la del Nivel 0 se entrega primero → el Empiece Ya pendiente va "sin botella"
  update pr_premios set entregado_en = null, avisado_en = null, nota = null where id = v_ey;
  update pr_premios set entregado_en = date '2026-10-30' where clave = 'n0-' || v_ins;
  out := out || jsonb_build_object('D_ey_nota', (select nota from pr_premios where id = v_ey),
                                   'D_n0_estado', (select botella_entregada_en from n0_estado where inscrito_id = v_ins));

  -- D2) Llega después otro Empiece Ya pendiente con botella → nace "sin botella" (sin esperar al cron)
  insert into pr_premios (clave, programa, tipo, codigo, nombre, div, cantidad, premio, nivel, periodo_fin, origen, recibido_en)
  values ('test-ey2-' || v_ins, 'Programa ¡Empiece Ya!', 'final', '9999991', 'PRUEBA', 'WV08', 1,
          'Utensilio de 1.5L + Botella de Acero Inoxidable + Multi Cooker', 'Nivel II', date '2026-11-25', 'resultado', date '2026-10-30')
  returning id into v_ey2;
  out := out || jsonb_build_object('D2_ey_nuevo_nota', (select nota from pr_premios where id = v_ey2));

  -- D3) Premios desmarca la botella del Nivel 0 → los Empiece Ya vuelven a llevar su botella
  update pr_premios set entregado_en = null where clave = 'n0-' || v_ins;
  out := out || jsonb_build_object(
    'D3_ey_notas', (select jsonb_agg(coalesce(nota, '(sin nota)') order by nivel) from pr_premios where id in (v_ey, v_ey2)),
    'D3_n0_estado', coalesce((select botella_entregada_en::text from n0_estado where inscrito_id = v_ins), 'null'));

  -- J) Un Empiece Ya viejo (de otro ingreso, mismo código) entregado no cierra la botella
  insert into pr_premios (clave, programa, tipo, codigo, nombre, div, cantidad, premio, nivel, periodo_fin, origen,
                          recibido_en, avisado_en, entregado_en)
  values ('test-ey-viejo-' || v_ins, 'Programa ¡Empiece Ya!', 'final', '9999991', 'PRUEBA', 'WV08', 1,
          'Utensilio de 1.5L + Botella de Acero Inoxidable', 'Nivel I', date '2025-01-15', 'resultado',
          date '2025-01-10', date '2025-01-20', date '2025-01-20');
  out := out || jsonb_build_object('J_n0_entregado', coalesce((select entregado_en::text from pr_premios where clave = 'n0-' || v_ins), 'null'));

  -- E) vista de la oficina
  r := ts_admin_datos(v_adm);
  out := out || jsonb_build_object(
    'E_personas', (select count(*) from jsonb_array_elements(r -> 'personas')),
    'E_yo', (select x -> 'test' from jsonb_array_elements(r -> 'personas') x where x ->> 'id' = v_ins::text),
    'E_errores', r -> 'errores_bloque', 'E_plan', jsonb_array_length(r -> 'plan'));

  -- F) Solo del Nivel Cero: entra con su DNI (con puntos), doble inicio = el mismo intento, la oficina lo anula
  r := ts_entrar(' 99.999.902 ', '{}'::jsonb);
  out := out || jsonb_build_object('F_login', r - 'token');
  v_tok2 := (r ->> 'token')::uuid;
  out := out || jsonb_build_object('F_estado_dni', ts_estado(v_tok2) -> 'estado',
                                   'F_sesion_plataforma', coalesce((asesor_sesion_valida(v_tok2) ->> 'ok'), 'false'));
  begin
    perform ts_entrar('99999999', '{}'::jsonb);
    out := out || '{"F_dni_desconocido":"PERMITIDO (mal)"}';
  exception when others then
    out := out || jsonb_build_object('F_dni_desconocido', sqlerrm);
  end;
  a1 := ts_iniciar(v_tok2);
  a2 := ts_iniciar(v_tok2);
  out := out || jsonb_build_object('F_doble_inicio_mismo', a1 ->> 'id' = a2 ->> 'id');
  perform ts_admin_anular(v_adm, (a1 ->> 'id')::uuid);
  begin
    perform ts_responder(v_tok2, (a1 ->> 'id')::uuid, a1 -> 'pregunta' ->> 'id', '"o1"'::jsonb);
    out := out || '{"F_responder_anulado":"PERMITIDO (mal)"}';
  exception when others then
    out := out || jsonb_build_object('F_responder_anulado', sqlerrm);
  end;
  a2 := ts_iniciar(v_tok2);
  out := out || jsonb_build_object('F_nuevo_tras_anular', a2 ->> 'id' <> a1 ->> 'id');

  -- I) Bloqueado: ni entra (con DNI o celular) ni sigue con una sesión vieja
  insert into asesores (celular, nombre, activo) values (cel3, 'PRUEBA BLOQUEADA', false);
  insert into asesor_sesion (token, celular) values (v_tok3, cel3);
  begin
    perform ts_entrar('99999903', '{}'::jsonb);
    out := out || '{"I_login_bloqueado":"PERMITIDO (mal)"}';
  exception when others then
    out := out || jsonb_build_object('I_login_bloqueado', sqlerrm);
  end;
  begin
    perform ts_estado(v_tok3);
    out := out || '{"I_sesion_bloqueado":"PERMITIDO (mal)"}';
  exception when others then
    out := out || jsonb_build_object('I_sesion_bloqueado', sqlerrm);
  end;

  -- K) Enlaces de consulta: solo http(s)
  r := ts_admin_config(v_adm, jsonb_build_object('recursos', jsonb_build_array(
         jsonb_build_object('nombre', 'Bueno', 'url', 'https://ejemplo.pe/x'),
         jsonb_build_object('nombre', 'Malo', 'url', 'javascript:alert(1)'))));
  out := out || jsonb_build_object('K_recursos', r -> 'recursos');

  raise exception 'SIMULACION_OK %', out::text;
end $$;
