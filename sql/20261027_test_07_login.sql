-- =====================================================================
-- Test del Nivel 0 · entrada con el celular
-- Muchos nuevos todavía no figuran en el equipo (eq_personas) y la plataforma
-- no los deja entrar. Para el test basta con estar inscrito en el Nivel Cero:
-- ts_login da una sesión de asesor_sesion que solo sirve para el test
-- (la plataforma la sigue rechazando). Quien sí tiene acceso entra normal
-- (asesor_login) y queda con sesión en toda la plataforma.
-- =====================================================================

create or replace function public.ts_login(p_celular text, p_ctx jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cel text := cel_norm(p_celular); v_ip text := ip_cliente(); v_fallos int; p jsonb; v_tok uuid;
begin
  if (acceso_de(v_cel) ->> 'ok')::boolean then
    return asesor_login(v_cel, coalesce(p_ctx, '{}'::jsonb)) || jsonb_build_object('alcance', 'plataforma');
  end if;
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
  return jsonb_build_object('token', v_tok, 'nombre', p ->> 'nombre', 'celular', v_cel, 'alcance', 'test');
end $$;

-- La sesión vale si la plataforma la acepta, o si ese celular está inscrito en el Nivel Cero.
create or replace function public.ts_sesion(p_token uuid) returns jsonb
language plpgsql volatile set search_path = public as $$
declare v_s jsonb; v_cel text; p jsonb;
begin
  v_s := asesor_sesion_valida(p_token);
  if coalesce((v_s ->> 'ok')::boolean, false) then return v_s; end if;
  select celular into v_cel from asesor_sesion where token = p_token;
  if v_cel is not null then
    p := ts_persona_cel(v_cel);
    if p is not null then
      update asesor_sesion set ultimo_uso = now() where token = p_token;
      return jsonb_build_object('ok', true, 'nombre', p ->> 'nombre', 'celular', v_cel);
    end if;
  end if;
  raise exception 'Tu sesión venció. Vuelve a entrar con tu celular.';
end $$;

revoke all on function public.ts_login(text, jsonb) from public, anon, authenticated;
grant execute on function public.ts_login(text, jsonb) to anon, authenticated;
revoke all on function public.ts_sesion(uuid) from public, anon, authenticated;
