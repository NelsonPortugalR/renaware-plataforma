-- Los módulos del hub, agrupados, con sus direcciones vigentes y qué tipo de traspaso aceptan.
alter table public.plataforma_modulos
  add column if not exists grupo text not null default 'Ventas',
  add column if not exists traspaso_staff boolean not null default false,
  add column if not exists traspaso_asesor boolean not null default false;

insert into public.plataforma_modulos (id, nombre, descripcion, url, roles, orden, grupo, traspaso_staff) values
 ('pedidos', 'Pedidos y seguimiento de clientes', 'Las órdenes oficiales de WV08 y los seguimientos después de la venta.',
  'https://renaware-pedidos.nelson1614.workers.dev', '{admin,asistente}', 4, 'Ventas', true)
on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, url = excluded.url,
  roles = excluded.roles, orden = excluded.orden, grupo = excluded.grupo, traspaso_staff = excluded.traspaso_staff;

update public.plataforma_modulos set grupo = 'Ventas', orden = 1, traspaso_staff = true, traspaso_asesor = true,
  url = 'https://renaware-peru.nelson1614.workers.dev' where id = 'cotizador';
update public.plataforma_modulos set grupo = 'Ventas', orden = 2, roles = '{admin,asistente}',
  url = 'https://renaware-registro.nelson1614.workers.dev',
  descripcion = 'El formulario interno para ingresar ventas y afiliaciones.' where id = 'registro';
update public.plataforma_modulos set grupo = 'Ventas', orden = 3, traspaso_staff = true,
  url = 'https://renaware-registro.nelson1614.workers.dev/admin' where id = 'admin-registros';
update public.plataforma_modulos set grupo = 'Ventas', orden = 5 where id = 'importar-pedidos';
update public.plataforma_modulos set grupo = 'Ventas', orden = 6 where id = 'conciliar';
update public.plataforma_modulos set grupo = 'Equipo', orden = 7, nombre = 'Premios', traspaso_staff = true,
  descripcion = 'Premios de Rena Ware: de lo declarado a lo entregado y publicado.',
  url = 'https://panel-equipo.pages.dev' where id = 'equipo';
update public.plataforma_modulos set grupo = 'Equipo', orden = 8,
  descripcion = 'Ganadores oficiales de todos los grupos, por período.' where id = 'empiece-ya';
update public.plataforma_modulos set grupo = 'Equipo', orden = 9, traspaso_staff = true where id = 'nivel-cero';
update public.plataforma_modulos set grupo = 'Equipo', orden = 10, traspaso_staff = true where id = 'bienvenida';
update public.plataforma_modulos set grupo = 'Oficina', orden = 11, traspaso_staff = true where id = 'reparaciones';
update public.plataforma_modulos set grupo = 'Oficina', orden = 12, traspaso_staff = true where id = 'facturacion';
