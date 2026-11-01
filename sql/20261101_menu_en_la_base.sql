-- ============================================================================
-- El menú del hub vive en la base (01/11/2026). APLICADO con execute_sql.
--
-- Antes: el hub tenía escrito en su código a qué grupo iba cada módulo
-- (Ventas/Equipo/Oficina) y filtraba a mano el Test del Nivel 0 para los
-- asesores. Un módulo nuevo caía en «Otros» hasta tocar el hub.
--
-- Ahora: plataforma_modulos dice el grupo y la condición de visibilidad, y
-- plataforma_menu() devuelve a cada persona exactamente los módulos que le
-- tocan. Registrar un módulo = una fila. El hub solo pinta.
-- ============================================================================

-- 1) Dos columnas más en la tabla de módulos
alter table public.plataforma_modulos add column if not exists grupo text;
alter table public.plataforma_modulos add column if not exists visible_fn text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'plataforma_modulos_visible_fn_chk') then
    alter table public.plataforma_modulos add constraint plataforma_modulos_visible_fn_chk
      check (visible_fn is null or visible_fn ~ '^[a-z_][a-z0-9_]*$');
  end if;
end $$;
comment on column public.plataforma_modulos.grupo is
  'Encabezado bajo el que el hub muestra el módulo: Vender, Pedidos, Equipo, Oficina. Sin grupo cae en «Otros» y lo marca plataforma_salud().';
comment on column public.plataforma_modulos.visible_fn is
  'Nombre de una función (p_token uuid) returns boolean que decide si el módulo se le muestra a ese asesor (null de token = equipo de oficina). Sin función: lo ven todos los de sus roles.';

-- 2) Condiciones de visibilidad, cada una con el prefijo de su módulo
-- Test del Nivel 0: solo los nuevos inscritos en el Nivel Cero (el equipo de oficina siempre)
create or replace function public.ts_visible(p_token uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_e text;
begin
  if p_token is null then return true; end if;
  begin
    v_e := ts_estado(p_token) ->> 'estado';
  exception when others then
    return false;
  end;
  return v_e is not null and v_e <> 'no_inscrito';
end $$;
grant execute on function public.ts_visible(uuid) to anon, authenticated;

-- Local del equipo: solo las socias activas del local (el equipo de oficina siempre)
create or replace function public.loc_visible(p_token uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_token is null
      or exists (select 1
                   from asesor_sesion s
                   join eq_personas p on cel_norm(p.celular) = s.celular
                   join loc_personas lp on lp.asesor_id = p.id and lp.activo
                  where s.token = p_token)
$$;
grant execute on function public.loc_visible(uuid) to anon, authenticated;

-- 3) El menú de cada persona, decidido en la base
create or replace function public.plataforma_menu(p_token uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_rol text; m record; v_vis boolean; v_out jsonb := '[]'::jsonb;
begin
  if p_token is null then
    select rol into v_rol from perfiles where user_id = auth.uid() and activo;
    if v_rol is null then
      raise exception 'Tu cuenta no tiene un rol asignado. Pídeselo al administrador.';
    end if;
  else
    if not coalesce((asesor_sesion_valida(p_token) ->> 'ok')::boolean, false) then
      raise exception 'Tu sesión venció. Vuelve a entrar con tu celular.';
    end if;
    v_rol := 'asesor';
  end if;
  for m in select * from plataforma_modulos where activo and v_rol = any(roles) order by orden, id loop
    v_vis := true;
    if m.visible_fn is not null then
      begin
        execute format('select public.%I($1)', m.visible_fn) into v_vis using p_token;
      exception when others then
        v_vis := false;   -- si la condición falla, el módulo no se muestra y el menú no se cae
      end;
    end if;
    if coalesce(v_vis, false) then
      v_out := v_out || jsonb_build_object('id', m.id, 'nombre', m.nombre, 'descripcion', m.descripcion, 'url', m.url,
                                           'roles', to_jsonb(m.roles), 'orden', m.orden, 'acceso', m.acceso, 'grupo', m.grupo);
    end if;
  end loop;
  return v_out;
end $$;
grant execute on function public.plataforma_menu(uuid) to anon, authenticated;

-- 4) Los módulos que faltaban en el hub
insert into public.plataforma_modulos (id, nombre, descripcion, url, roles, acceso, activo, orden, grupo, visible_fn) values
  ('zonas', 'Zonas de crédito', 'Dónde sí hay crédito y dónde no.',
   'https://zonas-de-credito.nelson1614.workers.dev', array['admin','asistente','gestor','asesor'], 'libre', true, 2, 'Vender', null),
  ('local', 'Local del equipo', 'Turnos del local: confirmar, ofrecer, cambiar.',
   'https://local-equipo-arequipa.nelson1614.workers.dev', array['admin','asistente','asesor'], 'libre', true, 26, 'Equipo', 'loc_visible')
on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, url = excluded.url,
  roles = excluded.roles, acceso = excluded.acceso, activo = true, orden = excluded.orden, grupo = excluded.grupo, visible_fn = excluded.visible_fn;

-- 5) Grupo, orden y una descripción que cabe en una línea del celular
update public.plataforma_modulos set grupo = 'Vender',  orden = 0 where id = 'chat';   -- el hub lo pinta como caja de pregunta, no como tarjeta
update public.plataforma_modulos set grupo = 'Vender',  orden = 1,  descripcion = 'Listas vigentes, especiales, repuestos y puntos.' where id = 'cotizador';
update public.plataforma_modulos set grupo = 'Vender',  orden = 3,  descripcion = 'El formulario para ingresar ventas y afiliaciones.' where id = 'registro';
update public.plataforma_modulos set grupo = 'Pedidos', orden = 11, descripcion = 'Revisa y da seguimiento a cada registro.' where id = 'admin-registros';
update public.plataforma_modulos set grupo = 'Pedidos', orden = 12, descripcion = 'Órdenes oficiales y seguimiento post-venta.' where id = 'pedidos';
update public.plataforma_modulos set grupo = 'Pedidos', orden = 13, descripcion = 'Carga el reporte oficial de pedidos.' where id = 'importar-pedidos';
update public.plataforma_modulos set grupo = 'Pedidos', orden = 14, descripcion = 'Cruza cada venta con su pedido oficial.' where id = 'conciliar';
update public.plataforma_modulos set grupo = 'Equipo',  orden = 21, descripcion = 'De lo declarado a lo entregado y publicado.' where id in ('premios', 'equipo');
update public.plataforma_modulos set grupo = 'Equipo',  orden = 22, descripcion = 'Resultados oficiales por período.' where id = 'empiece-ya';
update public.plataforma_modulos set grupo = 'Equipo',  orden = 23, descripcion = 'Asistencia de los nuevos: 5 clases en 30 días.' where id = 'nivel-cero';
update public.plataforma_modulos set grupo = 'Equipo',  orden = 24, descripcion = 'Lo rinden los nuevos al terminar el Nivel 0.', visible_fn = 'ts_visible' where id = 'test';
update public.plataforma_modulos set grupo = 'Equipo',  orden = 25, descripcion = 'Mensajes de bienvenida y seguimiento del Nivel 0.' where id = 'bienvenida';
update public.plataforma_modulos set grupo = 'Oficina', orden = 31, descripcion = 'Lo que los clientes dejan en la oficina.' where id = 'reparaciones';
update public.plataforma_modulos set grupo = 'Oficina', orden = 32, descripcion = 'Qué falta facturar y que ninguna declaración venza.' where id = 'facturacion';

-- 6) plataforma_salud() también avisa de módulos activos sin grupo o cuya visible_fn no existe
--    (nuevo hallazgo 'modulos_sin_grupo_o_sin_condicion'; la tarjeta de Hoy lo lee). Aplicado con
--    create or replace de plataforma_salud() (misma función que en 20261031_plataforma_salud.sql más el CTE
--    modulos_sin_grupo) y un replace() sobre el cuerpo de hoy_items_v2 que agrega la frase al detalle.
--
-- Comprobado el 01/11: asesora sin nada → cotizador, zonas; socia del local → + local;
-- inscrita en Nivel Cero → + test; admin → Vender(chat, cotizador, zonas, registro) ·
-- Pedidos(admin-registros, pedidos, importar-pedidos, conciliar) · Equipo(premios, empiece-ya,
-- nivel-cero, test, bienvenida, local) · Oficina(reparaciones, facturacion).
