-- ============================================================================
-- Acceso único por traspaso
-- El hub entra una sola vez. Al abrir un módulo, crea un código de un solo uso
-- (vence en 2 minutos) y lo pasa en el enlace (#traspaso=<código>). El módulo lo
-- canjea y recibe la credencial que usa: sesión de Supabase (correo), token de
-- admin (es_admin) o token de asesor (celular). Nada de contraseñas en enlaces.
-- ============================================================================

create table public.traspasos (
  codigo uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('staff','asesor')),
  user_id uuid references auth.users(id) on delete cascade,
  asesor_token uuid,
  destino text,
  creado_en timestamptz not null default now(),
  expira_en timestamptz not null default now() + interval '2 minutes',
  usado_en timestamptz
);
comment on table public.traspasos is 'Códigos de un solo uso para pasar la sesión del hub a cada módulo. Solo los tocan las funciones.';
alter table public.traspasos enable row level security;
-- Sin políticas: ni anon ni authenticated leen o escriben la tabla directamente.

-- ---- El hub, con cuenta (correo), crea un código --------------------------
create function public.traspaso_crear(p_destino text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_codigo uuid;
begin
  if not exists (select 1 from perfiles where user_id = auth.uid() and activo) then
    raise exception 'Tu cuenta no tiene un rol asignado.';
  end if;
  delete from traspasos where creado_en < now() - interval '1 day';   -- limpieza barata
  insert into traspasos (tipo, user_id, destino) values ('staff', auth.uid(), p_destino)
  returning codigo into v_codigo;
  return v_codigo;
end $$;
revoke execute on function public.traspaso_crear(text) from public, anon;
grant execute on function public.traspaso_crear(text) to authenticated, service_role;

-- ---- El hub, con sesión de asesor (celular), crea un código ----------------
create function public.traspaso_crear_asesor(p_token uuid, p_destino text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_s jsonb; v_codigo uuid;
begin
  v_s := asesor_sesion_valida(p_token);
  if not coalesce((v_s->>'ok')::boolean, false) then
    raise exception 'Tu sesión venció. Vuelve a entrar con tu celular.';
  end if;
  insert into traspasos (tipo, asesor_token, destino) values ('asesor', p_token, p_destino)
  returning codigo into v_codigo;
  return v_codigo;
end $$;
revoke execute on function public.traspaso_crear_asesor(uuid, text) from public;
grant execute on function public.traspaso_crear_asesor(uuid, text) to anon, authenticated, service_role;

-- ---- Consumo del código (una sola vez, dentro del plazo) ------------------
-- La llama la Edge Function "traspaso" con la llave de servicio. Devuelve lo
-- que necesita el módulo: para staff, correo + rol + token de admin (la sesión
-- de Supabase la fabrica la Edge Function); para asesor, el token de asesor.
create function public.traspaso_consumir(p_codigo uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t traspasos; v_email text; v_nombre text; v_rol text; v_admin uuid; v_s jsonb;
begin
  select * into t from traspasos where codigo = p_codigo for update;
  if not found or t.usado_en is not null or t.expira_en < now() then
    return jsonb_build_object('ok', false, 'motivo', 'El enlace ya se usó o venció. Vuelve a abrirlo desde la plataforma.');
  end if;
  update traspasos set usado_en = now() where codigo = p_codigo;

  if t.tipo = 'asesor' then
    v_s := asesor_sesion_valida(t.asesor_token);
    if not coalesce((v_s->>'ok')::boolean, false) then
      return jsonb_build_object('ok', false, 'motivo', 'La sesión del asesor ya no es válida.');
    end if;
    return jsonb_build_object('ok', true, 'tipo', 'asesor', 'token', t.asesor_token,
                              'nombre', v_s->>'nombre', 'celular', v_s->>'celular');
  end if;

  select u.email, p.nombre, p.rol into v_email, v_nombre, v_rol
    from auth.users u join perfiles p on p.user_id = u.id
   where u.id = t.user_id and p.activo;
  if v_email is null then
    return jsonb_build_object('ok', false, 'motivo', 'La cuenta ya no está activa.');
  end if;
  -- Token para los módulos que validan con es_admin (precios, Nivel Cero, bienvenida, reparaciones)
  if v_rol in ('admin', 'asistente') then
    insert into admin_sesion default values returning token into v_admin;
  end if;
  return jsonb_build_object('ok', true, 'tipo', 'staff', 'email', v_email, 'nombre', v_nombre,
                            'rol', v_rol, 'admin_token', v_admin, 'destino', t.destino);
end $$;
revoke execute on function public.traspaso_consumir(uuid) from public, anon, authenticated;
grant execute on function public.traspaso_consumir(uuid) to service_role;

-- ---- Canje directo para asesores (sin pasar por la Edge Function) ---------
create function public.traspaso_canjear_asesor(p_codigo uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t traspasos; v_s jsonb;
begin
  select * into t from traspasos where codigo = p_codigo and tipo = 'asesor' for update;
  if not found or t.usado_en is not null or t.expira_en < now() then
    return jsonb_build_object('ok', false, 'motivo', 'El enlace ya se usó o venció. Vuelve a abrirlo desde la plataforma.');
  end if;
  update traspasos set usado_en = now() where codigo = p_codigo;
  v_s := asesor_sesion_valida(t.asesor_token);
  if not coalesce((v_s->>'ok')::boolean, false) then
    return jsonb_build_object('ok', false, 'motivo', 'La sesión del asesor ya no es válida.');
  end if;
  return jsonb_build_object('ok', true, 'tipo', 'asesor', 'token', t.asesor_token,
                            'nombre', v_s->>'nombre', 'celular', v_s->>'celular');
end $$;
revoke execute on function public.traspaso_canjear_asesor(uuid) from public;
grant execute on function public.traspaso_canjear_asesor(uuid) to anon, authenticated, service_role;
