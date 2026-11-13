-- =====================================================================================================
-- Seguridad: las vistas no se vuelven a abrir solas (13 de noviembre de 2026). Aplicado en la base; este archivo es la copia.
--
-- Qué pasó: el 10/11 se cerró el listado de Facturación (fact_listos: RUC, cuentas, CCI) para que no se leyera sin
-- sesión. El 12/11, desde otra conversación, esa vista se volvió a crear (la misma consulta) y, sin querer, quedó
-- abierta otra vez. Así funciona Postgres: una vista nueva nace leyendo con el permiso de su dueño (se salta las
-- reglas de las tablas) y con lectura para todos; y «create or replace view» sin opciones borra las opciones que tenía.
-- Lo avisó la historia de cambios del respaldo (respaldo.cambios, corrida del 13/11 a las 2:40) y el chequeo de salud.
--
-- Qué queda:
--   1) fact_listos cerrada de nuevo (la oficina la lee igual: se probó con la cuenta de Nelson).
--   2) Una guardia: cada vez que alguien crea o vuelve a crear una vista en public, queda con security_invoker
--      (lee con el permiso de quien pregunta, así mandan las reglas de las tablas). No toca los permisos de la vista.
--      Se probó creando una vista de prueba, con «create view» y con «create or replace view», y deshaciéndola.
--
-- Regla que sale de aquí: lo que haya que mostrar sin sesión se hace con una función, no con una vista.
-- Para apagar la guardia:  alter event trigger plataforma_vistas_seguras disable;
-- =====================================================================================================

-- 1) El listado de Facturación, otra vez cerrado
revoke all on public.fact_listos from anon;
alter view public.fact_listos set (security_invoker = on);

-- 2) La guardia
create or replace function public.plataforma_vistas_seguras()
returns event_trigger language plpgsql set search_path to 'public', 'pg_catalog' as $fn$
declare r record;
begin
  for r in
    select c.oid::regclass as vista
      from pg_event_trigger_ddl_commands() d join pg_class c on c.oid = d.objid
     where d.command_tag = 'CREATE VIEW' and c.relnamespace = 'public'::regnamespace and c.relkind = 'v'
       and not (coalesce(c.reloptions, '{}'::text[]) && array['security_invoker=on', 'security_invoker=true', 'security_invoker=1'])
  loop
    begin
      execute format('alter view %s set (security_invoker = on)', r.vista);
    exception when others then null;       -- nunca estorba a quien crea la vista
    end;
  end loop;
exception when others then null;
end $fn$;

do $$
begin
  if not exists (select 1 from pg_event_trigger where evtname = 'plataforma_vistas_seguras') then
    execute 'create event trigger plataforma_vistas_seguras on ddl_command_end when tag in (''CREATE VIEW'') execute function public.plataforma_vistas_seguras()';
  end if;
end $$;
