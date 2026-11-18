# Mini ERP · Control de Fletes — versión V58 (Fernando)

## Qué hay en esta carpeta

| Archivo | Para qué |
|---|---|
| `index.html` | El portal (0.49 MB; antes 5.3 MB) |
| `data/precios-cemento.js` | Tabla de precios de cemento (se carga al abrir el portal) |
| `data/plantilla-precios.js` | Plantilla Excel de precios (solo se descarga al exportar precios) |
| `data/semilla-*.js` | Históricos de costos, subproveedores y ventas de cemento. Solo se usan **una vez**, al llenar una base nueva |
| `supabase/01_esquema.sql` | Crea todas las tablas, funciones, seguridad y el depósito de archivos en un Supabase nuevo |
| `supabase/02_primer_administrador.sql` | Prepara tu acceso de administrador |
| `supabase/03_ajustes_despues_de_restaurar.sql` | Deja como administradores solo a fernando.compras y administrador.maestro |

> Importante: sube **toda la carpeta** (index.html + data/). Si solo subes el index.html, el módulo de cemento no tendrá precios.

## Novedades V58

- **Altas rápidas desde la OC:** razón social, fletera, tipo de unidad, ubicación por parada, producto por renglón, operador, unidad de fletera y tarifa de la ruta, sin salir de la OC ni perder la captura.
- **Carga masiva en Excel** (Catálogos): plantilla, exportación de catálogos actuales y carga con vista previa (nuevos / ya existen / repetidos en archivo / errores). No se cargan duplicados.
- **Editar desde la OC:** razón social, fletera, tipo de unidad, ubicación, producto, operador, unidad y tarifa; y **proveedores de recolección** (alta/edición desde cada parada de carga, además de Agregar/Editar/Dar de baja en Catálogos y hoja propia en la plantilla de Excel).
- **Bloqueo de duplicados** también en altas manuales (RFC, nombre, clave o ruta; sin importar mayúsculas, acentos o puntos).
- **Pestaña Manual** con guía completa y glosario; los términos del portal muestran su definición al pasar el mouse con liga al glosario.

## Cambios respecto a la versión original (V56)

1. **Cancelar OC**: botón "Cancelar OC" en el histórico por etapas, con motivo obligatorio que queda en la bitácora. No se puede cancelar una OC ya liberada a pago. Las canceladas pasan a la sección "OC canceladas" y dejan de contar en el dashboard.
2. Sección **"Todas las OC activas"** para el administrador y quien tenga el permiso "Cancelar/eliminar órdenes" (antes el administrador no veía las OC de otros).
3. **Más ligero**: el portal pasa de 5.3 MB a 1.6 MB en la primera carga; los históricos de cemento ya no se descargan en cada visita.
4. **Respaldo completo** (sección Respaldo): el botón anterior no funcionaba. Ahora descarga todas las tablas y los archivos XML/PDF/evidencias.
5. **Restaurar en base nueva**: carga un respaldo en un Supabase nuevo y prepara el acceso de cada usuario.
6. **Dashboard**: se corrigió un error que impedía mostrar el resumen ejecutivo y el "Control de riesgos operativos".
7. El permiso de cemento ya no depende de nombres de usuario escritos en el código. Lo da el rol `compra_cemento` (casilla en Usuarios) o ser administrador.
8. La recarga automática cada 12 s se pausa cuando la pestaña no está visible.

## Migrar a tu propio Supabase (cuando decidas)

1. Crea un proyecto en supabase.com con tu cuenta.
2. SQL Editor → pega `01_esquema.sql` → Run.
3. Edita en `02_primer_administrador.sql` tu correo → Run.
4. En Authentication → URL Configuration, pon la dirección donde publicarás el portal (Site URL y Redirect URLs).
5. En `index.html` cambia las 2 líneas `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` por las de tu proyecto (Settings → API).
6. Publica la carpeta (por ejemplo, GitHub Pages).
7. Abre el portal → "Crear mi cuenta" con el usuario y correo del paso 3.
8. Respaldo → "Restaurar en una base nueva" → elige `Respaldo_MiniERP_2026-11-17.json`.
9. SQL Editor → pega `03_ajustes_despues_de_restaurar.sql` → Run.
10. Cada usuario entra a "Crear mi cuenta" con su **mismo usuario y correo** de siempre: recupera sus OC, permisos y firma.
