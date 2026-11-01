-- Chat de la plataforma: fichas iniciales (lo que no es tabla: reglas, programas, servicios, horarios).
-- Fuente: reglas documentadas del equipo al 31/10/2026. Lo que cambia con el tiempo (vigencias, precios de listas,
-- puntos) NO va en fichas: lo dan las herramientas sobre las tablas. Se puede volver a correr (por proyecto + título).

create unique index if not exists chat_fichas_titulo_idx on public.chat_fichas (proyecto, titulo);

insert into public.chat_fichas (proyecto, tema, titulo, contenido, roles, fuente) values

('renaware', 'periodos', 'Períodos y semanas de Rena Ware', $f$
- Un período de bonificación (PB) dura 14 días y empieza un jueves; hay 26 al año (PB01 a PB26). El año de períodos arranca el 25 de diciembre de 2025 (PB01-2026).
- Cada período tiene semana 1 y semana 2 (jueves a miércoles). Las semanas de Rena Ware también se numeran 1 a 52 arrancando jueves.
- El cierre nominal es el miércoles; el corte real para que un pedido cuente es el viernes siguiente a las 11:00 a. m. (hora de Lima).
- Semana de bono: la primera semana de cada período el puntaje sube 15 % (a veces lo extienden unos días o es 20 %; se avisa en el grupo del equipo). La configuración vigente la da periodo_actual (en_semana_de_bono_15).
- Bono por puntos: cuando el puntaje total del período sube a un nivel (p. ej. Nivel 3 = 9 %), todas las ventas del período pasan a ese porcentaje, no solo las siguientes.
- Un pedido cuenta puntos cuando se despacha o entrega (fecha_sistema, o fecha_reescrito si es reescrito); no cuenta si es reuso ni si fue rechazado o cancelado.
- PPV = puntos personales (ventas propias). GPV = PPV más el PPV de todo su equipo (incluye el propio). TOV = producción total de la organización.
$f$, array['admin','asistente','gestor','asesor'], 'reglas del equipo'),

('renaware', 'precios', 'Listas de precios: cuáles hay y cómo se combinan', $f$
- Hay cuatro tipos de lista en el cotizador, en este orden: Tienda en línea, Lista General, Especiales y Flash (más la lista de Repuestos). Las promociones (Especiales y Flash) cambian seguido; solo se usan las vigentes (listas_vigentes).
- Tienda en línea: solo al contado, solo venta a terceros (nunca autocompra), no se mezcla con otras listas, debe pagarse el 100 % antes del despacho a cualquier dirección. Su comisión y sus puntos son menores que los de la lista regular.
- Lista General, Especiales y Flash sí se mezclan entre sí y sirven para autocompra, venta a terceros, contado y crédito. La General se usa para mostrar precios regulares, comparar contra la promoción y cuando el cliente quiere un solo producto. Los Especiales suelen traer los productos principales y los Flash los complementarios; cada promoción tiene número (Especial #16, Flash #3) e incluye el producto principal más su acompañamiento y a veces un regalo.
- Las vigencias de las listas suelen extenderse unos días; la fecha vigente está en la base (listas_vigentes), no en el PDF.
- Herramienta de cierre de la Lista General (solo después de varios «no» o «mejor más adelante»): 15 % de descuento por pago del 100 % al momento con tarjeta de crédito o débito (es la lista de tienda en línea: comisión y puntos menores).
- Herramienta de cierre de las listas de promociones (también solo después de varios «no»): el regalo vigente de cada lista.
- Upsell que Rena Ware a veces lanza: al comprar una promoción de Especiales o Flash el cliente puede elegir UNO de dos productos a casi 50 % de descuento; aplica según contado o crédito y tiene vigencia propia.
- Coaching: la clave no es memorizar nombres sino mantener la calma al buscar el producto en el catálogo y la lista.
$f$, array['admin','asistente','gestor','asesor'], 'reglas del equipo'),

('renaware', 'credito', 'Reglas de crédito y contado', $f$
- Inicial mínima: 10 % del precio de cliente (también en autocompra); el cliente puede dar más, nunca menos. Según la inicial se calculan las cuotas posibles (cotizar).
- Saldo a financiar mínimo S/ 1,050 (por eso se usa S/ 1,200 de precio como referencia). Cuota mensual mínima S/ 150. Plazos: 3, 6, 9, 12, 15 o 18 cuotas.
- Gastos y comisiones: S/ 20 por mes, se cobran una sola vez por pedido: con varios ítems al crédito la cuota mensual baja S/ 20 por cada ítem adicional (2 ítems = 20, 3 = 40).
- Interés aproximado 50 % anual. Prepagar 3 o más cuotas va a capital. Pagar el saldo dentro de los 30 días de la entrega no genera interés y mantiene el precio contado.
- Contado: si el pedido es menor a S/ 500 o la zona no tiene crédito, se paga el 100 % antes del despacho. Un pedido ≤ S/ 500 implica inicial ≤ S/ 50, por eso una inicial menor a S/ 50 se bloquea.
- Evaluación: el ingreso mensual del cliente debe ser en promedio 6 veces el valor de la cuota; con sustento bajo conviene 12 a 18 cuotas. Si tiene menos de 3 meses en su actividad, Rena Ware suele pedir garante.
- La dirección de vivienda debe estar en zona de crédito; si el trabajo está fuera de zona, la entrega solo puede ser en casa. La entrega siempre es en zona de crédito.
- Sustentos por fuente de ingreso: independiente (boletas de compra, boletas o facturas emitidas, licencia, estado de cuenta, Excel de Yape), dependiente (boletas de pago de 2 meses), alquileres (recibo de luz de la propiedad + tributo), jubilado (constancia de pensión). Recibo de servicios de menos de 3 meses, no exigido a nombre del cliente.
- Dos referencias personales (no el cónyuge ni el asesor que vende). Rechazado → devolución a cuenta del cliente (BCP, Interbank o BBVA). Aprobado → despachada → entregada.
- Los valores vigentes (porcentaje de inicial, saldo mínimo, cuota mínima, gasto mensual) están en reglas_credito y los devuelve cotizar.
$f$, array['admin','asistente','gestor','asesor'], 'reglas del equipo'),

('renaware', 'precios', 'Precio de autocompra (precio de asesor) y comisiones', $f$
- Precio de autocompra = precio de cliente − (comisión × 1.18). La comisión es el 15 % del valor comisionable del producto (el cuadro de comisiones está al final de la lista de precios; la misma tabla muestra los puntos de cada venta).
- La base ya trae el precio de autocompra de cada producto (precio_autocompra en precios_buscar).
- Repuestos: el precio de asesor es la base y el precio de cliente sale de un factor configurable, redondeado hacia arriba y sin decimales, salvo donde se cargó el precio oficial pieza por pieza.
- Autocompra con factura solo si el asesor ya facturó y comisionó antes con Rena Ware (RUC 10); si no, boleta o pasar a venta a terceros. Autocompra al crédito con factura: solo RUC 10.
$f$, array['admin','asistente','gestor','asesor'], 'reglas del equipo'),

('renaware', 'programas', 'Programa Empiece Ya', $f$
- Ventana: el período en que se inscribe el nuevo más los 2 períodos completos siguientes (3 PB en total). Si no aparece entre los ganadores en esos tres, ya no ganó.
- Niveles: Nivel I = 750 PPV + 2 afiliados; Nivel II = 1,500 PPV + 3 afiliados; Nivel III = 3,500 GPV (mínimo 750 PPV) + 4 afiliados. Los niveles vigentes con su premio están en concursos_vigentes.
- Los premios son acumulativos: la misma persona puede volver a salir en otro PB con otro premio. En el conteo de ganadores cada asesor cuenta una sola vez (primera calificación).
- Los resultados oficiales salen en RenaKit (pu.renakit.com) al cierre de cada período; se cargan por PB en la base (empiece_ya_buscar dice hasta qué PB están cargados). Si ya recibió la botella de acero por el Nivel Cero, se descuenta de su Empiece Ya.
- Si alguien nuevo gana su Empiece Ya, el PPV del afiliado cae en el GPV de quien lo afilió.
$f$, array['admin','asistente','gestor','asesor'], 'programa Rena Ware'),

('renaware', 'programas', 'Nivel Cero y test del Nivel 0', $f$
- Nivel Cero: quien asiste a 5 capacitaciones dentro de sus primeros 30 días gana la botella de acero (es un adelanto del Empiece Ya: si ya la recibió, se descuenta cuando gana el Empiece Ya).
- Al completar las 5 clases tiene 15 días para rendir el test del Nivel 0 en la plataforma (/test/); por ahora aprueba quien lo termina y la nota queda registrada. Al aprobar, la botella entra a Premios como recibida y por entregar.
- Capacitaciones habituales en la oficina: martes 9:30 a. m., miércoles 4:00 p. m. y viernes 4:30 p. m. (capacitaciones trae las programadas). La demostración en vivo con degustación es los miércoles a las 4:00 p. m.
- La bienvenida por WhatsApp dura 5 días (mini entrenamiento) y el seguimiento del Nivel 0 va del día 6 al 30, siempre con la fecha límite; la meta es que recoja su kit y venga a capacitarse.
$f$, array['admin','asistente','gestor','asesor'], 'reglas del equipo'),

('renaware', 'programas', 'Ascenso, calificación, moción y desactivación', $f$
- Ascenso a Desarrollador de Equipo: 100 PPV + 4,000 GPV, o 750 PPV + 3,500 GPV, acumulados en 2 períodos consecutivos (el GPV incluye el PPV). El ascenso siempre es un premio, dé o no premio el concurso vigente.
- Calificar como Desarrollador de Equipo: al menos 50 PPV y al menos 2,000 GPV en el período, o en promedio de los dos últimos.
- Moción: tras 3 períodos en que un Desarrollador califica solo como asesor entra en moción y debe volver a cumplir los requisitos del ascenso; se le avisa en su tercer período.
- Desactivación: un asesor con 13 períodos sin acumular 250 PPV se desactiva; se le avisa un período antes (en el 12). La lista de quienes se desactivan la publica Rena Ware cada período.
- TOV: cuando alguien asciende, desde el período siguiente su GPV deja de contar en el GPV de su patrocinador y pasa a sumar al TOV, mientras califique; si deja de calificar vuelve a sumar al GPV del patrocinador.
- Reconocimientos por TOV acumulado de dos períodos seguidos: 10,000; 12,500; 15,000; 18,000 y 20,000 (se comunica una sola vez por monto).
- En concursos que premian por ganadores dentro del GPV se considera el cargo que se tenía antes de iniciar el concurso.
$f$, array['admin','asistente','gestor','asesor'], 'reglas Rena Ware'),

('renaware', 'programas', 'Concursos de referencia (consultar vigencia en concursos_vigentes)', $f$
- Miami para nuevos: los ganadores del Nivel III del Empiece Ya tienen 3 períodos adicionales para completar 5 Empiece Ya y ganar el viaje.
- Miami para asesores: ascender a Desarrollador de Equipo y luego calificar 2 de 3 períodos con 7,500 GPV, más 3 Empiece Ya personales.
- Tu Bono (agosto 2026, solo asesores que NO están en Empiece Ya, un solo período): afiliaciones 3 = Nivel I y 5 = Nivel II; ventas 2,000 PPV + 1 ganador Empiece Ya = Nivel I y 3,000 PPV + 1 ganador = Nivel II.
- Concurso de Liderazgo (solo Desarrollador de Equipo en adelante, dos semanas): 2 ganadores de categoría personal de cualquier nivel + 1 ganador Empiece Ya = Nivel 1; 3 + 1 = Nivel 2.
- Contrato del líder con Rena Ware: meta de 30,000 de TOV mensual en promedio.
- Lo vigente, con premio y requisito, está en pr_catalogo (concursos_vigentes); esta ficha es referencia de cómo funcionan.
$f$, array['admin','asistente','gestor','asesor'], 'programas Rena Ware 2026'),

('renaware', 'premios', 'Premios: estados y comunicaciones', $f$
- Todo premio ganado lleva estado que se cambia a mano en Premios: declarado (lo calculó el equipo), confirmado (apareció en RenaKit), recibido en oficina, entregado al asesor, publicado (foto en el grupo).
- Comunicaciones: cuando sale en RenaKit se avisa que ganó (una sola vez); cuando llega a oficina se le avisa que lo recoja y se repite cada período hasta que esté entregado; la foto en el grupo es parte del reconocimiento.
- La lista de premios en oficina funciona como inventario (premios con estado por_entregar).
$f$, array['admin','asistente','gestor','asesor'], 'reglas del equipo'),

('renaware', 'servicios', 'Servicios y repuestos: precios al cliente y margen del asesor', $f$
- Jerarquía: vender productos + formar equipo = el negocio. Servicios y repuestos son ingreso extra que cubre los gastos del día y permite seguir visitando.
- Rena Lite: cuesta S/ 60, se vende a S/ 90 (gana S/ 30). Botella de acero: cuesta S/ 60, se vende a S/ 90 (gana S/ 30).
- Repuestos (asas, perillas, olla a presión, extractor, filtro): asas y perillas cuestan en promedio S/ 22 y se venden a S/ 28 (gana S/ 6); en general el asesor gana de S/ 6 a S/ 20 por pieza. Precios exactos: repuestos_buscar. Repuesto de filtro de agua: aprox. S/ 455, gana S/ 50 y es punto comisionable.
- Reparación de cocina: revisión gratis y sin compromiso; se recoge la cocina y se lleva al técnico; en 4–5 días da diagnóstico y, si el cliente acepta, se repara. El asesor gana aprox. S/ 40–60 (referencial); el resto es del técnico.
- Limpieza profunda / lavado y mantenimiento: S/ 35 por utensilio (olla, tapa, Nutri Sensor y asas); unos 3 días útiles (hasta 1 semana); gana S/ 10; pago al final por Yape o efectivo. Quita manchas de calor, reduce quemado y mejora el brillo.
- Pulido profesional (después del lavado): S/ 120–150 por olla, ~3 semanas, gana S/ 25; no incluye cambio de asas ni perillas; no se promociona, se explica si lo piden. Reparación de tapa por soldadura ~S/ 50 (gana S/ 15).
- Garantía (se evalúa antes de cobrar): si es algo del acero (base, perno que se salió, agujeros) y no hay golpes visibles, se lleva para evaluación; si pasa la garantía Rena Ware lo cambia gratis.
- El margen de cada reparación es para el asesor que trajo al cliente (reparaciones muestra margen_asesor).
$f$, array['admin','asistente','gestor','asesor'], 'guía de visitas del equipo'),

('renaware', 'servicios', 'Ciclos de repuestos de filtros y seguimiento post-venta', $f$
- Filtro de agua (Aqua Nano): el prefiltro se cambia cada 1 año y el elemento desechable (repuesto principal) cada 4 años; el filtro de aire cada 18 meses. Quien compra un repuesto reinicia el ciclo desde esa compra.
- Seguimiento de clientes tras la entrega: al recibir, video de lavado + recomendaciones según producto (sartenes: freír sin aceite; filtro: cómo conectarlo; cocina: cómo usarla; olla a presión: uso); a la semana, video de lavado del Nutri Sensor (ollas); al mes, brillo, buen uso y Rena Lite (ollas); un mes antes de terminar las cuotas, contacto.
- Los pendientes de seguimiento los calcula la base (seguimiento_clientes) y los mensajes se mandan desde el módulo Bienvenida.
$f$, array['admin','asistente','gestor','asesor'], 'reglas del equipo'),

('renaware', 'credito', 'Zonas de crédito', $f$
- La venta al crédito solo se hace en zonas autorizadas por Rena Ware (lista oficial «Zonas Autorizadas»). Si el distrito está en la lista tiene crédito, salvo en las zonas restringidas dentro del distrito (zona_credito las lista con su motivo); «solo urbana» significa que fuera de la zona urbana no hay crédito.
- Si el distrito no aparece, no tiene crédito: la venta es al contado y se paga el 100 % antes del despacho.
- La misma base alimenta el buscador de zonas y el formulario de registro. La vigencia de la lista cargada la da zona_credito.
$f$, array['admin','asistente','gestor','asesor'], 'lista oficial Rena Ware'),

('renaware', 'registro', 'Estados de un registro de venta o afiliación', $f$
- Todo registro (afiliación, contado o crédito) pasa por: nuevo → revisado (la información está completa) → ingresado (ya se envió a Rena Ware) → procesado (ya se ve en el sistema; en ese momento se guarda el número de pedido, y en afiliaciones el código del asesor).
- Crédito: además lleva resultado observado / aprobado / rechazado; observado guarda las observaciones y el analista. Aprobado abre despachada y entregada; rechazado abre la devolución (solicitada y hecha).
- Reescrito: igual al contrato pero con el número de pedido arriba; solo de pedidos ya visibles en el sistema.
- Afiliación: cuesta S/ 70 (Yape a nombre de Portugal Research International o cuenta de Rena Ware), con constancia obligatoria; el dato clave es de qué asesor será el afiliado.
- Los pedidos se versionan al editar (versión 2, 3…) sin perder lo original. Cada pedido tiene línea de tiempo (hitos).
- El registro interno es lo que el equipo ingresó; la realidad oficial es el reporte de pedidos de Rena Ware (pedidos_buscar / puntos_periodo). La conciliación cruza ambos.
$f$, array['admin','asistente','gestor'], 'reglas del equipo'),

('renaware', 'plataforma', 'Módulos de la plataforma y dónde se hace cada cosa', $f$
- Registrar una venta o afiliación: módulo Registro (formulario tipo chat). Revisar, ingresar y dar seguimiento a cada registro: Pedidos y afiliaciones (admin).
- Precios, promociones, repuestos y simulador de puntos: Precios y promociones (cotizador).
- Órdenes oficiales y seguimiento post-venta: Pedidos y clientes. Subir el reporte de Rena Ware y conciliar: desde el hub (Hoy).
- Premios (de lo declarado a lo entregado y publicado), Ganadores Empiece Ya (todos los grupos), Nivel Cero (asistencia), Test del Nivel 0, Bienvenida por WhatsApp, Reparaciones, Facturación, Zonas de crédito, Local del equipo (turnos).
- Direcciones exactas y roles: modulos_plataforma. Un solo acceso en el hub y cada módulo se abre ya con sesión (traspaso).
$f$, array['admin','asistente','gestor','asesor'], 'plataforma'),

('renaware', 'oficina', 'Oficina, marca y atención', $f$
- Oficina: Av. Cayma 628, Of. 502, Arequipa, a media cuadra de la Av. Ejército (referencia: Scotiabank). Hay un video de cómo llegar.
- Si la oficina está cerrada, se recibe al cliente igual y se le atiende en el almacén de Rena Ware, a unos metros de la oficina.
- Marca pública (por cumplimiento con Rena Ware): «Nelson Portugal, Representante Independiente de Rena Ware», nunca «Rena Ware Arequipa».
- Clientes fuera de Arequipa: pueden enviar su equipo por Shalom u Olva; hay cobertura nacional derivando al asesor de su ciudad. Quien quiera afiliarse y no es de Arequipa se maneja digital.
- Trato al cliente: siempre de usted en los mensajes del equipo.
$f$, array['admin','asistente','gestor','asesor'], 'reglas del equipo'),

('renaware', 'ventas', 'Flujo comercial, cita y seguimiento', $f$
- Flujo: mensaje inicial → llamada telefónica si no responde (no llamar por WhatsApp) → recordatorio → cita (oficina o domicilio) → atención (primero la solicitud del cliente, luego venta o afiliación). Se mide en prospectos, citas, atenciones y ventas/afiliaciones.
- Sacar la cita: «le llevo un regalo de parte de la compañía y le muestro las promociones sin compromiso»; siempre cerrar con doble alternativa de día («¿la visito hoy o mañana?»); el objetivo de la llamada es agendar, no vender. Hasta las 3 p. m. se ofrece hoy y mañana; después solo mañana o el siguiente día (sábado: «hoy sábado o lunes»).
- Objeción «ya tengo Rena Ware»: por ser cliente se le llevan dos regalos y su opinión vale doble. Objeción «mejor voy a la oficina»: «perfecto, ¿hoy o mañana?».
- Seguimiento si no contesta: hasta 3 llamadas el mismo día, mensaje de reactivación al día siguiente, invitación a los eventos semanales, luego seguimiento regular.
- Escalera de cierre: si no compra, que separe; si no, que se afilie y le sale a menos; si no, afiliarla e invitarla a trabajar juntas. En la casa: demostrar Rena Lite, lavado del Nutri Sensor, quitar manchas de calor, enseñar a usar el Nutri Sensor, receta en vivo, revisar productos sin usar y repuestos; recién al sentarse, catálogo y promociones, preguntando primero si compra al crédito o al contado.
$f$, array['admin','asistente','gestor','asesor'], 'metodología del equipo'),

('renaware', 'facturacion', 'Facturación de asesores (RMT) y SUNAT', $f$
- Las semanas de Rena Ware arrancan jueves: la semana N empieza el 25-12-2025 + (N−1)×7; su período es (N−1)/2.
- fact_facturas.estado: borrador = comisión pendiente de facturar; emitida / enviada / cobrada = ya facturada. IGV 18 % sobre el neto (columnas generadas). Las comisiones ya facturadas se detectan por diferencia entre reportes FPD semanales de Rena Ware (lo que desaparece del pendiente se facturó); por eso la fecha puede ser estimada.
- Vencimientos de las declaraciones mensuales según el último dígito del RUC (fact_vencimientos); Hoy avisa cuando están por vencer. Perder dos cuotas consecutivas de un fraccionamiento lo quiebra entero.
- La emisión electrónica va por Nubefact (PSE); el token nunca se expone en el navegador. Lo que le falta a cada asesor para poder facturar lo dice facturacion_pendiente (RUC, CCI, cuenta bancaria, cuenta de detracción, clave SOL).
$f$, array['admin','gestor'], 'reglas del equipo'),

('renaware', 'local', 'Local compartido del equipo (turnos y cuentas)', $f$
- Horario del local: mañana 9:00 a. m.–1:30 p. m. y tarde 1:30–6:00 p. m. Hay 8 socias con turnos fijos; el domingo en la tarde rota entre todas (una por domingo, aviso el lunes; «no puedo» pasa a la siguiente; el «sí» se confirma entre 48 y 24 h antes; quien cubrió un domingo no entra en las 3 rondas siguientes).
- Cada una confirma su turno el día anterior; si no puede, lo cede o lo cambia desde la plataforma del local (los cedidos se muestran con máximo 7 días de anticipación).
- Cuentas: mensualidad de S/ 90 por persona (S/ 45 quien tiene un solo turno a la semana), vence el 1 de cada mes y se puede pagar hasta el día 7; hubo un gasto único de S/ 50 por persona (letrero e implementación). El último día de cada mes la plataforma pregunta si continúa el mes siguiente.
- Turnos reales por fecha: local_turnos.
$f$, array['admin'], 'reglas del local')

on conflict (proyecto, titulo) do update set
  tema = excluded.tema, contenido = excluded.contenido, roles = excluded.roles, fuente = excluded.fuente, activo = true, actualizado_en = now();
