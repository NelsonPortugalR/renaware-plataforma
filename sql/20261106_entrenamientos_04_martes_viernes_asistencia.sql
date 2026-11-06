-- Entrenamientos · 6 nov: el desayuno de líderes (martes 9:30 a. m.) y la charla de la
-- oportunidad (viernes 5:00 p. m.) sí cuentan para la asistencia del Nivel Cero (son
-- presenciales en la oficina). Pasan a llevar asistencia y a verse para los asesores;
-- los eventos futuros no editados a mano siguen a la plantilla (el disparador crea sus clases).
update public.hor_plantillas set asistencia = true, publico = true, actualizado_en = now()
 where not borrada and modo = 'presencial' and ((dia = 2 and hora = '09:30') or (dia = 5 and hora = '17:00'));
update public.hor_eventos e set asistencia = true, publico = true, actualizado_en = now()
  from public.hor_plantillas t
 where e.plantilla_id = t.id and not t.borrada and ((t.dia = 2 and t.hora = '09:30') or (t.dia = 5 and t.hora = '17:00'))
   and e.fecha >= public.hoy_lima() and not e.editado;
