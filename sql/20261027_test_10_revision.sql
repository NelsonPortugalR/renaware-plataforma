-- =====================================================================
-- Test del Nivel 0 · ajustes tras la revisión independiente
-- (el generador ts_generar / ts_opc_soles / ts_zonas_aqp se corrigió en 03)
-- 1) La nota de la oficina ya no le llega al asesor (ts_estado).
-- 2) Un solo intento abierto por persona; un intento anulado ya no se responde ni premia.
-- 3) Si una pregunta falla al armarse, ese paso sale del intento en vez de trabarlo.
-- 4) Botella sin duplicar y sin perderse: Empiece Ya nuevo pendiente → «sin botella» al toque;
--    deshacer una entrega (del Nivel 0 o del Empiece Ya) deshace el cruce; solo cuenta el
--    Empiece Ya de su ingreso (no uno de más de 14 días antes de inscribirse).
-- 5) Entrada: un número bloqueado no entra al test; ts_login ya no devuelve el nombre.
-- 6) Enlaces de consulta: solo http(s).
-- =====================================================================

-- ---------- 1) estado para el asesor, sin la nota interna ----------
create or replace function public.ts_estado(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_s jsonb; p jsonb; w jsonb; t ts_intentos;
begin
  v_s := ts_sesion(p_token);
  p := ts_persona_cel(v_s ->> 'celular');
  if p is null then
    return jsonb_build_object('nombre', v_s ->> 'nombre', 'estado', 'no_inscrito', 'config', ts_config_publica());
  end if;
  w := ts_ventana(p) - 'nota_persona';
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

-- ---------- 2) un solo intento abierto por persona ----------
create unique index if not exists ts_intentos_uno_abierto on public.ts_intentos (inscrito_id)
  where terminado_en is null and not anulado and origen = 'asesor';

create or replace function public.ts_iniciar(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_s jsonb; p jsonb; w jsonb; v_id uuid; t ts_intentos; v_inicio date;
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
  v_inicio := coalesce((p ->> 'inicio')::date, hoy_lima());
  begin
    insert into ts_intentos (inscrito_id, celular, nombre, origen, plan, ctx)
    values ((p ->> 'id')::uuid, cel_norm(v_s ->> 'celular'), p ->> 'nombre', 'asesor', ts_plan(),
            jsonb_build_object('inicio', v_inicio, 'ey', ts_ey(v_inicio)))
    returning id into v_id;
  exception when unique_violation then
    -- doble toque: ya se abrió uno, se sigue con ese
    select * into t from ts_intentos
     where inscrito_id = (p ->> 'id')::uuid and terminado_en is null and not anulado and origen = 'asesor';
    return ts_intento_publico(t);
  end;
  perform ts_preparar(v_id);
  select * into t from ts_intentos where id = v_id;
  return ts_intento_publico(t);
end $$;

-- ---------- 3) armar la pregunta sin trabar el intento ----------
create or replace function public.ts_generar_seguro(p_paso text, p_ctx jsonb, p_usados jsonb) returns jsonb
language plpgsql volatile set search_path = public as $$
begin
  return ts_generar(p_paso, p_ctx, p_usados);
exception when others then
  raise warning 'ts_generar(%) falló: %', p_paso, sqlerrm;
  return null;
end $$;

create or replace function public.ts_preparar(p_id uuid) returns void
language plpgsql volatile set search_path = public as $$
declare t ts_intentos; q jsonb; v_paso text; v_bloque text; cfg ts_config; v_nota int;
begin
  select * into cfg from ts_config where id = 'vigente';
  loop
    select * into t from ts_intentos where id = p_id for update;
    if t.anulado then return; end if;
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
    q := ts_generar_seguro(v_paso, t.ctx, coalesce(t.usados -> v_paso, '[]'::jsonb));
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

create or replace function public.ts_responder_int(p_id uuid, p_pregunta text, p_respuesta jsonb) returns jsonb
language plpgsql volatile set search_path = public as $$
declare t ts_intentos; ok boolean; q jsonb; v_paso text; v_nueva jsonb; v_dato text; v_logica text;
begin
  select * into t from ts_intentos where id = p_id for update;
  if not found then raise exception 'No encontré ese test.'; end if;
  if t.anulado then raise exception 'Ese intento se anuló. Vuelve a empezar tu test.'; end if;
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
    v_nueva := ts_generar_seguro(v_paso, t.ctx, coalesce(t.usados -> v_paso, '[]'::jsonb));
    if v_nueva is null then v_nueva := ts_generar_seguro(v_paso, t.ctx, '[]'::jsonb); end if;
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

create or replace function public.ts_responder(p_token uuid, p_intento uuid, p_pregunta text, p_respuesta jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_s jsonb; p jsonb; w jsonb; t ts_intentos;
begin
  v_s := ts_sesion(p_token);
  p := ts_persona_cel(v_s ->> 'celular');
  if p is not null then
    select * into t from ts_intentos
     where id = p_intento and origen = 'asesor' and inscrito_id = (p ->> 'id')::uuid;
  end if;
  if t.id is null then raise exception 'Ese test no es tuyo.'; end if;
  if t.anulado then raise exception 'Ese intento se anuló. Vuelve a empezar tu test.'; end if;
  -- pasado el plazo ya no hay test, tampoco para terminar uno empezado
  w := ts_ventana(p);
  if w ->> 'estado' = 'vencido' then
    raise exception 'Tu plazo para el test venció el %.', to_char((w ->> 'hasta')::date, 'DD/MM');
  end if;
  if w ->> 'estado' <> 'habilitado' then raise exception 'Tu test no está habilitado.'; end if;
  return ts_responder_int(p_intento, p_pregunta, p_respuesta);
end $$;

-- ---------- 4) la botella: sin duplicar y sin perderse ----------
create or replace function public.ts_sync_persona(p_inscrito uuid) returns void
language plpgsql volatile set search_path = public as $$
declare r pr_premios; p jsonb; v_cod text; v_real text; e n0_estado; ey pr_premios; v_desde date;
  c_junto constant text := 'Se entregó junto con su Empiece Ya.';
  c_sin constant text := 'Entregar sin botella: ya la recibió por el Nivel Cero.';
begin
  select * into r from pr_premios where clave = 'n0-' || p_inscrito;
  if not found then return; end if;
  p := n0_inscritos_json(p_inscrito) -> 0;
  v_cod := nullif(p ->> 'codigo', '');
  if v_cod is not null and r.codigo is distinct from v_cod then
    update pr_premios set codigo = v_cod, actualizado_en = now() where id = r.id returning * into r;
  end if;
  -- sin código de Rena Ware todavía (va "—" en Premios): no se cruza con ningún Empiece Ya
  v_real := case when r.codigo ~ '^\d{4,7}$' then r.codigo end;
  -- solo el Empiece Ya de su ingreso (no uno que terminó más de 14 días antes de que empezara)
  v_desde := coalesce((p ->> 'inicio')::date - 14, r.recibido_en - 90);

  -- Nivel Cero ya la marcó entregada
  select * into e from n0_estado where inscrito_id = p_inscrito;
  if e.botella_entregada_en is not null and r.entregado_en is null then
    update pr_premios
       set avisado_en = coalesce(avisado_en, e.botella_entregada_en), entregado_en = e.botella_entregada_en,
           actualizado_en = now()
     where id = r.id
    returning * into r;
  end if;

  -- Se cerró «junto con su Empiece Ya», pero ese Empiece Ya ya no figura entregado: se reabre
  if v_real is not null and r.entregado_en is not null and position(c_junto in coalesce(r.nota, '')) > 0
     and not exists (select 1 from pr_premios y
                      where y.programa ilike '%empiece ya%' and y.codigo = v_real
                        and y.entregado_en is not null and y.premio ilike '%botella de acero%'
                        and (y.origen <> 'declarado' or y.confirmado_en is not null) and y.periodo_fin >= v_desde) then
    update pr_premios
       set entregado_en = null,
           publicado_en = case when publicado_en >= entregado_en then null else publicado_en end,
           nota = nullif(btrim(replace(nota, c_junto, '')), ''), actualizado_en = now()
     where id = r.id
    returning * into r;
  end if;

  -- Su Empiece Ya (con botella de acero) ya se entregó: no se repite
  if r.entregado_en is null and v_real is not null then
    select * into ey from pr_premios
     where programa ilike '%empiece ya%' and codigo = v_real and entregado_en is not null
       and premio ilike '%botella de acero%' and (origen <> 'declarado' or confirmado_en is not null)
       and periodo_fin >= v_desde
     order by entregado_en limit 1;
    if found then
      update pr_premios
         set avisado_en = coalesce(avisado_en, ey.entregado_en), entregado_en = ey.entregado_en,
             publicado_en = coalesce(publicado_en, ey.publicado_en, ey.entregado_en),
             nota = concat_ws(' ', nullif(nota, ''), c_junto),
             actualizado_en = now()
       where id = r.id
      returning * into r;
    end if;
  end if;

  if v_real is not null then
    if r.entregado_en is not null and position(c_junto in coalesce(r.nota, '')) = 0 then
      -- La botella del Nivel 0 se entregó antes: su Empiece Ya pendiente va sin botella
      update pr_premios
         set nota = concat_ws(' ', nullif(nota, ''), c_sin), actualizado_en = now()
       where programa ilike '%empiece ya%' and codigo = v_real and entregado_en is null and periodo_fin >= v_desde
         and premio ilike '%botella de acero%' and position(c_sin in coalesce(nota, '')) = 0;
    elsif r.entregado_en is null then
      -- Se deshizo la entrega del Nivel 0: su Empiece Ya vuelve a llevar su botella
      update pr_premios
         set nota = nullif(btrim(replace(nota, c_sin, '')), ''), actualizado_en = now()
       where programa ilike '%empiece ya%' and codigo = v_real and position(c_sin in coalesce(nota, '')) > 0;
    end if;
  end if;
end $$;

create or replace function public.ts_tg_premios() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; v_cambio boolean;
begin
  v_cambio := tg_op = 'INSERT' or new.entregado_en is distinct from old.entregado_en or new.codigo is distinct from old.codigo;
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
    if v_cambio and new.codigo ~ '^\d{4,7}$' then
      perform ts_sync_persona(substr(new.clave, 4)::uuid);
    end if;
  elsif v_cambio and (new.programa ilike '%empiece ya%' or tg_op = 'UPDATE' and old.programa ilike '%empiece ya%') then
    -- un Empiece Ya nuevo, entregado o desmarcado (o con otro código): la botella del Nivel 0 se pone al día
    for r in select substr(clave, 4)::uuid as id from pr_premios
              where origen = 'nivel_cero' and clave like 'n0-%' and codigo ~ '^\d{4,7}$'
                and (codigo = new.codigo or tg_op = 'UPDATE' and codigo = old.codigo) loop
      perform ts_sync_persona(r.id);
    end loop;
  end if;
  return null;
end $$;

-- ---------- 5) entrada ----------
create or replace function public.ts_login(p_celular text, p_ctx jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cel text := cel_norm(p_celular); v_ip text := ip_cliente(); v_fallos int; v_acc jsonb; p jsonb; v_tok uuid;
begin
  v_acc := acceso_de(v_cel);
  if (v_acc ->> 'ok')::boolean then
    return (asesor_login(v_cel, coalesce(p_ctx, '{}'::jsonb)) - 'nombre') || jsonb_build_object('alcance', 'plataforma');
  end if;
  if v_acc ->> 'motivo' = 'bloqueado' then raise exception 'Ese número está bloqueado. Habla con tu líder.'; end if;
  select count(*) into v_fallos from login_intentos
   where ip = v_ip and not ok and creado > now() - interval '15 minutes';
  if v_fallos >= 10 then raise exception 'Demasiados intentos. Espera 15 minutos.'; end if;
  p := ts_persona_cel(v_cel);
  insert into login_intentos (ip, dato, ok) values (v_ip, v_cel, p is not null);
  if p is null then
    raise exception 'No encontramos tu inscripción en el Nivel Cero con ese número. Avísale a tu líder.';
  end if;
  insert into asesor_sesion (celular, dispositivo, navegador, so, pantalla, zona, idioma, ip, pais)
  values (v_cel, p_ctx ->> 'dispositivo', p_ctx ->> 'navegador', p_ctx ->> 'so', p_ctx ->> 'pantalla',
          p_ctx ->> 'zona', p_ctx ->> 'idioma', v_ip, pedir_header('cf-ipcountry'))
  returning token into v_tok;
  return jsonb_build_object('token', v_tok, 'celular', v_cel, 'alcance', 'test');
end $$;

create or replace function public.ts_sesion(p_token uuid) returns jsonb
language plpgsql volatile set search_path = public as $$
declare v_s jsonb; v_cel text; p jsonb;
begin
  v_s := asesor_sesion_valida(p_token);
  if coalesce((v_s ->> 'ok')::boolean, false) then return v_s; end if;
  select celular into v_cel from asesor_sesion where token = p_token;
  if v_cel is not null and (acceso_de(v_cel) ->> 'motivo') is distinct from 'bloqueado' then
    p := ts_persona_cel(v_cel);
    if p is not null then
      update asesor_sesion set ultimo_uso = now() where token = p_token;
      return jsonb_build_object('ok', true, 'nombre', p ->> 'nombre', 'celular', v_cel);
    end if;
  end if;
  raise exception 'Tu sesión venció. Vuelve a entrar con tu celular.';
end $$;

-- ---------- 6) enlaces de consulta: solo http(s) ----------
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
    recursos     = case when p_cambios ? 'recursos'
                        then coalesce((select jsonb_agg(jsonb_build_object('nombre', btrim(x ->> 'nombre'), 'url', btrim(x ->> 'url')))
                                         from jsonb_array_elements(p_cambios -> 'recursos') x
                                        where btrim(x ->> 'url') ~* '^https?://[^\s]+$'), '[]'::jsonb)
                        else recursos end,
    actualizado_en = now()
   where id = 'vigente';
  return (select to_jsonb(c) from ts_config c where id = 'vigente');
end $$;

-- ---------- permisos de lo nuevo ----------
revoke all on function public.ts_generar_seguro(text, jsonb, jsonb) from public, anon, authenticated;
