-- Test del Nivel 0 · enlaces de consulta (libro abierto), editables desde Ajustes
alter table public.ts_config add column if not exists recursos jsonb not null
  default '[{"nombre":"Precios y promociones","url":"https://renaware-peru.nelson1614.workers.dev"}]'::jsonb;
comment on column public.ts_config.recursos is 'Enlaces que el asesor ve para rendir el test a libro abierto: [{"nombre","url"}].';

create or replace function public.ts_config_publica() returns jsonb
language sql stable set search_path = public as $$
  select jsonb_build_object('nota_minima', nota_minima, 'dias_ventana', dias_ventana, 'premio', premio,
                            'pasos', cardinality(ts_plan()), 'recursos', recursos)
    from ts_config where id = 'vigente'
$$;

create or replace function public.ts_admin_config(p_token uuid, p_cambios jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform ts_admin_ok(p_token);
  update ts_config set
    nota_minima  = coalesce((p_cambios ->> 'nota_minima')::smallint, nota_minima),
    dias_ventana = coalesce((p_cambios ->> 'dias_ventana')::smallint, dias_ventana),
    aplica_desde = coalesce((p_cambios ->> 'aplica_desde')::date, aplica_desde),
    premio       = coalesce(nullif(btrim(p_cambios ->> 'premio'), ''), premio),
    cuentas      = case when p_cambios ? 'cuentas' then coalesce(p_cambios -> 'cuentas', '[]'::jsonb) else cuentas end,
    recursos     = case when p_cambios ? 'recursos' then coalesce(p_cambios -> 'recursos', '[]'::jsonb) else recursos end,
    actualizado_en = now()
   where id = 'vigente';
  return (select to_jsonb(c) from ts_config c where id = 'vigente');
end $$;

revoke all on function public.ts_config_publica() from public, anon, authenticated;
