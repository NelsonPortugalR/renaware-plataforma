-- El motor de concursos de agosto (PPV digitado, concursos, reglas, detección) queda archivado.
-- Premios (pr_*) lo reemplaza. eq_personas se queda: es la base de personas de todos los módulos.
create schema if not exists archivo;
comment on schema archivo is 'Motor de concursos de agosto 2026, archivado el 21/10/2026. Reemplazado por Premios (pr_*).';

-- Los disparadores que alimentaban eq_ppv desde registros e hitos dejan de correr.
-- (tg_eq_afiliado se queda: mantiene eq_personas al día con las afiliaciones.)
drop trigger if exists tg_eq_hito on public.hitos;
drop trigger if exists tg_eq_registro on public.registros;

alter table public.eq_concursos set schema archivo;
alter table public.eq_reglas set schema archivo;
alter table public.eq_flags set schema archivo;
alter table public.eq_deteccion set schema archivo;
alter table public.eq_rutina set schema archivo;
alter table public.eq_carga set schema archivo;
alter table public.eq_premios set schema archivo;
alter table public.eq_puntaje_extra set schema archivo;
alter table public.eq_avisos set schema archivo;
alter table public.eq_listas set schema archivo;
alter table public.eq_ppv set schema archivo;
alter view public.eq_v_puntos_pedido set schema archivo;
alter view public.eq_v_ppv_sistema set schema archivo;

-- Nadie debe poder disparar el recálculo viejo desde la web
revoke execute on function public.eq_recalcular_todo() from public, anon, authenticated;
revoke execute on function public.eq_sync_ppv(uuid) from public, anon, authenticated;
revoke execute on function public.eq_refrescar_ppv(uuid) from public, anon, authenticated;
