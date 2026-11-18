-- =====================================================================
-- MINI ERP · CONTROL DE FLETES · Esquema completo para Supabase
-- Reconstruido a partir del código del portal y de la estructura real
-- de la base actual (17-nov-2026).
--
-- CÓMO USARLO: en tu proyecto nuevo de Supabase abre "SQL Editor",
-- pega TODO este archivo y pulsa "Run". Se puede ejecutar una sola vez
-- sobre un proyecto vacío.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. USUARIOS Y PERMISOS
-- ---------------------------------------------------------------------
create table public.perfiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  nombre_completo  text,
  puesto           text,
  rol              text not null default 'usuario',   -- 'usuario', 'administrador', 'usuario|compra_cemento'
  activo           boolean not null default true,
  autorizador_id   uuid,                              -- quién autoriza sus OC (sin FK: permite migración)
  firma_url        text,                              -- firma en imagen base64
  email            text,
  usuario          text unique,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table public.permisos_usuario (
  id                   uuid primary key default gen_random_uuid(),
  usuario_id           uuid not null unique references public.perfiles(id) on delete cascade,
  crear_oc             boolean not null default false,
  ver_oc               boolean not null default false,
  editar_oc            boolean not null default false,
  eliminar_oc          boolean not null default false,
  autorizar_oc         boolean not null default false,
  ver_xml              boolean not null default false,
  validar_xml          boolean not null default false,
  ver_pagos            boolean not null default false,
  registrar_pagos      boolean not null default false,
  ver_catalogos        boolean not null default false,
  editar_catalogos     boolean not null default false,
  ver_dashboard        boolean not null default false,
  administrar_usuarios boolean not null default false
);

-- Accesos que el administrador prepara; la persona los "activa" creando su cuenta.
create table public.accesos_pendientes (
  id                   uuid primary key default gen_random_uuid(),
  email                text not null unique,
  nombre_completo      text,
  puesto               text,
  usuario              text,
  autorizador_id       uuid,
  crear_oc             boolean not null default false,
  ver_oc               boolean not null default false,
  editar_oc            boolean not null default false,
  eliminar_oc          boolean not null default false,
  autorizar_oc         boolean not null default false,
  ver_xml              boolean not null default false,
  validar_xml          boolean not null default false,
  ver_pagos            boolean not null default false,
  registrar_pagos      boolean not null default false,
  ver_catalogos        boolean not null default false,
  editar_catalogos     boolean not null default false,
  ver_dashboard        boolean not null default false,
  administrar_usuarios boolean not null default false,
  activo               boolean not null default true,
  consumido            boolean not null default false,
  -- Columnas nuevas (solo para la migración desde la base anterior):
  rol                  text not null default 'usuario',
  firma_url            text,
  perfil_anterior_id   uuid,      -- id del usuario en la base vieja; al activar la cuenta se reasignan sus OC
  created_at           timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. CATÁLOGOS
-- ---------------------------------------------------------------------
create table public.empresas_receptoras (
  id               uuid primary key default gen_random_uuid(),
  razon_social     text not null,
  rfc              text,
  regimen_fiscal   text,
  uso_cfdi         text,
  calle            text,
  numero_exterior  text,
  numero_interior  text,
  colonia          text,
  municipio        text,
  estado           text,
  codigo_postal    text,
  pais             text default 'MEXICO',
  activo           boolean not null default true,
  created_at       timestamptz not null default now()
);

create table public.fleteras (
  id                   uuid primary key default gen_random_uuid(),
  razon_social         text not null,
  rfc                  text,
  contacto             text,
  telefono             text,
  correo               text,
  regimen_fiscal       text,
  activo               boolean not null default true,
  created_at           timestamptz not null default now(),
  nombre_comercial     text,
  metodo_pago          text,
  retencion_aplicable  boolean not null default true,
  porcentaje_retencion numeric not null default 0.04
);

create table public.ubicaciones (
  id                   uuid primary key default gen_random_uuid(),
  nombre               text not null,
  tipo                 text,
  razon_social         text,
  rfc                  text,
  calle                text,
  numero_exterior      text,
  numero_interior      text,
  colonia              text,
  municipio            text,
  estado               text,
  codigo_postal        text,
  pais                 text default 'MEXICO',
  referencia_horario   text,
  observaciones        text,
  requiere_cita_sanver boolean not null default false,
  activo               boolean not null default true,
  created_at           timestamptz not null default now(),
  localidad            text,
  liga_ubicacion       text,
  contacto             text,
  telefono             text,
  distancia_km         numeric default 0
);

create table public.productos_frecuentes (
  id                       uuid primary key default gen_random_uuid(),
  nombre_captura           text not null,
  producto_interno         text,
  marca                    text,
  presentacion             text,
  descripcion_oc           text,
  bienes_transp            text,
  unidad_sat               text,
  unidad_captura           text,
  peso_unitario_kg         numeric default 0,
  activo                   boolean not null default true,
  created_at               timestamptz not null default now(),
  material_peligroso       boolean not null default false,
  clave_material_peligroso text,
  embalaje                 text,
  tolerancia_peso_pct      numeric
);

create table public.tipos_unidad (
  id      uuid primary key default gen_random_uuid(),
  nombre  text not null,
  activo  boolean not null default true
);

create table public.tarifas (
  id                  uuid primary key default gen_random_uuid(),
  fletera_id          uuid references public.fleteras(id),
  tipo_unidad_id      uuid references public.tipos_unidad(id),
  origen_id           uuid references public.ubicaciones(id),
  destino_id          uuid references public.ubicaciones(id),
  monto               numeric not null default 0,
  activo              boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  producto_familia    text,
  incluye_iva         boolean not null default false,
  porcentaje_iva      numeric,
  retencion_aplicable boolean not null default true,
  total_esperado      numeric,
  vigencia_desde      date,
  vigencia_hasta      date,
  observaciones       text
);

create table public.distancias_ruta (
  id           uuid primary key default gen_random_uuid(),
  origen_id    uuid not null references public.ubicaciones(id) on delete cascade,
  destino_id   uuid not null references public.ubicaciones(id) on delete cascade,
  distancia_km numeric not null default 0,
  activo       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (origen_id, destino_id)
);

-- ---------------------------------------------------------------------
-- 3. ÓRDENES DE SERVICIO (OC de flete)
-- Las columnas de usuarios (solicitante_id, autorizado_por_id, …) NO tienen
-- llave foránea a propósito: así la migración puede cargar las OC antes de
-- que cada persona active su cuenta, y luego se reasignan automáticamente.
-- ---------------------------------------------------------------------
create table public.ordenes_servicio (
  id                              uuid primary key default gen_random_uuid(),
  folio                           text not null unique,
  empresa_receptora_id            uuid references public.empresas_receptoras(id),
  fletera_id                      uuid references public.fleteras(id),
  tipo_unidad_id                  uuid references public.tipos_unidad(id),
  tipo_servicio                   text,
  fecha_solicitud                 date default current_date,
  fecha_requerida                 date,
  estatus                         text not null default 'ENVIADO A FLETERA',
  solicitante_id                  uuid,
  autorizador_asignado_id         uuid,
  autorizado_por_id               uuid,
  fecha_autorizacion              timestamptz,
  tarifa_base                     numeric default 0,
  iva                             numeric default 0,
  retencion                       numeric default 0,
  total                           numeric default 0,
  observaciones                   text,
  created_at                      timestamptz not null default now(),
  updated_at                      timestamptz not null default now(),
  porcentaje_retencion            numeric default 0.04,
  fiscal_esperado                 jsonb default '{}'::jsonb,
  version                         integer not null default 1,
  solicitado_por_snapshot         text,
  puesto_solicita_snapshot        text,
  firma_solicita_snapshot         text,
  autorizado_por_snapshot         text,
  puesto_autoriza_snapshot        text,
  firma_autoriza_snapshot         text,
  distancia_km                    numeric default 0,
  valor_mercancia_sin_iva         numeric default 0,
  costo_km                        numeric default 0,
  costo_ton_km                    numeric default 0,
  impacto_flete_pct               numeric default 0,
  remisiones                      jsonb default '[]'::jsonb,
  etapa                           text default 'CREADA',
  documentos_validados            boolean not null default false,
  documentos_validados_at         timestamptz,
  documentos_validados_por        uuid,
  entrega_confirmada              boolean not null default false,
  entrega_confirmada_at           timestamptz,
  entrega_confirmada_por_id       uuid,
  valor_mercancia_real_sin_iva    numeric,
  toneladas_reales                numeric,
  costo_km_real                   numeric,
  costo_ton_km_real               numeric,
  impacto_flete_real_pct          numeric,
  comprador_pago_snapshot         text,
  puesto_comprador_pago_snapshot  text,
  firma_comprador_pago_snapshot   text,
  pago_autorizado_por_id          uuid,
  fecha_autorizacion_pago         timestamptz,
  pago_autorizado_por_snapshot    text,
  puesto_autoriza_pago_snapshot   text,
  firma_autoriza_pago_snapshot    text,
  liberado_pago                   boolean not null default false,
  liberado_pago_at                timestamptz,
  apoyos_flete                    jsonb default '[]'::jsonb,
  apoyo_total_esperado            numeric default 0,
  flete_bruto_despues_apoyo       numeric default 0,
  impacto_despues_apoyo_pct       numeric default 0,
  costo_ton_km_despues_apoyo      numeric default 0,
  distancia_carta_porte_km        numeric
);
create index on public.ordenes_servicio (solicitante_id);
create index on public.ordenes_servicio (autorizador_asignado_id);
create index on public.ordenes_servicio (estatus);

create table public.puntos_orden (
  id                 uuid primary key default gen_random_uuid(),
  orden_id           uuid not null references public.ordenes_servicio(id) on delete cascade,
  partida            integer not null default 1,
  tipo               text,
  ubicacion_id       uuid references public.ubicaciones(id) on delete set null,
  proveedor_cliente  text,
  material           text,
  cantidad           numeric,
  observaciones      text,
  created_at         timestamptz not null default now(),
  referencias        text,
  contacto           text,
  telefono           text,
  liga               text
);
create index on public.puntos_orden (orden_id);

create table public.mercancias_orden (
  id                       uuid primary key default gen_random_uuid(),
  orden_id                 uuid not null references public.ordenes_servicio(id) on delete cascade,
  producto_frecuente_id    uuid references public.productos_frecuentes(id) on delete set null,
  producto_interno         text,
  descripcion              text,
  bienes_transp            text,
  unidad_sat               text,
  unidad_captura           text,
  cantidad                 numeric default 0,
  peso_unitario_kg         numeric,
  peso_total_kg            numeric default 0,
  created_at               timestamptz not null default now(),
  valor_mercancia_sin_iva  numeric default 0,
  proveedor_cliente        text
);
create index on public.mercancias_orden (orden_id);

create table public.facturas_xml (
  id                     uuid primary key default gen_random_uuid(),
  orden_id               uuid references public.ordenes_servicio(id) on delete cascade,
  uuid_fiscal            text unique,
  rfc_emisor             text,
  razon_social_emisor    text,
  rfc_receptor           text,
  razon_social_receptor  text,
  subtotal               numeric,
  iva                    numeric,
  retencion              numeric,
  total                  numeric,
  fecha_emision          timestamptz,
  resultado_validacion   text,
  diferencias            jsonb,
  archivo_url            text,
  created_at             timestamptz not null default now(),
  xml_nombre             text,
  folio_factura          text,
  serie                  text,
  tiene_carta_porte      boolean,
  carta_porte_version    text,
  peso_bruto_total       numeric,
  num_total_mercancias   integer,
  validado_por           uuid,
  validado_at            timestamptz
);
create index on public.facturas_xml (orden_id);

create table public.evidencias_entrega (
  id              uuid primary key default gen_random_uuid(),
  orden_id        uuid not null references public.ordenes_servicio(id) on delete cascade,
  nombre_archivo  text,
  storage_path    text,
  tipo_mime       text,
  observaciones   text,
  subido_por      uuid,
  created_at      timestamptz not null default now()
);
create index on public.evidencias_entrega (orden_id);

-- ---------------------------------------------------------------------
-- 4. BITÁCORA (auditoría + datos del módulo de cemento y catálogos JSON)
-- ---------------------------------------------------------------------
create table public.bitacora (
  id           bigint generated by default as identity primary key,
  usuario_id   uuid,
  accion       text,
  modulo       text,
  registro_id  text,
  detalle      jsonb,
  created_at   timestamptz not null default now()
);
create index on public.bitacora (modulo, registro_id, created_at desc);
create index on public.bitacora (modulo, created_at desc);

-- ---------------------------------------------------------------------
-- 5. updated_at automático
-- ---------------------------------------------------------------------
create or replace function public.tocar_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
create trigger t_upd_ordenes  before update on public.ordenes_servicio for each row execute function public.tocar_updated_at();
create trigger t_upd_perfiles before update on public.perfiles         for each row execute function public.tocar_updated_at();
create trigger t_upd_tarifas  before update on public.tarifas          for each row execute function public.tocar_updated_at();
create trigger t_upd_dist     before update on public.distancias_ruta  for each row execute function public.tocar_updated_at();

-- ---------------------------------------------------------------------
-- 6. FUNCIONES DE APOYO PARA PERMISOS
-- ---------------------------------------------------------------------
create or replace function public.es_usuario_activo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo)
$$;

create or replace function public.tiene_permiso(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select coalesce((to_jsonb(pu) ->> p)::boolean, false) or pu.administrar_usuarios
    from permisos_usuario pu join perfiles pf on pf.id = pu.usuario_id
    where pu.usuario_id = auth.uid() and pf.activo
  ), false)
$$;

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.tiene_permiso('administrar_usuarios')
$$;

create or replace function public.es_cemento() returns boolean
language sql stable security definer set search_path = public as $$
  select public.es_admin() or exists (
    select 1 from perfiles where id = auth.uid() and activo
      and 'compra_cemento' = any (regexp_split_to_array(lower(coalesce(rol,'')), '[|,; ]+')))
$$;

-- ---------------------------------------------------------------------
-- 7. FUNCIONES QUE LLAMA EL PORTAL (RPC)
-- ---------------------------------------------------------------------
-- Login con "usuario": devuelve el correo para iniciar sesión.
create or replace function public.resolver_usuario_login(p_usuario text) returns text
language sql stable security definer set search_path = public as $$
  select email from perfiles
  where lower(usuario) = lower(trim(p_usuario)) and activo
  limit 1
$$;

-- Perfil + permisos del usuario que inició sesión.
create or replace function public.obtener_mi_acceso() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when p.id is null then null else
    jsonb_build_object('perfil', to_jsonb(p), 'permisos', coalesce(to_jsonb(pu), '{}'::jsonb)) end
  from (select 1) x
  left join perfiles p on p.id = auth.uid()
  left join permisos_usuario pu on pu.usuario_id = p.id
$$;

-- Folio consecutivo por día: AAAAMMDD-001 (hora de Ciudad de México).
create or replace function public.generar_folio() returns text
language plpgsql security definer set search_path = public as $$
declare pref text := to_char(now() at time zone 'America/Mexico_City', 'YYYYMMDD'); n int;
begin
  if not public.es_usuario_activo() then raise exception 'Sin acceso'; end if;
  perform pg_advisory_xact_lock(hashtext('folio_oc_' || pref));
  select coalesce(max(nullif(regexp_replace(split_part(folio, '-', 2), '\D', '', 'g'), '')::int), 0) + 1
    into n from ordenes_servicio where folio like pref || '-%';
  return pref || '-' || lpad(n::text, 3, '0');
end $$;

create or replace function public.actualizar_mi_firma(p_firma text) returns void
language sql security definer set search_path = public as $$
  update perfiles set firma_url = p_firma where id = auth.uid()
$$;

-- Antes de crear la cuenta, valida que el administrador haya preparado el acceso.
create or replace function public.validar_acceso_pendiente(p_usuario text, p_email text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a accesos_pendientes;
begin
  select * into a from accesos_pendientes
   where lower(email) = lower(trim(p_email)) and lower(usuario) = lower(trim(p_usuario));
  if a.id is null then return jsonb_build_object('valido', false, 'mensaje', 'No existe un acceso preparado con ese usuario y correo. Pídelo al administrador.'); end if;
  if a.consumido then return jsonb_build_object('valido', false, 'mensaje', 'Ese acceso ya fue activado. Inicia sesión con tu usuario o usa "Olvidé mi contraseña".'); end if;
  if not a.activo then return jsonb_build_object('valido', false, 'mensaje', 'Ese acceso está dado de baja.'); end if;
  return jsonb_build_object('valido', true, 'mensaje', 'ok');
end $$;

-- Reasigna todo lo que pertenecía a un id de usuario viejo hacia el nuevo (migración).
create or replace function public.reasignar_usuario(p_viejo uuid, p_nuevo uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.es_admin() then raise exception 'Solo el administrador'; end if;
  if p_viejo is null or p_nuevo is null or p_viejo = p_nuevo then return; end if;
  update ordenes_servicio set solicitante_id            = p_nuevo where solicitante_id            = p_viejo;
  update ordenes_servicio set autorizador_asignado_id   = p_nuevo where autorizador_asignado_id   = p_viejo;
  update ordenes_servicio set autorizado_por_id         = p_nuevo where autorizado_por_id         = p_viejo;
  update ordenes_servicio set documentos_validados_por  = p_nuevo where documentos_validados_por  = p_viejo;
  update ordenes_servicio set entrega_confirmada_por_id = p_nuevo where entrega_confirmada_por_id = p_viejo;
  update ordenes_servicio set pago_autorizado_por_id    = p_nuevo where pago_autorizado_por_id    = p_viejo;
  update facturas_xml       set validado_por   = p_nuevo where validado_por   = p_viejo;
  update evidencias_entrega set subido_por     = p_nuevo where subido_por     = p_viejo;
  update bitacora           set usuario_id     = p_nuevo where usuario_id     = p_viejo;
  update perfiles           set autorizador_id = p_nuevo where autorizador_id = p_viejo;
  update accesos_pendientes set autorizador_id = p_nuevo where autorizador_id = p_viejo;
end $$;
revoke execute on function public.reasignar_usuario(uuid, uuid) from public, anon;
grant execute on function public.reasignar_usuario(uuid, uuid) to authenticated;  -- valida internamente que sea administrador

-- Al crearse una cuenta en Supabase Auth: crea su perfil y permisos desde el acceso preparado.
create or replace function public.crear_perfil_desde_acceso() returns trigger
language plpgsql security definer set search_path = public as $$
declare a accesos_pendientes;
begin
  select * into a from accesos_pendientes
   where lower(email) = lower(new.email) and activo and not consumido
   limit 1;
  if a.id is null then return new; end if;   -- cuenta sin acceso preparado: no entra al ERP
  insert into perfiles (id, nombre_completo, puesto, rol, activo, autorizador_id, firma_url, email, usuario)
  values (new.id, a.nombre_completo, a.puesto, coalesce(a.rol, 'usuario'), true, a.autorizador_id, a.firma_url,
          lower(new.email), lower(coalesce(a.usuario, new.raw_user_meta_data ->> 'usuario')))
  on conflict (id) do nothing;
  insert into permisos_usuario (usuario_id, crear_oc, ver_oc, editar_oc, eliminar_oc, autorizar_oc, ver_xml, validar_xml,
                                ver_pagos, registrar_pagos, ver_catalogos, editar_catalogos, ver_dashboard, administrar_usuarios)
  values (new.id, a.crear_oc, a.ver_oc, a.editar_oc, a.eliminar_oc, a.autorizar_oc, a.ver_xml, a.validar_xml,
          a.ver_pagos, a.registrar_pagos, a.ver_catalogos, a.editar_catalogos, a.ver_dashboard, a.administrar_usuarios)
  on conflict (usuario_id) do nothing;
  update accesos_pendientes set consumido = true where id = a.id;
  if a.perfil_anterior_id is not null then perform public.reasignar_usuario(a.perfil_anterior_id, new.id); end if;
  return new;
end $$;
create trigger t_crear_perfil after insert on auth.users
  for each row execute function public.crear_perfil_desde_acceso();

-- Importación del respaldo (solo administrador). Conserva ids y fechas; si se
-- vuelve a ejecutar, ignora lo que ya existe.
create or replace function public.importar_respaldo(p_tabla text, p_filas jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer := 0; k integer; cols text; todas text[]; r jsonb;
begin
  if not public.es_admin() then raise exception 'Solo el administrador puede importar respaldos'; end if;
  if p_tabla not in ('empresas_receptoras','fleteras','ubicaciones','productos_frecuentes','tipos_unidad','tarifas',
                     'distancias_ruta','ordenes_servicio','puntos_orden','mercancias_orden','facturas_xml',
                     'evidencias_entrega','bitacora','accesos_pendientes') then
    raise exception 'Tabla no permitida: %', p_tabla;
  end if;
  select array_agg(c.column_name::text order by c.ordinal_position) into todas
    from information_schema.columns c where c.table_schema = 'public' and c.table_name = p_tabla;
  -- Fila por fila: solo las columnas que esa fila trae con valor; las demás toman su valor por omisión.
  for r in select value from jsonb_array_elements(p_filas) loop
    select string_agg(quote_ident(x), ',') into cols from unnest(todas) x
     where r ? x and jsonb_typeof(r -> x) <> 'null';
    if cols is null then continue; end if;
    execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1) on conflict do nothing',
                   p_tabla, cols, cols, p_tabla) using r;
    get diagnostics k = row_count; n := n + k;
  end loop;
  if p_tabla = 'bitacora' then
    perform setval(pg_get_serial_sequence('public.bitacora', 'id'), greatest((select max(id) from bitacora), 1));
  end if;
  return n;
end $$;

grant execute on function public.resolver_usuario_login(text)           to anon, authenticated;
grant execute on function public.validar_acceso_pendiente(text, text)   to anon, authenticated;
grant execute on function public.obtener_mi_acceso()                    to authenticated;
grant execute on function public.generar_folio()                        to authenticated;
grant execute on function public.actualizar_mi_firma(text)              to authenticated;
grant execute on function public.importar_respaldo(text, jsonb)         to authenticated;

-- ---------------------------------------------------------------------
-- 8. SEGURIDAD POR FILA (RLS)
-- Nadie sin sesión puede leer nada. Los permisos replican los del portal.
-- ---------------------------------------------------------------------
alter table public.perfiles             enable row level security;
alter table public.permisos_usuario     enable row level security;
alter table public.accesos_pendientes   enable row level security;
alter table public.empresas_receptoras  enable row level security;
alter table public.fleteras             enable row level security;
alter table public.ubicaciones          enable row level security;
alter table public.productos_frecuentes enable row level security;
alter table public.tipos_unidad         enable row level security;
alter table public.tarifas              enable row level security;
alter table public.distancias_ruta      enable row level security;
alter table public.ordenes_servicio     enable row level security;
alter table public.puntos_orden         enable row level security;
alter table public.mercancias_orden     enable row level security;
alter table public.facturas_xml         enable row level security;
alter table public.evidencias_entrega   enable row level security;
alter table public.bitacora             enable row level security;

-- Usuarios
create policy perfiles_leer   on public.perfiles for select to authenticated using (public.es_usuario_activo() or id = auth.uid());
create policy perfiles_admin  on public.perfiles for all    to authenticated using (public.es_admin()) with check (public.es_admin());
create policy permisos_leer   on public.permisos_usuario for select to authenticated using (usuario_id = auth.uid() or public.es_admin());
create policy permisos_admin  on public.permisos_usuario for all    to authenticated using (public.es_admin()) with check (public.es_admin());
create policy accesos_admin   on public.accesos_pendientes for all  to authenticated using (public.es_admin()) with check (public.es_admin());

-- Catálogos: todos los usuarios activos leen; editan quienes tienen "editar_catalogos".
do $$ declare t text; begin
  foreach t in array array['empresas_receptoras','fleteras','productos_frecuentes','tipos_unidad','tarifas'] loop
    execute format('create policy %1$s_leer on public.%1$I for select to authenticated using (public.es_usuario_activo())', t);
    execute format('create policy %1$s_alta on public.%1$I for insert to authenticated with check (public.tiene_permiso(''editar_catalogos''))', t);
    execute format('create policy %1$s_cambio on public.%1$I for update to authenticated using (public.tiene_permiso(''editar_catalogos'')) with check (public.tiene_permiso(''editar_catalogos''))', t);
    execute format('create policy %1$s_borra on public.%1$I for delete to authenticated using (public.es_admin())', t);
  end loop;
end $$;
-- Ubicaciones: también las da de alta el módulo de cemento (puntos CEMEX).
create policy ubicaciones_leer   on public.ubicaciones for select to authenticated using (public.es_usuario_activo());
create policy ubicaciones_alta   on public.ubicaciones for insert to authenticated with check (public.tiene_permiso('editar_catalogos') or public.es_cemento());
create policy ubicaciones_cambio on public.ubicaciones for update to authenticated using (public.tiene_permiso('editar_catalogos') or public.es_cemento()) with check (public.tiene_permiso('editar_catalogos') or public.es_cemento());
create policy ubicaciones_borra  on public.ubicaciones for delete to authenticated using (public.es_admin());

create policy distancias_leer   on public.distancias_ruta for select to authenticated using (public.es_usuario_activo());
create policy distancias_alta   on public.distancias_ruta for insert to authenticated with check (public.es_usuario_activo());
create policy distancias_cambio on public.distancias_ruta for update to authenticated using (public.es_usuario_activo()) with check (public.es_usuario_activo());

-- Órdenes
create policy ordenes_leer on public.ordenes_servicio for select to authenticated using (public.es_usuario_activo());
create policy ordenes_alta on public.ordenes_servicio for insert to authenticated with check (public.tiene_permiso('crear_oc'));
create policy ordenes_cambio on public.ordenes_servicio for update to authenticated
  using (public.es_usuario_activo() and (
        solicitante_id = auth.uid() or autorizador_asignado_id = auth.uid()
     or public.tiene_permiso('editar_oc') or public.tiene_permiso('eliminar_oc') or public.tiene_permiso('autorizar_oc')
     or public.tiene_permiso('ver_xml') or public.tiene_permiso('validar_xml') or public.tiene_permiso('registrar_pagos')))
  with check (public.es_usuario_activo());
create policy ordenes_borra on public.ordenes_servicio for delete to authenticated using (public.es_admin());

do $$ declare t text; begin
  foreach t in array array['puntos_orden','mercancias_orden'] loop
    execute format('create policy %1$s_leer on public.%1$I for select to authenticated using (public.es_usuario_activo())', t);
    execute format('create policy %1$s_escribe on public.%1$I for all to authenticated using (public.tiene_permiso(''crear_oc'') or public.tiene_permiso(''editar_oc'')) with check (public.tiene_permiso(''crear_oc'') or public.tiene_permiso(''editar_oc''))', t);
  end loop;
end $$;

create policy facturas_leer   on public.facturas_xml for select to authenticated using (public.es_usuario_activo());
create policy facturas_alta   on public.facturas_xml for insert to authenticated with check (public.tiene_permiso('ver_xml') or public.tiene_permiso('validar_xml'));
create policy facturas_cambio on public.facturas_xml for update to authenticated using (public.tiene_permiso('ver_xml') or public.tiene_permiso('validar_xml')) with check (public.tiene_permiso('ver_xml') or public.tiene_permiso('validar_xml'));

create policy evidencias_leer on public.evidencias_entrega for select to authenticated using (public.es_usuario_activo());
create policy evidencias_alta on public.evidencias_entrega for insert to authenticated with check (public.es_usuario_activo());

create policy bitacora_leer on public.bitacora for select to authenticated using (public.es_usuario_activo());
create policy bitacora_alta on public.bitacora for insert to authenticated with check (public.es_usuario_activo() and usuario_id = auth.uid());

-- ---------------------------------------------------------------------
-- 9. ARCHIVOS (XML, PDF, evidencias de entrega)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('erp-fletes-documentos', 'erp-fletes-documentos', false)
on conflict (id) do nothing;
create policy docs_leer  on storage.objects for select to authenticated using (bucket_id = 'erp-fletes-documentos' and public.es_usuario_activo());
create policy docs_subir on storage.objects for insert to authenticated with check (bucket_id = 'erp-fletes-documentos' and public.es_usuario_activo());
