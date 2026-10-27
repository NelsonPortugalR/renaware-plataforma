-- =====================================================================
-- Test del Nivel 0 · tablas y contenido fijo  (prefijo ts_)
-- Quien completa sus 5 clases tiene 15 días para aprobar el test (90+).
-- Aprobado = botella de acero como premio "Nivel Cero" en Premios.
-- Mecánica del quiz anterior: 5 opciones, si falla se explica la lógica
-- (sin dar la respuesta) y sale otra pregunta del mismo tipo hasta acertar.
-- Nota = round(100 × pasos ÷ intentos).
-- =====================================================================

create table if not exists public.ts_config (
  id            text primary key default 'vigente' check (id = 'vigente'),
  nota_minima   smallint not null default 90 check (nota_minima between 50 and 100),
  dias_ventana  smallint not null default 15 check (dias_ventana between 1 and 90),
  aplica_desde  date not null default date '2026-10-27',   -- quien logró sus clases antes, no rinde test
  premio        text not null default 'Botella de acero inoxidable',
  fotos_promos  text not null default 'https://renaware-peru.nelson1614.workers.dev/promociones/',
  cuentas       jsonb not null default '[]'::jsonb,           -- [{"banco":"BCP","validos":["1941234...","00219400..."]}]
  actualizado_en timestamptz not null default now()
);
insert into public.ts_config (id) values ('vigente') on conflict (id) do nothing;
comment on table public.ts_config is 'Test Nivel 0: ajustes (fila única). cuentas = números válidos por banco para la pregunta de cuentas; vacía = esa pregunta no sale.';

create table if not exists public.ts_pasos (
  clave   text primary key,
  bloque  text not null check (bloque in ('productos','credito','zonas','pagos','empiece','comisiones','objeciones')),
  orden   smallint not null,
  titulo  text not null,
  activo  boolean not null default true
);
comment on table public.ts_pasos is 'Test Nivel 0: los pasos en orden. activo=false lo saca del test (se apaga desde la vista de oficina).';

insert into public.ts_pasos (clave, bloque, orden, titulo) values
  ('identificar',   'productos',  10, 'Reconocer productos'),
  ('precio_general','productos',  20, 'Precio en la lista general'),
  ('precio_promo',  'productos',  30, 'Precio de una promoción'),
  ('regalo_promo',  'productos',  40, 'Regalo de las promociones'),
  ('inicial',       'credito',    50, 'Inicial mínima'),
  ('medios_inicial','credito',    60, 'Medios para la inicial'),
  ('saldo',         'credito',    70, 'Saldo contra entrega'),
  ('cuota_n',       'credito',    80, 'Cuota a crédito'),
  ('cuota_20',      'credito',    90, 'Cuota con inicial mayor'),
  ('prepago',       'credito',   100, 'Adelantar pagos'),
  ('financiables',  'zonas',     110, 'Qué se puede financiar'),
  ('cuotas_max',    'zonas',     120, 'Cuotas máximas'),
  ('inicial_100',   'zonas',     130, 'Pago al 100 %'),
  ('caso_100',      'zonas',     140, 'Otro caso de pago al 100 %'),
  ('zona',          'zonas',     150, 'Zonas de crédito'),
  ('cuentas',       'pagos',     160, 'Cuentas de Rena Ware'),
  ('medios_saldo',  'pagos',     170, 'Medios para el saldo'),
  ('pago_cuotas',   'pagos',     180, 'Cómo se pagan las cuotas'),
  ('ey_plazo',      'empiece',   190, 'Plazo del Empiece Ya'),
  ('ey_n1',         'empiece',   200, 'Nivel I'),
  ('ey_n2',         'empiece',   210, 'Nivel II'),
  ('ey_gpv',        'empiece',   220, 'Qué es el GPV'),
  ('ey_rol',        'empiece',   230, 'Tu rol con tus afiliados'),
  ('com_donde',     'comisiones',240, 'Dónde ver la comisión'),
  ('com_pct',       'comisiones',250, 'Cuánto es la comisión'),
  ('auto_que',      'comisiones',260, 'Qué es la autocompra'),
  ('auto_ejemplo',  'comisiones',270, 'Ejemplo de autocompra'),
  ('venta_gana',    'comisiones',280, 'Cuánto ganas por una venta'),
  ('frase_oro',     'objeciones',290, 'La frase de oro'),
  ('objeciones_3',  'objeciones',300, 'Las 3 objeciones'),
  ('obj_caro',      'objeciones',310, '«Es caro»'),
  ('obj_tengo',     'objeciones',320, '«Ya tengo»'),
  ('obj_repuesto',  'objeciones',330, '«Se me quema todo» / repuesto')
on conflict (clave) do nothing;

-- Preguntas de texto fijo. Varias filas por paso = variantes para el reintento.
-- multi: todas las correctas + n_incorrectas de las incorrectas.
create table if not exists public.ts_banco (
  id             text primary key,
  paso           text not null references public.ts_pasos(clave),
  texto          text not null,
  correctas      jsonb not null,
  incorrectas    jsonb not null,
  n_incorrectas  smallint not null default 4,
  logica         text not null,
  activo         boolean not null default true,
  actualizado_en timestamptz not null default now()
);
comment on table public.ts_banco is 'Test Nivel 0: preguntas de texto fijo (medios de pago, objeciones, conceptos). Varias filas por paso = variantes para cuando fallan.';

create table if not exists public.ts_personas (
  inscrito_id    uuid primary key,
  hasta          date,                      -- plazo corregido a mano
  excluido       boolean not null default false,
  nota           text,
  actualizado_en timestamptz not null default now()
);
comment on table public.ts_personas is 'Test Nivel 0: ajustes por persona (inscrito de Nivel Cero): plazo corregido o fuera del test.';

create table if not exists public.ts_intentos (
  id            uuid primary key default gen_random_uuid(),
  inscrito_id   uuid,                        -- null = práctica de la oficina
  celular       text,
  nombre        text,
  origen        text not null default 'asesor' check (origen in ('asesor','oficina')),
  iniciado_en   timestamptz not null default now(),
  terminado_en  timestamptz,
  plan          text[] not null,
  paso_idx      smallint not null default 0,
  ctx           jsonb not null default '{}'::jsonb,
  pregunta      jsonb,                       -- la pregunta en curso, con su clave
  usados        jsonb not null default '{}'::jsonb,
  log           jsonb not null default '[]'::jsonb,
  intentos      smallint not null default 0,
  aciertos      smallint not null default 0,
  nota          smallint,
  aprobado      boolean,
  anulado       boolean not null default false
);
create index if not exists ts_intentos_inscrito on public.ts_intentos (inscrito_id, iniciado_en desc);
comment on table public.ts_intentos is 'Test Nivel 0: un intento completo por fila. log = cada respuesta (paso, bloque, ok). nota = round(100 × pasos ÷ intentos).';

alter table public.ts_config   enable row level security;
alter table public.ts_pasos    enable row level security;
alter table public.ts_banco    enable row level security;
alter table public.ts_personas enable row level security;
alter table public.ts_intentos enable row level security;
revoke all on public.ts_config, public.ts_pasos, public.ts_banco, public.ts_personas, public.ts_intentos from anon, authenticated;
