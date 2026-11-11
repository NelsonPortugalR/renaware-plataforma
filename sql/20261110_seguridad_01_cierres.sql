-- =====================================================================================================
-- Seguridad, primera tanda (10 y 11 de noviembre de 2026). Todo aplicado en la base; este archivo es la copia.
-- Sale de la revisión claude/revision-plataforma-2026-11.md. Nada de esto cambia el trabajo diario:
-- quien tiene sesión de la oficina ve exactamente lo mismo que antes (se comparó tabla por tabla).
--
-- Para deshacer algo puntual:
--   · el listado de Facturación:      grant select on public.fact_listos to anon;
--   · las políticas con perfil:       alter policy <nombre> on public.<tabla> using (true) [with check (true)];
--   · el vencimiento de sesiones:     volver a crear es_admin() sin la condición de ultimo_uso.
-- =====================================================================================================

-- 1) El listado de Facturación (RUC, cuentas, CCI) ya no se lee sin sesión, ni con una cuenta cualquiera:
--    la vista pasa a leer con los permisos de quien pregunta, y sus tablas exigen perfil de la oficina.
revoke all on public.fact_listos from anon;
alter view public.fact_listos set (security_invoker = on);
alter view public.v_listas_vigentes set (security_invoker = on);   -- catálogo: sigue abierto, pero por sus propias políticas

-- 2) Las sesiones de administrador vencen a los 30 días sin uso (antes no vencían nunca).
create or replace function public.es_admin(p_token uuid)
returns boolean language plpgsql security definer set search_path to 'public' as $$
begin
  if p_token is null then return false; end if;
  update admin_sesion set ultimo_uso = now()
   where token = p_token and not revocada and ultimo_uso > now() - interval '30 days';
  return found;
end $$;
update admin_sesion set revocada = true where not revocada and ultimo_uso < now() - interval '30 days';

-- 3) Las tablas que confiaban en «cualquier cuenta con correo» ahora exigen un perfil activo de la oficina.
--    Eran 46 políticas con condición «true» para el rol authenticated.
do $$
declare r record; v_expr text := 'public.tiene_rol(''admin'', ''asistente'', ''gestor'')';
begin
  for r in
    select c.relname as tabla, p.polname as pol,
           p.polqual is not null as con_using, p.polwithcheck is not null as con_check
      from pg_policy p join pg_class c on c.oid = p.polrelid
     where c.relnamespace = 'public'::regnamespace
       and p.polroles::regrole[]::text = '{authenticated}'
       and coalesce(pg_get_expr(p.polqual, p.polrelid), 'true') = 'true'
       and coalesce(pg_get_expr(p.polwithcheck, p.polrelid), 'true') = 'true'
  loop
    if r.con_using and r.con_check then
      execute format('alter policy %I on public.%I using (%s) with check (%s)', r.pol, r.tabla, v_expr, v_expr);
    elsif r.con_using then
      execute format('alter policy %I on public.%I using (%s)', r.pol, r.tabla, v_expr);
    elsif r.con_check then
      execute format('alter policy %I on public.%I with check (%s)', r.pol, r.tabla, v_expr);
    end if;
  end loop;
end $$;

-- 4) Archivos: documentos de clientes, plantillas y fotos de premios, solo para la oficina.
alter policy "admin ve archivos" on storage.objects using (bucket_id = 'documentos' and public.tiene_rol('admin', 'asistente', 'gestor'));
alter policy "admin sube archivos" on storage.objects with check (bucket_id = 'documentos' and public.tiene_rol('admin', 'asistente', 'gestor'));
alter policy "admin sube plantillas" on storage.objects with check (bucket_id = 'plantillas' and public.tiene_rol('admin', 'asistente', 'gestor'));
alter policy "admin actualiza plantillas" on storage.objects using (bucket_id = 'plantillas' and public.tiene_rol('admin', 'asistente', 'gestor'));
alter policy premios_escribe_autenticado on storage.objects with check (bucket_id = 'premios' and public.tiene_rol('admin', 'asistente', 'gestor'));
alter policy premios_actualiza_autenticado on storage.objects using (bucket_id = 'premios' and public.tiene_rol('admin', 'asistente', 'gestor')) with check (bucket_id = 'premios' and public.tiene_rol('admin', 'asistente', 'gestor'));
alter policy premios_borra_autenticado on storage.objects using (bucket_id = 'premios' and public.tiene_rol('admin', 'asistente', 'gestor'));

-- 5) acceso_de(celular) devolvía el nombre de la persona a cualquiera que probara un número.
--    Solo la usan por dentro asesor_login, asesor_sesion_valida y el test; ya no se puede llamar desde fuera.
revoke execute on function public.acceso_de(text) from public, anon, authenticated;

-- 6) Vigencia: el reporte FPD se carga por dos caminos y solo se miraba uno (alarma falsa de 22 días).
update public.plataforma_fuentes
   set ultima_sql = 'select greatest((select max(cargado_en) from fact_carga_fpd), (select max(cargado_en) from fact_fpd_snapshot))::date',
       nota = 'Cuenta la carga del reporte por cualquiera de sus dos caminos (fact_carga_fpd o fact_fpd_snapshot).',
       actualizado_en = now()
 where id = 'reporte-fpd';

-- 7) plataforma_salud() deja de tener puntos ciegos. Además de lo que ya miraba, ahora avisa de:
--      · funciones públicas que entregan datos de clientes o asesores sin pedir sesión,
--      · vistas que leen con los permisos de su dueño (se saltan las políticas),
--      · tablas abiertas a cualquier cuenta con correo,
--      · carpetas de archivos donde cualquiera puede subir o reemplazar.
--    «de_seguridad» cuenta solo lo que es puerta abierta; «hallazgos» sigue siendo el total.
create or replace function public.plataforma_salud()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
with catalogos as (
  select unnest(array['productos','cot_servicios','cot_grupos','listas_precios','piezas','pieza_alias','factores_credito','reglas_credito','site_config',
                      'zc_zonas','zc_distritos','zc_config','zc_cargas','wa_mensajes','wa_secuencias','plataforma_modulos','organizaciones',
                      'eya_historico','eya_premios','eya_periodos','eya_items','eya_item_alias',
                      'loc_turnos','loc_propuestas','loc_eventos','loc_config','loc_personas','loc_cobros','loc_pagos','loc_continuidad']) as t
),
abiertas_a_proposito as (
  -- funciones que se dejan abiertas sin sesión porque así trabaja el módulo; cada una con su porqué
  select * from (values
    ('web_datos',  'cifras agregadas de la web pública'),
    ('ent_ruta_ok','solo valida un boleto de subida ya emitido')
  ) as x(fn, motivo)
),
pol as (
  -- políticas que de verdad abren la puerta sin sesión: para anon/public y sin condición de rol
  select p.tablename, p.policyname, p.cmd
    from pg_policies p
   where p.schemaname = 'public' and ('anon' = any(p.roles) or 'public' = any(p.roles))
     and coalesce(p.qual, 'true') !~ 'tiene_rol|auth\.uid|es_admin'
     and coalesce(p.with_check, 'true') !~ 'tiene_rol|auth\.uid|es_admin'
),
escritura_anon as (
  select tablename, string_agg(policyname || '[' || cmd || ']', ', ') as politicas
    from pol where cmd <> 'SELECT' group by tablename
),
lectura_anon_no_catalogo as (
  select tablename from pol where cmd in ('SELECT','ALL') and tablename not in (select t from catalogos) group by tablename
),
sin_rls as (
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
),
definer_anon as (
  select p.proname, p.prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.prosecdef
     and p.prorettype <> 'trigger'::regtype
     and has_function_privilege('anon', p.oid, 'EXECUTE')
     and not (p.prosrc ~* 'es_admin\s*\(|auth\.uid|tiene_rol|asesor_sesion_valida|loc_sesion_persona|loc_admin_ok|ts_sesion|p_token|p_pin|login_intentos|traspaso_consumir|reg_sesion')
),
definer_anon_sin_chequeo as (
  select proname from definer_anon
   where prosrc ~* '\m(insert|update|delete|truncate)\M'
),
lectura_personas_sin_sesion as (
  -- funciones que cualquiera puede llamar y que leen datos de clientes o asesores sin pedir sesión
  select proname from definer_anon
   where prosrc ~* '\m(clientes|cliente_direcciones|cliente_referencias|eq_personas|registros|registro_versiones|credito_persona|asesores|pr_premios|fact_facturas|documentos|perfiles|loc_personas|crm_pedidos)\M'
     and proname not in (select fn from abiertas_a_proposito)
   group by proname
),
vistas_con_permiso_del_dueno as (
  -- una vista sin security_invoker lee con los permisos de quien la creó y se salta las políticas de sus tablas
  select c.relname
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind = 'v'
     and not (coalesce(c.reloptions, '{}'::text[]) && array['security_invoker=on','security_invoker=true','security_invoker=1'])
     and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('authenticated', c.oid, 'SELECT'))
),
cualquier_cuenta as (
  -- políticas que dejan pasar a cualquier cuenta con correo, tenga o no perfil de la oficina
  select p.tablename
    from pg_policies p
   where p.schemaname = 'public' and p.roles = '{authenticated}'::name[]
     and coalesce(p.qual, 'true') = 'true' and coalesce(p.with_check, 'true') = 'true'
     and p.tablename not in (select t from catalogos)
   group by p.tablename
),
archivos_abiertos as (
  -- carpetas de archivos donde cualquiera puede subir o reemplazar sin boleto ni sesión
  select p.policyname || ' [' || p.cmd || ']' as politica
    from pg_policies p
   where p.schemaname = 'storage' and p.tablename = 'objects'
     and ('anon' = any(p.roles) or 'public' = any(p.roles))
     and p.cmd <> 'SELECT'
     and coalesce(p.qual, '') !~ '_ruta_ok|tiene_rol|es_admin'
     and coalesce(p.with_check, '') !~ '_ruta_ok|tiene_rol|es_admin'
),
modulos_sin_pendientes as (
  select m.id from plataforma_modulos m
   where m.activo and m.acceso not in ('hub','libre')
     and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                      where n.nspname = 'public' and p.proname = 'hoy_items_v2' and p.prosrc ~ ('''' || m.id || ''''))
),
modulos_sin_grupo as (
  -- sin grupo el hub lo manda a «Otros»; sin función de visibilidad válida, plataforma_menu lo esconde
  select m.id from plataforma_modulos m
   where m.activo and (m.grupo is null
     or (m.visible_fn is not null and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                                   where n.nspname = 'public' and p.proname = m.visible_fn)))
),
cuenta as (
  select (select count(*) from escritura_anon) + (select count(*) from lectura_anon_no_catalogo) + (select count(*) from sin_rls)
       + (select count(*) from definer_anon_sin_chequeo) + (select count(*) from modulos_sin_pendientes) + (select count(*) from modulos_sin_grupo)
       + (select count(*) from lectura_personas_sin_sesion) + (select count(*) from vistas_con_permiso_del_dueno)
       + (select count(*) from cualquier_cuenta) + (select count(*) from archivos_abiertos) as total,
         (select count(*) from escritura_anon) + (select count(*) from lectura_anon_no_catalogo) + (select count(*) from sin_rls)
       + (select count(*) from definer_anon_sin_chequeo) + (select count(*) from lectura_personas_sin_sesion)
       + (select count(*) from vistas_con_permiso_del_dueno) + (select count(*) from cualquier_cuenta) + (select count(*) from archivos_abiertos) as seguridad
)
select jsonb_build_object(
  'hallazgos', (select total from cuenta),
  'de_seguridad', (select seguridad from cuenta),
  'escritura_anon', (select coalesce(jsonb_agg(jsonb_build_object('tabla', tablename, 'politicas', politicas) order by tablename), '[]'::jsonb) from escritura_anon),
  'lectura_anon_no_catalogo', (select coalesce(jsonb_agg(tablename order by tablename), '[]'::jsonb) from lectura_anon_no_catalogo),
  'sin_rls', (select coalesce(jsonb_agg(relname order by relname), '[]'::jsonb) from sin_rls),
  'funciones_publicas_que_escriben_sin_chequeo', (select coalesce(jsonb_agg(proname order by proname), '[]'::jsonb) from definer_anon_sin_chequeo),
  'funciones_publicas_que_leen_personas_sin_sesion', (select coalesce(jsonb_agg(proname order by proname), '[]'::jsonb) from lectura_personas_sin_sesion),
  'vistas_con_permiso_del_dueno', (select coalesce(jsonb_agg(relname order by relname), '[]'::jsonb) from vistas_con_permiso_del_dueno),
  'tablas_para_cualquier_cuenta', (select coalesce(jsonb_agg(tablename order by tablename), '[]'::jsonb) from cualquier_cuenta),
  'archivos_que_cualquiera_puede_subir', (select coalesce(jsonb_agg(politica order by politica), '[]'::jsonb) from archivos_abiertos),
  'modulos_sin_bloque_en_hoy', (select coalesce(jsonb_agg(id order by id), '[]'::jsonb) from modulos_sin_pendientes),
  'modulos_sin_grupo_o_sin_condicion', (select coalesce(jsonb_agg(id order by id), '[]'::jsonb) from modulos_sin_grupo),
  'revisado', now()
)
$function$;

-- 8) Hoy (admin) nombra también lo nuevo en la tarjeta «reglas de la plataforma sin cumplir».
--    Se parcha el texto de hoy_items_v2 en su sitio, sin reescribir la función entera.
do $do$
declare
  v text := pg_get_functiondef('public.hoy_items_v2(text)'::regprocedure);
  a1 text := $a$case when jsonb_array_length(s->'modulos_sin_bloque_en_hoy') > 0 then 'Módulos sin bloque en Hoy: '$a$;
  a2 text := $a$case when jsonb_array_length(s->'escritura_anon') > 0 or jsonb_array_length(s->'sin_rls') > 0 then 'alto' else 'info' end$a$;
  n1 text;
begin
  if position('funciones_publicas_que_leen_personas_sin_sesion' in v) > 0 then return; end if;   -- ya aplicado
  if position(a1 in v) = 0 or position(a2 in v) = 0 then raise exception 'ancla no encontrada en hoy_items_v2'; end if;
  n1 := $n$case when jsonb_array_length(coalesce(s->'funciones_publicas_que_leen_personas_sin_sesion', '[]'::jsonb)) > 0 then 'Funciones que entregan datos de personas sin pedir sesión: ' || (select string_agg(x #>> '{}', ', ') from jsonb_array_elements(s->'funciones_publicas_que_leen_personas_sin_sesion') x) || '.' end,
              case when jsonb_array_length(coalesce(s->'archivos_que_cualquiera_puede_subir', '[]'::jsonb)) > 0 then 'Carpetas de archivos donde cualquiera puede subir: ' || (select string_agg(x #>> '{}', ', ') from jsonb_array_elements(s->'archivos_que_cualquiera_puede_subir') x) || '.' end,
              case when jsonb_array_length(coalesce(s->'vistas_con_permiso_del_dueno', '[]'::jsonb)) > 0 then 'Vistas que se saltan las políticas de sus tablas: ' || (select string_agg(x #>> '{}', ', ') from jsonb_array_elements(s->'vistas_con_permiso_del_dueno') x) || '.' end,
              case when jsonb_array_length(coalesce(s->'tablas_para_cualquier_cuenta', '[]'::jsonb)) > 0 then 'Tablas abiertas a cualquier cuenta con correo: ' || (select string_agg(x #>> '{}', ', ') from jsonb_array_elements(s->'tablas_para_cualquier_cuenta') x) || '.' end,
              $n$;
  v := replace(v, a1, n1 || a1);
  v := replace(v, a2, $r$case when coalesce((s->>'de_seguridad')::int, jsonb_array_length(s->'escritura_anon') + jsonb_array_length(s->'sin_rls')) > 0 then 'alto' else 'info' end$r$);
  execute v;
end $do$;
