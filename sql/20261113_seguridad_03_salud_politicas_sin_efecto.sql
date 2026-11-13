-- =====================================================================================================
-- Salud: una política que quedó sin efecto ya no cuenta como puerta abierta (13 de noviembre de 2026).
-- Aplicado en la base; este archivo es la copia.
--
-- Ese día se cerró la escritura directa del Local del equipo (repo local-equipo-arequipa,
-- sql/20261113_cierre_escritura_directa_APLICADO.sql). Se hizo sin quitar políticas, que es el camino que no pide
-- confirmación: la política ALL queda con «using (false) with check (false)» y la lectura pasa a una política propia.
-- plataforma_salud() seguía contándolas como escritura sin sesión porque solo miraba para quién era la política;
-- ahora salta las que no dejan pasar nada. Con eso los hallazgos bajaron de 28 a 22 (de seguridad, de 25 a 19):
-- quedan el formulario de registro (11 funciones), las carpetas de archivos sin boleto (6) y tres módulos sin
-- bloque en Hoy.
--
-- Es un parche sobre la función viva (su copia completa está en sql/20261110_seguridad_01_cierres.sql):
-- lee la definición actual, cambia un punto y la vuelve a crear. Si ya está aplicado, no hace nada.
-- =====================================================================================================

do $do$
declare
  v text := pg_get_functiondef('public.plataforma_salud()'::regprocedure);
  a text := $a$     and coalesce(p.with_check, 'true') !~ 'tiene_rol|auth\.uid|es_admin'
),
escritura_anon as ($a$;
  n text := $n$     and coalesce(p.with_check, 'true') !~ 'tiene_rol|auth\.uid|es_admin'
     -- una política que quedó sin efecto (using false / with check false) ya no abre nada: es la forma de cerrar sin borrar
     and not (coalesce(p.qual, p.with_check, 'true') = 'false' and coalesce(p.with_check, p.qual, 'true') = 'false')
),
escritura_anon as ($n$;
begin
  if position('ya no abre nada' in v) > 0 then return; end if;   -- ya aplicado
  if position(a in v) = 0 then raise exception 'ancla no encontrada en plataforma_salud'; end if;
  execute replace(v, a, n);
end $do$;
