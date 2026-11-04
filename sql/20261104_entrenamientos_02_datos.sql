-- =====================================================================
-- Entrenamientos · datos iniciales: categorías y documentos (sin archivo aún),
-- módulos y lecciones, el horario habitual, el módulo en el hub, las fuentes
-- de Vigencia y las herramientas del chat.
-- =====================================================================

-- ---------------------------------------------------------------- documentos
insert into public.doc_categorias (id, nombre, descripcion, orden) values
  ('precios',   'Listas de precios',     'Lista regular y promociones del mes: la digital (foto y precio) para el cliente y para el asesor, y la completa de Rena Ware con comisiones.', 1),
  ('repuestos', 'Repuestos y servicios', 'La lista de repuestos de Rena Ware, nuestra lista de repuestos y servicios con precio al cliente, y la ganancia del asesor.', 2),
  ('concursos', 'Concursos y programas', 'Las fotos del Empiece Ya y de los concursos vigentes, y un PDF por concurso (crea un documento nuevo por cada uno).', 3)
on conflict (id) do nothing;

insert into public.doc_documentos (categoria_id, clave, titulo, descripcion, audiencia, orden) values
  ('precios', 'lista-regular-cliente',  'Precio regular · lista digital para el cliente',
     'Foto y precio resumido de cada producto de la lista general. Se le puede enviar al cliente.', 'cliente', 1),
  ('precios', 'lista-promo-cliente',    'Promociones del mes · lista digital para el cliente',
     'Especiales y Flash vigentes con foto y precio. Se le puede enviar al cliente.', 'cliente', 2),
  ('precios', 'lista-regular-asesor',   'Precio regular · autocompra (para el asesor)',
     'Precio de autocompra de cada producto de la lista general. Solo para el equipo.', 'asesor', 3),
  ('precios', 'lista-promo-asesor',     'Promociones del mes · autocompra (para el asesor)',
     'Precio de autocompra de los Especiales y Flash vigentes. Solo para el equipo.', 'asesor', 4),
  ('precios', 'lista-regular-completa', 'Lista de precio regular COMPLETA (Rena Ware)',
     'La lista oficial completa: imágenes, precios, comisiones y puntos. Cambia poco; aquí quedan todas las versiones.', 'asesor', 5),
  ('precios', 'lista-promo-completa',   'Lista de promociones COMPLETA (Rena Ware)',
     'El PDF oficial de los Especiales y Flash del mes: imágenes, precios, comisiones y puntos.', 'asesor', 6),
  ('repuestos', 'repuestos-rw',         'Lista de repuestos de Rena Ware',
     'La que manda Rena Ware: precio de asesor y precio de cliente.', 'asesor', 1),
  ('repuestos', 'repuestos-servicios',  'Repuestos y servicios · precio al cliente',
     'Nuestra lista completa: repuestos, Rena Lite, limpieza, cambio de asas y perillas, instalación de filtro y demás servicios, con precio de cliente.', 'cliente', 2),
  ('repuestos', 'repuestos-ganancia',   'Ganancia de repuestos para el asesor',
     'Cuánto gana el asesor en cada repuesto y servicio (margen). Solo para el equipo.', 'asesor', 3),
  ('concursos', 'foto-empiece-ya',      'Programa Empiece Ya',
     'La foto del programa vigente para los nuevos: premios por nivel y plazo.', 'asesor', 1),
  ('concursos', 'foto-concurso-viaje',  'Concurso de viaje vigente (asesores con más de 30 días)',
     'Más de 30 días = ya pasó la venta de los 2 períodos siguientes al período en que se afilió.', 'asesor', 2),
  ('concursos', 'foto-viaje-antiguos',  'Viaje para asesores antiguos (más de 30 días)',
     'Para asesores con más de 30 días en el equipo.', 'asesor', 3),
  ('concursos', 'foto-concurso-afiliacion', 'Concurso de afiliación vigente',
     'La foto del concurso de afiliación del momento.', 'asesor', 4)
on conflict (clave) do nothing;

-- ---------------------------------------------------------------- entrenamientos
do $$
declare m uuid;
begin
  if exists (select 1 from ent_modulos) then return; end if;

  insert into ent_modulos (titulo, descripcion, orden) values ('Empieza bien', 'Lo primero que necesita un asesor nuevo para arrancar.', 1) returning id into m;
  insert into ent_lecciones (modulo_id, titulo, descripcion, orden) values
    (m, 'Sesión de bienvenida', 'Tu primera sesión: qué es Rena Ware, cómo trabaja el equipo y qué viene en tus primeros 30 días.', 1),
    (m, 'Programa Empiece Ya', 'Qué gana el nuevo, el soporte de la oficina y el acompañamiento a campo.', 2),
    (m, 'Autocompra y comisiones', 'Cómo se calcula el precio de autocompra y cuánto se gana por cada venta.', 3),
    (m, 'La regla de oro', 'Cada punto de la regla de oro, explicado en detalle.', 4);

  insert into ent_modulos (titulo, descripcion, orden) values ('Consigue citas', 'De dónde salen los prospectos y cómo se convierten en citas.', 2) returning id into m;
  insert into ent_lecciones (modulo_id, titulo, descripcion, orden) values
    (m, 'Círculo de influencia', 'Cómo sacar citas de tu círculo de influencia.', 1),
    (m, 'El módulo', 'Cómo trabajar el módulo para conseguir citas.', 2),
    (m, 'El Facebook', 'Cómo usar Facebook para prospectar.', 3);

  insert into ent_modulos (titulo, descripcion, orden) values ('La presentación', 'Cómo presentar el producto y dar el precio con seguridad.', 3) returning id into m;
  insert into ent_lecciones (modulo_id, titulo, descripcion, orden) values
    (m, 'La presentación', 'La presentación paso a paso.', 1),
    (m, 'Guion para dar el precio', 'Lista de precio regular y promoción: la secuencia para responder cuánto cuesta.', 2),
    (m, 'Guiones de venta de productos', 'Argumentos de venta por producto.', 3),
    (m, 'Royal Prestige vs. Rena Ware', 'Las fortalezas de Rena Ware frente a la competencia (sin atacar).', 4);

  insert into ent_modulos (titulo, descripcion, orden) values ('Cierra la venta', 'Del interés al contrato.', 4) returning id into m;
  insert into ent_lecciones (modulo_id, titulo, descripcion, orden) values
    (m, 'Pre-cierre', 'Cómo preparar el cierre desde la presentación.', 1),
    (m, 'Manejo de objeciones', 'Las objeciones más comunes y cómo responderlas.', 2),
    (m, 'Contratos: contado y crédito', 'Cómo llenar y explicar el contrato al contado y al crédito.', 3),
    (m, 'El service (taller de cocina)', 'El taller de cocina en casa del cliente: cómo se hace y qué vende.', 4);

  insert into ent_modulos (titulo, descripcion, orden) values ('Crece en el negocio', 'Plan de compensación, afiliación, la oficina y cómo cobrar.', 5) returning id into m;
  insert into ent_lecciones (modulo_id, titulo, descripcion, orden) values
    (m, 'Plan de compensación', 'Cómo se gana en cada nivel y cómo se asciende.', 1),
    (m, 'Estrategias de afiliación', 'Cómo afiliar y formar tu propio equipo.', 2),
    (m, 'La oficina: estructura de reuniones', 'Qué reunión hay cada día y para qué sirve cada una.', 3),
    (m, 'Cobrar: SUNAT, facturar y declarar', 'Cómo cobrar tus comisiones: RUC, factura y declaración.', 4);

  insert into ent_modulos (titulo, descripcion, orden) values ('Trabaja en ti', 'Liderazgo personal y gestión del tiempo.', 6) returning id into m;
  insert into ent_lecciones (modulo_id, titulo, descripcion, orden) values
    (m, 'Liderazgo personal (Cambiae)', 'El cambio empieza por uno mismo.', 1),
    (m, 'Rutinas y gestión del tiempo', 'Rutinas que sostienen el negocio semana a semana.', 2),
    (m, 'Los miedos: trabajar en ti', 'Cómo reconocer y trabajar los miedos que frenan.', 3);
end $$;

-- ---------------------------------------------------------------- horario habitual
do $$
begin
  if exists (select 1 from hor_plantillas) then return; end if;
  insert into hor_plantillas (dia, hora, titulo, descripcion, lugar, modo, facilitador, tipo, asistencia, solo_inicio_periodo, publico, orden) values
    (1, '09:00', 'Capacitación por Zoom', null, null, 'zoom', 'Juan Carlos Ezaine', 'capacitacion', true, false, true, 1),
    (2, '09:30', 'Desayuno de líderes', null, 'Oficina · Av. Cayma 628, Of. 502', 'presencial', null, 'reunion', false, false, false, 2),
    (2, '20:00', 'Taller de cocina por Zoom', null, null, 'zoom', 'Cristina Román y/o sus líderes', 'capacitacion', true, false, true, 3),
    (3, '16:00', 'Taller de cocina y entrenamiento en productos', null, 'Oficina · Av. Cayma 628, Of. 502', 'presencial', null, 'capacitacion', true, false, true, 4),
    (4, '10:00', 'Lanzamiento del nuevo concurso', 'El jueves que empieza el período, después del cierre.', 'Oficina · Av. Cayma 628, Of. 502', 'presencial', null, 'evento', true, true, true, 5),
    (4, '21:00', 'Capacitación por Zoom', null, null, 'zoom', 'Nelson Portugal', 'capacitacion', true, false, true, 6),
    (5, '17:00', 'Charla de la oportunidad', 'Reclutamiento: trae a tus invitados.', 'Oficina · Av. Cayma 628, Of. 502', 'presencial', null, 'reclutamiento', false, false, true, 7);
end $$;
select public.hor_materializar(public.hoy_lima(), public.hoy_lima() + 21);

-- ---------------------------------------------------------------- el módulo en el hub
insert into public.plataforma_modulos (id, nombre, descripcion, url, roles, orden, activo, acceso, grupo) values
  ('entrenamientos', 'Entrenamientos', 'Guías por módulo, listas para ver y descargar y el horario de la semana.',
   'https://renaware-plataforma.nelson1614.workers.dev/entrenamientos/', array['admin','asistente','asesor'], 20, true, 'asesor', 'Equipo'),
  ('listas', 'Listas y fotos', 'Listas de precios, repuestos y concursos: vista previa y descarga.',
   'https://renaware-plataforma.nelson1614.workers.dev/entrenamientos/#listas', array['admin','asistente','asesor'], 4, true, 'asesor', 'Vender')
on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, url = excluded.url, roles = excluded.roles,
  orden = excluded.orden, activo = excluded.activo, acceso = excluded.acceso, grupo = excluded.grupo;

-- ---------------------------------------------------------------- vigencia de los datos
update public.plataforma_fuentes set
  nombre = 'Horario de la semana (clases del Nivel Cero)',
  accion = 'Revisa el horario de la semana en Entrenamientos: apaga lo que no habrá y agrega lo extra. Lo que lleva asistencia pasa solo a Nivel Cero.',
  modulo = 'entrenamientos', cadencia = 'vigencia', dia = 0, aviso_dias = 3,
  ultima_sql = 'select max(fecha) from hor_eventos where activo and asistencia and fecha <= hoy_lima()',
  vence_sql = 'select max(fecha) from hor_eventos where activo and asistencia'
where id = 'clases-nivel-cero';

insert into public.plataforma_fuentes (id, nombre, accion, modulo, roles, cadencia, dia, aviso_dias, ultima_sql, vence_sql, pendientes_sql, en_hoy, activo, orden) values
  ('listas-digitales', 'Listas digitales del mes (Listas y fotos)',
   'Sube en Listas y fotos la lista de promociones del mes (cliente y asesor) antes de que venza la cargada.',
   'listas', array['admin','asistente'], 'vigencia', 0, 5,
   'select max(v.creado_en)::date from doc_versiones v join doc_documentos d on d.id = v.documento_id where d.clave like ''lista-promo%'' and not v.borrada',
   'select min(x.vigente_hasta) from (select distinct on (v.documento_id) v.vigente_hasta from doc_versiones v join doc_documentos d on d.id = v.documento_id where d.clave like ''lista-promo%'' and not v.borrada order by v.documento_id, v.version desc) x',
   null, true, true, 11)
on conflict (id) do nothing;

-- ---------------------------------------------------------------- chat: herramientas y ficha
insert into public.chat_herramientas (proyecto, nombre, tipo, descripcion, parametros, sql, roles, orden, activo) values
  ('renaware', 'horario_semana', 'sql',
   'Horario de capacitaciones y eventos del equipo de una semana (lunes a domingo) con fecha, día, hora, modo (zoom/presencial), lugar, facilitador y si lleva asistencia del Nivel Cero. Sin fecha devuelve la semana actual; con fecha, la semana que contiene esa fecha. El jueves que empieza un período hay lanzamiento de concurso a las 10:00 a. m.',
   '{"type":"object","properties":{"fecha":{"type":"string","description":"Una fecha (AAAA-MM-DD) dentro de la semana que te interesa. Vacío = esta semana."}}}',
   $q$
with s as (select coalesce(nullif($1->>'fecha', '')::date, hoy_lima()) as f),
     l as (select f - ((extract(dow from f)::int + 6) % 7) as lunes from s)
select e.fecha,
       (array['domingo','lunes','martes','miércoles','jueves','viernes','sábado'])[extract(dow from e.fecha)::int + 1] as dia,
       to_char(e.hora, 'HH24:MI') as hora, e.titulo, e.modo, e.lugar, e.facilitador, e.enlace, e.tipo,
       e.asistencia as lleva_asistencia_nivel_cero, e.nota,
       (e.fecha = periodo_inicio(periodo_indice(e.fecha))) as es_inicio_de_periodo
from hor_eventos e, l
where e.fecha between l.lunes and l.lunes + 6 and e.activo and (coalesce($2->>'rol', '') <> 'asesor' or e.publico)
order by e.fecha, e.hora
   $q$,
   array['admin','asistente','gestor','asesor'], 80, true),
  ('renaware', 'documentos_listas', 'sql',
   'Base de documentos del equipo (Listas y fotos): listas de precios digitales (cliente y asesor), listas completas de Rena Ware, repuestos y servicios, fotos del Empiece Ya y de los concursos, PDF por concurso. Devuelve título, categoría, vigencia de la versión cargada, nota y el enlace para ver o descargar. Con q filtra por palabra.',
   '{"type":"object","properties":{"q":{"type":"string","description":"Palabra para filtrar, p. ej. \"promociones\", \"repuestos\", \"viaje\". Vacío lista todo."}}}',
   $q$
select c.nombre as categoria, d.titulo, d.clave, d.descripcion, d.audiencia,
       v.version, v.vigente_desde, v.vigente_hasta, v.nota, v.archivo, v.paginas,
       case when v.ruta is null then null else 'https://kiexpdaaoegbtesqmaff.supabase.co/storage/v1/object/public/entrenamientos/' || v.ruta end as url,
       (v.id is null) as sin_archivo
from doc_documentos d
join doc_categorias c on c.id = d.categoria_id
left join lateral (select * from doc_versiones x where x.documento_id = d.id and not x.borrada order by x.version desc limit 1) v on true
where not d.borrado and d.activo and c.activo
  and (coalesce($2->>'rol', '') <> 'asesor' or 'asesor' = any(d.roles))
  and (coalesce($1->>'q', '') = '' or unaccent_safe(d.titulo || ' ' || coalesce(d.descripcion, '') || ' ' || c.nombre) ilike '%' || unaccent_safe($1->>'q') || '%')
order by c.orden, d.orden
   $q$,
   array['admin','asistente','gestor','asesor'], 81, true),
  ('renaware', 'entrenamientos_lecciones', 'sql',
   'Sistema de entrenamiento del equipo: módulos y lecciones, qué materiales tiene cada una (guía PDF, video, libro, enlace) y cuántos asesores la completaron. Con q filtra por tema.',
   '{"type":"object","properties":{"q":{"type":"string","description":"Palabra para filtrar por módulo o lección, p. ej. \"objeciones\". Vacío lista todo."}}}',
   $q$
select m.titulo as modulo, l.titulo as leccion, l.descripcion,
       string_agg(r.tipo || case when r.url is not null then ' (enlace)' else '' end, ', ' order by r.orden) filter (where r.id is not null) as materiales,
       (select count(*) from ent_progreso p where p.leccion_id = l.id and p.completado_en is not null) as completaron
from ent_modulos m
join ent_lecciones l on l.modulo_id = m.id and not l.borrada and l.activo
left join ent_recursos r on r.leccion_id = l.id and not r.borrado and r.activo
where not m.borrado and m.activo
  and (coalesce($1->>'q', '') = '' or unaccent_safe(m.titulo || ' ' || l.titulo || ' ' || coalesce(l.descripcion, '')) ilike '%' || unaccent_safe($1->>'q') || '%')
group by m.orden, m.titulo, l.orden, l.id, l.titulo, l.descripcion
order by m.orden, l.orden
   $q$,
   array['admin','asistente','gestor','asesor'], 82, true);

update public.chat_fichas set contenido = replace(contenido,
  '- Capacitaciones habituales en la oficina: martes 9:30 a. m., miércoles 4:00 p. m. y viernes 4:30 p. m. (capacitaciones trae las programadas). La demostración en vivo con degustación es los miércoles a las 4:00 p. m.',
  '- Horario de la semana (fechas y horas reales, con lo que se apagó o agregó): lo da la herramienta horario_semana. El habitual: lunes 9:00 a. m. capacitación por Zoom con Juan Carlos Ezaine; martes 9:30 a. m. desayuno de líderes y 8:00 p. m. taller de cocina por Zoom (Cristina Román y/o sus líderes); miércoles 4:00 p. m. taller de cocina y entrenamiento en productos en la oficina (demostración en vivo con degustación); jueves 9:00 p. m. capacitación por Zoom con Nelson Portugal, y el jueves que empieza el período, 10:00 a. m., lanzamiento del nuevo concurso en la oficina; viernes 5:00 p. m. charla de la oportunidad (reclutamiento). Las guías, listas y el horario están en el módulo Entrenamientos de la plataforma.'),
  actualizado_en = now()
where proyecto = 'renaware' and titulo = 'Nivel Cero y test del Nivel 0';
