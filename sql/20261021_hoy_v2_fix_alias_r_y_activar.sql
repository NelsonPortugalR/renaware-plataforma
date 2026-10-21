-- Aplicada el 21/10/2026 (migración hoy_v2_fix_alias_r_y_activar).
-- hoy_items_v2 usaba el alias r sobre registros en el bloque "Bienvenida" y la función
-- ya declara "r record": chocaban y fallaba al correr. Se corrigió el alias a g, se verificó
-- que corre para admin, asistente y gestor, y hoy() pasó a usar hoy_items_v2.
do $do$
declare d text; n text;
begin
  d := pg_get_functiondef('public.hoy_items_v2(text)'::regprocedure);
  n := regexp_replace(d,
        '(from registros) r(\s+where) r\.tipo = ''afiliacion'' and coalesce\(r\.fecha, r\.creado_en::date\)(.*?)m\.inscrito_id = r\.id',
        '\1 g\2 g.tipo = ''afiliacion'' and coalesce(g.fecha, g.creado_en::date)\3m.inscrito_id = g.id');
  if n = d then raise exception 'No encontré el bloque a corregir en hoy_items_v2'; end if;
  execute n;
  perform public.hoy_items_v2('admin');
  perform public.hoy_items_v2('asistente');
  perform public.hoy_items_v2('gestor');
end $do$;

create or replace function public.hoy()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_rol text; v_nombre text;
begin
  select rol, nombre into v_rol, v_nombre from perfiles where user_id = auth.uid() and activo;
  if v_rol is null then
    raise exception 'Tu cuenta no tiene un rol asignado. Pídeselo al administrador.';
  end if;
  return hoy_items_v2(v_rol) || jsonb_build_object('rol', v_rol, 'nombre', v_nombre);
end $$;
