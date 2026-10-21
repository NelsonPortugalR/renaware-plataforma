-- ============================================================================
-- Pantalla "Hoy", versión 2: alimentada por los módulos vivos.
-- Fuera: concursos de agosto, cumpleaños y aniversarios (sin datos ni dueño).
-- Dentro: registros, cargas pendientes, conciliación, seguimiento de clientes,
-- premios, reparaciones, Nivel Cero y facturación.
-- Cada módulo va en su propio bloque: si uno falla, los demás igual aparecen.
-- ============================================================================
create or replace function public.hoy_items(p_rol text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_hoy  date := hoy_lima();
  v_pi   int  := periodo_indice(v_hoy);
  v_ini  date := periodo_inicio(v_pi);
  v_fin  date := periodo_inicio(v_pi) + 13;
  v_pbc  int  := periodo_numero(v_pi - 1);
  v_anio int  := extract(year from periodo_inicio(v_pi - 1) + 13)::int;
  v_meses text[] := array['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
  v_ollas constant text := '(COOKER|OLLA|CACEROLA|SIGNATURE|PRINCESA|RENAWOK|RENA WOK|SAUCEPAN|SAUCIER|RONDEAU|ASADOR|CONTESSA|PRESSURE)';
  v_items jsonb := '[]'::jsonb;
  v_res jsonb := '{}'::jsonb;
  v_n int; v_a int; v_b int; v_c int; v_cr int; v_meta int;
  v_f date; v_pb int; v_pbey int; v_pts bigint;
  v_txt text; v_sem text;
  r record;
begin
  if p_rol in ('admin','asistente') then

    -- ---- Registros sin revisar (más de 2 días en "nuevo") ----
    select count(*), min(creado_en)::date,
           count(*) filter (where tipo = 'afiliacion'),
           count(*) filter (where tipo = 'contado'),
           count(*) filter (where tipo = 'credito')
      into v_n, v_f, v_a, v_c, v_cr
      from registros
     where estado = 'nuevo' and creado_en < now() - interval '2 days';
    if v_n > 0 then
      v_txt := lista_es(array_remove(array[
        case when v_a > 0 then v_a || case when v_a = 1 then ' afiliación' else ' afiliaciones' end end,
        case when v_c > 0 then v_c || ' de contado' end,
        case when v_cr > 0 then v_cr || ' de crédito' end], null));
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id','registros-sin-revisar','modulo','Pedidos',
        'nivel', case when v_f < v_hoy - 7 then 'alto' else 'medio' end,
        'titulo', v_n || case when v_n = 1 then ' registro sin revisar' else ' registros sin revisar' end,
        'detalle', v_txt || '. El más antiguo es del ' || to_char(v_f, 'DD/MM') || '.',
        'enlace','admin-registros'));
    end if;

    -- ---- Créditos observados ----
    select count(*) into v_n from registros where tipo = 'credito' and resultado::text = 'observado';
    if v_n > 0 then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id','creditos-observados','modulo','Pedidos','nivel','alto',
        'titulo', v_n || case when v_n = 1 then ' crédito observado' else ' créditos observados' end,
        'detalle','Rena Ware pidió información adicional. Resuélvelo para que siga la evaluación.',
        'enlace','admin-registros'));
    end if;

    -- ---- Ventas que coinciden con pedidos oficiales ----
    begin
      select count(*), count(*) filter (where x->>'nivel' = 'segura') into v_n, v_a
        from jsonb_array_elements(conciliacion_calcular()) x;
      if v_n > 0 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','conciliar','modulo','Pedidos','nivel', case when v_a > 0 then 'alto' else 'medio' end,
          'titulo', v_n || case when v_n = 1 then ' venta coincide con un pedido oficial' else ' ventas coinciden con pedidos oficiales' end,
          'detalle', case when v_a = v_n then 'Todas son coincidencias seguras. Al confirmarlas se marcan el número de pedido, el despacho y la entrega.'
                          when v_a > 0 then v_a || ' son seguras y ' || (v_n - v_a) || ' conviene revisarlas. Al confirmar se marcan el número de pedido, el despacho y la entrega.'
                          else 'Conviene revisarlas una por una antes de confirmar.' end,
          'enlace','conciliar','boton','Revisar y confirmar'));
      end if;
    exception when others then null;
    end;

    -- ---- Reporte oficial de pedidos RW ----
    select max(substring(periodo from 'PB(\d+)')::int) into v_pb from crm_pedidos where periodo like v_anio || '-PB%';
    select max(updated_at)::date into v_f from crm_pedidos;
    if v_pb is not null then
      select coalesce(sum(puntos), 0), count(*) into v_pts, v_n from crm_pedidos
       where periodo like v_anio || '-PB' || v_pb || ' %' and coalesce(estatus, '') !~* '^(RECHAZ|CANCEL)';
      v_res := jsonb_build_object('pb', v_pb, 'puntos', v_pts, 'pedidos', v_n);
    end if;
    if coalesce(v_pb, 0) < v_pbc then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id','reporte-rw','modulo','Datos oficiales','nivel','alto',
        'titulo', case when v_pbc - coalesce(v_pb, 0) = 1 then 'Falta el reporte de pedidos del PB' || v_pbc
                       else 'Faltan los reportes de pedidos del PB' || (coalesce(v_pb, 0) + 1) || ' al PB' || v_pbc end,
        'detalle', coalesce('El último cargado es el PB' || v_pb || ', subido el ' || to_char(v_f, 'DD/MM') || '. ', '')
                   || 'De ese reporte salen los puntos, los despachos y los seguimientos de clientes.',
        'enlace','importar-pedidos','boton','Subir el reporte'));
    end if;

    -- ---- Resultados oficiales de Empiece Ya ----
    select max(pb::int) into v_pbey from eya_periodos where anio::int = v_anio;
    if coalesce(v_pbey, 0) < v_pbc then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id','eya','modulo','Datos oficiales','nivel','medio',
        'titulo', case when v_pbc - coalesce(v_pbey, 0) = 1 then 'Faltan los resultados de Empiece Ya del PB' || v_pbc
                       else 'Faltan los resultados de Empiece Ya del PB' || (coalesce(v_pbey, 0) + 1) || ' al PB' || v_pbc end,
        'detalle', coalesce('El último cargado es el PB' || v_pbey || '. ', '') || 'Salen en RenaKit al cierre de cada período.',
        'enlace','empiece-ya'));
    end if;

    -- ---- Ventas en sistema sin número de pedido ----
    select count(*) into v_n from registros
     where estado = 'procesado' and tipo in ('contado','credito')
       and nullif(trim(numero_pedido::text), '') is null;
    if v_n > 0 then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id','sin-numero-pedido','modulo','Pedidos','nivel','medio',
        'titulo', v_n || case when v_n = 1 then ' venta en sistema sin número de pedido' else ' ventas en sistema sin número de pedido' end,
        'detalle','Sin ese número no se pueden cruzar con el reporte oficial de Rena Ware.',
        'enlace','admin-registros'));
    end if;

    -- ---- Ventas listas sin despacho marcado ----
    select count(*) into v_n from registros rg
     where rg.estado = 'procesado' and rg.tipo in ('contado','credito')
       and (rg.tipo = 'contado' or rg.resultado::text = 'aprobado')
       and not exists (select 1 from hitos h where h.registro_id = rg.id and h.tipo::text in ('despachado','entregado'));
    if v_n > 0 then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id','sin-despacho','modulo','Pedidos','nivel','medio',
        'titulo', v_n || case when v_n = 1 then ' venta sin despacho marcado' else ' ventas sin despacho marcado' end,
        'detalle','Al conciliar con el reporte oficial se marca solo; si no, márcalo en el pedido.',
        'enlace','admin-registros'));
    end if;

    -- ---- Vendedores recientes del reporte que no están en la base del equipo ----
    select count(distinct c.id_vendedor) into v_n from crm_pedidos c
     where c.id_vendedor is not null
       and c.fecha_ordenado ~ '^\d{2}/\d{2}/\d{4}'
       and to_date(left(c.fecha_ordenado, 10), 'DD/MM/YYYY') >= v_hoy - 60
       and not exists (select 1 from eq_personas p where p.codigo_asesor = c.id_vendedor::text);
    if v_n > 0 then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id','vendedores-sin-cruzar','modulo','Equipo','nivel','medio',
        'titulo', v_n || case when v_n = 1 then ' vendedor del reporte no está en la base del equipo' else ' vendedores del reporte no están en la base del equipo' end,
        'detalle','Vendieron en los últimos dos meses, pero no se les puede cruzar hasta registrarlos o corregir su código.',
        'enlace','pedidos'));
    end if;

    -- ---- Seguimiento de clientes (bienvenida, Nutri Sensor, brillo, fin de cuotas) ----
    begin
      with ped as (
        select c.n_orden, upper(coalesce(c.productos, '')) as prod,
               case when c.delivery_date ~ '^\d{2}/\d{2}/\d{4}' then to_date(left(c.delivery_date, 10), 'DD/MM/YYYY') end as entrega,
               case when c.fecha_ordenado ~ '^\d{2}/\d{2}/\d{4}' then to_date(left(c.fecha_ordenado, 10), 'DD/MM/YYYY') end as orden,
               c.credito_contado, c.cuotas
          from crm_pedidos c
         where coalesce(c.estatus, '') ~* 'ENTREGADA'
      ), acc as (
        select n_orden, 'bienvenida' as tipo, entrega as vence from ped where entrega is not null
        union all select n_orden, 'semana1', entrega + 7 from ped where entrega is not null and prod ~ v_ollas
        union all select n_orden, 'mes1', entrega + 30 from ped where entrega is not null and prod ~ v_ollas
        union all select n_orden, 'fincuotas', (orden + make_interval(months => cuotas - 1))::date
                    from ped where orden is not null and credito_contado ilike 'cr%' and coalesce(cuotas, 0) > 0
      )
      select count(*) filter (where vence < v_hoy), count(*) filter (where vence between v_hoy and v_hoy + 7)
        into v_a, v_b
        from acc a
       where a.vence >= v_hoy - 45
         and not exists (select 1 from crm_seguimiento s where s.n_orden = a.n_orden and s.tipo = a.tipo);
      if coalesce(v_a, 0) + coalesce(v_b, 0) > 0 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','seguimiento-clientes','modulo','Clientes','nivel', case when v_a > 0 then 'alto' else 'medio' end,
          'titulo', case when v_a > 0 and v_b > 0 then v_a || ' seguimientos de clientes vencidos y ' || v_b || ' para esta semana'
                         when v_a > 0 then v_a || case when v_a = 1 then ' seguimiento de cliente vencido' else ' seguimientos de clientes vencidos' end
                         else v_b || case when v_b = 1 then ' seguimiento de cliente para esta semana' else ' seguimientos de clientes para esta semana' end end,
          'detalle','Bienvenida, video del Nutri Sensor, brillo y aviso de fin de cuotas; cada uno con su mensaje listo.',
          'enlace','pedidos'));
      end if;
    exception when others then null;
    end;

    -- ---- Premios del equipo (WV08) ----
    begin
      select count(*) filter (where tipo = 'declarado' and confirmado_en is null),
             count(*) filter (where recibido_en is not null and entregado_en is null),
             count(*) filter (where recibido_en is not null and entregado_en is null and avisado_en is null),
             count(*) filter (where entregado_en is not null and publicado_en is null)
        into v_a, v_b, v_c, v_n
        from pr_premios where div = 'WV08';
      if v_b > 0 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','premios-por-entregar','modulo','Premios','nivel','alto',
          'titulo', v_b || case when v_b = 1 then ' premio en oficina por entregar' else ' premios en oficina por entregar' end,
          'detalle', case when v_c > 0 then v_c || case when v_c = 1 then ' aún sin avisar al ganador.' else ' aún sin avisar a los ganadores.' end
                          else 'Los ganadores ya están avisados.' end,
          'enlace','equipo'));
      end if;
      if v_a > 0 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','premios-declarados','modulo','Premios','nivel','medio',
          'titulo', v_a || case when v_a = 1 then ' premio declarado sin confirmar' else ' premios declarados sin confirmar' end,
          'detalle','Se confirman cuando aparecen en los resultados oficiales de Rena Ware.',
          'enlace','equipo'));
      end if;
      if v_n > 0 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','premios-sin-publicar','modulo','Premios','nivel','info',
          'titulo', v_n || case when v_n = 1 then ' premio entregado sin publicar en el grupo' else ' premios entregados sin publicar en el grupo' end,
          'detalle','La foto en el grupo es parte del reconocimiento.',
          'enlace','equipo'));
      end if;
    exception when others then null;
    end;

    -- ---- Reparaciones ----
    begin
      select count(*) filter (where o.estado = 'listo'),
             count(*) filter (where o.estado = 'listo' and not exists
               (select 1 from rep_eventos e where e.orden_id = o.id and not e.anulado and e.paso ~* 'avis')),
             count(*) filter (where o.estado <> 'listo' and o.fecha_estimada is not null and o.fecha_estimada < v_hoy)
        into v_a, v_b, v_c
        from rep_ordenes o
       where not o.anulado and o.entregado_en is null and o.cerrado_en is null;
      if v_a > 0 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','reparaciones-listas','modulo','Reparaciones','nivel','alto',
          'titulo', v_a || case when v_a = 1 then ' reparación lista por entregar' else ' reparaciones listas por entregar' end,
          'detalle', case when v_b > 0 then v_b || case when v_b = 1 then ' aún sin avisar al cliente.' else ' aún sin avisar al cliente.' end
                          else 'Los clientes ya están avisados.' end,
          'enlace','reparaciones'));
      end if;
      if v_c > 0 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','reparaciones-atrasadas','modulo','Reparaciones','nivel','medio',
          'titulo', v_c || case when v_c = 1 then ' reparación pasó su fecha estimada' else ' reparaciones pasaron su fecha estimada' end,
          'detalle','Conviene avisar al cliente del nuevo plazo antes de que pregunte.',
          'enlace','reparaciones'));
      end if;
    exception when others then null;
    end;

    -- ---- Nivel Cero: nuevos a una semana de vencer su plazo ----
    begin
      select clases_meta into v_meta from n0_config where id = 'vigente';
      select count(*), string_agg(x->>'nombre' || ' (vence ' || to_char((x->>'vence')::date, 'DD/MM') || ', lleva '
                                  || coalesce(x->>'validas', '0') || ' de ' || coalesce(v_meta::text, '5') || ')', '; ' order by (x->>'vence')::date)
        into v_n, v_txt
        from jsonb_array_elements(n0_inscritos_json(null)) x
       where x->>'estado' = 'en_curso'
         and not coalesce((x->>'excluido')::boolean, false)
         and (x->>'vence')::date between v_hoy and v_hoy + 7;
      if v_n > 0 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','nivel-cero-por-vencer','modulo','Nivel Cero','nivel','medio',
          'titulo', v_n || case when v_n = 1 then ' nuevo a una semana de vencer su Nivel Cero' else ' nuevos a una semana de vencer su Nivel Cero' end,
          'detalle', v_txt || '.',
          'enlace','nivel-cero'));
      end if;
    exception when others then null;
    end;
  end if;

  if p_rol in ('admin','gestor') then
    -- ---- Declaraciones que vencen en los próximos 10 días (una tarjeta por mes) ----
    begin
      for r in
        select v.anio, v.mes::int as mes, min(v.vence) as desde, max(v.vence) as hasta, min(v.vence) - v_hoy as dias,
               string_agg(replace(v.grupo::text, '-', ' y ') || ' (' || to_char(v.vence, 'DD/MM') || ', ' || c.n
                          || case when c.n = 1 then ' asesor)' else ' asesores)' end, '; ' order by v.vence) as detalle
          from fact_vencimientos v
          join lateral (
            select count(*) as n from eq_personas p
             where p.activo and nullif(trim(p.ruc::text), '') is not null
               and right(trim(p.ruc::text), 1) = any(string_to_array(replace(v.grupo::text, '-', ','), ','))
          ) c on true
         where v.vence between v_hoy and v_hoy + 10 and c.n > 0
         group by v.anio, v.mes
         order by min(v.vence)
      loop
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','vence-' || r.anio || '-' || r.mes,'modulo','Facturación',
          'nivel', case when r.dias <= 3 then 'alto' else 'medio' end,
          'titulo','Declaración de ' || v_meses[r.mes] || ': vence '
                   || case when r.desde = r.hasta then 'el ' || to_char(r.desde, 'DD/MM') else 'del ' || to_char(r.desde, 'DD/MM') || ' al ' || to_char(r.hasta, 'DD/MM') end,
          'detalle','Por último dígito del RUC: ' || r.detalle || '.',
          'enlace','facturacion'));
      end loop;
    exception when others then null;
    end;

    -- ---- Comisiones pendientes de facturar ----
    begin
      select count(*), count(distinct persona_id), (array_agg(etiqueta_semana order by periodo_ind, semana))[1]
        into v_n, v_a, v_sem
        from fact_facturas where estado = 'borrador';
      if v_n > 0 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','fact-borradores','modulo','Facturación','nivel','medio',
          'titulo', v_n || case when v_n = 1 then ' comisión pendiente de facturar' else ' comisiones pendientes de facturar' end,
          'detalle','De ' || v_a || case when v_a = 1 then ' asesor' else ' asesores' end
                    || coalesce('; la más antigua es de la semana ' || v_sem, '') || '.',
          'enlace','facturacion'));
      end if;
    exception when others then null;
    end;

    -- ---- Reporte FPD semanal ----
    begin
      select max(cargado_en)::date into v_f from fact_fpd_snapshot;
      if v_f is not null and v_f < v_hoy - 7 then
        v_items := v_items || jsonb_build_array(jsonb_build_object(
          'id','fact-fpd','modulo','Facturación','nivel','medio',
          'titulo','Falta cargar el reporte FPD de esta semana',
          'detalle','El último se cargó el ' || to_char(v_f, 'DD/MM') || '. De ahí salen las comisiones por facturar.',
          'enlace','facturacion'));
      end if;
    exception when others then null;
    end;

    -- ---- Sin RUC (solo si no hay ninguno) ----
    select count(*) into v_n from eq_personas where activo and nullif(trim(ruc::text), '') is not null;
    if v_n = 0 then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id','fact-sin-ruc','modulo','Facturación','nivel','info',
        'titulo','Ningún asesor tiene RUC cargado',
        'detalle','Es el primer dato para emitir sus facturas, junto con la cuenta de detracción y el CCI.',
        'enlace','facturacion'));
    end if;
  end if;

  select coalesce(jsonb_agg(t.x order by case t.x->>'nivel' when 'alto' then 0 when 'medio' then 1 else 2 end, t.i), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(v_items) with ordinality as t(x, i);

  return jsonb_build_object(
    'periodo', jsonb_build_object('numero', periodo_numero(v_pi), 'inicio', v_ini, 'fin', v_fin, 'hoy', v_hoy),
    'oficial', v_res,
    'items', v_items);
end $$;
