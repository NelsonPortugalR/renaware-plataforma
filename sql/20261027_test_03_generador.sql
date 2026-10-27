-- =====================================================================
-- Test del Nivel 0 · lectura de la data viva y generador de preguntas
-- Todo sale de la base al momento de armar cada pregunta: si cambia la
-- lista, la promoción, la zona o el programa, cambia el test.
-- =====================================================================

-- ---------- formato ----------
create or replace function public.ts_fmt(n numeric) returns text
language sql immutable as $$ select to_char(round(coalesce(n, 0)), 'FM999,999,990') $$;

create or replace function public.ts_soles(n numeric) returns text
language sql immutable as $$ select 'S/ ' || to_char(round(coalesce(n, 0)), 'FM999,999,990') $$;

create or replace function public.ts_norm(t text) returns text
language sql immutable as $$
  select btrim(regexp_replace(translate(upper(coalesce(t, '')), 'ÁÉÍÓÚÜÑÀÈÌÒÙ', 'AEIOUUNAEIOU'), '\s+', ' ', 'g'))
$$;

-- "JUEGO DE ÚTILES DE COCINA" -> "Juego de Útiles de Cocina"; respeta códigos como IC-450 o CTU-500.
create or replace function public.ts_bonito(t text) returns text
language plpgsql immutable as $$
declare
  r text := initcap(lower(btrim(coalesce(t, ''))));
  pares text[] := array[
    '\mDe\M','de', '\mDel\M','del', '\mCon\M','con', '\mPara\M','para', '\mY\M','y', '\mLa\M','la',
    '\mEl\M','el', '\mLos\M','los', '\mLas\M','las', '\mEn\M','en', '\mSin\M','sin', '\mPor\M','por',
    '\mAl\M','al', '\mCm\M','cm', '\mPzs\M','pzs', '\mUv\M','UV', '\mEm\M','EM', '\mRw\M','RW',
    '\mIc-','IC-', '\mRwf-','RWF-', '\mCtu-','CTU-', '\mUcu\M','UCU', '\mLx-','LX-', '\mRw15pe\M','RW15PE',
    '\mA\M','a', '\mIii\M','III', '\mIi\M','II'];
  i int;
begin
  if r = '' then return r; end if;
  for i in 1 .. array_length(pares, 1) / 2 loop
    r := regexp_replace(r, pares[2 * i - 1], pares[2 * i], 'g');
  end loop;
  return upper(left(r, 1)) || substr(r, 2);
end $$;

create or replace function public.ts_qid() returns text
language sql volatile as $$ select 'q' || substr(md5(random()::text || clock_timestamp()::text), 1, 12) $$;

create or replace function public.ts_bloque_nombre(b text) returns text
language sql immutable as $$
  select case b
    when 'productos'  then 'Productos y precios'
    when 'credito'    then 'Inicial, saldo y cuotas'
    when 'zonas'      then 'Crédito y zonas'
    when 'pagos'      then 'Cuentas y pagos'
    when 'empiece'    then 'Empiece Ya'
    when 'comisiones' then 'Comisiones y autocompra'
    when 'objeciones' then 'Frase de oro y objeciones'
    else coalesce(b, '') end
$$;

-- Bono por puntos del período (3 % desde 100, 6 % desde 500, 9 % desde 1,250; el 12 % es de líderes).
create or replace function public.ts_bono_pct(p_pts numeric) returns int
language sql immutable as $$
  select case when p_pts >= 1250 then 9 when p_pts >= 500 then 6 when p_pts >= 100 then 3 else 0 end
$$;

-- ---------- reglas de crédito vigentes ----------
create or replace function public.ts_reglas() returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object(
    'pct',        coalesce(r.pct_inicial_minima, 0.10),
    'saldo_min',  coalesce(r.saldo_minimo, 1050),
    'cuota_min',  coalesce(r.cuota_minima, 150),
    'gasto',      coalesce(r.gasto_mensual, 20),
    'contado100', coalesce(r.contado_minimo_100, 500),
    'factores',   coalesce((select jsonb_object_agg(f.meses::text, f.factor) from factores_credito f where f.activo), '{}'::jsonb),
    'plazos',     coalesce((select jsonb_agg(f.meses order by f.meses) from factores_credito f where f.activo), '[3,6,9,12,15,18]'::jsonb))
  from (select 1) x
  left join reglas_credito r on r.id = 'vigente'
$$;

-- cuota = factor(meses) × (precio − inicial) + gasto mensual  (verificado contra la lista general)
create or replace function public.ts_cuota(p_precio numeric, p_meses int, p_pct numeric, p_rg jsonb) returns int
language sql immutable as $$
  select round((p_rg -> 'factores' ->> p_meses::text)::numeric * (p_precio - round(p_precio * p_pct))
               + (p_rg ->> 'gasto')::numeric)::int
$$;

-- plazos con saldo y cuota por encima de los mínimos
create or replace function public.ts_plazos_validos(p_precio numeric, p_pct numeric, p_rg jsonb) returns int[]
language sql immutable as $$
  select coalesce(array_agg(m order by m), '{}'::int[])
    from (select e::int as m from jsonb_array_elements_text(p_rg -> 'plazos') e) t
   where (p_precio - round(p_precio * p_pct)) >= (p_rg ->> 'saldo_min')::numeric
     and ts_cuota(p_precio, m, p_pct, p_rg) >= (p_rg ->> 'cuota_min')::numeric
$$;

-- ---------- productos y promociones vigentes (con foto) ----------
create or replace function public.ts_generales()
returns table(codigo text, nombre text, precio numeric, puntos int, vc numeric, foto text)
language sql stable set search_path = public as $$
  select p.codigo, ts_bonito(split_part(p.nombre, ' · ', 1)), p.precio, p.puntos, p.valor_comisionable,
         s.data -> 'imagenes' ->> p.codigo
    from productos p
    join v_listas_vigentes l on l.id = p.lista_id
    left join site_config s on s.id = 'rena-ware'
   where p.activo and p.lista_id = 'general' and coalesce(p.precio, 0) > 0
$$;

create or replace function public.ts_promos()
returns table(codigo text, etiqueta text, componentes text, precio numeric, puntos int, vc numeric,
              regalo text, foto text, lista text, lista_nombre text, hasta date)
language sql stable set search_path = public as $$
  select p.codigo,
         coalesce(nullif(btrim(p.categoria), ''), split_part(p.nombre, ' · ', 1)),
         coalesce((select string_agg(ts_bonito(c), ' + ' order by o)
                     from unnest(p.componentes) with ordinality u(c, o)),
                  ts_bonito(coalesce(nullif(split_part(p.nombre, ' · ', 2), ''), p.nombre))),
         p.precio, p.puntos, p.valor_comisionable, nullif(btrim(p.regalo), ''),
         coalesce(s.data -> 'imagenes' ->> p.codigo,
                  (select c.fotos_promos from ts_config c where c.id = 'vigente') || p.codigo || '.webp'),
         l.id, l.nombre, l.vigente_hasta
    from productos p
    join v_listas_vigentes l on l.id = p.lista_id
    left join site_config s on s.id = 'rena-ware'
   where p.activo and coalesce(p.precio, 0) > 0
     and l.id not in ('general', 'tienda-online', 'repuestos')
     and not coalesce(l.sin_puntos, false)
     and not coalesce(l.exenta_minimos, false)
$$;

-- ---------- zonas de crédito en Arequipa (de la lista vigente) ----------
create or replace function public.ts_zonas_aqp() returns table(nombre text, credito boolean)
language sql stable set search_path = public as $$
  -- Distritos de Arequipa para la pregunta de zonas: sí o no, sin medias tintas. Los de
  -- «solo zona urbana» no salen (hay crédito en una parte). El nombre va sin paréntesis.
  with cand(nombre, clave) as (values
    ('Cercado de Arequipa', 'Arequipa'), ('Alto Selva Alegre', null), ('Cayma', null), ('Cerro Colorado', null),
    ('Characato', null), ('Chiguata', null), ('Jacobo Hunter', null), ('La Joya', null), ('Mariano Melgar', null),
    ('Miraflores', null), ('Mollebaya', null), ('Paucarpata', null), ('Pocsi', null), ('Polobaya', null),
    ('Quequeña', null), ('Sabandía', null), ('Sachaca', null), ('San Juan de Siguas', null),
    ('San Juan de Tarucani', null), ('Santa Isabel de Siguas', null), ('Santa Rita de Siguas', null),
    ('Socabaya', null), ('Tiabaya', null), ('Uchumayo', null), ('Vítor', null), ('Yanahuara', null),
    ('Yarabamba', null), ('Yura', null), ('José Luis Bustamante y Rivero', null), ('Majes', null),
    ('Mollendo', null), ('Camaná', null), ('Chivay', null), ('Cocachacra', null), ('Mejía', null),
    ('Punta de Bombón', null), ('Aplao', null)),
  dist as (
    select ts_norm(d.distrito) as k, d.todo_restringido, d.solo_urbana from zc_distritos d
     where d.activo and ts_norm(d.departamento) = 'AREQUIPA'
    union all
    select ts_norm(a), d.todo_restringido, d.solo_urbana from zc_distritos d, unnest(d.alias) a
     where d.activo and ts_norm(d.departamento) = 'AREQUIPA'),
  c as (
    select c.nombre,
           bool_or(not x.todo_restringido and not x.solo_urbana) as si,
           bool_or(x.solo_urbana and not x.todo_restringido) as urbana
      from cand c left join dist x on x.k = ts_norm(coalesce(c.clave, c.nombre))
     group by c.nombre)
  select nombre, coalesce(si, false) from c where not coalesce(urbana, false) or coalesce(si, false)
$$;

-- ---------- programa Empiece Ya que le toca a una fecha de ingreso (Premios · pr_catalogo) ----------
create or replace function public.ts_num(t text, patron text) returns numeric
language sql immutable as $$
  select nullif(regexp_replace(regexp_replace(substring(t from patron), '[,\.](\d{3})', '\1', 'g'), '[^0-9]', '', 'g'), '')::numeric
$$;

create or replace function public.ts_ey(p_fecha date) returns jsonb
language plpgsql stable set search_path = public as $$
declare v_desde date; v_hasta date; v_prog text; r record; o jsonb; k text; f date := coalesce(p_fecha, hoy_lima());
begin
  select vigencia_desde, vigencia_hasta, programa into v_desde, v_hasta, v_prog
    from pr_catalogo
   where activo and programa ilike '%empiece ya%' and nivel = 'Nivel I'
     and f between vigencia_desde and vigencia_hasta
   order by vigencia_desde desc limit 1;
  if v_desde is null then
    select vigencia_desde, vigencia_hasta, programa into v_desde, v_hasta, v_prog
      from pr_catalogo
     where activo and programa ilike '%empiece ya%' and nivel = 'Nivel I'
     order by (vigencia_desde <= f) desc, vigencia_desde desc limit 1;
  end if;
  o := jsonb_build_object('programa', coalesce(v_prog, 'Programa ¡Empiece Ya!'), 'desde', v_desde, 'hasta', v_hasta);
  for r in
    select nivel, premio, requisito from pr_catalogo
     where activo and programa ilike '%empiece ya%' and vigencia_desde = v_desde and vigencia_hasta = v_hasta
       and nivel in ('Nivel I', 'Nivel II', 'Nivel III', 'Nivel IV')
  loop
    k := case r.nivel when 'Nivel I' then 'n1' when 'Nivel II' then 'n2' when 'Nivel III' then 'n3' else 'n4' end;
    o := o || jsonb_build_object(k, jsonb_strip_nulls(jsonb_build_object(
      'premio', r.premio, 'requisito', r.requisito,
      'ppv', ts_num(r.requisito, '(?:mínimo\s+)?([0-9][0-9,\.]*)\s*PPV'),
      'gpv', ts_num(r.requisito, '([0-9][0-9,\.]*)\s*GPV'),
      'af', ts_num(r.requisito, '(\d+)\s+nuevos?\s+afiliad'),
      'semanas', ts_num(r.requisito, 'primeras\s+(\d+)\s+semanas'))));
  end loop;
  return o;
end $$;

-- ---------- armado de preguntas ----------
-- Mezcla correctas e incorrectas y guarda la clave (ids de las correctas).
create or replace function public.ts_q(p_paso text, p_texto text, p_correctas jsonb, p_incorrectas jsonb,
                                       p_logica text, p_extra jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile set search_path = public as $$
declare v_ops jsonb := '[]'::jsonb; v_clave jsonb := '[]'::jsonb; r record; i int := 0;
begin
  for r in
    select t, ok from (
      select distinct on (t) t, ok, pri from (
        select x as t, true as ok, 0 as pri from jsonb_array_elements_text(coalesce(p_correctas, '[]'::jsonb)) x
        union all
        select x, false, 1 from jsonb_array_elements_text(coalesce(p_incorrectas, '[]'::jsonb)) x
      ) a
      where btrim(coalesce(t, '')) <> ''
      order by t, pri
    ) b
    order by random()
  loop
    i := i + 1;
    v_ops := v_ops || jsonb_build_array(jsonb_build_object('id', 'o' || i, 't', r.t));
    if r.ok then v_clave := v_clave || jsonb_build_array('o' || i); end if;
  end loop;
  return jsonb_build_object(
      'id', ts_qid(), 'paso', p_paso,
      'tipo', case when jsonb_array_length(v_clave) > 1 then 'multi' else 'single' end,
      'texto', p_texto, 'opciones', v_ops, 'clave', v_clave, 'logica', p_logica)
    || jsonb_strip_nulls(coalesce(p_extra, '{}'::jsonb));
end $$;

-- Vuelve a mezclar una pregunta de opciones (cuando no hay otra variante para el reintento).
create or replace function public.ts_remezclar(q jsonb) returns jsonb
language sql volatile set search_path = public as $$
  select ts_q(q ->> 'paso', q ->> 'texto',
              (select coalesce(jsonb_agg(o ->> 't'), '[]'::jsonb) from jsonb_array_elements(q -> 'opciones') o
                where q -> 'clave' ? (o ->> 'id')),
              (select coalesce(jsonb_agg(o ->> 't'), '[]'::jsonb) from jsonb_array_elements(q -> 'opciones') o
                where not (q -> 'clave' ? (o ->> 'id'))),
              q ->> 'logica',
              (q - 'id' - 'paso' - 'texto' - 'opciones' - 'clave' - 'logica'))
$$;

-- 1 correcta + n distractores en soles, distintos entre sí, a partir de errores creíbles.
create or replace function public.ts_opc_soles(p_correcto numeric, p_cand numeric[], p_n int default 4)
returns jsonb language plpgsql volatile set search_path = public as $$
-- Opciones de montos. Las falsas salen primero de los errores típicos (p_cand) y, si faltan, de
-- montos cercanos con un poco de azar. La correcta cae en cualquier lugar de menor a mayor
-- (cuántas van por debajo se sortea), y todas quedan separadas (mín. 4 % de la correcta):
-- así no se nota por ser la del medio, la segunda más alta ni "la distinta".
declare v_ok int := round(p_correcto)::int; v_vistos int[];
        v_gap int := greatest(2, round(abs(p_correcto) * 0.04)::int);
        v_bajo int[] := '{}'; v_alto int[] := '{}'; c numeric; v int; k int; n_bajo int;
begin
  v_vistos := array[v_ok];
  for c in select x from unnest(p_cand) x where x is not null order by random() loop
    v := round(c)::int;
    if v > 0 and not exists (select 1 from unnest(v_vistos) w where abs(w - v) < v_gap) then
      v_vistos := v_vistos || v;
      if v < v_ok then v_bajo := v_bajo || v; else v_alto := v_alto || v; end if;
    end if;
  end loop;
  k := 1;
  while (cardinality(v_bajo) < p_n or cardinality(v_alto) < p_n) and k <= 14 loop
    v := round(v_ok * (1 - (0.06 + random() * 0.03) * k))::int;
    if cardinality(v_bajo) < p_n and v > 0 and not exists (select 1 from unnest(v_vistos) w where abs(w - v) < v_gap) then
      v_vistos := v_vistos || v; v_bajo := v_bajo || v;
    end if;
    v := round(v_ok * (1 + (0.06 + random() * 0.04) * k))::int;
    if cardinality(v_alto) < p_n and not exists (select 1 from unnest(v_vistos) w where abs(w - v) < v_gap) then
      v_vistos := v_vistos || v; v_alto := v_alto || v;
    end if;
    k := k + 1;
  end loop;
  n_bajo := least(cardinality(v_bajo), floor(random() * (p_n + 1))::int);
  if p_n - n_bajo > cardinality(v_alto) then n_bajo := least(cardinality(v_bajo), p_n - cardinality(v_alto)); end if;
  return jsonb_build_object('correctas', jsonb_build_array(ts_soles(v_ok)),
    'incorrectas', (select coalesce(jsonb_agg(ts_soles(x)), '[]'::jsonb)
                      from unnest(v_bajo[1:n_bajo] || v_alto[1:p_n - n_bajo]) x));
end $$;

-- n textos al azar de una lista, sin repetir y sin los que se excluyen (p. ej. la correcta)
create or replace function public.ts_algunos(p_lista text[], p_n int, p_menos text[] default '{}') returns jsonb
language sql volatile as $$
  select coalesce(jsonb_agg(v), '[]'::jsonb)
    from (select v from (select distinct v from unnest(p_lista) v
                          where v is not null and not (v = any(coalesce(p_menos, '{}')))) d
          order by random() limit greatest(p_n, 0)) s
$$;

-- ---------- el generador: una pregunta nueva para un paso ----------
-- p_usados: lo ya usado en ese paso dentro del intento (productos, variantes), para que el reintento sea otro.
create or replace function public.ts_generar(p_paso text, p_ctx jsonb, p_usados jsonb default '[]'::jsonb)
returns jsonb language plpgsql volatile set search_path = public as $$
declare
  rg jsonb := ts_reglas();
  cfg ts_config;
  v_us text[];
  pct numeric; smin numeric; cmin numeric; c100 numeric;
  plazos int[]; v_max int;
  b record; g record; pr record; x record;
  v_found boolean;
  o jsonb; vals int[]; m int; nn int; corr int; v_ini int; i int; j int;
  t_items jsonb; t_nombres jsonb; t_clave jsonb;
  v_txt text; v_form text; v_reg text; v_lista text;
  v_correctas jsonb; v_incorrectas jsonb;
  ey jsonb; n1 jsonb; n2 jsonb; n3 jsonb;
  n1_ppv numeric; n1_af int; n1_pr text; n2_ppv numeric; n2_af int; n2_pr text;
  n3_gpv numeric; n3_ppv numeric; n3_af int; n3_pr text; v_sem int;
  v_desc numeric; v_bono int; v_pp numeric; v_pa numeric;
begin
  select * into cfg from ts_config where id = 'vigente';
  v_us := coalesce((select array_agg(e) from jsonb_array_elements_text(coalesce(p_usados, '[]'::jsonb)) e), '{}'::text[]);
  pct := (rg ->> 'pct')::numeric; smin := (rg ->> 'saldo_min')::numeric;
  cmin := (rg ->> 'cuota_min')::numeric; c100 := (rg ->> 'contado100')::numeric;
  plazos := coalesce((select array_agg(e::int order by e::int) from jsonb_array_elements_text(rg -> 'plazos') e),
                     '{3,6,9,12,15,18}'::int[]);
  v_max := plazos[cardinality(plazos)];

  ey := coalesce(p_ctx -> 'ey', ts_ey(hoy_lima()));
  n1 := coalesce(ey -> 'n1', '{}'::jsonb); n2 := coalesce(ey -> 'n2', '{}'::jsonb); n3 := coalesce(ey -> 'n3', '{}'::jsonb);
  n1_ppv := coalesce((n1 ->> 'ppv')::numeric, 750);  n1_af := coalesce((n1 ->> 'af')::int, 2);
  n1_pr  := coalesce(n1 ->> 'premio', 'Utensilio de 1.5L + Botella de Acero Inoxidable');
  n2_ppv := coalesce((n2 ->> 'ppv')::numeric, 1500); n2_af := coalesce((n2 ->> 'af')::int, 3);
  n2_pr  := coalesce(n2 ->> 'premio', 'Utensilio de 1.5L + Botella de Acero Inoxidable + Multi Cooker');
  n3_gpv := coalesce((n3 ->> 'gpv')::numeric, 3500); n3_ppv := coalesce((n3 ->> 'ppv')::numeric, 750);
  n3_af  := coalesce((n3 ->> 'af')::int, 4);
  n3_pr  := coalesce(n3 ->> 'premio', 'Utensilio de 1.5L + Botella de Acero Inoxidable + Olla a Presión 8 L');
  v_sem  := coalesce((n1 ->> 'semanas')::int, 4);

  -- ===== pasos de texto fijo (banco) =====
  if exists (select 1 from ts_banco where paso = p_paso) then
    select * into b from ts_banco where paso = p_paso and activo and not (id = any(v_us)) order by random() limit 1;
    if not found then
      select * into b from ts_banco where paso = p_paso and activo order by random() limit 1;
    end if;
    if not found then return null; end if;
    if jsonb_array_length(b.correctas) > 1 then
      -- marca varias: algunas válidas al azar (de 2 a todas) y el resto inválidas, hasta 5 opciones;
      -- así el reintento no es la misma pregunta y no siempre hay una sola inválida
      nn := least(jsonb_array_length(b.correctas), 2 + floor(random() * (jsonb_array_length(b.correctas) - 1))::int);
      nn := greatest(nn, 5 - jsonb_array_length(b.incorrectas));
      v_correctas := (select jsonb_agg(v) from (select value as v from jsonb_array_elements(b.correctas) order by random() limit nn) s);
      v_incorrectas := (select coalesce(jsonb_agg(v), '[]'::jsonb)
                          from (select value as v from jsonb_array_elements(b.incorrectas) order by random() limit 5 - nn) s);
      return ts_q(p_paso, b.texto, v_correctas, v_incorrectas, b.logica,
                  jsonb_build_object('usa', jsonb_build_array(b.id), 'tipo', 'multi'));
    end if;
    v_incorrectas := (select coalesce(jsonb_agg(v), '[]'::jsonb)
                        from (select value as v from jsonb_array_elements(b.incorrectas) order by random()
                              limit b.n_incorrectas) s);
    return ts_q(p_paso, b.texto, b.correctas, v_incorrectas, b.logica, jsonb_build_object('usa', jsonb_build_array(b.id)));
  end if;

  -- ===== Productos y precios =====
  if p_paso = 'identificar' then
    -- solo productos principales (sin repuestos ni cartuchos) y uno por tipo (ollas, sartenes,
    -- agua y aire, equipos, cubiertos y útiles), para que no salgan dos que en foto se ven iguales
    t_items := '[]'::jsonb; i := 0;
    for g in
      select * from (
        select distinct on (f.fam) gg.*
          from ts_generales() gg
          cross join lateral (select case
                   when lower(gg.nombre) ~ '(inducción|multi cooker|nutrex|tetera)' then 'equipos'
                   when lower(gg.nombre) ~ '(filtr|botella|aqua|purificador)' then 'agua_aire'
                   when lower(gg.nombre) ~ '(sartén|wok|parrilla|grill)' then 'sartenes'
                   when lower(gg.nombre) ~ '(cubiertos|cuchillos|útiles|espátulas|bandeja|rena lite)' then 'utiles'
                   else 'ollas' end as fam) f
         where gg.foto is not null and gg.precio >= 450
           and gg.nombre !~* '(cartucho|repuesto|elemento|alojamiento|bandas|pre filtro)'
           and not (gg.codigo = any(v_us))
         order by f.fam, random()) s
      order by random() limit 5
    loop
      i := i + 1;
      t_items := t_items || jsonb_build_array(jsonb_build_object('id', 'i' || i, 'codigo', g.codigo,
                                                                 'nombre', g.nombre, 'foto', g.foto));
    end loop;
    -- si algún tipo se quedó sin productos (cambió la lista), se completa con otros
    if i < 5 then
      for g in
        select gg.* from ts_generales() gg
         where gg.foto is not null and gg.precio >= 450
           and gg.nombre !~* '(cartucho|repuesto|elemento|alojamiento|bandas|pre filtro)'
           and not (gg.codigo = any(v_us))
           and not exists (select 1 from jsonb_array_elements(t_items) e where e ->> 'codigo' = gg.codigo)
         order by random() limit 5 - i
      loop
        i := i + 1;
        t_items := t_items || jsonb_build_array(jsonb_build_object('id', 'i' || i, 'codigo', g.codigo,
                                                                   'nombre', g.nombre, 'foto', g.foto));
      end loop;
    end if;
    if i < 5 then
      if cardinality(v_us) > 0 then return ts_generar(p_paso, p_ctx, '[]'::jsonb); end if;
      return null;
    end if;
    t_nombres := '[]'::jsonb; t_clave := '{}'::jsonb; j := 0;
    for x in select value as v from jsonb_array_elements(t_items) order by random() loop
      j := j + 1;
      t_nombres := t_nombres || jsonb_build_array(jsonb_build_object('id', 'n' || j, 't', x.v ->> 'nombre'));
      t_clave := t_clave || jsonb_build_object(x.v ->> 'id', 'n' || j);
    end loop;
    return jsonb_build_object(
      'id', ts_qid(), 'paso', p_paso, 'tipo', 'emparejar',
      'texto', 'Empareja cada producto con su nombre.',
      'items', (select jsonb_agg(jsonb_build_object('id', value ->> 'id', 'foto', value ->> 'foto')) from jsonb_array_elements(t_items)),
      'nombres', t_nombres, 'clave', t_clave,
      'logica', 'Ubica cada producto por su foto en el catálogo o en la lista de precio general, y fíjate bien en su nombre.',
      'usa', (select jsonb_agg(value ->> 'codigo') from jsonb_array_elements(t_items)));
  end if;

  if p_paso = 'precio_general' then
    select * into g from ts_generales() gg where gg.precio > 1600 and not (gg.codigo = any(v_us)) order by random() limit 1;
    if not found then select * into g from ts_generales() gg where gg.precio > 1600 order by random() limit 1; end if;
    if not found then return null; end if;
    o := ts_opc_soles(g.precio, array(
           select p from (select distinct gg.precio as p from ts_generales() gg where gg.precio <> g.precio) s
            order by abs(p - g.precio) limit 14));
    return ts_q(p_paso, '¿Cuánto cuesta al contado?', o -> 'correctas', o -> 'incorrectas',
      'Los precios están en la lista de precio general: ubica el producto por su nombre y lee su precio al contado.',
      jsonb_build_object('foto', g.foto, 'sub', g.nombre, 'usa', jsonb_build_array(g.codigo)));
  end if;

  if p_paso = 'precio_promo' then
    select * into pr from ts_promos() pp where not (pp.codigo = any(v_us)) order by random() limit 1;
    if not found then select * into pr from ts_promos() pp order by random() limit 1; end if;
    if not found then return null; end if;
    o := ts_opc_soles(pr.precio, array(
           select p from (select distinct pp.precio as p from ts_promos() pp
                           where pp.lista = pr.lista and pp.precio <> pr.precio) s
            order by abs(p - pr.precio) limit 14));
    return ts_q(p_paso, '¿Cuánto cuesta esta promoción?', o -> 'correctas', o -> 'incorrectas',
      format('Las promociones vigentes están en la lista «%s»: ubica la promoción por su número y lee su precio.', pr.lista_nombre),
      jsonb_build_object('foto', pr.foto, 'sub', pr.etiqueta || ' · ' || pr.componentes, 'usa', jsonb_build_array(pr.codigo)));
  end if;

  if p_paso = 'regalo_promo' then
    select pp.regalo, pp.lista_nombre into v_reg, v_lista
      from ts_promos() pp where pp.regalo is not null
     group by pp.regalo, pp.lista_nombre order by count(*) desc limit 1;
    if v_reg is null then return null; end if;
    -- los regalos inventados no pueden parecerse al real (si el real trae botella, no va «Una botella de acero»)
    v_incorrectas := ts_algunos(
      array(select distinct btrim(p.regalo) from productos p where nullif(btrim(p.regalo), '') is not null)
        || array(select d.t from (values ('Ninguno: el regalo es solo para la lista general', 'ninguno'),
                                         ('Una botella de acero', 'botella'), ('Un descuento del 15 %', 'descuento'),
                                         ('Un pack de 12 Rena Lite', 'rena lite'), ('Una tetera de 3 L', 'tetera')) d(t, k)
                  where lower(v_reg) not like '%' || d.k || '%'),
      4, array[v_reg]);
    return ts_q(p_paso, format('Si tu cliente toma una promoción de la lista «%s», ¿qué regalo se lleva?', v_lista),
      jsonb_build_array(v_reg), v_incorrectas,
      'Cada lista de especiales trae su regalo vigente, escrito en la misma lista. Es tu herramienta de cierre: si toma la promoción ahora, se lleva el regalo.',
      jsonb_build_object('usa', jsonb_build_array(md5(v_reg))));
  end if;

  -- ===== Inicial, saldo y cuotas =====
  if p_paso = 'inicial' then
    v_found := false;
    if random() < 0.6 then
      select pp.codigo, pp.precio, pp.foto, pp.etiqueta || ' · ' || pp.componentes as sub into x
        from ts_promos() pp where pp.precio > c100 and not (pp.codigo = any(v_us)) order by random() limit 1;
      v_found := found;
    end if;
    if not v_found then
      select gg.codigo, gg.precio, gg.foto, gg.nombre as sub into x
        from ts_generales() gg where gg.precio > c100 and not (gg.codigo = any(v_us)) order by random() limit 1;
      v_found := found;
    end if;
    if not v_found then
      select gg.codigo, gg.precio, gg.foto, gg.nombre as sub into x
        from ts_generales() gg where gg.precio > c100 order by random() limit 1;
      v_found := found;
    end if;
    if not v_found then return null; end if;
    corr := round(x.precio * pct);
    o := ts_opc_soles(corr, array[x.precio * 0.05, x.precio * 0.15, x.precio * 0.20, x.precio * 0.30, x.precio * 0.25]);
    return ts_q(p_paso, '¿Cuánto es la inicial mínima?', o -> 'correctas', o -> 'incorrectas',
      format('La inicial mínima es el %s %% del precio: busca el precio en la lista y calcula ese porcentaje.', ts_fmt(pct * 100)),
      jsonb_build_object('foto', x.foto, 'sub', x.sub, 'usa', jsonb_build_array(x.codigo)));
  end if;

  if p_paso = 'saldo' then
    select * into g from ts_generales() gg where gg.precio > 1600 and not (gg.codigo = any(v_us)) order by random() limit 1;
    if not found then select * into g from ts_generales() gg where gg.precio > 1600 order by random() limit 1; end if;
    if not found then return null; end if;
    v_ini := round(g.precio * pct);
    o := ts_opc_soles(g.precio - v_ini, array[g.precio, g.precio + v_ini, v_ini, g.precio - 2 * v_ini, g.precio * 0.5]);
    return ts_q(p_paso, 'Si el cliente da la inicial mínima, ¿cuánto es el saldo a pagar contra entrega?',
      o -> 'correctas', o -> 'incorrectas',
      format('El saldo contra entrega es el precio menos la inicial mínima (el %s %%). Calcúlalo con el precio de la lista.', ts_fmt(pct * 100)),
      jsonb_build_object('foto', g.foto, 'sub', g.nombre, 'usa', jsonb_build_array(g.codigo)));
  end if;

  if p_paso = 'cuota_n' then
    select * into g from ts_generales() gg
     where gg.precio > 1600 and cardinality(ts_plazos_validos(gg.precio, pct, rg)) > 0 and not (gg.codigo = any(v_us))
     order by random() limit 1;
    if not found then
      select * into g from ts_generales() gg
       where gg.precio > 1600 and cardinality(ts_plazos_validos(gg.precio, pct, rg)) > 0 order by random() limit 1;
    end if;
    if not found then return null; end if;
    vals := ts_plazos_validos(g.precio, pct, rg);
    m := vals[1 + floor(random() * cardinality(vals))::int];
    corr := ts_cuota(g.precio, m, pct, rg);
    v_ini := round(g.precio * pct);
    nn := coalesce((select v from unnest(vals) v where v <> m order by random() limit 1), case when m = 3 then 6 else 3 end);
    o := ts_opc_soles(corr, array[(g.precio - v_ini) / m, g.precio / m, ts_cuota(g.precio, nn, pct, rg), v_ini]);
    return ts_q(p_paso, format('Si lo compra a crédito en %s cuotas, con la inicial mínima, ¿cuánto es cada cuota?', m),
      o -> 'correctas', o -> 'incorrectas',
      format('La cuota a %s cuotas la encuentras en la lista de precio general: búscala para ese producto y ese plazo.', m),
      jsonb_build_object('foto', g.foto, 'sub', g.nombre, 'usa', jsonb_build_array(g.codigo)));
  end if;

  if p_paso = 'cuota_20' then
    select * into g from ts_generales() gg
     where gg.precio > 1600 and 12 = any(ts_plazos_validos(gg.precio, 0.20, rg)) and not (gg.codigo = any(v_us))
     order by random() limit 1;
    if not found then
      select * into g from ts_generales() gg
       where gg.precio > 1600 and 12 = any(ts_plazos_validos(gg.precio, 0.20, rg)) order by random() limit 1;
    end if;
    if not found then return null; end if;
    v_ini := round(g.precio * 0.20);
    corr := ts_cuota(g.precio, 12, 0.20, rg);
    o := ts_opc_soles(corr, array[ts_cuota(g.precio, 12, pct, rg), (g.precio - v_ini) / 12.0, g.precio / 12.0, v_ini,
                                  ts_cuota(g.precio, 9, 0.20, rg), ts_cuota(g.precio, 15, 0.20, rg)]);
    return ts_q(p_paso, format('Si el cliente da %s de inicial (el 20 %%), ¿cuánto sería la cuota en 12 cuotas?', ts_soles(v_ini)),
      o -> 'correctas', o -> 'incorrectas',
      'En Precios y promociones abre el producto, entra a «Crédito», escribe esa inicial en lugar de la mínima y lee la cuota a 12 meses.',
      jsonb_build_object('foto', g.foto, 'sub', g.nombre, 'usa', jsonb_build_array(g.codigo)));
  end if;

  -- ===== Crédito y zonas =====
  if p_paso = 'financiables' then
    nn := 2 + floor(random() * 2)::int;
    v_correctas := (select jsonb_agg(nombre) from (
                      select gg.nombre from ts_generales() gg
                       where gg.precio - round(gg.precio * pct) >= smin order by random() limit nn) s);
    v_incorrectas := (select jsonb_agg(nombre) from (
                      select gg.nombre from ts_generales() gg
                       where gg.precio - round(gg.precio * pct) < smin order by random() limit 5 - nn) s);
    if coalesce(jsonb_array_length(v_correctas), 0) < 1 or coalesce(jsonb_array_length(v_incorrectas), 0) < 1 then
      return null;
    end if;
    return ts_q(p_paso, '¿Cuáles de estos productos se pueden financiar a crédito? (marca todas las respuestas válidas)',
      v_correctas, v_incorrectas,
      format('Se puede financiar si el saldo (el precio menos la inicial mínima) es de %s o más. Revisa el precio de cada uno en la lista.', ts_soles(smin)),
      jsonb_build_object('tipo', 'multi'));
  end if;

  if p_paso = 'cuotas_max' then
    -- casi siempre un producto que no llega al plazo más largo (la trampa del quiz anterior),
    -- pero a veces uno que sí: así el plazo más largo no es siempre la opción falsa
    v_found := false;
    if random() < 0.7 then
      select * into g from ts_generales() gg
       where cardinality(ts_plazos_validos(gg.precio, pct, rg)) > 0
         and (ts_plazos_validos(gg.precio, pct, rg))[cardinality(ts_plazos_validos(gg.precio, pct, rg))] < v_max
         and not (gg.codigo = any(v_us))
       order by random() limit 1;
      v_found := found;
    end if;
    if not v_found then
      select * into g from ts_generales() gg
       where cardinality(ts_plazos_validos(gg.precio, pct, rg)) > 0 and not (gg.codigo = any(v_us))
       order by random() limit 1;
      v_found := found;
    end if;
    if not v_found then
      select * into g from ts_generales() gg
       where cardinality(ts_plazos_validos(gg.precio, pct, rg)) > 0 order by random() limit 1;
      v_found := found;
    end if;
    if not v_found then return null; end if;
    vals := ts_plazos_validos(g.precio, pct, rg);
    corr := vals[cardinality(vals)];
    v_incorrectas := (select coalesce(jsonb_agg(v || ' cuotas'), '[]'::jsonb)
                        from (select v from unnest(plazos) v where v <> corr order by (v = v_max) desc, random() limit 4) s);
    return ts_q(p_paso, '¿Hasta cuántas cuotas como máximo se puede financiar?',
      jsonb_build_array(corr || ' cuotas'), v_incorrectas,
      format('La cuota mínima es de %s. El máximo de cuotas es el plazo más largo cuya cuota siga siendo de %s o más: mira la cuota de cada plazo en la lista y elige el último que cumpla. Ojo: no siempre es el plazo más alto.', ts_soles(cmin), ts_soles(cmin)),
      jsonb_build_object('foto', g.foto, 'sub', g.nombre, 'usa', jsonb_build_array(g.codigo)));
  end if;

  if p_paso = 'inicial_100' then
    select * into g from ts_generales() gg where gg.precio <= c100 and not (gg.codigo = any(v_us)) order by random() limit 1;
    if not found then select * into g from ts_generales() gg where gg.precio <= c100 order by random() limit 1; end if;
    if not found then return null; end if;
    -- el precio no va en la pregunta: hay que buscarlo y saber la regla
    o := ts_opc_soles(g.precio, array[g.precio * pct, g.precio * 0.5, g.precio * 0.2, g.precio * 1.18]
                                || array(select p from (select distinct gg.precio as p from ts_generales() gg where gg.precio <> g.precio) s
                                          order by abs(p - g.precio) limit 4));
    return ts_q(p_paso, '¿Cuánto es la inicial de este producto?',
      o -> 'correctas', o -> 'incorrectas',
      format('Busca su precio en la lista. Los pedidos de %s o menos se pagan al 100 %%: tienen que estar cancelados para ser despachados.', ts_soles(c100)),
      jsonb_build_object('foto', g.foto, 'sub', g.nombre, 'usa', jsonb_build_array(g.codigo)));
  end if;

  if p_paso = 'zona' then
    v_form := case when 'f:no' = any(v_us) and not ('f:si' = any(v_us)) then 'si'
                   when 'f:si' = any(v_us) and not ('f:no' = any(v_us)) then 'no'
                   when random() < 0.5 then 'no' else 'si' end;
    v_correctas := (select jsonb_agg(nombre) from (
                      select z.nombre from ts_zonas_aqp() z
                       where z.credito = (v_form = 'si') and not (('z:' || z.nombre) = any(v_us))
                       order by random() limit 1) s);
    if v_correctas is null then
      v_correctas := (select jsonb_agg(nombre) from (
                        select z.nombre from ts_zonas_aqp() z where z.credito = (v_form = 'si') order by random() limit 1) s);
    end if;
    v_incorrectas := (select jsonb_agg(nombre) from (
                        select z.nombre from ts_zonas_aqp() z where z.credito = (v_form <> 'si') order by random() limit 4) s);
    if v_correctas is null or coalesce(jsonb_array_length(v_incorrectas), 0) < 2 then return null; end if;
    return ts_q(p_paso,
      case when v_form = 'si' then '¿En cuál de estos distritos SÍ hay venta al crédito?'
           else '¿En cuál de estos distritos NO hay venta al crédito?' end,
      v_correctas, v_incorrectas,
      'Antes de ofrecer crédito revisa la zona en el buscador de zonas de crédito: si el distrito no figura en la lista, o está restringido, ahí no hay crédito y el cliente paga el 100 % antes del despacho.',
      jsonb_build_object('usa', jsonb_build_array('f:' || v_form, 'z:' || (v_correctas ->> 0))));
  end if;

  -- ===== Cuentas y pagos =====
  if p_paso = 'cuentas' then
    if jsonb_array_length(coalesce(cfg.cuentas, '[]'::jsonb)) = 0 then return null; end if;
    t_items := '[]'::jsonb; t_clave := '{}'::jsonb; i := 0;
    for x in select value as v from jsonb_array_elements(cfg.cuentas) loop
      i := i + 1;
      t_items := t_items || jsonb_build_array(jsonb_build_object('id', 'c' || i, 'label', 'Cuenta ' || (x.v ->> 'banco')));
      t_clave := t_clave || jsonb_build_object('c' || i, coalesce(x.v -> 'validos', '[]'::jsonb));
    end loop;
    return jsonb_build_object(
      'id', ts_qid(), 'paso', p_paso, 'tipo', 'escribir',
      'texto', 'Escribe los números de cuenta de Rena Ware (solo números, sin guiones). Vale el número de cuenta o el CCI.',
      'campos', t_items, 'clave', t_clave,
      'logica', 'Pide los números de cuenta a tu líder y guárdalos en tu celular. Escríbelos solo con números, sin guiones ni espacios.',
      'usa', '[]'::jsonb);
  end if;

  -- ===== Empiece Ya (el programa que le toca según su fecha de ingreso) =====
  if p_paso = 'ey_plazo' then
    v_txt := format('%s semanas desde que se afilia', v_sem);
    return ts_q(p_paso, '¿Cuánto tiempo tiene un asesor nuevo para ganar su Empiece Ya?',
      jsonb_build_array(v_txt),
      ts_algunos(array['1 semana desde que se afilia', '2 semanas desde que se afilia', '8 semanas desde que se afilia',
                       '6 meses desde que se afilia', 'No hay plazo: cuando quiera', 'Un año, mientras siga activo'], 4, array[v_txt]),
      'El Empiece Ya tiene un plazo corto que corre desde el día en que te afilias: por eso se arranca desde el primer día. Repasa el mensaje del Empiece Ya que te enviamos.',
      jsonb_build_object('usa', jsonb_build_array('plazo')));
  end if;

  if p_paso in ('ey_n1', 'ey_n2') then
    v_form := case when 'f:premio' = any(v_us) then 'req' else 'premio' end;
    if p_paso = 'ey_n1' then
      if v_form = 'premio' then
        v_txt := format('En tu Empiece Ya logras %s puntos y %s afiliados. ¿Qué ganas?', ts_fmt(n1_ppv), n1_af);
        v_correctas := jsonb_build_array(n1_pr);
        v_incorrectas := ts_algunos(array[n2_pr, n3_pr, 'Solo la botella de acero', format('Un bono de %s en efectivo', ts_soles(n1_ppv))], 4, array[n1_pr]);
      else
        v_txt := format('¿Qué necesitas para ganar el Nivel I del Empiece Ya (%s)?', n1_pr);
        v_correctas := jsonb_build_array(format('%s puntos y %s afiliados', ts_fmt(n1_ppv), n1_af));
        v_incorrectas := ts_algunos(array[format('%s puntos y %s afiliados', ts_fmt(n2_ppv), n2_af),
                                          format('%s puntos de grupo y %s afiliados', ts_fmt(n3_gpv), n3_af),
                                          format('%s puntos, sin afiliados', ts_fmt(n1_ppv)),
                                          format('%s afiliados, sin puntos', n1_af)], 4,
                                    array[format('%s puntos y %s afiliados', ts_fmt(n1_ppv), n1_af)]);
      end if;
    else
      if v_form = 'premio' then
        v_txt := format('En tu Empiece Ya logras %s puntos y %s afiliados. ¿Qué ganas?', ts_fmt(n2_ppv), n2_af);
        v_correctas := jsonb_build_array(n2_pr);
        v_incorrectas := ts_algunos(array[n1_pr, n3_pr, 'Solo el utensilio de 1.5 L', format('Un bono de %s en efectivo', ts_soles(n2_ppv))], 4, array[n2_pr]);
      else
        v_txt := format('¿Qué necesitas para ganar el Nivel II del Empiece Ya (%s)?', n2_pr);
        v_correctas := jsonb_build_array(format('%s puntos y %s afiliados', ts_fmt(n2_ppv), n2_af));
        v_incorrectas := ts_algunos(array[format('%s puntos y %s afiliados', ts_fmt(n1_ppv), n1_af),
                                          format('%s puntos de grupo y %s afiliados', ts_fmt(n3_gpv), n3_af),
                                          format('%s puntos, sin afiliados', ts_fmt(n2_ppv)),
                                          format('%s afiliados, sin puntos', n2_af)], 4,
                                    array[format('%s puntos y %s afiliados', ts_fmt(n2_ppv), n2_af)]);
      end if;
    end if;
    return ts_q(p_paso, v_txt, v_correctas, v_incorrectas,
      'Cada nivel del Empiece Ya pide puntos de tus ventas y afiliados nuevos dentro de tu plazo, y cada nivel suma un premio más. Repasa los niveles en el mensaje del Empiece Ya que te enviamos.',
      jsonb_build_object('usa', jsonb_build_array('f:' || v_form)));
  end if;

  if p_paso = 'ey_gpv' then
    v_form := case when 'f:def' = any(v_us) then 'calc' else 'def' end;
    if v_form = 'def' then
      v_txt := format('Para el Nivel III piden %s puntos de GPV, con un mínimo de %s tuyos. ¿Qué significa GPV?', ts_fmt(n3_gpv), ts_fmt(n3_ppv));
      v_correctas := jsonb_build_array(format('Grupo personal: tus puntos más los de tus afiliados, con mínimo %s tuyos', ts_fmt(n3_ppv)));
      v_incorrectas := jsonb_build_array(
        format('%s puntos solo de tus ventas personales, sin contar a nadie más', ts_fmt(n3_gpv)),
        format('%s soles vendidos entre todo el equipo de la oficina en el mes', ts_fmt(n3_gpv)),
        'Los puntos de tu líder sumados a los tuyos durante todo tu plazo',
        'Puntos de regalo que Rena Ware te da al afiliarte y al hacer tu primera venta');
    else
      -- dos casos: llega (grupo y mínimo personal) o no llega (grupo sí, pero le falta su mínimo)
      if random() < 0.5 then
        v_pp := n3_ppv + 150; v_pa := n3_gpv - v_pp + 100;
        v_correctas := jsonb_build_array(format('Sí: tu GPV es %s y tus %s personales cubren el mínimo', ts_fmt(v_pp + v_pa), ts_fmt(v_pp)));
        v_incorrectas := jsonb_build_array(
          format('No: para el Nivel III solo cuentan tus %s puntos personales', ts_fmt(v_pp)),
          format('No: tus afiliados tienen que llegar solos a los %s puntos', ts_fmt(n3_gpv)),
          'Sí, pero solo si ya eres líder y tienes tu propio equipo',
          format('No: necesitas %s puntos personales, sin contar afiliados', ts_fmt(n3_gpv)));
      else
        v_pp := n3_ppv - 150; v_pa := n3_gpv - v_pp + 300;
        v_correctas := jsonb_build_array(format('No: te faltan %s puntos personales para el mínimo de %s', ts_fmt(n3_ppv - v_pp), ts_fmt(n3_ppv)));
        v_incorrectas := jsonb_build_array(
          format('Sí: entre todos suman %s, así que ya pasaste los %s', ts_fmt(v_pp + v_pa), ts_fmt(n3_gpv)),
          format('No: tus afiliados tienen que llegar solos a los %s puntos', ts_fmt(n3_gpv)),
          'Sí, pero solo si ya eres líder y tienes tu propio equipo',
          format('No: necesitas %s puntos personales, sin contar afiliados', ts_fmt(n3_gpv)));
      end if;
      v_txt := format('Tus ventas suman %s puntos y las de tus afiliados, %s. Para el Nivel III piden %s de GPV con mínimo %s tuyos. ¿Llegas?',
                      ts_fmt(v_pp), ts_fmt(v_pa), ts_fmt(n3_gpv), ts_fmt(n3_ppv));
    end if;
    return ts_q(p_paso, v_txt, v_correctas, v_incorrectas,
      'El PPV son los puntos de tus ventas personales; el GPV suma también los de las personas que afilias. Por eso el Nivel III se logra en equipo, siempre que cumplas el mínimo de venta personal.',
      jsonb_build_object('usa', jsonb_build_array('f:' || v_form)));
  end if;

  -- ===== Comisiones y autocompra =====
  if p_paso = 'auto_ejemplo' then
    -- una promoción grande al azar (como la gourmet con filtro): cuánto te descuentan; los puntos van en el dato
    select pp.codigo, pp.etiqueta, pp.componentes, pp.precio, pp.puntos, pp.vc, pp.foto into x
      from ts_promos() pp
     where pp.vc > 0 and pp.puntos >= n1_ppv and not (pp.codigo = any(v_us))
     order by random() limit 1;
    v_found := found;
    if not v_found then
      select gg.codigo, gg.nombre as etiqueta, gg.nombre as componentes, gg.precio, gg.puntos, gg.vc, gg.foto into x
        from ts_generales() gg where gg.vc > 0 and gg.precio > 1600 and not (gg.codigo = any(v_us)) order by random() limit 1;
      v_found := found;
    end if;
    if not v_found then
      select pp.codigo, pp.etiqueta, pp.componentes, pp.precio, pp.puntos, pp.vc, pp.foto into x
        from ts_promos() pp where pp.vc > 0 and pp.puntos >= n1_ppv order by random() limit 1;
      v_found := found;
    end if;
    if not v_found then return null; end if;
    v_desc := round(x.vc * 0.15 * 1.18);
    o := ts_opc_soles(v_desc, array[x.vc * 0.15, x.precio * 0.15, x.precio * 0.10, x.precio * 0.15 * 1.18, x.vc * 0.30]);
    return ts_q(p_paso,
      format('Te autocompras %s, que cuesta %s. ¿Cuánto te descuentan?',
             case when x.etiqueta = x.componentes then 'este producto' else 'esta promoción (' || x.etiqueta || ')' end, ts_soles(x.precio)),
      o -> 'correctas', o -> 'incorrectas',
      'Tu descuento sale de tu comisión: busca el valor comisionable en el cuadro de comisiones, calcula tu comisión y súmale el IGV. En Precios y promociones, abre la promoción y entra a «Precio Autocompra»: ahí sale como «Menos tu descuento».',
      jsonb_build_object('foto', x.foto, 'sub', x.componentes, 'usa', jsonb_build_array(x.codigo),
        'dato', case
          when x.puntos >= n2_ppv then format('Y además te suma %s puntos: ya pasas los %s del Nivel II del Empiece Ya (%s, con %s afiliados).', ts_fmt(x.puntos), ts_fmt(n2_ppv), n2_pr, n2_af)
          when x.puntos >= n2_ppv * 0.8 then format('Y además te suma %s puntos: casi llegas a los %s del Nivel II del Empiece Ya (%s, con %s afiliados).', ts_fmt(x.puntos), ts_fmt(n2_ppv), n2_pr, n2_af)
          when x.puntos >= n1_ppv then format('Y además te suma %s puntos: ya pasas los %s del Nivel I del Empiece Ya.', ts_fmt(x.puntos), ts_fmt(n1_ppv))
          else format('Y además te suma %s puntos para tu Empiece Ya.', ts_fmt(x.puntos)) end));
  end if;

  if p_paso = 'venta_gana' then
    -- comisión y bono redondeados por separado, para que el dato sume exacto
    select it.*, bk.etiqueta as rango into x from (
        select c.*, c.comision + c.bono as total from (
          select pp.codigo, pp.etiqueta || ' · ' || pp.componentes as nombre, pp.etiqueta as corto, pp.precio, pp.puntos, pp.vc,
                 pp.foto, true as es_promo, round(pp.vc * 0.15) as comision, round(pp.vc * ts_bono_pct(pp.puntos) / 100.0) as bono
            from ts_promos() pp
          union all
          select gg.codigo, gg.nombre, gg.nombre, gg.precio, gg.puntos, gg.vc, gg.foto, false,
                 round(gg.vc * 0.15), round(gg.vc * ts_bono_pct(gg.puntos) / 100.0)
            from ts_generales() gg) c) it
      join (values ('Entre S/ 500 y S/ 700', 500, 700), ('Entre S/ 800 y S/ 1,000', 800, 1000),
                   ('Entre S/ 1,001 y S/ 1,500', 1001, 1500)) bk(etiqueta, lo, hi)
        on it.total between bk.lo and bk.hi
     where not (it.codigo = any(v_us))
     order by it.es_promo desc, random()
     limit 1;
    if not found then return null; end if;
    v_bono := ts_bono_pct(x.puntos);
    return ts_q(p_paso,
      format('Vendes %s, de %s. Si es tu única venta del período, ¿cuánto ganas aprox. entre comisión y bono?',
             case when x.es_promo then 'esta promoción (' || x.corto || ')' else 'este producto' end, ts_soles(x.precio)),
      jsonb_build_array(x.rango),
      ts_algunos(array['Entre S/ 500 y S/ 700', 'Entre S/ 800 y S/ 1,000', 'Entre S/ 1,001 y S/ 1,500',
                       'Menos de S/ 200', 'Más de S/ 3,000'], 4, array[x.rango]),
      'Ganas el 15 % del valor comisionable más un bono según tus puntos del período: 3 % desde 100 puntos, 6 % desde 500 y 9 % desde 1,250. Busca el valor comisionable y los puntos en el cuadro de comisiones y calcula.',
      jsonb_build_object('foto', x.foto, 'sub', x.nombre, 'usa', jsonb_build_array(x.codigo),
        'dato', format('Comisión %s + bono del %s %% (%s) = %s. Además, los puntos suman para tus premios.',
                       ts_soles(x.comision), v_bono, ts_soles(x.bono), ts_soles(x.total))));
  end if;

  return null;
end $$;
