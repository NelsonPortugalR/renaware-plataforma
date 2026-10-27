-- =====================================================================
-- Test del Nivel 0 · entrada con DNI y aprobación al terminar
-- Pedido de Nelson (27/10): un solo enlace que se copia y pega; el asesor entra
-- con su DNI, el celular lo recuerda y no pierde lo avanzado. Por ahora aprueba
-- todo el que termina el test; la nota se registra igual (luego se podrá pedir
-- una nota mínima, p. ej. el promedio).
-- 1) ts_sesiones: sesión solo para el test, ligada al inscrito (no sirve para la
--    plataforma, aunque la persona ya sea asesor del equipo).
-- 2) ts_entrar(documento): DNI (o carné), y también su celular por si acaso.
-- 3) ts_sesion / ts_persona_de: la sesión del test lleva al inscrito exacto.
-- 4) ts_config.exigir_nota (false): aprueba al terminar; con true vuelve a pedir
--    nota_minima. ts_config_publica y el final del intento lo informan.
-- =====================================================================

-- ---------- 1) sesiones del test ----------
create table if not exists public.ts_sesiones (
  token       uuid primary key default gen_random_uuid(),
  inscrito_id uuid not null,
  documento   text,
  creada      timestamptz not null default now(),
  ultimo_uso  timestamptz not null default now(),
  dispositivo text, navegador text, so text, pantalla text, zona text, idioma text, ip text, pais text
);
create index if not exists ts_sesiones_inscrito on public.ts_sesiones (inscrito_id);
alter table public.ts_sesiones enable row level security;
revoke all on table public.ts_sesiones from anon, authenticated;

-- ---------- 2) buscar por documento y entrar ----------
create or replace function public.ts_doc_norm(t text) returns text
language sql immutable as $$ select upper(regexp_replace(coalesce(t, ''), '[^0-9A-Za-z]', '', 'g')) $$;

-- El inscrito del Nivel Cero con ese DNI (si hay más de uno, el que logró sus clases o el más reciente)
create or replace function public.ts_persona_dni(p_doc text) returns jsonb
language plpgsql stable set search_path = public as $$
declare v jsonb; r record; mejor jsonb; d text := ts_doc_norm(p_doc);
begin
  if d ~ '^\d{7}$' then d := lpad(d, 8, '0'); end if;   -- DNI escrito sin el 0 de adelante
  if length(d) < 8 then return null; end if;
  for r in select i.id from n0_inscritos i
            where ts_doc_norm(i.dni) = d or (d ~ '^\d{8}$' and ts_doc_norm(i.dni) ~ '^\d{7}$' and lpad(ts_doc_norm(i.dni), 8, '0') = d) loop
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

create or replace function public.ts_entrar(p_doc text, p_ctx jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_doc text := ts_doc_norm(p_doc); v_ip text := ip_cliente(); v_fallos int; p jsonb; v_tok uuid;
begin
  if v_doc ~ '^\d{7}$' then v_doc := lpad(v_doc, 8, '0'); end if;
  select count(*) into v_fallos from login_intentos
   where ip = v_ip and not ok and creado > now() - interval '15 minutes';
  if v_fallos >= 10 then raise exception 'Demasiados intentos. Espera 15 minutos.'; end if;
  p := ts_persona_dni(v_doc);
  if p is null and v_doc ~ '^9\d{8}$' then p := ts_persona_cel(v_doc); end if;   -- también vale su celular
  insert into login_intentos (ip, dato, ok) values (v_ip, 'test:' || v_doc, p is not null);
  if p is null then
    raise exception 'No encontramos ese DNI en el Nivel Cero. Revísalo o avísale a tu líder.';
  end if;
  if (acceso_de(p ->> 'celular') ->> 'motivo') = 'bloqueado' then
    raise exception 'Tu acceso está bloqueado. Habla con tu líder.';
  end if;
  insert into ts_sesiones (inscrito_id, documento, dispositivo, navegador, so, pantalla, zona, idioma, ip, pais)
  values ((p ->> 'id')::uuid, v_doc, p_ctx ->> 'dispositivo', p_ctx ->> 'navegador', p_ctx ->> 'so', p_ctx ->> 'pantalla',
          p_ctx ->> 'zona', p_ctx ->> 'idioma', v_ip, pedir_header('cf-ipcountry'))
  returning token into v_tok;
  return jsonb_build_object('token', v_tok, 'alcance', 'test');
end $$;

-- ---------- 3) la sesión lleva al inscrito exacto ----------
create or replace function public.ts_sesion(p_token uuid) returns jsonb
language plpgsql volatile set search_path = public as $$
declare v_s jsonb; v_cel text; p jsonb; s ts_sesiones;
begin
  -- sesión del test (con DNI)
  select * into s from ts_sesiones where token = p_token;
  if found then
    p := n0_inscritos_json(s.inscrito_id) -> 0;
    if p is not null and (acceso_de(p ->> 'celular') ->> 'motivo') is distinct from 'bloqueado' then
      update ts_sesiones set ultimo_uso = now() where token = p_token;
      return jsonb_build_object('ok', true, 'nombre', p ->> 'nombre', 'celular', p ->> 'celular', 'inscrito_id', s.inscrito_id);
    end if;
    raise exception 'Tu sesión venció. Vuelve a entrar con tu DNI.';
  end if;
  -- sesión de la plataforma
  v_s := asesor_sesion_valida(p_token);
  if coalesce((v_s ->> 'ok')::boolean, false) then return v_s; end if;
  -- sesión del test con celular (la de antes)
  select celular into v_cel from asesor_sesion where token = p_token;
  if v_cel is not null and (acceso_de(v_cel) ->> 'motivo') is distinct from 'bloqueado' then
    p := ts_persona_cel(v_cel);
    if p is not null then
      update asesor_sesion set ultimo_uso = now() where token = p_token;
      return jsonb_build_object('ok', true, 'nombre', p ->> 'nombre', 'celular', v_cel);
    end if;
  end if;
  raise exception 'Tu sesión venció. Vuelve a entrar con tu DNI.';
end $$;

create or replace function public.ts_persona_de(v_s jsonb) returns jsonb
language sql stable set search_path = public as $$
  select case when v_s ? 'inscrito_id' then n0_inscritos_json((v_s ->> 'inscrito_id')::uuid) -> 0
              else ts_persona_cel(v_s ->> 'celular') end
$$;

create or replace function public.ts_estado(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_s jsonb; p jsonb; w jsonb; t ts_intentos;
begin
  v_s := ts_sesion(p_token);
  p := ts_persona_de(v_s);
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

create or replace function public.ts_iniciar(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_s jsonb; p jsonb; w jsonb; v_id uuid; t ts_intentos; v_inicio date;
begin
  v_s := ts_sesion(p_token);
  p := ts_persona_de(v_s);
  if p is null then raise exception 'No encontramos tu inscripción en el Nivel Cero. Avísale a tu líder.'; end if;
  w := ts_ventana(p);
  if (w ->> 'abierto') is not null then
    select * into t from ts_intentos where id = (w ->> 'abierto')::uuid;
    return ts_intento_publico(t);
  end if;
  if w ->> 'estado' = 'aprobado' then raise exception 'Ya terminaste tu test.'; end if;
  if w ->> 'estado' = 'vencido' then raise exception 'Tu plazo para el test venció el %.', to_char((w ->> 'hasta')::date, 'DD/MM'); end if;
  if w ->> 'estado' <> 'habilitado' then raise exception 'Tu test se habilita al completar tus 5 clases.'; end if;
  v_inicio := coalesce((p ->> 'inicio')::date, hoy_lima());
  begin
    insert into ts_intentos (inscrito_id, celular, nombre, origen, plan, ctx)
    values ((p ->> 'id')::uuid, cel_norm(coalesce(v_s ->> 'celular', p ->> 'celular')), p ->> 'nombre', 'asesor', ts_plan(),
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

create or replace function public.ts_responder(p_token uuid, p_intento uuid, p_pregunta text, p_respuesta jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_s jsonb; p jsonb; w jsonb; t ts_intentos;
begin
  v_s := ts_sesion(p_token);
  p := ts_persona_de(v_s);
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

-- ---------- 4) aprueba al terminar (la nota se registra igual) ----------
alter table public.ts_config add column if not exists exigir_nota boolean not null default false;

create or replace function public.ts_preparar(p_id uuid) returns void
language plpgsql volatile set search_path = public as $$
declare t ts_intentos; q jsonb; v_paso text; v_bloque text; cfg ts_config; v_nota int; v_aprueba boolean;
begin
  select * into cfg from ts_config where id = 'vigente';
  loop
    select * into t from ts_intentos where id = p_id for update;
    if t.anulado then return; end if;
    if t.paso_idx >= cardinality(t.plan) then
      v_nota := round(100.0 * cardinality(t.plan) / greatest(t.intentos, 1));
      -- sin nota mínima, aprueba todo el que termina; con nota mínima, la de Ajustes
      v_aprueba := not coalesce(cfg.exigir_nota, false) or v_nota >= cfg.nota_minima;
      update ts_intentos
         set pregunta = null, terminado_en = coalesce(terminado_en, now()),
             nota = v_nota, aprobado = v_aprueba
       where id = p_id;
      if v_aprueba and t.origen = 'asesor' and t.inscrito_id is not null then
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

create or replace function public.ts_config_publica() returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('nota_minima', nota_minima, 'exigir_nota', exigir_nota, 'dias_ventana', dias_ventana,
                            'premio', premio, 'pasos', cardinality(ts_plan()), 'recursos', recursos)
    from ts_config where id = 'vigente'
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
             'exigir_nota', (select exigir_nota from ts_config where id = 'vigente'),
             'pasos', cardinality(t.plan), 'intentos', t.intentos, 'errores', t.intentos - t.aciertos,
             'minutos', round(extract(epoch from (t.terminado_en - t.iniciado_en)) / 60.0),
             'por_bloque', ts_errores_bloque(t.log)) end)
$$;

create or replace function public.ts_admin_config(p_token uuid, p_cambios jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ts_admin_ok(p_token);
  update ts_config set
    nota_minima  = coalesce((p_cambios ->> 'nota_minima')::smallint, nota_minima),
    exigir_nota  = coalesce((p_cambios ->> 'exigir_nota')::boolean, exigir_nota),
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

-- ---------- permisos ----------
grant execute on function public.ts_entrar(text, jsonb) to anon, authenticated;
revoke all on function public.ts_doc_norm(text) from public, anon, authenticated;
revoke all on function public.ts_persona_dni(text) from public, anon, authenticated;
revoke all on function public.ts_persona_de(jsonb) from public, anon, authenticated;
