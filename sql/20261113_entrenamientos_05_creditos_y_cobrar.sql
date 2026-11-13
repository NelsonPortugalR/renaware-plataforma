-- =====================================================================================================
-- Entrenamientos: los dos módulos que faltaban (13 de noviembre de 2026). Aplicado en la base; este archivo es la copia.
--
-- Pedido de Nelson:
--   · «Créditos y pedidos»: enseñar qué información hay que pedirle al cliente para un crédito y cómo se llena el pedido.
--   · «Cómo cobrar»: un módulo grande con tres lecciones, en este orden: Abrir cuentas, Facturar, Declarar.
-- Antes todo «cómo cobrar» era una sola lección dentro de «Crece en el negocio» («Cobrar: SUNAT, facturar y declarar»);
-- se retira (no tenía materiales ni avance de nadie). No se borra: queda marcada, como todo en la plataforma.
--
-- Los módulos quedan así: 1 Empieza bien · 2 Consigue citas · 3 La presentación · 4 Cierra la venta ·
-- 5 Créditos y pedidos · 6 Cómo cobrar · 7 Crece en el negocio · 8 Trabaja en ti.
-- «Contratos: contado y crédito» se queda en «Cierra la venta» (es cerrar; el pedido y el crédito van en el módulo nuevo).
--
-- Las lecciones nacen sin material: Nelson o su asistente lo suben desde /asesores/ con el modo edición,
-- y ahí mismo se cambian nombres, descripciones y orden. Se puede volver a correr: no duplica nada.
-- =====================================================================================================

do $$
declare v_cred uuid; v_cob uuid;
begin
  -- «Créditos y pedidos»
  select id into v_cred from ent_modulos where titulo = 'Créditos y pedidos' and not borrado limit 1;
  if v_cred is null then
    insert into ent_modulos (titulo, descripcion, orden, roles)
    values ('Créditos y pedidos', 'Qué pedirle al cliente para su crédito y cómo llenar el pedido sin errores.', 5, array['admin', 'asistente', 'asesor'])
    returning id into v_cred;
  end if;
  insert into ent_lecciones (modulo_id, titulo, descripcion, orden)
  select v_cred, x.titulo, x.descripcion, x.orden
    from (values ('Qué pedir para un crédito', 'Los datos y documentos del cliente que necesitamos para que su crédito salga.', 1),
                 ('Llenado del pedido', 'Cómo llenar el pedido paso a paso, al contado y al crédito.', 2)) as x(titulo, descripcion, orden)
   where not exists (select 1 from ent_lecciones l where l.modulo_id = v_cred and l.titulo = x.titulo);

  -- «Cómo cobrar»
  select id into v_cob from ent_modulos where titulo = 'Cómo cobrar' and not borrado limit 1;
  if v_cob is null then
    insert into ent_modulos (titulo, descripcion, orden, roles)
    values ('Cómo cobrar', 'Lo que hay que tener y hacer para que te paguen tus comisiones.', 6, array['admin', 'asistente', 'asesor'])
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

  -- los dos módulos que seguían bajan un lugar («Crece en el negocio» ya no habla de cobrar)
  update ent_modulos set orden = 7, descripcion = 'Plan de compensación, afiliación y la oficina.', actualizado_en = now()
   where id = '65f0e01d-8652-4471-9a31-67d12ee1105f' and (orden <> 7 or descripcion <> 'Plan de compensación, afiliación y la oficina.');
  update ent_modulos set orden = 8, actualizado_en = now()
   where id = '115cbb6c-6bc2-4a04-b027-0ecdd6c2462b' and orden <> 8;
end $$;
