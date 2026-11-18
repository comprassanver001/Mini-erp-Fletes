-- =====================================================================
-- PRIMER ADMINISTRADOR · ejecútalo DESPUÉS de 01_esquema.sql
-- 1) Cambia el correo y el usuario por los tuyos.
-- 2) Run.
-- 3) Abre el portal → "Crear mi cuenta" → captura ese mismo usuario y
--    correo, y elige tu contraseña. Entrarás como administrador.
-- =====================================================================
insert into public.accesos_pendientes
  (email, usuario, nombre_completo, puesto, rol,
   crear_oc, ver_oc, editar_oc, eliminar_oc, autorizar_oc, ver_xml, validar_xml,
   ver_pagos, registrar_pagos, ver_catalogos, editar_catalogos, ver_dashboard, administrar_usuarios)
values
  ('TU_CORREO@sanver.com.mx', 'administrador', 'Fernando Treviño Reséndez', 'Jefe de Compras', 'administrador|compra_cemento',
   true, true, true, true, true, true, true,
   true, true, true, true, true, true);
