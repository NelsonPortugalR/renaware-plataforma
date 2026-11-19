-- =====================================================================================================
-- Listas: la categoría «Números de cuenta» (19 de noviembre de 2026). Aplicado en la base; este archivo es la copia.
--
-- Pedido de Nelson: «una categoría adicional que diga números de cuentas… los números de cuenta de Rena Ware». Mandó la
-- imagen oficial con las cuentas de BCP, Interbank y BBVA a nombre de Rena Ware del Perú S.A.
--
-- Qué queda:
--   · La categoría «cuentas» (Números de cuenta) en Listas, con el documento «Cuentas de Rena Ware» (clave cuentas-rena-ware,
--     para el cliente: se le puede enviar). La asesora la tiene además como botón en su inicio y en el buscador (#cuentas).
--   · La versión 1 es la imagen que mandó Nelson. Desde el chat no se puede subir a Storage, así que la imagen va como archivo
--     fijo del sitio (renaware-plataforma/public/archivos/) y la versión guarda su dirección completa. La página, doc_vigente y
--     la herramienta del chat aceptan esa dirección tal cual. Cuando la oficina suba una versión nueva desde el modo edición,
--     esa irá a Storage como todas.
--   · Los números van también como texto en la descripción del documento, una línea por número: la página les pone un botón
--     «Copiar» (copia solo los dígitos) y el buscador y el chat los encuentran. Se cambian en «Editar» del documento.
--
-- OJO con el CCI del BBVA: en la imagen dice 0011-910-000100004302-74, que tiene 21 dígitos (un CCI tiene 20). Con 011, el
-- código del BBVA, los dos dígitos de control (7 y 4) cuadran, así que en el texto va 011-910-000100004302-74. Los de BCP e
-- Interbank cuadran tal como están en la imagen. Falta que Nelson lo confirme con Rena Ware.
--
-- Se puede volver a correr: no duplica nada.
-- =====================================================================================================

-- 1) La categoría y el documento con su imagen
insert into doc_categorias (id, nombre, descripcion, orden, roles, activo)
values ('cuentas', 'Números de cuenta', 'Las cuentas de Rena Ware para que el cliente deposite o transfiera. Cada número se copia con un toque.',
        4, array['admin', 'asistente', 'asesor'], true)
on conflict (id) do nothing;

do $$
declare v_doc uuid;
begin
  select id into v_doc from doc_documentos where clave = 'cuentas-rena-ware' and not borrado limit 1;
  if v_doc is null then
    insert into doc_documentos (categoria_id, clave, titulo, descripcion, audiencia, roles, orden, activo)
    values ('cuentas', 'cuentas-rena-ware', 'Cuentas de Rena Ware', $t$A nombre de RENA WARE DEL PERÚ S.A.
BCP · Cuenta corriente: 193-0714516-0-32
BCP · CCI: 002-193-000714516032-16
Interbank · Cuenta: 164-3001186510
Interbank · CCI: 003-164-003001186510-19
BBVA · Cuenta corriente: 0011-0910-01-00004302
BBVA · CCI: 011-910-000100004302-74$t$, 'cliente', array['admin', 'asistente', 'asesor'], 1, true)
    returning id into v_doc;
  end if;
  if not exists (select 1 from doc_versiones where documento_id = v_doc and not borrada) then
    insert into doc_versiones (documento_id, version, ruta, archivo, bytes, content_type, portada)
    values (v_doc, 1, 'https://renaware-plataforma.nelson1614.workers.dev/archivos/cuentas-rena-ware.jpg', 'Cuentas Rena Ware.jpg', 90366, 'image/jpeg',
            'https://renaware-plataforma.nelson1614.workers.dev/archivos/cuentas-rena-ware-portada.jpg');
  end if;
end $$;

-- 2) doc_vigente (lo que usan otros sistemas para jalar un documento por su clave): una dirección completa pasa tal cual.
--    Parche sobre la función viva: lee la definición actual, cambia dos puntos y la vuelve a crear. Si ya está, no hace nada.
do $do$
declare
  v text := pg_get_functiondef('public.doc_vigente(uuid,text)'::regprocedure);
  a1 text := $a$'url', 'https://kiexpdaaoegbtesqmaff.supabase.co/storage/v1/object/public/entrenamientos/' || v.ruta,$a$;
  n1 text := $n$'url', case when v.ruta ~ '^https?://' then v.ruta else 'https://kiexpdaaoegbtesqmaff.supabase.co/storage/v1/object/public/entrenamientos/' || v.ruta end,$n$;
  a2 text := $a$'portada', case when v.portada is null then null else 'https://kiexpdaaoegbtesqmaff.supabase.co/storage/v1/object/public/entrenamientos/' || v.portada end)$a$;
  n2 text := $n$'portada', case when v.portada is null then null when v.portada ~ '^https?://' then v.portada else 'https://kiexpdaaoegbtesqmaff.supabase.co/storage/v1/object/public/entrenamientos/' || v.portada end)$n$;
begin
  if position('^https?://' in v) > 0 then return; end if;   -- ya aplicado
  if position(a1 in v) = 0 or position(a2 in v) = 0 then raise exception 'ancla no encontrada en doc_vigente'; end if;
  execute replace(replace(v, a1, n1), a2, n2);
end $do$;

-- 3) El chat (herramienta documentos_listas): el mismo enlace, y que sepa que ahí están las cuentas
update chat_herramientas set
  descripcion = 'Base de documentos del equipo (Listas y fotos): listas de precios digitales (cliente y asesor), listas completas de Rena Ware, '
             || 'repuestos y servicios, fotos del Empiece Ya y de los concursos, PDF por concurso, y los números de cuenta de Rena Ware para '
             || 'depósitos y transferencias (banco, cuenta y CCI van en la descripción del documento «Cuentas de Rena Ware»). Devuelve título, '
             || 'categoría, descripción, vigencia de la versión cargada, nota y el enlace para ver o descargar. Con q filtra por palabra.',
  sql = replace(sql,
    $a$case when v.ruta is null then null else 'https://kiexpdaaoegbtesqmaff.supabase.co/storage/v1/object/public/entrenamientos/' || v.ruta end as url$a$,
    $n$case when v.ruta is null then null when v.ruta ~ '^https?://' then v.ruta else 'https://kiexpdaaoegbtesqmaff.supabase.co/storage/v1/object/public/entrenamientos/' || v.ruta end as url$n$),
  actualizado_en = now()
where id = '6892e61b-8a3b-490f-812a-76bc1d0e2ae0' and position('^https?://' in sql) = 0;
