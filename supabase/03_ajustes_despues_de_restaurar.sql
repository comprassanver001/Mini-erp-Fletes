-- =====================================================================
-- AJUSTES DESPUÉS DE RESTAURAR EL RESPALDO · ejecutar una vez
-- Decisión 18-nov-2026: el único administrador es fernando.compras.
-- administrador.maestro (ligado al correo personal de la desarrolladora
-- anterior) queda dado de baja.
-- =====================================================================
update public.accesos_pendientes
   set administrar_usuarios = false
 where lower(usuario) in ('rmg', 'karla');

update public.accesos_pendientes
   set activo = false, administrar_usuarios = false
 where lower(usuario) = 'administrador.maestro';

-- Por si alguno ya activó su cuenta antes de correr este ajuste:
update public.permisos_usuario pu
   set administrar_usuarios = false
  from public.perfiles p
 where p.id = pu.usuario_id and lower(p.usuario) in ('rmg', 'karla');

update public.perfiles set rol = 'usuario'
 where lower(usuario) in ('rmg', 'karla') and rol = 'administrador';

-- Verificación: quién queda como administrador
select 'acceso preparado' origen, usuario from public.accesos_pendientes where administrar_usuarios
union all
select 'cuenta activa', p.usuario from public.permisos_usuario pu join public.perfiles p on p.id = pu.usuario_id where pu.administrar_usuarios;
