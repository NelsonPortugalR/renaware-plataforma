-- =====================================================================================================
-- Salud: la clave del bot de pedidos cuenta como chequeo (19 de noviembre de 2026). Aplicado en la base; este archivo es la copia.
--
-- El 18/11, desde otro chat, se creó crm_bot_registrar(p_clave, p_filas): la llama un bot con su propia clave y antes de
-- tocar nada la valida con crm_bot_valida (compara el sha256 contra crm_bot_claves activas). plataforma_salud() no conocía
-- ese chequeo y la contaba como «función pública que escribe sin chequeo» y «que lee personas sin sesión»: dos hallazgos
-- falsos (de 22 a 24). Ahora la reconoce y vuelven a ser 22 (19 de seguridad).
--
-- Parche sobre la función viva: agrega crm_bot_valida a la lista de chequeos reconocidos. Si ya está, no hace nada.
-- =====================================================================================================

do $do$
declare v text := pg_get_functiondef('public.plataforma_salud()'::regprocedure);
begin
  if position('crm_bot_valida' in v) > 0 then return; end if;   -- ya aplicado
  if (select count(*) from regexp_matches(v, '\|reg_sesion''', 'g')) <> 1 then raise exception 'ancla no encontrada en plataforma_salud'; end if;
  execute replace(v, '|reg_sesion''', '|reg_sesion|crm_bot_valida''');
end $do$;
