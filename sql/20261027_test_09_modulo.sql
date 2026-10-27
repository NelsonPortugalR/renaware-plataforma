-- Test del Nivel 0 · módulo en la plataforma (después de publicar /test/)
-- acceso 'asesor': el asesor entra con su sesión (traspaso de asesor) y la oficina con admin_sesion.
insert into plataforma_modulos (id, nombre, descripcion, url, roles, orden, activo, acceso)
values ('test', 'Test del Nivel 0',
        'Al completar sus 5 clases, los nuevos lo aprueban y ganan su botella.',
        'https://renaware-plataforma.nelson1614.workers.dev/test/',
        array['admin','asistente','asesor'], 13, true, 'asesor')
on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, url = excluded.url,
  roles = excluded.roles, orden = excluded.orden, activo = excluded.activo, acceso = excluded.acceso;
