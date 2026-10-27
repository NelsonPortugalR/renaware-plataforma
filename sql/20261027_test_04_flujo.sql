-- =====================================================================
-- Test del Nivel 0 · ventana, intentos, nota y premio
-- Ventana: desde el día de su 5.ª clase válida hasta 15 días después (ambos incluidos).
-- Aprueba con nota >= ts_config.nota_minima (90). Intentos ilimitados en la ventana.
-- Al aprobar: fila en Premios (pr_premios, programa 'Nivel Cero') = botella por entregar.
-- No se repite: si su Empiece Ya (que trae botella) ya se entregó, la botella del
-- Nivel 0 se cierra sola; si la botella del Nivel 0 se entregó primero, el Empiece Ya
-- pendiente queda marcado "entregar sin botella".
-- =====================================================================

-- ---------- estado del test de una persona (núcleo, lo usan asesor, oficina, Nivel Cero y Bienvenida) ----------
create or replace function public.ts_resumen(p_id uuid, p_estado_n0 text, p_logro date, p_excluido boolean)
returns jsonb language plpgsql stable set search_path = public as $$
declare cfg ts_config; o ts_personas; a record; v_hasta date; v_hoy date := hoy_lima();
  v_n int; v_mejor int; v_abierto uuid; v_estado text; b record;
begin
  select * into cfg from ts_config where id = 'vigente';
  select * into o from ts_personas where inscrito_id = p_id;
  select count(*) filter (where terminado_en is not null),
         max(nota) filter (where terminado_en is not null),
         (array_agg(id order by iniciado_en desc) filter (where terminado_en is null))[1]
    into v_n, v_mejor, v_abierto
    from ts_intentos where inscrito_id = p_id and origen = 'asesor' and not anulado;
  select id, nota, terminado_en into a from ts_intentos
   where inscrito_id = p_id and origen = 'asesor' and not anulado and aprobado
   order by terminado_en limit 1;
  v_hasta := coalesce(o.hasta, p_logro + cfg.dias_ventana);
  v_estado := case
    when coalesce(p_excluido, false) or coalesce(o.excluido, false) then 'excluido'
    when a.id is not null then 'aprobado'
    when p_estado_n0 is distinct from 'logro' or p_logro is null then 'clases'
    when p_logro < cfg.aplica_desde then 'no_aplica'
    when v_hoy <= v_hasta then 'habilitado'
    else 'vencido' end;
  select recibido_en, avisado_en, entregado_en, nota into b from pr_premios where clave = 'n0-' || p_id;
  return jsonb_build_object(
    'estado', v_estado,
    'desde', case when p_logro is not null then p_logro end,
    'hasta', case when p_logro is not null then v_hasta end,
    'hasta_editado', o.hasta is not null,
    'dias', case when v_estado = 'habilitado' then v_hasta - v_hoy end,
    'intentos', coalesce(v_n, 0), 'mejor', v_mejor, 'abierto', v_abierto,
    'aprobado_en', (a.terminado_en at time zone 'America/Lima')::date, 'nota', a.nota,
    'botella', case when b.recibido_en is null then null
                    when b.entregado_en is not null then 'entregada'
                    else 'por_entregar' end,
    'botella_entregada_en', b.entregado_en,
    'nota_persona', o.nota);
end $$;

-- inscrito de Nivel Cero por celular (si hay más de uno, el que ya logró y el más reciente)
create or replace function public.ts_persona_cel(p_cel text) returns jsonb
language plpgsql stable set search_path = public as $$
declare v jsonb; r record; mejor jsonb; c text := cel_norm(p_cel);
begin
  if length(c) < 9 then return null; end if;
  for r in select i.id from n0_inscritos i where cel_norm(i.celular) = c loop
    v := n0_inscritos_json(r.id) -> 0;
    continue when v is null;
    if mejor is null
       or (v ->> 'estado' = 'logro' and mejor ->> 'estado' <> 'logro')
       or ((v ->> 'estado' = 'logro') = (mejor ->> 'estado' = 'logro')
           and coalesce(v ->> 'fecha_inscripcion', '') > coalesce(mejor ->> 'fecha_inscripcion', '')) then
      mejor := v;
    end if;
  end loop;
  return mejor;
end $$;

create or replace function public.ts_ventana(p jsonb) returns jsonb
language sql stable set search_path = public as $$
  select ts_resumen((p ->> 'id')::uuid, p ->> 'estado', (p ->> 'logro_fecha')::date, coalesce((p ->> 'excluido')::boolean, false))
      || jsonb_build_object('clases', jsonb_build_object(
           'validas', coalesce((p ->> 'validas')::int, 0),
           'meta', (select clases_meta from n0_config where id = 'vigente'),
           'vence', p ->> 'vence', 'estado', p ->> 'estado'))
$$;

-- ---------- el plan: pasos activos que hoy se pueden armar ----------
create or replace function public.ts_plan() returns text[]
language sql stable set search_path = public as $$
  select coalesce(array_agg(p.clave order by p.orden), '{}'::text[])
    from ts_pasos p
   where p.activo
     and (p.clave <> 'cuentas' or jsonb_array_length((select cuentas from ts_config where id = 'vigente')) > 0)
     and (p.clave not in ('precio_promo', 'regalo_promo') or exists (select 1 from ts_promos()))
     and (p.clave <> 'regalo_promo' or exists (select 1 from ts_promos() where regalo is not null))
     and (p.clave <> 'identificar' or (select count(*) from ts_generales() where foto is not null) >= 5)
     and (not exists (select 1 from ts_banco b where b.paso = p.clave)
          or exists (select 1 from ts_banco b where b.paso = p.clave and b.activo))
$$;

create or replace function public.ts_config_publica() returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('nota_minima', nota_minima, 'dias_ventana', dias_ventana, 'premio', premio,
                            'pasos', cardinality(ts_plan()))
    from ts_config where id = 'vigente'
$$;

-- ---------- vista pública de un intento (sin respuestas) ----------
create or replace function public.ts_errores_bloque(p_log jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('bloque', bloque, 'nombre', ts_bloque_nombre(bloque),
                                               'respuestas', n, 'errores', e) order by o), '[]'::jsonb)
    from (select x ->> 'bloque' as bloque, count(*) n, count(*) filter (where not (x ->> 'ok')::boolean) e, min(i) o
            from jsonb_array_elements(coalesce(p_log, '[]'::jsonb)) with ordinality t(x, i)
           group by x ->> 'bloque') s
$$;

create or replace function public.ts_intento_publico(t ts_intentos) returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'id', t.id, 'origen', t.origen,
    'paso', least(t.paso_idx + 1, cardinality(t.plan)), 'total', cardinality(t.plan),
    'intentos', t.intentos, 'aciertos', t.aciertos,
    'pregunta', case when t.terminado_en is null and t.pregunta is not null
                     then t.pregunta - 'clave' - 'logica' - 'dato' - 'usa' end,
    'bloques', (select coalesce(jsonb_agg(jsonb_build_object('bloque', bloque, 'nombre', ts_bloque_nombre(bloque),
                                                             'pasos', n, 'hechos', h) order by o), '[]'::jsonb)
                  from (select p.bloque, min(u.ord) o, count(*) n, count(*) filter (where u.ord <= t.paso_idx) h
                          from unnest(t.plan) with ordinality u(clave, ord)
                          join ts_pasos p on p.clave = u.clave
                         group by p.bloque) s),
    'fin', case when t.terminado_en is not null then jsonb_build_object(
             'nota', t.nota, 'aprobado', t.aprobado,
             'nota_minima', (select nota_minima from ts_config where id = 'vigente'),
             'pasos', cardinality(t.plan), 'intentos', t.intentos, 'errores', t.intentos - t.aciertos,
             'minutos', round(extract(epoch from (t.terminado_en - t.iniciado_en)) / 60.0),
             'por_bloque', ts_errores_bloque(t.log)) end)
$$;

-- ---------- avanzar: arma la pregunta del paso actual o cierra el intento ----------
create or replace function public.ts_preparar(p_id uuid) returns void
language plpgsql volatile set search_path = public as $$
declare t ts_intentos; q jsonb; v_paso text; v_bloque text; cfg ts_config; v_nota int;
begin
  select * into cfg from ts_config where id = 'vigente';
  loop
    select * into t from ts_intentos where id = p_id for update;
    if t.paso_idx >= cardinality(t.plan) then
      v_nota := round(100.0 * cardinality(t.plan) / greatest(t.intentos, 1));
      update ts_intentos
         set pregunta = null, terminado_en = coalesce(terminado_en, now()),
             nota = v_nota, aprobado = v_nota >= cfg.nota_minima
       where id = p_id;
      if v_nota >= cfg.nota_minima and t.origen = 'asesor' and t.inscrito_id is not null then
        perform ts_premiar(t.inscrito_id, v_nota);
      end if;
      return;
    end if;
    v_paso := t.plan[t.paso_idx + 1];
    q := ts_generar(v_paso, t.ctx, coalesce(t.usados -> v_paso, '[]'::jsonb));
    if q is null then
      -- con la data de hoy no se puede armar ese paso: sale del plan de este intento
      update ts_intentos set plan = plan[1:paso_idx] || plan[paso_idx + 2:] where id = p_id;
      continue;
    end if;
    select bloque into v_bloque from ts_pasos where clave = v_paso;
    q := q || jsonb_build_object('bloque', v_bloque, 'bloque_nombre', ts_bloque_nombre(v_bloque));
    update ts_intentos
       set pregunta = q,
           usados = jsonb_set(usados, array[v_paso], coalesce(usados -> v_paso, '[]'::jsonb) || coalesce(q -> 'usa', '[]'::jsonb))
     where id = p_id;
    return;
  end loop;
end $$;

create or replace function public.ts_corregir(q jsonb, r jsonb) returns boolean
language plpgsql immutable as $$
begin
  if r is null or q is null then return false; end if;
  case q ->> 'tipo'
    when 'single' then
      return jsonb_typeof(r) = 'string' and jsonb_array_length(q -> 'clave') = 1 and (r #>> '{}') = (q -> 'clave' ->> 0);
    when 'multi' then
      if jsonb_typeof(r) <> 'array' then return false; end if;
      return (select coalesce(array_agg(distinct x order by x), '{}'::text[]) from jsonb_array_elements_text(r) x)
           = (select coalesce(array_agg(distinct x order by x), '{}'::text[]) from jsonb_array_elements_text(q -> 'clave') x);
    when 'emparejar' then
      if jsonb_typeof(r) <> 'object' then return false; end if;
      return not exists (select 1 from jsonb_each_text(q -> 'clave') k where (r ->> k.key) is distinct from k.value);
    when 'escribir' then
      if jsonb_typeof(r) <> 'object' then return false; end if;
      return not exists (
        select 1 from jsonb_each(q -> 'clave') k
         where not exists (
           select 1 from jsonb_array_elements_text(k.value) v
            where regexp_replace(v, '\D', '', 'g') <> ''
              and regexp_replace(v, '\D', '', 'g') = regexp_replace(coalesce(r ->> k.key, ''), '\D', '', 'g')));
    else
      return false;
  end case;
end $$;

-- responder la pregunta en curso. Acierta: avanza. Falla: explica la lógica y sale otra del mismo tipo.
create or replace function public.ts_responder_int(p_id uuid, p_pregunta text, p_respuesta jsonb) returns jsonb
language plpgsql volatile set search_path = public as $$
declare t ts_intentos; ok boolean; q jsonb; v_paso text; v_nueva jsonb; v_dato text; v_logica text;
begin
  select * into t from ts_intentos where id = p_id for update;
  if not found then raise exception 'No encontré ese test.'; end if;
  if t.terminado_en is not null then
    return jsonb_build_object('intento', ts_intento_publico(t));
  end if;
  if t.pregunta is null or (t.pregunta ->> 'id') is distinct from p_pregunta then
    return jsonb_build_object('desfase', true, 'intento', ts_intento_publico(t));
  end if;
  q := t.pregunta; v_paso := q ->> 'paso';
  ok := ts_corregir(q, p_respuesta);
  update ts_intentos
     set intentos = intentos + 1, aciertos = aciertos + case when ok then 1 else 0 end,
         log = log || jsonb_build_array(jsonb_build_object('paso', v_paso, 'bloque', q ->> 'bloque', 'ok', ok, 'en', now()))
   where id = p_id;
  if ok then
    v_dato := q ->> 'dato';
    update ts_intentos set paso_idx = paso_idx + 1 where id = p_id;
    perform ts_preparar(p_id);
  else
    v_logica := q ->> 'logica';
    v_nueva := ts_generar(v_paso, t.ctx, coalesce(t.usados -> v_paso, '[]'::jsonb));
    if v_nueva is null then v_nueva := ts_generar(v_paso, t.ctx, '[]'::jsonb); end if;
    if v_nueva is null then
      v_nueva := case when q ->> 'tipo' in ('single', 'multi') then ts_remezclar(q) else q || jsonb_build_object('id', ts_qid()) end;
    end if;
    v_nueva := v_nueva || jsonb_build_object('bloque', q ->> 'bloque', 'bloque_nombre', q ->> 'bloque_nombre');
    update ts_intentos
       set pregunta = v_nueva,
           usados = jsonb_set(usados, array[v_paso], coalesce(usados -> v_paso, '[]'::jsonb) || coalesce(v_nueva -> 'usa', '[]'::jsonb))
     where id = p_id;
  end if;
  select * into t from ts_intentos where id = p_id;
  return jsonb_build_object('ok', ok,
                            'dato', case when ok then v_dato end,
                            'logica', case when not ok then v_logica end,
                            'intento', ts_intento_publico(t));
end $$;

-- ---------- premio: botella del Nivel 0 en Premios ----------
create or replace function public.ts_sync_persona(p_inscrito uuid) returns void
language plpgsql volatile set search_path = public as $$
declare r pr_premios; p jsonb; v_cod text; v_real text; e n0_estado; ey pr_premios;
begin
  select * into r from pr_premios where clave = 'n0-' || p_inscrito;
  if not found then return; end if;
  p := n0_inscritos_json(p_inscrito) -> 0;
  v_cod := nullif(p ->> 'codigo', '');
  if v_cod is not null and r.codigo is distinct from v_cod then
    update pr_premios set codigo = v_cod, actualizado_en = now() where id = r.id;
    r.codigo := v_cod;
  end if;
  -- sin código de Rena Ware todavía (va "—" en Premios): no se cruza con ningún Empiece Ya
  v_real := case when r.codigo ~ '^\d{4,7}$' then r.codigo end;

  -- Nivel Cero ya la marcó entregada
  select * into e from n0_estado where inscrito_id = p_inscrito;
  if e.botella_entregada_en is not null and r.entregado_en is null then
    update pr_premios
       set avisado_en = coalesce(avisado_en, e.botella_entregada_en), entregado_en = e.botella_entregada_en,
           actualizado_en = now()
     where id = r.id
    returning * into r;
  end if;

  -- Su Empiece Ya (con botella de acero) ya se entregó: no se repite
  if r.entregado_en is null and v_real is not null then
    select * into ey from pr_premios
     where programa ilike '%empiece ya%' and codigo = v_real and entregado_en is not null
       and premio ilike '%botella de acero%' and (origen <> 'declarado' or confirmado_en is not null)
     order by entregado_en limit 1;
    if found then
      update pr_premios
         set avisado_en = coalesce(avisado_en, ey.entregado_en), entregado_en = ey.entregado_en,
             publicado_en = coalesce(publicado_en, ey.publicado_en, ey.entregado_en),
             nota = concat_ws(' ', nullif(nota, ''), 'Se entregó junto con su Empiece Ya.'),
             actualizado_en = now()
       where id = r.id
      returning * into r;
    end if;
  end if;

  -- La botella del Nivel 0 se entregó antes: su Empiece Ya pendiente va sin botella
  if r.entregado_en is not null and v_real is not null and coalesce(r.nota, '') not ilike '%junto con su Empiece Ya%' then
    update pr_premios
       set nota = concat_ws(' ', nullif(nota, ''), 'Entregar sin botella: ya la recibió por el Nivel Cero.'),
           actualizado_en = now()
     where programa ilike '%empiece ya%' and codigo = v_real and entregado_en is null
       and premio ilike '%botella de acero%' and coalesce(nota, '') not ilike '%sin botella%';
  end if;
end $$;

create or replace function public.ts_sync_todo() returns int
language plpgsql volatile set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select substr(clave, 4)::uuid as id from pr_premios where origen = 'nivel_cero' and clave like 'n0-%' loop
    perform ts_sync_persona(r.id); n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.ts_premiar(p_inscrito uuid, p_nota int) returns void
language plpgsql volatile set search_path = public as $$
declare p jsonb; cfg ts_config; v_hoy date := hoy_lima(); i int; v_cod text; v_div text; v_org text; v_elite text;
begin
  select * into cfg from ts_config where id = 'vigente';
  p := n0_inscritos_json(p_inscrito) -> 0;
  if p is null then return; end if;
  v_cod := coalesce(nullif(p ->> 'codigo', ''), '—');   -- "—" = aún sin código (igual que el alta a mano de Premios)
  v_div := coalesce((select upper(e.codigo_division) from eq_personas e
                      where v_cod is not null and e.codigo_asesor = v_cod and e.codigo_division is not null limit 1), 'WV08');
  select organizacion, elite into v_org, v_elite from pr_premios
   where div = v_div and organizacion is not null and origen = 'resultado' order by periodo_fin desc limit 1;
  i := periodo_indice(v_hoy);
  insert into pr_premios (clave, programa, tipo, codigo, nombre, div, elite, organizacion, cantidad,
                          premio, nivel, periodo_fin, periodo_num, origen, recibido_en, nota)
  values ('n0-' || p_inscrito, 'Nivel Cero', 'final', v_cod, upper(coalesce(p ->> 'nombre', '')), v_div, v_elite, v_org, 1,
          cfg.premio, 'Nivel 0', periodo_inicio(i) + 13, periodo_numero(i), 'nivel_cero', v_hoy,
          format('5 clases al %s · test aprobado con %s el %s.',
                 to_char((p ->> 'logro_fecha')::date, 'DD/MM'), p_nota, to_char(v_hoy, 'DD/MM')))
  on conflict (clave) do nothing;
  perform ts_sync_persona(p_inscrito);
end $$;

-- ---------- espejo entre Premios y Nivel Cero, y cierre por Empiece Ya ----------
create or replace function public.ts_tg_premios() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.origen = 'nivel_cero' and new.clave like 'n0-%' then
    -- lo que Premios marca (o desmarca) como entregado se ve en Nivel Cero.
    -- Al crear la fila no se empuja un vacío: Nivel Cero pudo haberla marcado antes.
    if tg_op = 'UPDATE' and new.entregado_en is distinct from old.entregado_en
       or tg_op = 'INSERT' and new.entregado_en is not null then
      insert into n0_estado (inscrito_id, botella_entregada_en)
      values (substr(new.clave, 4)::uuid, new.entregado_en)
      on conflict (inscrito_id) do update set botella_entregada_en = excluded.botella_entregada_en, actualizado_en = now()
        where n0_estado.botella_entregada_en is distinct from excluded.botella_entregada_en;
    end if;
    if new.entregado_en is not null and new.codigo ~ '^\d{4,7}$' then
      perform ts_sync_persona(substr(new.clave, 4)::uuid);
    end if;
  elsif new.programa ilike '%empiece ya%' and new.entregado_en is not null and new.codigo ~ '^\d{4,7}$' then
    for r in select substr(clave, 4)::uuid as id from pr_premios
              where origen = 'nivel_cero' and clave like 'n0-%' and entregado_en is null and codigo = new.codigo loop
      perform ts_sync_persona(r.id);
    end loop;
  end if;
  return null;
end $$;

create or replace trigger trg_ts_premios
  after insert or update of entregado_en, codigo on public.pr_premios
  for each row execute function public.ts_tg_premios();

create or replace function public.ts_tg_n0_estado() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update pr_premios
     set entregado_en = new.botella_entregada_en,
         avisado_en = case when new.botella_entregada_en is not null then coalesce(avisado_en, new.botella_entregada_en) else avisado_en end,
         actualizado_en = now()
   where clave = 'n0-' || new.inscrito_id
     and entregado_en is distinct from new.botella_entregada_en;
  return null;
end $$;

create or replace trigger trg_ts_n0_estado
  after insert or update of botella_entregada_en on public.n0_estado
  for each row execute function public.ts_tg_n0_estado();

-- =====================================================================
-- Asesor (sesión de celular: asesor_login / traspaso del hub)
-- =====================================================================
create or replace function public.ts_sesion(p_token uuid) returns jsonb
language plpgsql volatile set search_path = public as $$
declare v_s jsonb;
begin
  v_s := asesor_sesion_valida(p_token);
  if not coalesce((v_s ->> 'ok')::boolean, false) then
    raise exception 'Tu sesión venció. Vuelve a entrar con tu celular.';
  end if;
  return v_s;
end $$;

create or replace function public.ts_estado(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_s jsonb; p jsonb; w jsonb; t ts_intentos;
begin
  v_s := ts_sesion(p_token);
  p := ts_persona_cel(v_s ->> 'celular');
  if p is null then
    return jsonb_build_object('nombre', v_s ->> 'nombre', 'estado', 'no_inscrito', 'config', ts_config_publica());
  end if;
  w := ts_ventana(p);
  if (w ->> 'abierto') is not null then
    select * into t from ts_intentos where id = (w ->> 'abierto')::uuid;
  end if;
  return jsonb_build_object(
    'nombre', coalesce(nullif(p ->> 'nombre', ''), v_s ->> 'nombre'),
    'estado', w ->> 'estado', 'ventana', w,
    'intento', case when t.id is not null then ts_intento_publico(t) end,
    'historial', (select coalesce(jsonb_agg(jsonb_build_object('fecha', (i.terminado_en at time zone 'America/Lima')::date,
                                                               'nota', i.nota, 'aprobado', i.aprobado)
                                            order by i.terminado_en desc), '[]'::jsonb)
                    from ts_intentos i
                   where i.inscrito_id = (p ->> 'id')::uuid and i.origen = 'asesor'
                     and i.terminado_en is not null and not i.anulado),
    'config', ts_config_publica());
end $$;

create or replace function public.ts_iniciar(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_s jsonb; p jsonb; w jsonb; v_id uuid; t ts_intentos;
begin
  v_s := ts_sesion(p_token);
  p := ts_persona_cel(v_s ->> 'celular');
  if p is null then raise exception 'No encontramos tu inscripción en el Nivel Cero con este número. Avísale a tu líder.'; end if;
  w := ts_ventana(p);
  if (w ->> 'abierto') is not null then
    select * into t from ts_intentos where id = (w ->> 'abierto')::uuid;
    return ts_intento_publico(t);
  end if;
  if w ->> 'estado' = 'aprobado' then raise exception 'Ya aprobaste tu test.'; end if;
  if w ->> 'estado' = 'vencido' then raise exception 'Tu plazo para el test venció el %.', to_char((w ->> 'hasta')::date, 'DD/MM'); end if;
  if w ->> 'estado' <> 'habilitado' then raise exception 'Tu test se habilita al completar tus 5 clases.'; end if;
  insert into ts_intentos (inscrito_id, celular, nombre, origen, plan, ctx)
  values ((p ->> 'id')::uuid, cel_norm(v_s ->> 'celular'), p ->> 'nombre', 'asesor', ts_plan(),
          jsonb_build_object('inicio', coalesce((p ->> 'inicio')::date, hoy_lima()),
                             'ey', ts_ey(coalesce((p ->> 'inicio')::date, hoy_lima()))))
  returning id into v_id;
  perform ts_preparar(v_id);
  select * into t from ts_intentos where id = v_id;
  return ts_intento_publico(t);
end $$;

create or replace function public.ts_responder(p_token uuid, p_intento uuid, p_pregunta text, p_respuesta jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_s jsonb; p jsonb; w jsonb;
begin
  v_s := ts_sesion(p_token);
  p := ts_persona_cel(v_s ->> 'celular');
  if p is null or not exists (select 1 from ts_intentos where id = p_intento and origen = 'asesor' and not anulado
                                 and inscrito_id = (p ->> 'id')::uuid) then
    raise exception 'Ese test no es tuyo.';
  end if;
  -- pasado el plazo ya no hay test, tampoco para terminar uno empezado
  w := ts_ventana(p);
  if w ->> 'estado' = 'vencido' then
    raise exception 'Tu plazo para el test venció el %.', to_char((w ->> 'hasta')::date, 'DD/MM');
  end if;
  if w ->> 'estado' <> 'habilitado' then raise exception 'Tu test no está habilitado.'; end if;
  return ts_responder_int(p_intento, p_pregunta, p_respuesta);
end $$;

-- =====================================================================
-- Oficina (clave de admin, o traspaso desde la plataforma)
-- =====================================================================
create or replace function public.ts_admin_ok(p_token uuid) returns void
language plpgsql volatile set search_path = public as $$
begin
  if not es_admin(p_token) then raise exception 'Sesion invalida'; end if;
end $$;

create or replace function public.ts_admin_datos(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ins jsonb; v_personas jsonb;
begin
  perform ts_admin_ok(p_token);
  perform ts_sync_todo();
  v_ins := n0_inscritos_json(null);
  select coalesce(jsonb_agg(x order by
           case x -> 'test' ->> 'estado' when 'habilitado' then 0 when 'vencido' then 1 when 'aprobado' then 2 else 3 end,
           x -> 'test' ->> 'hasta' nulls last, x ->> 'nombre'), '[]'::jsonb)
    into v_personas
    from (select jsonb_build_object(
                   'id', i ->> 'id', 'nombre', i ->> 'nombre', 'celular', i ->> 'celular', 'codigo', i ->> 'codigo',
                   'afiliador', i ->> 'afiliador', 'inicio', i ->> 'inicio', 'logro_fecha', i ->> 'logro_fecha',
                   'validas', i -> 'validas', 'estado_n0', i ->> 'estado',
                   'test', ts_resumen((i ->> 'id')::uuid, i ->> 'estado', (i ->> 'logro_fecha')::date,
                                      coalesce((i ->> 'excluido')::boolean, false)),
                   'intentos', (select coalesce(jsonb_agg(jsonb_build_object(
                                   'id', t.id, 'iniciado', t.iniciado_en, 'terminado', t.terminado_en,
                                   'nota', t.nota, 'aprobado', t.aprobado, 'intentos', t.intentos,
                                   'pasos', cardinality(t.plan), 'paso', t.paso_idx,
                                   'por_bloque', ts_errores_bloque(t.log)) order by t.iniciado_en desc), '[]'::jsonb)
                                  from ts_intentos t
                                 where t.inscrito_id = (i ->> 'id')::uuid and t.origen = 'asesor' and not t.anulado)) as x
            from jsonb_array_elements(v_ins) i
           where i ->> 'estado' = 'logro'
              or exists (select 1 from ts_intentos t where t.inscrito_id = (i ->> 'id')::uuid)
              or exists (select 1 from ts_personas tp where tp.inscrito_id = (i ->> 'id')::uuid)) s;
  return jsonb_build_object(
    'hoy', hoy_lima(),
    'config', (select to_jsonb(c) from ts_config c where id = 'vigente'),
    'plan', ts_plan(),
    'pasos', (select coalesce(jsonb_agg(jsonb_build_object('clave', p.clave, 'bloque', p.bloque,
                                   'bloque_nombre', ts_bloque_nombre(p.bloque), 'titulo', p.titulo, 'activo', p.activo,
                                   'variantes', (select count(*) from ts_banco b where b.paso = p.clave and b.activo))
                                 order by p.orden), '[]'::jsonb) from ts_pasos p),
    'personas', v_personas,
    'en_clases', (select count(*) from jsonb_array_elements(v_ins) i where i ->> 'estado' = 'en_curso'),
    'errores_bloque', (select ts_errores_bloque(coalesce(jsonb_agg(e.v), '[]'::jsonb))
                         from ts_intentos t, jsonb_array_elements(t.log) as e(v)
                        where t.origen = 'asesor' and not t.anulado and t.terminado_en is not null),
    'practicas', (select count(*) from ts_intentos where origen = 'oficina'));
end $$;

create or replace function public.ts_admin_intento(p_token uuid, p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t ts_intentos;
begin
  perform ts_admin_ok(p_token);
  select * into t from ts_intentos where id = p_id;
  if not found then raise exception 'No encontré ese intento.'; end if;
  return ts_intento_publico(t) || jsonb_build_object(
    'nombre', t.nombre, 'iniciado', t.iniciado_en, 'terminado', t.terminado_en,
    'detalle', (select coalesce(jsonb_agg(jsonb_build_object('paso', x ->> 'paso', 'titulo', p.titulo,
                                   'bloque', ts_bloque_nombre(x ->> 'bloque'), 'ok', (x ->> 'ok')::boolean, 'en', x ->> 'en')
                                 order by i), '[]'::jsonb)
                  from jsonb_array_elements(t.log) with ordinality u(x, i)
                  left join ts_pasos p on p.clave = x ->> 'paso'));
end $$;

create or replace function public.ts_admin_config(p_token uuid, p_cambios jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ts_admin_ok(p_token);
  update ts_config set
    nota_minima  = coalesce((p_cambios ->> 'nota_minima')::smallint, nota_minima),
    dias_ventana = coalesce((p_cambios ->> 'dias_ventana')::smallint, dias_ventana),
    aplica_desde = coalesce((p_cambios ->> 'aplica_desde')::date, aplica_desde),
    premio       = coalesce(nullif(btrim(p_cambios ->> 'premio'), ''), premio),
    cuentas      = case when p_cambios ? 'cuentas' then coalesce(p_cambios -> 'cuentas', '[]'::jsonb) else cuentas end,
    actualizado_en = now()
   where id = 'vigente';
  return (select to_jsonb(c) from ts_config c where id = 'vigente');
end $$;

create or replace function public.ts_admin_paso(p_token uuid, p_clave text, p_activo boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform ts_admin_ok(p_token);
  update ts_pasos set activo = coalesce(p_activo, activo) where clave = p_clave;
end $$;

create or replace function public.ts_admin_persona(p_token uuid, p_inscrito uuid, p_cambios jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p jsonb;
begin
  perform ts_admin_ok(p_token);
  insert into ts_personas (inscrito_id) values (p_inscrito) on conflict (inscrito_id) do nothing;
  update ts_personas set
    hasta    = case when p_cambios ? 'hasta' then nullif(p_cambios ->> 'hasta', '')::date else hasta end,
    excluido = coalesce((p_cambios ->> 'excluido')::boolean, excluido),
    nota     = case when p_cambios ? 'nota' then nullif(btrim(p_cambios ->> 'nota'), '') else nota end,
    actualizado_en = now()
   where inscrito_id = p_inscrito;
  p := n0_inscritos_json(p_inscrito) -> 0;
  return ts_resumen(p_inscrito, p ->> 'estado', (p ->> 'logro_fecha')::date, coalesce((p ->> 'excluido')::boolean, false));
end $$;

-- práctica de la oficina: el mismo test, sin persona y sin premio
create or replace function public.ts_admin_practicar(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid; t ts_intentos;
begin
  perform ts_admin_ok(p_token);
  insert into ts_intentos (inscrito_id, nombre, origen, plan, ctx)
  values (null, 'Práctica de la oficina', 'oficina', ts_plan(),
          jsonb_build_object('inicio', hoy_lima(), 'ey', ts_ey(hoy_lima())))
  returning id into v_id;
  perform ts_preparar(v_id);
  select * into t from ts_intentos where id = v_id;
  return ts_intento_publico(t);
end $$;

create or replace function public.ts_admin_responder(p_token uuid, p_intento uuid, p_pregunta text, p_respuesta jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform ts_admin_ok(p_token);
  if not exists (select 1 from ts_intentos where id = p_intento and origen = 'oficina') then
    raise exception 'Ese intento no es una práctica de la oficina.';
  end if;
  return ts_responder_int(p_intento, p_pregunta, p_respuesta);
end $$;

create or replace function public.ts_admin_anular(p_token uuid, p_intento uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform ts_admin_ok(p_token);
  update ts_intentos set anulado = true where id = p_intento and not coalesce(aprobado, false);
end $$;

-- =====================================================================
-- Permisos: solo las funciones de entrada se pueden llamar desde la web
-- =====================================================================
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'ts\_%'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('ts_estado', 'ts_iniciar', 'ts_responder', 'ts_admin_datos', 'ts_admin_intento', 'ts_admin_config',
                     'ts_admin_paso', 'ts_admin_persona', 'ts_admin_practicar', 'ts_admin_responder', 'ts_admin_anular') then
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end $$;
