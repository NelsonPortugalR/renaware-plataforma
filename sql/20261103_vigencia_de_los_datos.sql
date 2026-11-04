-- ============================================================================
-- Vigencia de los datos (03/11/2026). APLICADO con execute_sql.
--
-- Todo lo que alimenta la plataforma y que una persona tiene que volver a subir:
-- listas de precios, reporte de pedidos, resultados de premios y de Empiece Ya,
-- reporte Aurora/FPD, declaraciones, catálogo de premios, zonas de crédito,
-- horario del local, clases del Nivel Cero, fichas del chat, premios por recibir.
--
-- Es un catálogo (plataforma_fuentes): una fila por fuente, con su cadencia y
-- los SELECT que dicen cuándo se alimentó por última vez y hasta cuándo sirve.
-- plataforma_fuentes_estado() calcula el estado de cada una (al día, por
-- vencer, vencido) y Hoy avisa de las que vencen; el hub tiene la pantalla
-- #vigencia con todas. Agregar una fuente nueva = una fila.
-- ============================================================================

-- 1) El catálogo
create table if not exists public.plataforma_fuentes (
  id              text primary key,
  nombre          text not null,
  accion          text,                      -- qué hacer y dónde, en una frase
  modulo          text references public.plataforma_modulos(id),
  roles           text[] not null default array['admin'],
  cadencia        text not null check (cadencia in ('vigencia','periodo','mensual','semanal','evento')),
  dia             int  not null default 0,   -- periodo: días después del cierre · mensual: día del mes · semanal: días de tolerancia · evento: días máximos de espera
  aviso_dias      int  not null default 5,   -- cuántos días antes de vencer avisa
  ultima_sql      text,                      -- SELECT → date: última vez que se alimentó (periodo: una fecha dentro del último período cubierto)
  vence_sql       text,                      -- SELECT → date: hasta cuándo sirve lo cargado (vigencia) o para cuándo se esperaba lo más antiguo (evento)
  pendientes_sql  text,                      -- SELECT → int: cuántos elementos esperan (evento)
  en_hoy          boolean not null default true,   -- false si el módulo ya avisa esto en Hoy por su cuenta
  activo          boolean not null default true,
  orden           int not null default 0,
  nota            text,
  actualizado_en  timestamptz not null default now()
);
comment on table public.plataforma_fuentes is 'Lo que alimenta la plataforma y hay que volver a subir: cadencia, cómo saber cuándo fue la última vez y hasta cuándo sirve. plataforma_fuentes_estado() lo evalúa; Hoy avisa; el hub lo muestra en #vigencia.';
alter table public.plataforma_fuentes enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'plataforma_fuentes' and policyname = 'fuentes_lectura') then
    create policy fuentes_lectura on public.plataforma_fuentes for select to authenticated using (auth.uid() is not null);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'plataforma_fuentes' and policyname = 'fuentes_admin') then
    create policy fuentes_admin on public.plataforma_fuentes for all to authenticated using (tiene_rol('admin')) with check (tiene_rol('admin'));
  end if;
end $$;

-- Los SELECT del catálogo pasan por el mismo validador que las herramientas del chat: solo lectura, una sentencia
create or replace function public.plataforma_fuentes_valida()
returns trigger language plpgsql as $$
begin
  if new.ultima_sql is not null then perform chat_sql_valida(new.ultima_sql); end if;
  if new.vence_sql is not null then perform chat_sql_valida(new.vence_sql); end if;
  if new.pendientes_sql is not null then perform chat_sql_valida(new.pendientes_sql); end if;
  new.actualizado_en := now();
  return new;
end $$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'plataforma_fuentes_valida' and tgrelid = 'public.plataforma_fuentes'::regclass) then
    create trigger plataforma_fuentes_valida before insert or update on public.plataforma_fuentes
      for each row execute function public.plataforma_fuentes_valida();
  end if;
end $$;

-- 2) El estado de cada fuente
create or replace function public.plataforma_fuentes_estado(p_rol text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  f record; v_hoy date := hoy_lima();
  v_ultima date; v_vence date; v_pend int; v_err text; v_cub int; v_due date;
  v_estado text; v_dias int; v_texto text; v_extra text; v_falta text; v_ult_txt text; v_cad text;
  v_out jsonb := '[]'::jsonb;
  meses text[] := array['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
begin
  -- sin rol explícito, el de la sesión (desde el hub); sin sesión (editor SQL), todas
  if p_rol is null then select rol into p_rol from perfiles where user_id = auth.uid() and activo; end if;
  for f in select * from plataforma_fuentes where activo and (p_rol is null or p_rol = any(roles)) order by orden, id loop
    v_ultima := null; v_vence := null; v_pend := null; v_err := null; v_falta := null; v_dias := null; v_cub := null; v_extra := '';
    begin
      if f.ultima_sql is not null then execute f.ultima_sql into v_ultima; end if;
      if f.vence_sql is not null then execute f.vence_sql into v_vence; end if;
      if f.pendientes_sql is not null then execute f.pendientes_sql into v_pend; end if;
    exception when others then
      v_err := sqlerrm;
    end;
    if v_err is null then
      case f.cadencia
        when 'periodo' then
          -- v_ultima es una fecha dentro del último período cubierto; se espera el siguiente, dia días después de su cierre
          v_cub := case when v_ultima is null then periodo_indice(v_hoy) - 2 else periodo_indice(v_ultima) end;
          v_vence := periodo_inicio(v_cub + 1) + 13 + f.dia;
          v_falta := 'PB' || periodo_numero(v_cub + 1);
        when 'mensual' then
          -- el día debido más reciente; hecho si se alimentó en ese mes, y entonces vence el del mes siguiente
          v_due := make_date(extract(year from v_hoy)::int, extract(month from v_hoy)::int, least(greatest(f.dia, 1), 28));
          if v_due > v_hoy then v_due := (v_due - interval '1 month')::date; end if;
          v_vence := case when v_ultima is not null and v_ultima >= date_trunc('month', v_due)::date
                          then (v_due + interval '1 month')::date else v_due end;
        when 'semanal' then
          v_vence := coalesce(v_ultima, v_hoy - 365) + 7 + f.dia;
        when 'evento' then
          if coalesce(v_pend, 0) = 0 then v_vence := null; end if;
        else null;   -- vigencia: la fecha viene de vence_sql
      end case;
    end if;
    if v_err is not null then v_estado := 'error';
    elsif v_vence is null then v_estado := 'al_dia';
    else
      v_dias := v_vence - v_hoy;
      v_estado := case when v_dias < 0 then 'vencido' when v_dias <= f.aviso_dias then 'por_vencer' else 'al_dia' end;
    end if;
    v_texto := case v_estado
      when 'error' then 'No se pudo calcular: ' || v_err
      when 'vencido' then 'Venció el ' || extract(day from v_vence) || ' de ' || meses[extract(month from v_vence)::int]
                          || ' (hace ' || -v_dias || case when v_dias = -1 then ' día).' else ' días).' end
      when 'por_vencer' then case v_dias when 0 then 'Vence hoy.' when 1 then 'Vence mañana.'
                             else 'Vence el ' || extract(day from v_vence) || ' de ' || meses[extract(month from v_vence)::int] || ' (en ' || v_dias || ' días).' end
      else case when v_vence is null then 'Al día.'
                else 'Al día hasta el ' || extract(day from v_vence) || ' de ' || meses[extract(month from v_vence)::int] || '.' end end;
    if v_falta is not null and v_estado in ('vencido', 'por_vencer') then v_extra := 'Falta el ' || v_falta || '.'; end if;
    if coalesce(v_pend, 0) > 0 then v_extra := trim(v_extra || ' ' || v_pend || ' por registrar.'); end if;
    v_ult_txt := case when f.cadencia = 'periodo' and v_cub is not null and v_ultima is not null then 'Último cargado: PB' || periodo_numero(v_cub)
                      when v_ultima is not null then 'Última vez: ' || to_char(v_ultima, 'DD/MM/YYYY') end;
    v_cad := case f.cadencia
      when 'vigencia' then 'Mientras dure lo cargado'
      when 'periodo' then 'Cada período, ' || f.dia || case when f.dia = 1 then ' día' else ' días' end || ' después del cierre'
      when 'mensual' then 'Cada mes, el día ' || f.dia
      when 'semanal' then 'Cada semana'
      else 'Cuando llega' end;
    v_out := v_out || jsonb_build_object(
      'id', f.id, 'nombre', f.nombre, 'accion', f.accion, 'modulo', f.modulo, 'cadencia', f.cadencia, 'cadencia_texto', v_cad,
      'ultima', v_ultima, 'ultima_texto', v_ult_txt, 'vence', v_vence, 'dias', v_dias, 'pendientes', v_pend,
      'estado', v_estado, 'estado_texto', v_texto, 'extra', nullif(v_extra, ''),
      'detalle', trim(v_texto || ' ' || v_extra), 'en_hoy', f.en_hoy);
  end loop;
  return v_out;
end $$;
grant execute on function public.plataforma_fuentes_estado(text) to authenticated;
revoke execute on function public.plataforma_fuentes_estado(text) from anon;

-- 3) La pantalla en el hub
insert into public.plataforma_modulos (id, nombre, descripcion, url, roles, acceso, activo, orden, grupo)
values ('vigencia', 'Vigencia de los datos', 'Qué toca volver a subir y cuándo vence.', '#vigencia', array['admin','asistente'], 'hub', true, 30, 'Oficina')
on conflict (id) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, url = excluded.url,
  roles = excluded.roles, acceso = excluded.acceso, activo = true, orden = excluded.orden, grupo = excluded.grupo;

-- 4) El catálogo inicial: lo que hoy alimenta la plataforma
insert into public.plataforma_fuentes (id, nombre, accion, modulo, roles, cadencia, dia, aviso_dias, ultima_sql, vence_sql, pendientes_sql, en_hoy, orden, nota) values
('listas-precios', 'Listas de precios y promociones',
 'Sube las listas nuevas en Precios y promociones (admin) antes de que venzan las vigentes.',
 'cotizador', array['admin','asistente'], 'vigencia', 0, 7,
 $q$select max(vigente_desde) from listas_precios where activa$q$,
 $q$select max(vigente_hasta) from listas_precios where activa and vigente_hasta is not null$q$,
 null, true, 10, 'La fecha es la de la última promoción activa con vencimiento; la lista general no vence.'),
('reporte-pedidos', 'Reporte de pedidos de Rena Ware',
 'Descarga el reporte de órdenes del período en el back office y súbelo en «Subir reporte de Rena Ware».',
 'importar-pedidos', array['admin','asistente'], 'periodo', 2, 2,
 $q$select max(periodo_inicio((split_part(periodo, '-', 1)::int - 2026) * 26 + substring(periodo from 'PB(\d+)')::int - 1)) from crm_pedidos$q$,
 null, null, false, 20, 'Hoy ya lo avisa el bloque «Datos oficiales» (reporte-rw).'),
('reporte-aurora', 'Reporte Aurora (montos y pendientes por facturar)',
 'Sube en Facturación el reporte Aurora del período: de ahí salen los montos y quién tiene pendiente por facturar.',
 'facturacion', array['admin','gestor'], 'periodo', 3, 3,
 $q$select aurora_hasta from fact_config where id = 'vigente'$q$,
 null, null, true, 30, null),
('reporte-fpd', 'Reporte FPD semanal (pagos a asesores)',
 'Sube el FPD de la semana en Facturación.',
 'facturacion', array['admin','gestor'], 'semanal', 1, 1,
 $q$select max(cargado_en)::date from fact_carga_fpd$q$,
 null, null, false, 31, 'Hoy ya lo avisa el bloque de Facturación (fpd).'),
('declaraciones', 'Declaraciones mensuales (SUNAT) al día',
 'Una vez al mes, marca en Facturación qué declaraciones ya se presentaron y pagaron.',
 'facturacion', array['admin','gestor'], 'mensual', 26, 3,
 $q$select max(greatest(creado_en::date, presentada_en, pagada_en, igv_pagado_en, renta_pagado_en, aviso_recibido_en)) from fact_declaraciones$q$,
 null, null, true, 32, 'El día 26 ya pasó el cronograma de SUNAT del mes anterior (vence entre el 12 y el 25).'),
('resultados-premios', 'Resultados de los programas de premios',
 'Descarga de RenaKit los resultados de cada programa del período y súbelos en Premios.',
 'premios', array['admin','asistente'], 'periodo', 7, 3,
 $q$select max(corte) from pr_cargas$q$,
 null, null, true, 40, null),
('catalogo-premios', 'Catálogo de premios vigente',
 'Cuando un programa termina, carga en Premios el catálogo del programa nuevo.',
 'premios', array['admin','asistente'], 'vigencia', 0, 7,
 $q$select max(creado_en)::date from pr_catalogo$q$,
 $q$select max(vigencia_hasta) from pr_catalogo where activo$q$,
 null, true, 41, null),
('recepcion-premios', 'Premios oficiales recibidos en oficina',
 'Al llegar los premios oficiales, márcalos como recibidos en Premios: ahí arranca el aviso al asesor.',
 'premios', array['admin','asistente'], 'evento', 21, 0,
 null,
 $q$select min(coalesce(confirmado_en, creado_en::date)) + 21 from pr_premios where div = 'WV08' and tipo = 'final' and recibido_en is null$q$,
 $q$select count(*) from pr_premios where div = 'WV08' and tipo = 'final' and recibido_en is null$q$,
 false, 42, 'Hoy ya lo avisa el bloque de Premios (premios-recibir).'),
('empiece-ya', 'Resultados de Empiece Ya',
 'Sube el PDF de resultados del período (RenaKit) en Ganadores Empiece Ya.',
 'empiece-ya', array['admin','asistente'], 'periodo', 7, 3,
 $q$select max(fecha_cierre) from eya_periodos$q$,
 null, null, false, 50, 'Hoy ya lo avisa el bloque de Empiece Ya (eya).'),
('zonas-credito', 'Lista de zonas autorizadas para crédito',
 'Pide a Créditos la lista vigente de zonas autorizadas y cárgala en Zonas de crédito.',
 'zonas', array['admin','asistente'], 'vigencia', 0, 30,
 $q$select cargado_en::date from zc_config where id = 'zonas'$q$,
 $q$select (make_date(split_part(vigencia, ' ', 2)::int, array_position(array['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'], lower(split_part(vigencia, ' ', 1))), 1) + interval '1 year')::date from zc_config where id = 'zonas'$q$,
 null, true, 60, 'Se considera vigente un año desde el mes de la lista (zc_config.vigencia, p. ej. «Abril 2025»).'),
('horario-local', 'Horario de turnos del local',
 'Antes de que termine el horario vigente, crea el del siguiente bloque en Local del equipo (admin).',
 'local', array['admin'], 'vigencia', 0, 14,
 $q$select (valor #>> '{}')::date from loc_config where clave = 'inicio'$q$,
 $q$select ((select (valor #>> '{}')::date from loc_config where clave = 'inicio') + (select (valor #>> '{}')::int from loc_config where clave = 'semanas') * 7 - 1)$q$,
 null, true, 70, null),
('clases-nivel-cero', 'Clases del Nivel Cero programadas',
 'Programa las clases de la semana en Nivel Cero.',
 'nivel-cero', array['admin','asistente'], 'semanal', 0, 2,
 $q$select max(fecha) from n0_clases where not borrada$q$,
 null, null, true, 80, null),
('asistencia-nivel-cero', 'Asistencia del Nivel Cero marcada',
 'Marca la asistencia de cada clase apenas termina; sin eso no corre el conteo de las 5 clases.',
 'nivel-cero', array['admin','asistente'], 'evento', 2, 0,
 null,
 $q$select min(c.fecha) + 2 from n0_clases c where not c.borrada and c.fecha < hoy_lima() and not exists (select 1 from n0_asistencias a where a.clase_id = c.id)$q$,
 $q$select count(*) from n0_clases c where not c.borrada and c.fecha < hoy_lima() and not exists (select 1 from n0_asistencias a where a.clase_id = c.id)$q$,
 true, 81, null),
('fichas-chat', 'Fichas del chat con fecha de vigencia',
 'Actualiza o apaga en chat_fichas lo que venció (promociones, reglas con fecha).',
 'chat', array['admin'], 'vigencia', 0, 3,
 $q$select max(actualizado_en)::date from chat_fichas where activo$q$,
 $q$select min(vigente_hasta) from chat_fichas where activo and vigente_hasta is not null$q$,
 null, true, 90, null)
on conflict (id) do update set nombre = excluded.nombre, accion = excluded.accion, modulo = excluded.modulo, roles = excluded.roles,
  cadencia = excluded.cadencia, dia = excluded.dia, aviso_dias = excluded.aviso_dias, ultima_sql = excluded.ultima_sql,
  vence_sql = excluded.vence_sql, pendientes_sql = excluded.pendientes_sql, en_hoy = excluded.en_hoy, orden = excluded.orden, nota = excluded.nota;

-- 5) Hoy: una tarjeta «Vigencia» por cada fuente vencida o por vencer que el módulo no avise ya
--    (bloque agregado a hoy_items_v2 con replace() sobre su cuerpo, antes del bloque de salud de la plataforma):
--
--    begin
--      for f in select * from jsonb_array_elements(plataforma_fuentes_estado(p_rol)) loop
--        if (f->>'en_hoy')::boolean and f->>'estado' in ('vencido','por_vencer','error') then
--          v_items := v_items || jsonb_build_array(jsonb_build_object(
--            'id', 'vigencia-' || (f->>'id'), 'modulo', 'Vigencia',
--            'nivel', case f->>'estado' when 'vencido' then 'alto' when 'por_vencer' then 'medio' else 'info' end,
--            'titulo', case f->>'estado' when 'vencido' then 'Vencido: ' when 'por_vencer' then
--                        case (f->>'dias')::int when 0 then 'Vence hoy: ' when 1 then 'Vence mañana: ' else 'Vence en ' || (f->>'dias') || ' días: ' end
--                      else 'Sin calcular: ' end || lower(left(f->>'nombre', 1)) || substr(f->>'nombre', 2),
--            'detalle', trim(coalesce(f->>'extra', '') || ' ' || coalesce(f->>'accion', '')), 'accion', f->>'ultima_texto', 'enlace', f->>'modulo'));
--        end if;
--      end loop;
--    exception when others then null;
--    end;

-- Estado el 03/11/2026 al aplicarlo: vencidos reporte-aurora (falta PB22), reporte-fpd (13 días) y zonas-credito
-- (lista de abril 2025); por vencer resultados-premios y empiece-ya (PB22, mañana); listas-precios vence el 11/11
-- (avisa desde el 4/11); el resto al día. Hoy muestra 3 tarjetas «Vigencia» (las dos de Facturación/Zonas vencidas y premios).
