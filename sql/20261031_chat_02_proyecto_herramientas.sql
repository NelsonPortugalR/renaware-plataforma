-- Chat de la plataforma: el proyecto "renaware" (prompt del sistema) y las herramientas iniciales.
-- Se puede volver a correr: cada herramienta se actualiza por (proyecto, nombre).
-- Convención del SQL de cada herramienta: $1 = argumentos (jsonb), $2 = quién pregunta (jsonb con rol, nombre, user_id).

insert into public.chat_proyectos (id, nombre, instrucciones, modelo, max_pasos, max_tokens) values ('renaware', 'Plataforma del Equipo Arequipa', $p$
Eres el asistente de datos de la plataforma del Equipo Arequipa (Nelson Portugal, Representante Independiente de Rena Ware, Arequipa, Perú). Respondes en español, para leer en el celular, usando SOLO lo que devuelven las herramientas.

Reglas:
1. Nunca inventes precios, puntos, fechas, nombres, estados ni montos. Todo número que digas debe salir de una herramienta. Si ninguna herramienta lo tiene, dilo con claridad y termina tu respuesta con la marca [SIN_DATOS].
2. Primero elige la herramienta que responde la pregunta. Para reglas, programas, servicios, horarios o cómo funciona algo, usa fichas_buscar. Para datos que no tienen herramienta propia, usa esquema (tablas y columnas vivas) y luego sql_lectura (solo SELECT, con LIMIT y solo las columnas necesarias). Puedes encadenar varias herramientas antes de responder.
3. Di de dónde salió cada dato y su corte: «según la lista Especiales para Compartir (vigente hasta el 11 de nov)», «según el reporte oficial cargado hasta el PB21». Los puntos y entregas oficiales vienen del reporte de pedidos de Rena Ware (rw_pedidos / crm_pedidos); el registro interno (registros) es lo que el equipo ingresó y puede no estar aún en el sistema de Rena Ware. Si el reporte oficial del período no está cargado, dilo.
4. Respuestas cortas: la cifra o la respuesta primero, el detalle después. Listas solo cuando hay varias filas; sin tablas anchas. Montos en soles: S/ 1,234. Fechas como «jue 5 de nov». Nombres de personas con mayúscula inicial.
5. Contexto fijo: los períodos de bonificación (PB) duran 14 días desde un jueves, hay 26 al año; el corte real del período es el viernes siguiente a las 11:00 a. m. de Lima. PPV = puntos personales; GPV = PPV más los de su equipo; TOV = producción total. La fecha, hora y período actuales vienen en el mensaje del sistema y en periodo_actual.
6. Si la pregunta es ambigua (qué período, qué lista, qué persona), asume lo vigente o lo más probable, dilo en una línea y responde; pregunta solo si es imposible decidir.
7. Datos sensibles: no muestres DNI completos, cuentas bancarias, claves, ni la evaluación crediticia de clientes salvo que te lo pidan de forma explícita y el rol sea admin. Nunca ejecutes ni sugieras cambios en la base: solo lees.
8. Cuando una pregunta se repite y no tiene herramienta propia, al final sugiere en una línea «esto podría ser una herramienta del chat» para que el administrador la agregue.
$p$, 'claude-sonnet-5-5', 8, 1500)
on conflict (id) do update set nombre = excluded.nombre, instrucciones = excluded.instrucciones, modelo = excluded.modelo,
  max_pasos = excluded.max_pasos, max_tokens = excluded.max_tokens, actualizado_en = now();

-- ---------- herramientas ----------
insert into public.chat_herramientas (proyecto, nombre, descripcion, parametros, tipo, sql, roles, orden) values

('renaware', 'fichas_buscar',
 'Busca en las fichas de reglas y conocimiento del equipo: crédito y contado, listas de precios, autocompra, programa Empiece Ya, Nivel Cero, ascenso y desactivación, concursos de referencia, servicios y repuestos (precios y margen), ciclos de filtros, zonas de crédito, estados de un registro, oficina y horarios, flujo comercial, facturación, local del equipo. Sin q devuelve el índice de fichas.',
 '{"type":"object","properties":{"q":{"type":"string","description":"Palabras clave de lo que buscas, p. ej. \"inicial mínima crédito\" o \"Empiece Ya niveles\"."}}}',
 'fichas', null, array['admin','asistente','gestor','asesor'], 1),

('renaware', 'esquema',
 'Mapa de la base: qué tablas y vistas existen (con comentario y filas aproximadas) y, si pasas tabla, sus columnas con tipo y comentario. Úsala antes de sql_lectura cuando no exista una herramienta para el dato.',
 '{"type":"object","properties":{"tabla":{"type":"string","description":"Nombre exacto de una tabla o vista para ver sus columnas."},"buscar":{"type":"string","description":"Filtra tablas por nombre, comentario o nombre de columna."}}}',
 'esquema', null, array['admin'], 2),

('renaware', 'sql_lectura',
 'Ejecuta una consulta SELECT de solo lectura sobre la base (PostgreSQL, esquema public). Usa esquema primero para conocer tablas y columnas. Pide solo las columnas necesarias, usa LIMIT (máx. 200 filas) y hoy_lima() en vez de now() para fechas. Funciones útiles: periodo_indice(fecha), periodo_numero(i), periodo_ciclo(i), periodo_inicio(i), unaccent_safe(texto) para comparar sin tildes. periodo_ind = (anio-2026)*26 + pb - 1.',
 '{"type":"object","properties":{"consulta":{"type":"string","description":"Una sola sentencia SELECT (o WITH ... SELECT), sin punto y coma final."},"limite":{"type":"integer","description":"Máximo de filas (por defecto 200)."}},"required":["consulta"]}',
 'sql_libre', null, array['admin'], 3),

('renaware', 'periodo_actual',
 'Fecha y hora de Lima, período de bonificación (PB) actual con su inicio, fin, día del período, semana 1 o 2, corte real (viernes 11:00 a. m.), período anterior, si hay bono de puntos extra vigente y si estamos en la semana de bono del 15 %.',
 '{"type":"object","properties":{}}',
 'sql', $sql$
with h as (select hoy_lima() as d, (now() at time zone 'America/Lima') as ahora),
     p as (select h.d, h.ahora, periodo_indice(h.d) as i from h),
     bs as (select data->'bonoSemana' as b from site_config where id = 'rena-ware')
select periodo_numero(p.i) as periodo_pb, periodo_ciclo(p.i) as anio,
       periodo_inicio(p.i) as inicio, periodo_inicio(p.i) + 13 as fin,
       p.d as hoy, to_char(p.ahora, 'HH24:MI') as hora_lima,
       (p.d - periodo_inicio(p.i) + 1) as dia_del_periodo,
       case when p.d - periodo_inicio(p.i) < 7 then 1 else 2 end as semana_del_periodo,
       (cierre_real(p.i) at time zone 'America/Lima') as corte_real_del_periodo,
       periodo_numero(p.i - 1) as periodo_anterior_pb, periodo_ciclo(p.i - 1) as periodo_anterior_anio,
       (select jsonb_build_object('porcentaje', b.porcentaje, 'lista', b.lista, 'desde', b.desde, 'hasta', b.hasta) from bono_extra_vigente(null) b) as bono_puntos_extra_vigente,
       (select coalesce((bs.b->>'activo')::boolean, false) and (((p.d - (bs.b->>'ancla')::date) % greatest((bs.b->>'cicloDias')::int, 1)) < (bs.b->>'duracionDias')::int) from bs) as en_semana_de_bono_15,
       (select bs.b from bs) as config_semana_de_bono
from p
$sql$, array['admin','asistente','gestor','asesor'], 10),

('renaware', 'listas_vigentes',
 'Las listas de precios y promociones del cotizador (tienda en línea, lista general, especiales, flash, repuestos): vigencia, si está vigente hoy, si permite contado/crédito/autocompra, si se mezcla con otras, avisos y cuántos productos tiene.',
 '{"type":"object","properties":{}}',
 'sql', $sql$
select l.id, l.nombre, l.vigente_desde, l.vigente_hasta,
       (l.vigente_desde <= hoy_lima() and (l.vigente_hasta is null or l.vigente_hasta >= hoy_lima())) as vigente,
       l.permite_contado, l.permite_credito, l.permite_autocompra, l.solo_terceros, l.se_mezcla, l.exenta_minimos, l.sin_puntos, l.max_items, l.aviso, l.pregunta,
       (select count(*) from productos p where p.lista_id = l.id and p.activo) as productos
from listas_precios l where l.activa order by l.orden
$sql$, array['admin','asistente','gestor','asesor'], 11),

('renaware', 'precios_buscar',
 'Busca productos y promociones por nombre, parte del nombre, código, categoría o número de especial/flash (p. ej. "especial 16", "aqua nano", "juego chef", "cocina de inducción"). Devuelve lista, precio de cliente, precio de autocompra (asesor), puntos, valor comisionable y regalo. Por defecto solo listas vigentes; incluir_vencidas=true para ver listas pasadas.',
 '{"type":"object","properties":{"q":{"type":"string","description":"Texto a buscar. Vacío lista todo lo vigente (máx. 60)."},"lista":{"type":"string","description":"Id de lista para filtrar (de listas_vigentes), p. ej. compartir, general, repuestos."},"incluir_vencidas":{"type":"boolean"}}}',
 'sql', $sql$
with s as (select unaccent_safe(trim(coalesce($1->>'q',''))) as q, nullif($1->>'lista','') as l, coalesce(($1->>'incluir_vencidas')::boolean, false) as iv),
     nums as (select (regexp_match(s.q, '(\d+)'))[1] as n from s),
     sin as (select unaccent_safe(x->>'termino') as termino, unaccent_safe(x->>'aplicaA') as aplica
             from site_config, jsonb_array_elements(data->'sinonimos') x where id = 'rena-ware'),
     ali as (select sin.aplica from sin, s where s.q <> '' and (sin.termino like '%' || s.q || '%' or s.q like '%' || trim(sin.termino) || '%'))
select p.lista_id as lista, l.nombre as lista_nombre, l.vigente_hasta as lista_vigente_hasta,
       (l.vigente_desde <= hoy_lima() and (l.vigente_hasta is null or l.vigente_hasta >= hoy_lima())) as lista_vigente,
       p.codigo, p.categoria, p.nombre, p.grupo, p.precio as precio_cliente, p.precio_asesor as precio_autocompra, p.puntos, p.valor_comisionable, p.regalo
from productos p join listas_precios l on l.id = p.lista_id, s
where p.activo and l.activa
  and (s.l is null or p.lista_id = s.l)
  and (s.iv or (l.vigente_desde <= hoy_lima() and (l.vigente_hasta is null or l.vigente_hasta >= hoy_lima())))
  and (s.q = ''
       or unaccent_safe(p.nombre) like '%' || s.q || '%'
       or unaccent_safe(coalesce(p.categoria,'')) like '%' || s.q || '%'
       or unaccent_safe(coalesce(p.grupo,'')) like '%' || s.q || '%'
       or p.codigo = s.q
       or exists (select 1 from ali where unaccent_safe(p.nombre) like '%' || ali.aplica || '%')
       or ((select n from nums) is not null and unaccent_safe(coalesce(p.categoria,'')) ~ ('#0?' || (select n from nums) || '\M')))
order by l.orden, p.orden
limit 60
$sql$, array['admin','asistente','gestor','asesor'], 12),

('renaware', 'cotizar',
 'Calcula un crédito con las reglas vigentes: inicial mínima (10 %), saldo a financiar, y para cada plazo (3 a 18 cuotas) la cuota mensual, gastos, intereses y total a pagar, indicando si cumple las reglas (saldo mínimo y cuota mínima). Si no pasas inicial, usa la mínima.',
 '{"type":"object","properties":{"precio":{"type":"number","description":"Precio de cliente del pedido en soles."},"inicial":{"type":"number","description":"Inicial que dará el cliente; si falta, la mínima."},"exento":{"type":"boolean","description":"true para listas exentas de mínimos."}},"required":["precio"]}',
 'sql', $sql$
with a as (select ($1->>'precio')::numeric as precio,
                  coalesce(($1->>'inicial')::numeric, inicial_minima(($1->>'precio')::numeric)) as inicial,
                  coalesce(($1->>'exento')::boolean, false) as exento)
select a.precio, a.inicial, inicial_minima(a.precio) as inicial_minima, a.precio - a.inicial as saldo_a_financiar,
       c.meses, c.cuota_mensual, c.importe_letra as total_en_cuotas, c.gastos as gastos_totales, c.intereses, c.precio_credito as total_a_pagar, c.valido as cumple_reglas,
       (select jsonb_build_object('inicial_minima_pct', r.pct_inicial_minima, 'saldo_minimo', r.saldo_minimo, 'cuota_minima', r.cuota_minima,
                                  'gasto_mensual', r.gasto_mensual, 'ingreso_debe_ser_x_cuota', r.relacion_ingresos, 'contado_100_hasta', r.contado_minimo_100)
          from reglas_credito r where r.id = 'vigente') as reglas
from a, cronograma(a.precio, a.inicial, a.exento) c
order by c.meses
$sql$, array['admin','asistente','gestor','asesor'], 13),

('renaware', 'repuestos_buscar',
 'Busca repuestos (asas, perillas, filtros, elementos desechables, prefiltros, botellas filtrantes, piezas de extractor, olla a presión, etc.) en la lista de repuestos y en la lista general: código, precio de cliente, precio de asesor y puntos. Acepta nombres coloquiales (alias).',
 '{"type":"object","properties":{"q":{"type":"string","description":"Qué repuesto buscas, p. ej. \"perilla\", \"prefiltro aqua nano\", \"asa olla 8 litros\"."}}}',
 'sql', $sql$
with s as (select unaccent_safe(trim(coalesce($1->>'q',''))) as q),
     ali as (select distinct z.nombre as pieza, z.codigo_general from pieza_alias a join piezas z on z.clave = a.clave, s
             where s.q <> '' and (unaccent_safe(a.alias) like '%' || s.q || '%' or unaccent_safe(z.nombre) like '%' || s.q || '%'))
select p.lista_id as lista, p.codigo, p.categoria, p.nombre, p.precio as precio_cliente, p.precio_asesor, p.puntos, p.regalo
from productos p, s
where p.activo and (p.lista_id = 'repuestos' or unaccent_safe(coalesce(p.categoria,'')) like 'repuestos%')
  and (s.q = ''
       or unaccent_safe(p.nombre) like '%' || s.q || '%'
       or unaccent_safe(coalesce(p.categoria,'')) like '%' || s.q || '%'
       or p.codigo = s.q
       or exists (select 1 from ali where unaccent_safe(p.nombre) like '%' || unaccent_safe(ali.pieza) || '%' or p.codigo = ali.codigo_general))
order by (p.lista_id = 'repuestos') desc, p.orden
limit 60
$sql$, array['admin','asistente','gestor','asesor'], 14),

('renaware', 'zona_credito',
 'Dice si una zona tiene crédito según la lista oficial de Zonas Autorizadas de Rena Ware. Busca por distrito, provincia, alias (p. ej. Hunter, Surco) o nombre de zona/urbanización. Si el distrito aparece, tiene crédito salvo en las zonas_sin_credito listadas; si no aparece ningún resultado, ese distrito no tiene crédito (venta al contado, 100 % antes del despacho).',
 '{"type":"object","properties":{"q":{"type":"string","description":"Distrito, provincia, alias o zona, p. ej. \"Cerro Colorado\", \"Cayma\", \"Moquegua\"."}},"required":["q"]}',
 'sql', $sql$
with s as (select unaccent_safe(trim(coalesce($1->>'q',''))) as q)
select d.departamento, d.provincia, d.distrito, d.alias, d.modalidad, d.solo_urbana, d.todo_restringido, d.todo_texto, d.todo_motivo,
       (select jsonb_agg(jsonb_build_object('zona', z.zona, 'motivo', z.motivo) order by z.zona)
          from zc_zonas z where z.distrito_id = d.id and z.carga_id is not distinct from d.carga_id) as zonas_sin_credito,
       (select c.vigencia from zc_config c where c.id = 'zonas') as vigencia_de_la_lista
from zc_distritos d, s
where d.activo and s.q <> ''
  and (unaccent_safe(d.distrito) like '%' || s.q || '%'
       or unaccent_safe(d.provincia) like '%' || s.q || '%'
       or exists (select 1 from unnest(d.alias) a where unaccent_safe(a) like '%' || s.q || '%')
       or exists (select 1 from unnest(d.provincia_alias) a where unaccent_safe(a) like '%' || s.q || '%')
       or exists (select 1 from zc_zonas z where z.distrito_id = d.id and unaccent_safe(z.zona) like '%' || s.q || '%'))
order by (unaccent_safe(d.distrito) = s.q) desc, d.departamento, d.provincia, d.distrito
limit 40
$sql$, array['admin','asistente','gestor','asesor'], 15),

('renaware', 'concursos_vigentes',
 'Catálogo de programas y concursos de Rena Ware (Empiece Ya, Nivel Cero, viajes, bonos) con nivel, premio, requisito y vigencia; marca cuáles están vigentes hoy.',
 '{"type":"object","properties":{"solo_vigentes":{"type":"boolean","description":"true (por defecto) para ver solo los vigentes."}}}',
 'sql', $sql$
with s as (select coalesce(($1->>'solo_vigentes')::boolean, true) as sv)
select c.programa, c.categoria, c.nivel, c.premio, c.requisito, c.vigencia_desde, c.vigencia_hasta, c.periodos, c.fuente,
       (coalesce(c.vigencia_desde, hoy_lima()) <= hoy_lima() and (c.vigencia_hasta is null or c.vigencia_hasta >= hoy_lima())) as vigente
from pr_catalogo c, s
where c.activo and (not s.sv or (coalesce(c.vigencia_desde, hoy_lima()) <= hoy_lima() and (c.vigencia_hasta is null or c.vigencia_hasta >= hoy_lima())))
order by c.vigencia_desde desc nulls last, c.programa, c.nivel
limit 60
$sql$, array['admin','asistente','gestor','asesor'], 16),

('renaware', 'asesor_buscar',
 'Busca asesores del equipo en la base de personas (eq_personas) por nombre, código de Rena Ware, celular o DNI: código, patrocinador, fecha y período de ingreso, si está activo, si es Desarrollador de Equipo, distrito.',
 '{"type":"object","properties":{"q":{"type":"string","description":"Nombre (o parte), código, celular o DNI."}},"required":["q"]}',
 'sql', $sql$
with s as (select unaccent_safe(trim(coalesce($1->>'q',''))) as q)
select p.id as persona_id, p.codigo_asesor, p.nombre, p.celular, p.activo, p.ingreso_fecha,
       periodo_numero(p.ingreso_ind) as pb_ingreso, periodo_ciclo(p.ingreso_ind) as anio_ingreso,
       pa.nombre as patrocinador, pa.codigo_asesor as patrocinador_codigo,
       (p.ascendio_ind is not null) as es_desarrollador, periodo_numero(p.ascendio_ind) as pb_ascenso,
       p.distrito, p.provincia, p.origen, p.codigo_division
from eq_personas p left join eq_personas pa on pa.id = p.patrocinador_id, s
where s.q <> '' and (p.nombre_norm like '%' || s.q || '%' or unaccent_safe(p.nombre) like '%' || s.q || '%'
                     or p.codigo_asesor = s.q or p.celular = s.q or p.dni = s.q)
order by p.activo desc, p.nombre
limit 25
$sql$, array['admin','asistente','gestor'], 20),

('renaware', 'equipo_de',
 'Árbol de un asesor: sus afiliados directos y las generaciones debajo (hasta 6), con patrocinador, ingreso y si están activos. Sirve para saber quién es de quién y cuántos tiene.',
 '{"type":"object","properties":{"q":{"type":"string","description":"Nombre o código del asesor raíz."}},"required":["q"]}',
 'sql', $sql$
with recursive s as (select unaccent_safe(trim(coalesce($1->>'q',''))) as q),
 raiz as (select p.id, p.nombre, p.codigo_asesor from eq_personas p, s
          where s.q <> '' and (p.codigo_asesor = s.q or p.nombre_norm like '%' || s.q || '%' or unaccent_safe(p.nombre) like '%' || s.q || '%')
          order by p.activo desc, (p.codigo_asesor = s.q) desc, p.nombre limit 1),
 arbol as (select r.id, r.nombre, r.codigo_asesor, 0 as nivel, null::text as patrocinador from raiz r
           union all
           select p.id, p.nombre, p.codigo_asesor, a.nivel + 1, a.nombre from eq_personas p join arbol a on p.patrocinador_id = a.id where a.nivel < 6)
select a.nivel as generacion, a.codigo_asesor, a.nombre, a.patrocinador, p.activo, p.ingreso_fecha, periodo_numero(p.ingreso_ind) as pb_ingreso, p.celular
from arbol a join eq_personas p on p.id = a.id
order by a.nivel, a.nombre
limit 300
$sql$, array['admin','asistente'], 21),

('renaware', 'puntos_periodo',
 'Puntos oficiales por vendedor en un período, según el reporte de pedidos de Rena Ware (rw_pedidos): puntos que cuentan, pedidos, entregados, despachados, rechazados y soles. Sin pb/anio usa el período actual. Si no devuelve filas, el reporte oficial de ese período todavía no se cargó (mira registros_periodo para lo interno).',
 '{"type":"object","properties":{"pb":{"type":"integer","description":"Número de período (1 a 26)."},"anio":{"type":"integer"},"vendedor":{"type":"string","description":"Filtra por nombre del vendedor."}}}',
 'sql', $sql$
with s as (select coalesce(($1->>'pb')::int, periodo_numero(periodo_indice(hoy_lima()))) as pb,
                  coalesce(($1->>'anio')::int, periodo_ciclo(periodo_indice(hoy_lima()))) as anio,
                  unaccent_safe(trim(coalesce($1->>'vendedor',''))) as v)
select r.anio, r.pb, r.periodo, r.vendedor, r.id_vendedor,
       sum(r.puntos) filter (where r.cuenta_puntos) as puntos, count(*) as pedidos,
       count(*) filter (where r.estado = 'entregado') as entregados,
       count(*) filter (where r.estado = 'despachado') as despachados,
       count(*) filter (where r.estado in ('rechazado','cancelado')) as rechazados_o_cancelados,
       sum(r.total) filter (where r.cuenta_puntos) as total_soles,
       max(r.updated_at)::date as reporte_actualizado_el
from rw_pedidos r, s
where r.anio = s.anio and r.pb = s.pb and (s.v = '' or unaccent_safe(r.vendedor) like '%' || s.v || '%')
group by r.anio, r.pb, r.periodo, r.vendedor, r.id_vendedor
order by puntos desc nulls last
limit 100
$sql$, array['admin','asistente','gestor'], 22),

('renaware', 'registros_periodo',
 'Lo que el equipo ingresó en el registro interno en un período: resumen (total, por revisar, revisados, ingresados, procesados, afiliaciones, contado, crédito, observados, iniciales) y por asesor (registros, afiliaciones, ventas, procesados, puntos). Sin pb/anio usa el período actual.',
 '{"type":"object","properties":{"pb":{"type":"integer"},"anio":{"type":"integer"}}}',
 'sql', $sql$
with s as (select coalesce(($1->>'pb')::int, periodo_numero(periodo_indice(hoy_lima()))) as pb,
                  coalesce(($1->>'anio')::int, periodo_ciclo(periodo_indice(hoy_lima()))) as anio),
     i as (select (s.anio - 2026) * 26 + (s.pb - 1) as ind, s.pb, s.anio from s),
     t as (
       select 'resumen' as fila, i.pb, i.anio, to_jsonb(r) - 'periodo_ind' as datos from i left join v_periodo_resumen r on r.periodo_ind = i.ind
       union all
       select 'asesor', i.pb, i.anio, to_jsonb(a) - 'periodo_ind' from i join v_asesor_periodo a on a.periodo_ind = i.ind)
select t.fila, t.pb, t.anio, t.datos from t
order by (t.fila = 'resumen') desc, (t.datos->>'puntos')::numeric desc nulls last
limit 120
$sql$, array['admin','asistente'], 23),

('renaware', 'registros_buscar',
 'Busca en el registro interno de ventas y afiliaciones (lo que el equipo ingresó) por cliente, asesor, código, número de pedido, celular o DNI: tipo, fecha, período, producto, inicial, cuotas, estado (nuevo/revisado/ingresado/procesado), resultado del crédito (observado/aprobado/rechazado) y número de pedido.',
 '{"type":"object","properties":{"q":{"type":"string"},"estado":{"type":"string","description":"nuevo, revisado, ingresado o procesado"},"tipo":{"type":"string","description":"afiliacion, contado o credito"}}}',
 'sql', $sql$
with s as (select unaccent_safe(trim(coalesce($1->>'q',''))) as q, nullif($1->>'estado','') as e, nullif($1->>'tipo','') as t)
select r.codigo, r.tipo, r.fecha, r.periodo_numero as pb, r.periodo_ciclo as anio, r.asesor, g.asesor_codigo, r.titular as cliente, r.celular,
       r.distrito, r.zona_credito, r.producto, r.adicionales, r.items_detalle, r.inicial, r.cuotas, r.precio_total, r.cuota_mensual, r.saldo_financiar,
       r.estado, r.resultado, g.numero_pedido, g.fecha_sistema, r.observacion_vence, r.creado_en::date as registrado_el
from v_registros r join registros g on g.id = r.id, s
where (s.q = '' or unaccent_safe(r.titular) like '%' || s.q || '%' or unaccent_safe(r.asesor) like '%' || s.q || '%'
       or r.codigo = s.q or g.numero_pedido = s.q or r.celular = s.q or r.dni = s.q)
  and (s.e is null or r.estado::text = s.e) and (s.t is null or r.tipo::text = s.t)
order by r.creado_en desc
limit 40
$sql$, array['admin','asistente'], 24),

('renaware', 'pedidos_buscar',
 'Busca pedidos oficiales de Rena Ware (reporte del back office) por cliente, vendedor, número de orden o celular: período, fechas de orden/despacho/entrega, estado, puntos, total, contado o crédito, cuotas y productos.',
 '{"type":"object","properties":{"q":{"type":"string"}},"required":["q"]}',
 'sql', $sql$
with s as (select unaccent_safe(trim(coalesce($1->>'q',''))) as q)
select r.n_orden, r.periodo, r.fecha_orden, r.fecha_despacho, r.fecha_entrega, r.estado, r.estatus, r.cuenta_puntos, r.puntos, r.total,
       r.credito_contado, c.cuotas, r.vendedor, r.cliente, r.celular, c.ciudad, c.productos
from rw_pedidos r join crm_pedidos c on c.n_orden = r.n_orden, s
where s.q <> '' and (unaccent_safe(r.cliente) like '%' || s.q || '%' or unaccent_safe(r.vendedor) like '%' || s.q || '%'
                     or r.n_orden::text = s.q or r.celular = s.q)
order by r.fecha_orden desc nulls last
limit 40
$sql$, array['admin','asistente','gestor'], 25),

('renaware', 'clientes_buscar',
 'Busca clientes en la base única por nombre, documento o celular, con sus pedidos oficiales (orden, período, estado, productos, total) y cuántas reparaciones tienen.',
 '{"type":"object","properties":{"q":{"type":"string"}},"required":["q"]}',
 'sql', $sql$
with s as (select unaccent_safe(trim(coalesce($1->>'q',''))) as q)
select c.id as cliente_id, c.nombre, c.documento, c.celular, c.correo, c.origen, c.trato,
       (select jsonb_agg(jsonb_build_object('n_orden', p.n_orden, 'periodo', p.periodo, 'estado', p.estado, 'productos', left(cp.productos, 160), 'total', p.total) order by p.fecha_orden desc nulls last)
          from rw_pedidos p join crm_pedidos cp on cp.n_orden = p.n_orden where cp.cliente_id = c.id) as pedidos,
       (select count(*) from rep_ordenes o where o.cliente_id = c.id and not coalesce(o.anulado, false)) as reparaciones
from clientes c, s
where c.fusionado_en is null and s.q <> ''
  and (unaccent_safe(c.nombre) like '%' || s.q || '%' or c.documento = s.q or c.celular = s.q
       or exists (select 1 from unnest(c.nombres_vistos) nv where unaccent_safe(nv) like '%' || s.q || '%'))
order by c.nombre
limit 20
$sql$, array['admin','asistente'], 26),

('renaware', 'premios',
 'Premios de Rena Ware del equipo (WV08): por persona o por estado — por_llegar (oficiales pendientes de llegar), por_entregar (en oficina), sin_publicar (entregados sin foto en el grupo), declarado (sin confirmar en RenaKit), entregado. Incluye programa, PB, nivel, premio y fechas.',
 '{"type":"object","properties":{"q":{"type":"string","description":"Nombre o código del asesor, premio o programa."},"estado":{"type":"string","description":"por_llegar, por_entregar, sin_publicar, declarado o entregado"}}}',
 'sql', $sql$
with s as (select nullif($1->>'estado','') as e, unaccent_safe(trim(coalesce($1->>'q',''))) as q)
select p.nombre, p.codigo, p.programa, p.pb, p.nivel, p.premio, p.cantidad, p.tipo, p.origen,
       case when p.entregado_en is not null and p.publicado_en is null then 'entregado_sin_publicar'
            when p.entregado_en is not null then 'entregado'
            when p.recibido_en is not null then 'en_oficina_por_entregar'
            when p.tipo = 'declarado' and p.confirmado_en is null then 'declarado_sin_confirmar'
            else 'pendiente_de_llegar' end as estado,
       p.declarado_en, p.confirmado_en, p.recibido_en, p.avisado_en, p.entregado_en, p.publicado_en, p.periodo_fin, p.nota
from pr_premios p, s
where p.div = 'WV08'
  and (s.q = '' or unaccent_safe(p.nombre) like '%' || s.q || '%' or p.codigo = s.q or unaccent_safe(p.premio) like '%' || s.q || '%' or unaccent_safe(p.programa) like '%' || s.q || '%')
  and (s.e is null
       or (s.e = 'por_entregar' and p.recibido_en is not null and p.entregado_en is null)
       or (s.e = 'por_llegar' and p.recibido_en is null and p.entregado_en is null)
       or (s.e = 'sin_publicar' and p.entregado_en is not null and p.publicado_en is null)
       or (s.e = 'declarado' and p.tipo = 'declarado' and p.confirmado_en is null)
       or (s.e = 'entregado' and p.entregado_en is not null))
order by coalesce(p.periodo_fin, p.creado_en::date) desc, p.nombre
limit 80
$sql$, array['admin','asistente'], 27),

('renaware', 'empiece_ya_buscar',
 'Dice si una persona ya ganó el Empiece Ya (resultados oficiales de todos los grupos): primera calificación, división, y los premios que figuran por PB. Incluye hasta qué PB están cargados los resultados.',
 '{"type":"object","properties":{"q":{"type":"string","description":"Nombre o código."}},"required":["q"]}',
 'sql', $sql$
with s as (select unaccent_safe(trim(coalesce($1->>'q',''))) as q)
select a.codigo, a.nombre, a.division, a.fecha_calificacion as primera_calificacion, a.origen,
       (select jsonb_agg(jsonb_build_object('anio', e.anio, 'pb', e.pb, 'premio', e.premio) order by e.anio, e.pb) from eya_premios e where e.codigo = a.codigo) as premios_por_pb,
       (select max(pe.fecha_cierre) from eya_periodos pe) as resultados_cargados_hasta
from eya_asesores a, s
where s.q <> '' and (unaccent_safe(a.nombre) like '%' || s.q || '%' or a.codigo = s.q)
order by a.nombre
limit 30
$sql$, array['admin','asistente','gestor','asesor'], 28),

('renaware', 'nuevos_nivel_cero',
 'Los nuevos del equipo en su Nivel Cero y ventana de Empiece Ya: afiliador, fecha de inscripción, clases válidas de 5, hasta cuándo vence el Nivel Cero, estado del Empiece Ya (en plazo o no), PB de ingreso, cierre de su ventana y estado del test.',
 '{"type":"object","properties":{"solo_en_curso":{"type":"boolean","description":"true (por defecto) para ver solo los que están dentro del plazo."},"q":{"type":"string","description":"Nombre para filtrar."}}}',
 'sql', $sql$
with s as (select coalesce(($1->>'solo_en_curso')::boolean, true) as sc, unaccent_safe(trim(coalesce($1->>'q',''))) as q)
select x->>'nombre' as nombre, x->>'afiliador' as afiliador, (x->>'fecha_inscripcion')::date as inscripcion,
       (x->>'validas')::int as clases_validas, (x->>'vence')::date as nivel_cero_vence, x->>'estado' as estado_nivel_cero,
       x->>'ey_estado' as estado_empiece_ya, (x->'pb_ingreso'->>'pb')::int as pb_ingreso, (x->'ey_fin'->>'cierre')::date as empiece_ya_hasta,
       x->'test'->>'estado' as test, (x->>'botella_entregada_en')::date as botella_entregada, x->>'celular' as celular
from jsonb_array_elements(n0_inscritos_json(null)) x, s
where not coalesce((x->>'excluido')::boolean, false)
  and (not s.sc or x->>'estado' = 'en_curso')
  and (s.q = '' or unaccent_safe(x->>'nombre') like '%' || s.q || '%')
order by (x->>'fecha_inscripcion')::date desc
limit 80
$sql$, array['admin','asistente'], 29),

('renaware', 'reparaciones',
 'Órdenes de reparación de la oficina (cocinas, ollas, tapas, limpieza, asas y perillas): estado, cliente, asesor, ítems, fecha de ingreso y estimada, precio al cliente, cobrado, costo del proveedor y margen del asesor. Por defecto solo las abiertas.',
 '{"type":"object","properties":{"q":{"type":"string","description":"Cliente, asesor, número de orden o celular."},"estado":{"type":"string"},"incluir_cerradas":{"type":"boolean"}}}',
 'sql', $sql$
with s as (select unaccent_safe(trim(coalesce($1->>'q',''))) as q, nullif($1->>'estado','') as e, coalesce(($1->>'incluir_cerradas')::boolean, false) as ic)
select o.numero, 'R-' || lpad(o.numero::text, 4, '0') as codigo, o.tipo, o.estado, o.cliente_nombre, o.cliente_celular, o.asesor_nombre, o.items, o.solicitud,
       o.garantia, o.proveedor, o.diagnostico, o.fecha_ingreso::date as ingreso, o.fecha_estimada, o.precio_cliente, o.cobrado, o.precio_proveedor, o.costo_envio,
       (coalesce(o.precio_cliente, 0) - coalesce(o.precio_proveedor, 0) - coalesce(o.costo_envio, 0)) as margen_asesor,
       o.entregado_en::date as entregado, o.cerrado_en::date as cerrado
from rep_ordenes o, s
where not coalesce(o.anulado, false) and (s.ic or o.cerrado_en is null)
  and (s.q = '' or unaccent_safe(o.cliente_nombre) like '%' || s.q || '%' or unaccent_safe(coalesce(o.asesor_nombre,'')) like '%' || s.q || '%'
       or o.numero::text = s.q or o.cliente_celular = s.q)
  and (s.e is null or o.estado = s.e)
order by o.fecha_ingreso desc
limit 50
$sql$, array['admin','asistente'], 30),

('renaware', 'pendientes_hoy',
 'La pantalla Hoy de la plataforma: lo que hay que atender ahora, por módulo y urgencia (registros sin revisar, créditos observados, reportes por cargar, conciliación, premios por entregar, reparaciones listas, Nivel Cero y tests por vencer, bienvenidas, seguimientos, facturación).',
 '{"type":"object","properties":{}}',
 'sql', $sql$
select x->>'modulo' as modulo, x->>'nivel' as urgencia, x->>'titulo' as titulo, x->>'detalle' as detalle, x->>'accion' as accion, x->>'enlace' as modulo_id
from jsonb_array_elements(hoy_items_v2(coalesce($2->>'rol', 'admin'))->'items') x
$sql$, array['admin','asistente','gestor'], 31),

('renaware', 'seguimiento_clientes',
 'Seguimientos post-venta pendientes o próximos (bienvenida al recibir, Nutri Sensor a la semana, brillo al mes, fin de cuotas, repuestos de filtros por ciclo): cliente, celular, vendedor, tipo, vence, días y estado.',
 '{"type":"object","properties":{"estado":{"type":"string","description":"pendientes (por defecto: vencido y próximo), vencido, proximo, hecho, al_dia, todos"}}}',
 'sql', $sql$
with s as (select coalesce($1->>'estado', 'pendientes') as e)
select j->>'cliente' as cliente, j->>'celular' as celular, j->>'vendedor' as vendedor, j->>'tipo' as tipo, j->>'clase' as clase,
       (j->>'vence')::date as vence, (j->>'dias')::int as dias, j->>'estado' as estado, j->>'sistema' as sistema, j->>'n_orden' as n_orden, j->>'periodo' as periodo
from crm_acciones(hoy_lima()) j, s
where (s.e = 'todos' or (s.e = 'pendientes' and j->>'estado' in ('vencido','proximo')) or j->>'estado' = s.e)
order by (j->>'vence')::date nulls last
limit 120
$sql$, array['admin','asistente'], 32),

('renaware', 'facturacion_pendiente',
 'Comisiones por facturar por asesor (fact_facturas en borrador): cuántas, neto pendiente, semanas, RUC y qué le falta para poder facturar.',
 '{"type":"object","properties":{}}',
 'sql', $sql$
select f.asesor, f.codigo_asesor, f.ruc, count(*) as comisiones_por_facturar, sum(f.neto) as neto_pendiente,
       min(f.etiqueta_semana) as desde_semana, max(f.etiqueta_semana) as hasta_semana,
       (select l.le_falta from fact_listos l where l.persona_id = f.persona_id) as le_falta_para_facturar
from fact_facturas f where f.estado = 'borrador'
group by f.persona_id, f.asesor, f.codigo_asesor, f.ruc
order by neto_pendiente desc
limit 100
$sql$, array['admin','gestor'], 33),

('renaware', 'local_turnos',
 'Turnos del local compartido del equipo: fecha, bloque (mañana/tarde), titular, estado (pendiente, confirmado, ofrecido, sin cubrir, cerrado). Por defecto, de hoy a 7 días.',
 '{"type":"object","properties":{"desde":{"type":"string","description":"AAAA-MM-DD"},"hasta":{"type":"string","description":"AAAA-MM-DD"},"persona":{"type":"string"}}}',
 'sql', $sql$
with s as (select coalesce(($1->>'desde')::date, hoy_lima()) as d1, coalesce(($1->>'hasta')::date, hoy_lima() + 7) as d2, unaccent_safe(trim(coalesce($1->>'persona',''))) as p)
select t.fecha, t.bloque, t.titular, t.titular_original, t.estado, t.modo, t.ofrecida_a, t.nota
from loc_turnos t, s
where t.fecha between s.d1 and s.d2 and (s.p = '' or unaccent_safe(coalesce(t.titular,'')) like '%' || s.p || '%')
order by t.fecha, t.bloque
limit 120
$sql$, array['admin'], 34),

('renaware', 'capacitaciones',
 'Clases del Nivel Cero programadas (fecha, hora, tema, modalidad) y el horario habitual de capacitaciones de la oficina.',
 '{"type":"object","properties":{}}',
 'sql', $sql$
select 'clase_programada' as tipo, c.fecha, c.hora::text as hora, c.tema, c.tipo as modalidad
from n0_clases c where not coalesce(c.borrada, false) and c.fecha >= hoy_lima() - 7
union all
select 'horario_habitual', null::date, x->>'hora',
       (array['lunes','martes','miércoles','jueves','viernes','sábado','domingo'])[case when (x->>'dia')::int = 0 then 7 else (x->>'dia')::int end],
       null
from n0_config n, jsonb_array_elements(n.horarios) x
order by 2 nulls last, 3
limit 40
$sql$, array['admin','asistente','gestor','asesor'], 35),

('renaware', 'modulos_plataforma',
 'Los módulos de la plataforma: nombre, para qué sirve, dirección web y qué roles lo ven. Úsala para decir dónde se hace algo (registrar una venta, ver premios, reparaciones, etc.).',
 '{"type":"object","properties":{}}',
 'sql', $sql$
select m.id, m.nombre, m.descripcion, m.url, m.roles, m.acceso from plataforma_modulos m where m.activo order by m.orden
$sql$, array['admin','asistente','gestor','asesor'], 36)

on conflict (proyecto, nombre) do update set
  descripcion = excluded.descripcion, parametros = excluded.parametros, tipo = excluded.tipo, sql = excluded.sql,
  roles = excluded.roles, orden = excluded.orden, activo = true, actualizado_en = now();
