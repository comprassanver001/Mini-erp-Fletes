-- =====================================================================
-- Mini ERP · Control de Fletes — V60
-- Portal del transportista y Coordinador de Transporte
--   * Usuarios de tipo TRANSPORTISTA ligados a una fletera: solo ven sus viajes
--     (a través de funciones) y cargan su información de embarque.
--   * Permiso nuevo COORDINAR_TRANSPORTE: revisa el checklist, autoriza y libera
--     el embarque (reemplaza la autorización del flete) o lo devuelve.
-- Se puede ejecutar más de una vez.
-- =====================================================================

-- 1. COLUMNAS NUEVAS ---------------------------------------------------
alter table public.perfiles           add column if not exists fletera_id uuid references public.fleteras(id) on delete set null;
alter table public.accesos_pendientes add column if not exists fletera_id uuid references public.fleteras(id) on delete set null;
alter table public.permisos_usuario   add column if not exists coordinar_transporte boolean not null default false;
alter table public.accesos_pendientes add column if not exists coordinar_transporte boolean not null default false;

-- 2. FUNCIONES DE PERMISOS ---------------------------------------------
-- Un transportista es un perfil con el rol 'transportista' y una fletera asignada.
create or replace function public.es_transportista() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo and fletera_id is not null
                   and 'transportista' = any (regexp_split_to_array(lower(coalesce(rol,'')), '[|,; ]+')))
$$;

create or replace function public.mi_fletera() returns uuid
language sql stable security definer set search_path = public as $$
  select fletera_id from perfiles where id = auth.uid() and activo and fletera_id is not null
     and 'transportista' = any (regexp_split_to_array(lower(coalesce(rol,'')), '[|,; ]+'))
$$;

-- Usuario interno activo: los transportistas NO cuentan como usuarios internos,
-- así que todas las políticas existentes les niegan el acceso a las tablas.
create or replace function public.es_usuario_activo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo
                   and not ('transportista' = any (regexp_split_to_array(lower(coalesce(rol,'')), '[|,; ]+'))))
$$;

create or replace function public.tiene_permiso(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select coalesce((to_jsonb(pu) ->> p)::boolean, false) or pu.administrar_usuarios
    from permisos_usuario pu join perfiles pf on pf.id = pu.usuario_id
    where pu.usuario_id = auth.uid() and pf.activo
      and not ('transportista' = any (regexp_split_to_array(lower(coalesce(pf.rol,'')), '[|,; ]+')))
  ), false)
$$;

create or replace function public.orden_de_mi_fletera(p_orden text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from ordenes_servicio o
                 where o.id::text = p_orden and o.fletera_id is not null and o.fletera_id = public.mi_fletera())
$$;

-- 3. EXPEDIENTE DEL EMBARQUE (lo que carga el transportista) -------------
create table if not exists public.embarques_transportista (
  orden_id       uuid primary key references public.ordenes_servicio(id) on delete cascade,
  estado         text not null default 'EN_CAPTURA'
                 check (estado in ('EN_CAPTURA','ENVIADO','DEVUELTO','LIBERADO')),
  datos          jsonb not null default '{}'::jsonb,   -- unidad, operador, gps, póliza, contrato, carta porte (resultado de validación)
  archivos       jsonb not null default '[]'::jsonb,   -- [{tipo, path, nombre, at}]
  nota_revision  text,
  enviado_at     timestamptz,
  enviado_por    uuid,
  revisado_at    timestamptz,
  revisado_por   uuid,
  actualizado_por uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
drop trigger if exists t_upd_embarques on public.embarques_transportista;
create trigger t_upd_embarques before update on public.embarques_transportista
  for each row execute function public.tocar_updated_at();

-- Solo el coordinador puede liberar o devolver un embarque.
create or replace function public.validar_estado_embarque() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.estado in ('LIBERADO','DEVUELTO')
     and (tg_op = 'INSERT' or new.estado is distinct from old.estado)
     and auth.uid() is not null and not public.tiene_permiso('coordinar_transporte') then
    raise exception 'Solo el Coordinador de Transporte puede liberar o devolver un embarque';
  end if;
  return new;
end $$;
drop trigger if exists t_estado_embarque on public.embarques_transportista;
create trigger t_estado_embarque before insert or update on public.embarques_transportista
  for each row execute function public.validar_estado_embarque();

alter table public.embarques_transportista enable row level security;
drop policy if exists embarques_leer   on public.embarques_transportista;
drop policy if exists embarques_alta   on public.embarques_transportista;
drop policy if exists embarques_cambio on public.embarques_transportista;
-- Internos leen y capturan (el comprador puede capturar en nombre del transportista).
-- El transportista NO escribe directo: usa transportista_guardar().
create policy embarques_leer on public.embarques_transportista for select to authenticated
  using (public.es_usuario_activo() or public.orden_de_mi_fletera(orden_id::text));
create policy embarques_alta on public.embarques_transportista for insert to authenticated
  with check (public.es_usuario_activo());
create policy embarques_cambio on public.embarques_transportista for update to authenticated
  using (public.es_usuario_activo()) with check (public.es_usuario_activo());

-- 4. EL COORDINADOR AUTORIZA LA OC Y REGISTRA EL XML VALIDADO ------------
drop policy if exists ordenes_cambio on public.ordenes_servicio;
create policy ordenes_cambio on public.ordenes_servicio for update to authenticated
  using (public.es_usuario_activo() and (
        solicitante_id = auth.uid() or autorizador_asignado_id = auth.uid()
     or public.tiene_permiso('editar_oc') or public.tiene_permiso('eliminar_oc') or public.tiene_permiso('autorizar_oc')
     or public.tiene_permiso('ver_xml') or public.tiene_permiso('validar_xml') or public.tiene_permiso('registrar_pagos')
     or public.tiene_permiso('coordinar_transporte')))
  with check (public.es_usuario_activo());

drop policy if exists facturas_alta   on public.facturas_xml;
drop policy if exists facturas_cambio on public.facturas_xml;
create policy facturas_alta   on public.facturas_xml for insert to authenticated
  with check (public.tiene_permiso('ver_xml') or public.tiene_permiso('validar_xml') or public.tiene_permiso('coordinar_transporte'));
create policy facturas_cambio on public.facturas_xml for update to authenticated
  using (public.tiene_permiso('ver_xml') or public.tiene_permiso('validar_xml') or public.tiene_permiso('coordinar_transporte'))
  with check (public.tiene_permiso('ver_xml') or public.tiene_permiso('validar_xml') or public.tiene_permiso('coordinar_transporte'));

-- 5. ARCHIVOS DEL TRANSPORTISTA: embarques/<orden_id>/... ----------------
drop policy if exists embarques_docs_leer  on storage.objects;
drop policy if exists embarques_docs_subir on storage.objects;
create policy embarques_docs_leer on storage.objects for select to authenticated
  using (bucket_id = 'erp-fletes-documentos' and (storage.foldername(name))[1] = 'embarques'
         and public.orden_de_mi_fletera((storage.foldername(name))[2]));
create policy embarques_docs_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'erp-fletes-documentos' and (storage.foldername(name))[1] = 'embarques'
              and public.orden_de_mi_fletera((storage.foldername(name))[2]));

-- 6. FUNCIONES DEL PORTAL DEL TRANSPORTISTA -------------------------------
-- Sus viajes (solo de su fletera, sin firmas ni datos internos de costos).
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
        'embarque', (select to_jsonb(et) - 'enviado_por' - 'revisado_por' - 'actualizado_por'
                     from embarques_transportista et where et.orden_id = o.id)
      ) order by o.created_at desc)
      from ordenes_servicio o
      where o.fletera_id = f and o.estatus <> 'CANCELADO'), '[]'::jsonb));
end $$;

-- Guarda (y opcionalmente envía a revisión) la información del embarque.
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
  if e.estado in ('ENVIADO','LIBERADO') then raise exception 'La información ya está en revisión del Coordinador de Transporte'; end if;
  if jsonb_typeof(coalesce(p_datos, '{}'::jsonb)) <> 'object' or jsonb_typeof(coalesce(p_archivos, '[]'::jsonb)) <> 'array' then
    raise exception 'Formato inválido'; end if;
  for a in select * from jsonb_array_elements(coalesce(p_archivos, '[]'::jsonb)) loop
    if coalesce(a ->> 'path', '') not like 'embarques/' || p_orden::text || '/%' then raise exception 'Archivo fuera del viaje'; end if;
  end loop;
  insert into embarques_transportista (orden_id, estado, datos, archivos, actualizado_por, enviado_at, enviado_por)
  values (p_orden, case when p_enviar then 'ENVIADO' else 'EN_CAPTURA' end, coalesce(p_datos, '{}'::jsonb), coalesce(p_archivos, '[]'::jsonb),
          auth.uid(), case when p_enviar then now() end, case when p_enviar then auth.uid() end)
  on conflict (orden_id) do update set
    estado = case when p_enviar then 'ENVIADO' else embarques_transportista.estado end,
    datos = excluded.datos, archivos = excluded.archivos, actualizado_por = auth.uid(),
    enviado_at = case when p_enviar then now() else embarques_transportista.enviado_at end,
    enviado_por = case when p_enviar then auth.uid() else embarques_transportista.enviado_por end;
  insert into bitacora (usuario_id, accion, modulo, registro_id, detalle)
  values (auth.uid(), case when p_enviar then 'TRANSPORTISTA: ENVIÓ A REVISIÓN' else 'TRANSPORTISTA: GUARDÓ AVANCE' end, 'ORDEN', o.folio,
          jsonb_build_object('archivos', jsonb_array_length(coalesce(p_archivos, '[]'::jsonb)),
                             'carta_porte_uuid', p_datos #>> '{cartaPorte,uuid}'));
  select * into e from embarques_transportista where orden_id = p_orden;
  return to_jsonb(e) - 'enviado_por' - 'revisado_por' - 'actualizado_por';
end $$;

revoke execute on function public.transportista_mis_viajes() from public, anon;
revoke execute on function public.transportista_guardar(uuid, jsonb, jsonb, boolean) from public, anon;
grant execute on function public.transportista_mis_viajes() to authenticated;
grant execute on function public.transportista_guardar(uuid, jsonb, jsonb, boolean) to authenticated;

-- 7. ALTA DE CUENTAS: copia fletera y permiso de coordinador ---------------
create or replace function public.crear_perfil_desde_acceso() returns trigger
language plpgsql security definer set search_path = public as $$
declare a accesos_pendientes;
begin
  select * into a from accesos_pendientes
   where lower(email) = lower(new.email) and activo and not consumido
   limit 1;
  if a.id is null then return new; end if;
  insert into perfiles (id, nombre_completo, puesto, rol, activo, autorizador_id, firma_url, email, usuario, fletera_id)
  values (new.id, a.nombre_completo, a.puesto, coalesce(a.rol, 'usuario'), true, a.autorizador_id, a.firma_url,
          lower(new.email), lower(coalesce(a.usuario, new.raw_user_meta_data ->> 'usuario')), a.fletera_id)
  on conflict (id) do nothing;
  insert into permisos_usuario (usuario_id, crear_oc, ver_oc, editar_oc, eliminar_oc, autorizar_oc, ver_xml, validar_xml,
                                ver_pagos, registrar_pagos, ver_catalogos, editar_catalogos, ver_dashboard, administrar_usuarios, coordinar_transporte)
  values (new.id, a.crear_oc, a.ver_oc, a.editar_oc, a.eliminar_oc, a.autorizar_oc, a.ver_xml, a.validar_xml,
          a.ver_pagos, a.registrar_pagos, a.ver_catalogos, a.editar_catalogos, a.ver_dashboard, a.administrar_usuarios, a.coordinar_transporte)
  on conflict (usuario_id) do nothing;
  update accesos_pendientes set consumido = true where id = a.id;
  if a.perfil_anterior_id is not null then perform public.reasignar_usuario(a.perfil_anterior_id, new.id); end if;
  return new;
end $$;

-- 8. RESPALDO: el expediente del embarque también se puede restaurar
create or replace function public.importar_respaldo(p_tabla text, p_filas jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer := 0; k integer; cols text; todas text[]; r jsonb;
begin
  if not public.es_admin() then raise exception 'Solo el administrador puede importar respaldos'; end if;
  if p_tabla not in ('empresas_receptoras','fleteras','ubicaciones','productos_frecuentes','tipos_unidad','tarifas',
                     'distancias_ruta','ordenes_servicio','puntos_orden','mercancias_orden','facturas_xml',
                     'evidencias_entrega','bitacora','accesos_pendientes','embarques_transportista') then
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

notify pgrst, 'reload schema';
