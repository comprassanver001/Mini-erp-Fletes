-- Corrección 18-nov-2026: importar_respaldo inserta fila por fila con las columnas que cada fila trae.
-- Ya incluida en 01_esquema.sql; este archivo es solo para bases creadas antes de la corrección.
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
