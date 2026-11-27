-- =====================================================================
-- SANVER Embarques — V61
--   * El Coordinador de Transporte APRUEBA cada solicitud antes de que llegue
--     al transportista: contrato SANVER vigente con la fletera y rentabilidad
--     dentro de los lineamientos.
--   * Contrato por fletera (número, vigencia y PDF) en el catálogo.
--   * Lineamientos de rentabilidad por tipo de servicio.
--   * Notificaciones en tiempo real (Supabase Realtime).
-- Requiere 05_transportistas_y_coordinador.sql. Se puede ejecutar más de una vez.
-- =====================================================================

-- 1. CONTRATO SANVER POR FLETERA -----------------------------------------
alter table public.fleteras add column if not exists contrato_numero   text;
alter table public.fleteras add column if not exists contrato_vigencia date;
alter table public.fleteras add column if not exists contrato_archivo  text;   -- ruta en el bucket
alter table public.fleteras add column if not exists whatsapp          text;
-- El coordinador puede registrar el contrato de la fletera al aprobar.
drop policy if exists fleteras_contrato_coordinador on public.fleteras;
create policy fleteras_contrato_coordinador on public.fleteras for update to authenticated
  using (public.tiene_permiso('coordinar_transporte')) with check (public.tiene_permiso('coordinar_transporte'));

-- 2. NUEVOS ESTADOS DEL EMBARQUE ------------------------------------------
--   POR_APROBAR → (coordinador) APROBADA = EN_CAPTURA → ENVIADO → LIBERADO
--               ↘ RECHAZADO (vuelve al comprador)        ↘ DEVUELTO
alter table public.embarques_transportista drop constraint if exists embarques_transportista_estado_check;
alter table public.embarques_transportista add constraint embarques_transportista_estado_check
  check (estado in ('POR_APROBAR','RECHAZADO','EN_CAPTURA','ENVIADO','DEVUELTO','LIBERADO'));
alter table public.embarques_transportista add column if not exists aprobado_por    uuid;
alter table public.embarques_transportista add column if not exists aprobado_at     timestamptz;
alter table public.embarques_transportista add column if not exists nota_aprobacion text;
alter table public.embarques_transportista add column if not exists aprobacion      jsonb not null default '{}'::jsonb;

-- Solo el coordinador aprueba, rechaza, libera o devuelve.
create or replace function public.validar_estado_embarque() returns trigger
language plpgsql security definer set search_path = public as $$
declare anterior text := case when tg_op = 'UPDATE' then old.estado else null end;
begin
  if auth.uid() is not null and new.estado is distinct from anterior and not public.tiene_permiso('coordinar_transporte') then
    if new.estado in ('LIBERADO','DEVUELTO','RECHAZADO')
       or (new.estado = 'EN_CAPTURA' and coalesce(anterior,'POR_APROBAR') in ('POR_APROBAR','RECHAZADO')) then
      raise exception 'Solo el Coordinador de Transporte puede aprobar, rechazar, liberar o devolver un embarque';
    end if;
  end if;
  return new;
end $$;

-- 3. EL TRANSPORTISTA SOLO VE VIAJES APROBADOS -----------------------------
create or replace function public.orden_de_mi_fletera(p_orden text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from ordenes_servicio o
    where o.id::text = p_orden and o.fletera_id is not null and o.fletera_id = public.mi_fletera()
      and o.estatus <> 'CANCELADO'
      and (o.autorizado_por_id is not null
           or exists (select 1 from embarques_transportista e where e.orden_id = o.id
                       and e.estado in ('EN_CAPTURA','ENVIADO','DEVUELTO','LIBERADO'))))
$$;

create or replace function public.transportista_mis_viajes() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f uuid := public.mi_fletera();
begin
  if f is null then raise exception 'Tu usuario no está ligado a una fletera'; end if;
  return jsonb_build_object(
    'fletera', (select jsonb_build_object('id', id, 'razon_social', razon_social, 'nombre_comercial', nombre_comercial, 'rfc', rfc, 'regimen_fiscal', regimen_fiscal)
                from fleteras where id = f),
    'viajes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'folio', o.folio, 'estatus', o.estatus, 'etapa', o.etapa, 'tipo_servicio', o.tipo_servicio,
        'fecha_solicitud', o.fecha_solicitud, 'fecha_requerida', o.fecha_requerida, 'created_at', o.created_at,
        'solicitado_por', o.solicitado_por_snapshot, 'autorizado', o.autorizado_por_id is not null, 'fecha_autorizacion', o.fecha_autorizacion,
        'documentos_validados', o.documentos_validados, 'entrega_confirmada', o.entrega_confirmada, 'liberado_pago', o.liberado_pago,
        'tarifa_base', o.tarifa_base, 'iva', o.iva, 'retencion', o.retencion, 'total', o.total,
        'distancia_km', o.distancia_km, 'valor_mercancia_sin_iva', o.valor_mercancia_sin_iva,
        'remisiones', o.remisiones, 'observaciones', o.observaciones,
        'unidad', (select nombre from tipos_unidad t where t.id = o.tipo_unidad_id),
        'receptor', (select jsonb_build_object('razon_social', e.razon_social, 'rfc', e.rfc, 'regimen_fiscal', e.regimen_fiscal,
                       'uso_cfdi', e.uso_cfdi, 'codigo_postal', e.codigo_postal) from empresas_receptoras e where e.id = o.empresa_receptora_id),
        'puntos', (select coalesce(jsonb_agg(jsonb_build_object(
                      'partida', p.partida, 'tipo', p.tipo, 'proveedor', coalesce(p.proveedor_cliente, u.razon_social), 'material', p.material,
                      'cantidad', p.cantidad, 'observaciones', p.observaciones, 'referencias', coalesce(p.referencias, u.referencia_horario),
                      'contacto', coalesce(p.contacto, u.contacto), 'telefono', coalesce(p.telefono, u.telefono), 'liga', coalesce(p.liga, u.liga_ubicacion),
                      'ubicacion', u.nombre, 'rfc', u.rfc, 'codigo_postal', u.codigo_postal,
                      'direccion', concat_ws(', ', nullif(trim(concat_ws(' ', u.calle, u.numero_exterior)), ''), u.colonia, u.municipio, u.estado, u.codigo_postal))
                    order by p.partida), '[]'::jsonb)
                   from puntos_orden p left join ubicaciones u on u.id = p.ubicacion_id where p.orden_id = o.id),
        'mercancias', (select coalesce(jsonb_agg(jsonb_build_object(
                      'clave', m.bienes_transp, 'descripcion', m.descripcion, 'cantidad', m.cantidad, 'unidad_captura', m.unidad_captura,
                      'unidad_sat', m.unidad_sat, 'peso_total_kg', m.peso_total_kg, 'valor_mercancia_sin_iva', m.valor_mercancia_sin_iva,
                      'proveedor', m.proveedor_cliente)), '[]'::jsonb)
                   from mercancias_orden m where m.orden_id = o.id),
        'embarque', (select to_jsonb(et) - 'enviado_por' - 'revisado_por' - 'actualizado_por' - 'aprobado_por' - 'aprobacion'
                     from embarques_transportista et where et.orden_id = o.id)
      ) order by o.created_at desc)
      from ordenes_servicio o
      where o.fletera_id = f and public.orden_de_mi_fletera(o.id::text)), '[]'::jsonb));
end $$;

create or replace function public.transportista_guardar(p_orden uuid, p_datos jsonb, p_archivos jsonb, p_enviar boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o ordenes_servicio; e embarques_transportista; a jsonb;
begin
  if public.mi_fletera() is null then raise exception 'Tu usuario no está ligado a una fletera'; end if;
  select * into o from ordenes_servicio where id = p_orden;
  if o.id is null or o.fletera_id is distinct from public.mi_fletera() then raise exception 'Este viaje no está asignado a tu fletera'; end if;
  if o.estatus = 'CANCELADO' then raise exception 'El viaje fue cancelado'; end if;
  if o.autorizado_por_id is not null then raise exception 'El embarque ya fue liberado; ya no se puede modificar'; end if;
  select * into e from embarques_transportista where orden_id = p_orden;
  if e.orden_id is null or e.estado in ('POR_APROBAR','RECHAZADO') then raise exception 'El viaje aún no ha sido aprobado por el Coordinador de Transporte'; end if;
  if e.estado in ('ENVIADO','LIBERADO') then raise exception 'La información ya está en revisión del Coordinador de Transporte'; end if;
  if jsonb_typeof(coalesce(p_datos, '{}'::jsonb)) <> 'object' or jsonb_typeof(coalesce(p_archivos, '[]'::jsonb)) <> 'array' then
    raise exception 'Formato inválido'; end if;
  for a in select * from jsonb_array_elements(coalesce(p_archivos, '[]'::jsonb)) loop
    if coalesce(a ->> 'path', '') not like 'embarques/' || p_orden::text || '/%' then raise exception 'Archivo fuera del viaje'; end if;
  end loop;
  -- El contrato SANVER que adjuntó el coordinador se conserva aunque el transportista no lo envíe.
  update embarques_transportista set
    estado = case when p_enviar then 'ENVIADO' else estado end,
    datos = coalesce(p_datos, '{}'::jsonb) || jsonb_build_object('contratoSanver', datos -> 'contratoSanver'),
    archivos = (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(archivos) x where x ->> 'tipo' = 'CONTRATO_SANVER')
               || (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(coalesce(p_archivos, '[]'::jsonb)) x where coalesce(x ->> 'tipo','') <> 'CONTRATO_SANVER'),
    actualizado_por = auth.uid(),
    enviado_at = case when p_enviar then now() else enviado_at end,
    enviado_por = case when p_enviar then auth.uid() else enviado_por end
  where orden_id = p_orden;
  insert into bitacora (usuario_id, accion, modulo, registro_id, detalle)
  values (auth.uid(), case when p_enviar then 'TRANSPORTISTA: ENVIÓ A REVISIÓN' else 'TRANSPORTISTA: GUARDÓ AVANCE' end, 'ORDEN', o.folio,
          jsonb_build_object('archivos', jsonb_array_length(coalesce(p_archivos, '[]'::jsonb)),
                             'carta_porte_uuid', p_datos #>> '{cartaPorte,uuid}'));
  select * into e from embarques_transportista where orden_id = p_orden;
  return to_jsonb(e) - 'enviado_por' - 'revisado_por' - 'actualizado_por' - 'aprobado_por' - 'aprobacion';
end $$;

-- 4. LINEAMIENTOS DE RENTABILIDAD -----------------------------------------
create table if not exists public.lineamientos_flete (
  tipo_servicio   text primary key,            -- 'GENERAL' aplica cuando el tipo no tiene uno propio
  max_pct_flete   numeric,                     -- % máximo del flete (sin IVA) sobre el valor de la mercancía
  max_costo_ton   numeric,                     -- $ máximo por tonelada (sin IVA)
  notas           text,
  updated_at      timestamptz not null default now(),
  updated_por     uuid
);
alter table public.lineamientos_flete enable row level security;
drop policy if exists lineamientos_leer on public.lineamientos_flete;
drop policy if exists lineamientos_escribir on public.lineamientos_flete;
create policy lineamientos_leer on public.lineamientos_flete for select to authenticated using (public.es_usuario_activo());
create policy lineamientos_escribir on public.lineamientos_flete for all to authenticated
  using (public.tiene_permiso('coordinar_transporte')) with check (public.tiene_permiso('coordinar_transporte'));
insert into public.lineamientos_flete (tipo_servicio, notas) values ('GENERAL', 'Define aquí el tope general de SANVER') on conflict do nothing;

-- 5. NOTIFICACIONES EN TIEMPO REAL ---------------------------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['ordenes_servicio','embarques_transportista','bitacora'] loop
      if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- 6. RESPALDO: incluye los lineamientos ------------------------------------
-- (importar_respaldo ya acepta embarques_transportista desde el script 05)

notify pgrst, 'reload schema';
