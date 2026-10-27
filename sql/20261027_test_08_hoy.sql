-- =====================================================================
-- Test del Nivel 0 · pendiente en «Hoy» de la plataforma (equipo de oficina)
-- Quien completó sus 5 clases y tiene el test por vencer (3 días o menos) sin aprobar.
-- Se agrega justo después del pendiente del Nivel Cero, en el mismo bloque de roles.
-- =====================================================================
do $patch$
declare d text;
  ancla text := $a$        'detalle', v_txt || '. Les quedan 7 días o menos para completar sus 5 clases.','enlace','nivel-cero'));
    end if;
$a$;
  nuevo text := $a$
    -- Test del Nivel 0: completaron sus clases y el test se les vence
    select count(*), string_agg(nombre, ', ' order by dias, nombre) into v_n, v_txt
      from (select initcap(lower(x->>'nombre')) as nombre, (x->'test'->>'dias')::int as dias
              from jsonb_array_elements(n0_inscritos_json(null)) x
             where x->'test'->>'estado' = 'habilitado' and (x->'test'->>'dias')::int <= 3
             order by 2 limit 6) s;
    if v_n > 0 then
      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id','test-vence','modulo','Test del Nivel 0','nivel','medio',
        'titulo', v_n || case when v_n = 1 then ' nuevo tiene su test por vencer' else ' nuevos tienen su test por vencer' end,
        'detalle', v_txt || '. Completaron sus 5 clases y les quedan 3 días o menos para aprobar el test y ganar su botella.',
        'enlace','test'));
    end if;
$a$;
begin
  d := pg_get_functiondef('public.hoy_items_v2(text)'::regprocedure);
  if position('test-vence' in d) > 0 then return; end if;
  if position(ancla in d) = 0 then raise exception 'hoy_items_v2: no encontré el pendiente del Nivel Cero'; end if;
  d := replace(d, ancla, ancla || nuevo);
  execute d;
end $patch$;
