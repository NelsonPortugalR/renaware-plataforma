-- =====================================================================================================
-- Entrenamientos: el módulo «Cómo cobrar» (13 de noviembre de 2026). Aplicado en la base; este archivo es la copia.
--
-- Pedido de Nelson: «Cómo cobrar» es un módulo grande con tres lecciones, en este orden: Abrir cuentas, Facturar,
-- Declarar. Antes todo eso era una sola lección dentro de «Crece en el negocio» («Cobrar: SUNAT, facturar y
-- declarar»); se retira (no tenía materiales ni avance de nadie). No se borra: queda marcada, como todo en la plataforma.
--
-- El mismo día se creó también «Créditos y pedidos» (qué pedir para un crédito, llenado del pedido) y Nelson lo
-- retiró a las pocas horas: «es cierto, ya estaba en cierre de venta». Ese tema es la lección «Contratos: contado
-- y crédito» de «Cierra la venta». El módulo y sus dos lecciones quedaron marcados (sin materiales ni avance);
-- este archivo ya no lo crea, solo deja escrito su retiro.
--
-- Los módulos quedan así: 1 Empieza bien · 2 Consigue citas · 3 La presentación · 4 Cierra la venta ·
-- 5 Cómo cobrar · 6 Crece en el negocio · 7 Trabaja en ti.
--
-- Las lecciones nacen sin material: Nelson o su asistente lo suben desde /asesores/ con el modo edición,
-- y ahí mismo se cambian nombres, descripciones y orden. Se puede volver a correr: no duplica nada.
-- =====================================================================================================

do $$
declare v_cob uuid;
begin
  -- «Cómo cobrar»
  select id into v_cob from ent_modulos where titulo = 'Cómo cobrar' and not borrado limit 1;
  if v_cob is null then
    insert into ent_modulos (titulo, descripcion, orden, roles)
    values ('Cómo cobrar', 'Lo que hay que tener y hacer para que te paguen tus comisiones.', 5, array['admin', 'asistente', 'asesor'])
    returning id into v_cob;
  end if;
  insert into ent_lecciones (modulo_id, titulo, descripcion, orden)
  select v_cob, x.titulo, x.descripcion, x.orden
    from (values ('Abrir cuentas', 'Lo que necesitas tener abierto para que te paguen: RUC, cuenta bancaria con CCI y cuenta de detracciones.', 1),
                 ('Facturar', 'Cómo emitir la factura de tus comisiones.', 2),
                 ('Declarar', 'La declaración a SUNAT: qué se declara y cuándo.', 3)) as x(titulo, descripcion, orden)
   where not exists (select 1 from ent_lecciones l where l.modulo_id = v_cob and l.titulo = x.titulo);

  -- la lección suelta que juntaba los tres temas se retira
  update ent_lecciones set borrada = true, actualizado_en = now()
   where id = 'a3401e00-e9bf-4d27-bdae-a09b4b7ff849' and not borrada;

  -- «Créditos y pedidos» (creado y retirado el mismo día): lo mismo que hace ent_borrar con un módulo
  update ent_modulos set borrado = true, actualizado_en = now()
   where id = '821c8629-22c1-4de0-981a-c1510b644456' and not borrado;
  update ent_lecciones set borrada = true, actualizado_en = now()
   where modulo_id = '821c8629-22c1-4de0-981a-c1510b644456' and not borrada;

  -- el orden final («Crece en el negocio» ya no habla de cobrar)
  update ent_modulos set orden = 5, actualizado_en = now() where id = v_cob and orden <> 5;
  update ent_modulos set orden = 6, descripcion = 'Plan de compensación, afiliación y la oficina.', actualizado_en = now()
   where id = '65f0e01d-8652-4471-9a31-67d12ee1105f' and (orden <> 6 or descripcion <> 'Plan de compensación, afiliación y la oficina.');
  update ent_modulos set orden = 7, actualizado_en = now()
   where id = '115cbb6c-6bc2-4a04-b027-0ecdd6c2462b' and orden <> 7;
end $$;
