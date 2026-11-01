-- Chat de la plataforma: registro del módulo en el hub.
-- url relativa (/chat/): vive en el mismo dominio del hub y usa su misma sesión, por eso acceso = 'hub' (sin traspaso).
-- Por ahora solo admin (Nelson lo prueba solo); para abrirlo al equipo basta agregar roles aquí
-- y ampliar los roles de las herramientas en chat_herramientas.
insert into public.plataforma_modulos (id, nombre, descripcion, url, roles, acceso, activo, orden)
values ('chat', 'Pregúntale', 'Pregunta en tus palabras: precios, puntos, premios, zonas, pedidos, pendientes. Responde con datos de la plataforma y dice de dónde salieron.', '/chat/', array['admin'], 'hub', true, 0)
on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, url = excluded.url, roles = excluded.roles, acceso = excluded.acceso, activo = true, orden = excluded.orden;
