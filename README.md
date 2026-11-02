# Benjaix Cup

## Eventos de lesión (017)

Ejecutar `supabase/017_injury_events.sql` después de 016. Añade “Lesión (+)” al registro administrativo de eventos y la muestra con un signo médico `+` en el minuto a minuto, sin modificar el marcador.

## Entretiempo y tanda visual (016)

Ejecutar `supabase/016_halftime_and_penalty_shootout.sql` después de 015. Añade Entretiempo (`ENT`) y una tanda pública de cinco penales por equipo. La tanda aparece únicamente cuando la fase es `PEN`; el administrador alterna cada balón entre pendiente, gol y fallo, y los goles verdes calculan automáticamente el marcador de penales.

## Marcador por goles y fases (015)

Ejecutar `supabase/015_event_score_and_match_period.sql` después de 014. Los partidos programados y en vivo pasan a calcular el marcador desde sus eventos de gol. Los resultados históricos finalizados sin eventos se conservan. La gestión del partido reemplaza el minuto general por Primer tiempo (PT), Segundo tiempo (ST), Primer/Segundo tiempo extra (ET) y Penales (PEN); el minuto exacto se mantiene en cada gol, tarjeta o cambio.

## Cambios de jugadores (014)

Ejecutar `supabase/014_match_substitutions.sql` después de 013. El administrador podrá registrar quién sale y quién entra durante un partido iniciado. Los siete titulares parten en cancha y los demás jugadores del plantel aparecen como suplentes; los cambios posteriores actualizan ambas listas y permiten reingresos. La función de base de datos valida equipo, alineación, minuto y orden cronológico.

## Administraci?n de copas (013)

Ejecutar `supabase/013_cup_management.sql` despu?s de 012 en el SQL Editor de Supabase para habilitar editar cruces y borrar copas existentes. Publicar el frontend no aplica esta migraci?n. Ambas funciones verifican el rol administrador en el servidor y realizan los cambios en una transacci?n.

En Panel ? Copas o en el reglamento de la copa, ?Editar copa? permite cambiar nombre y bases, intercambiar participantes de la primera ronda antes de cualquier actividad y borrar la copa con confirmaci?n. Cambiar un cruce retira sus alineaciones; los partidos sin cambios conservan las suyas. Borrar elimina partidos, eventos, alineaciones y votaciones asociados; conserva equipos y jugadores.


## Fútbol 7 exclusivamente

Todos los partidos son de fútbol 7: un portero y seis jugadores de campo. El editor permite únicamente 3-1-2, 3-2-1, 3-1-1-1, 2-3-1, 2-2-2 y 2-1-2-1, con exactamente siete titulares. El plantel puede tener suplentes adicionales.

Ejecutar `supabase/012_football_seven_only.sql` después de 010/011 para aplicar también la validación en Supabase. La migración no elimina ni recorta alineaciones anteriores: las incompatibles se muestran como registros pendientes de revisión, y se deben volver a asignar sus titulares antes del partido. No se modifican alineaciones históricas de partidos ya comenzados.

## Actualización 010: formaciones, bases y escudos

Si ya aplicaste 010 y subir escudos devuelve `new row violates row-level security policy`, ejecuta `supabase/011_fix_crest_storage_policies.sql`. Corrige una referencia ambigua: dentro de la consulta a equipos, `name` se interpretaba como el nombre del equipo, en lugar de la ruta del archivo. La corrección conserva RLS y los permisos de capitán/administrador; no borra escudos. No vuelvas a ejecutar 010 sobre una instalación que ya la aplicó.

Después de las migraciones 001–009, ejecutar **una vez** `supabase/010_formations_rules_crests.sql` en SQL Editor. No recrear el esquema. La publicación del frontend no ejecuta SQL ni crea el bucket automáticamente. Esta actualización conserva datos existentes y añade:

- Formaciones fijas de fútbol 7 (la actualización 012 retira los esquemas de once). El capitán asigna un jugador distinto a cada casilla; el orden se guarda en `slot_player_ids` y la cancha respeta esas posiciones.
- Edición administrativa del nombre y reglamento de cada copa, y del reglamento de liga desde el menú Reglamento. La creación de copa y sus bases es atómica mediante `create_cup_with_rules`. El tamaño y los participantes de copas existentes mantienen su historial; fecha y cancha se editan por partido.
- Bucket público `team-crests`: archivos WebP de hasta 64 KiB; escritura y eliminación solo por el capitán propietario o un administrador. El navegador reduce la imagen a 256 px por su lado mayor, mantiene la proporción/transparencia y convierte antes de enviarla. Formatos que el navegador no pueda decodificar se rechazan sin subir el original.
- URLs de escudo versionadas, caché de un año, carga diferida y eliminación del archivo anterior tras guardar el nuevo. La CDN reduce transferencias repetidas, pero no garantiza egress cero. Los originales no se almacenan. Si falla la limpieza, revisar archivos huérfanos desde Storage.
- Realtime aplica las filas recibidas en memoria y agrupa el renderizado; solo vuelve a consultar una tabla si el mensaje no contiene su clave. La carga inicial sigue siendo un snapshot público completo, paginado en bloques de 500 para evitar truncamiento. Los buscadores paginan la interfaz en seis encuentros y filtran localmente; no son paginación de servidor.
- Estadísticas en una tabla ordenable, incluidos jugadores con solo asistencias o tarjetas; eventos separados por equipo y cuadro conectado con el tercer lugar aparte.

Verificación: `node tests/check.cjs` y `python tests/upgrades_browser.py` (Playwright y Edge). La prueba de navegador usa demo y comprueba posiciones persistidas, búsquedas, edición de bases, conexiones, conversión PNG→WebP y tamaños móviles. No verifica permisos contra un Supabase real; después de aplicar SQL, probar carga de escudos con capitán propio, otro capitán, administrador y visitante.

HTML, CSS y JavaScript sin compilación. Frontend en `dist/`; Supabase con RLS, Auth y Realtime.

## Actualizar una instalación existente

Ejecuta **solo** `supabase/002_accounts_and_cups.sql` en SQL Editor. Conserva equipos y resultados y añade cuentas, membresías y copas. Ejecutar una vez; no volver a ejecutar `schema.sql` si ya está instalado.

Si el proyecto todavía no tiene tablas, ejecuta primero `supabase/schema.sql` y luego `supabase/002_accounts_and_cups.sql`.

Para las estadísticas y votaciones, ejecuta después `supabase/003_stats_and_expert.sql` y `supabase/004_live_expert.sql` una vez, en ese orden. Luego ejecuta `supabase/005_player_profiles_without_accounts.sql` y `supabase/006_fix_match_insert_policy.sql` para que los jugadores normales no necesiten cuenta y la política de partidos quede actualizada. La cuarta migración cambia las votaciones a funcionamiento automático durante el partido y conserva los votos históricos. En un proyecto vacío instala las seis migraciones en orden.

## Estadísticas y Jugador Experto Tanzy

- El administrador registra goles, asistencias, amarillas y rojas en Marcadores y eventos. Una asistencia se registra como evento independiente y se debe cargar una sola vez por pase de gol; no se infiere del marcador.
- Estadísticas ofrece rankings por goles, asistencias, goles + asistencias, amarillas y rojas; filtros por equipo y competencia. Por defecto incluye partidos finalizados; se pueden incluir los partidos en vivo como datos provisionales. Goles del marcador y goles de eventos pueden diferir si faltan eventos por cargar.
- La votación está **dentro del detalle del partido** y se abre automáticamente al marcarlo En vivo. Los candidatos son los jugadores de sus alineaciones y los jugadores que aparecen en eventos del encuentro, siempre de sus dos equipos. No se incluyen suplentes sin participación registrada ni todo el plantel. Si faltan alineaciones y eventos, se indica que aún no hay jugadores disponibles para votar.
- Cualquier visitante con acceso al sitio puede consultar los candidatos y conteos. Para votar necesita una cuenta con correo confirmado: no hace falta pertenecer a un equipo. Hay **un voto por cuenta y partido**, validado en la base de datos, y se puede cambiar mientras esté abierta. Esta regla no impide que una persona cree varias cuentas; no se presenta como protección absoluta contra fraude.
- Al marcar el partido Finalizado, se cierra automáticamente la votación y se publica al más votado. Los empates comparten premio; cero votos no proclama ganador. Si se devuelve a Programado se pausa; si vuelve a En vivo se reabre, conservando los votos. El servidor valida el estado del partido y la participación al emitir cada voto.
- La sección **Experto Tanzy del menú es una vitrina**, no una lista de votaciones abiertas: muestra los 12 partidos premiados más recientes, ordenados por fecha de cierre, con jugador, equipo, porcentaje, votos, marcador y enlace al partido. Debajo aparece el ranking acumulado de premios. Los líderes de partidos en vivo todavía no aparecen como ganadores.
- Las votaciones finalizadas de la versión anterior conservan sus candidatos y resultados como historial. Las votaciones nuevas y las que vuelven a estar en vivo usan participación registrada. Si se corrigen alineaciones/eventos, los candidatos automáticos sin participación dejan de aparecer; su voto almacenado no cuenta en los resultados visibles mientras no sean elegibles.
- Las identidades y elecciones individuales no son públicas. Cada cuenta puede leer solo su voto; los conteos públicos se actualizan con triggers y Realtime. Inserciones directas y cambios de conteos están bloqueados; se vota únicamente mediante la función validada.
- La demo incluye votos de ejemplo claramente identificados y permite probar la interacción sin cuenta. No envía votos reales ni simula usuarios reales en Supabase.

## Registro y confirmación de correo

1. En Supabase → Authentication → Providers → Email, habilita el registro por correo y **Confirm email**.
2. En Authentication → URL Configuration establece Site URL como `https://benjaix-cup-liga.equipontek.chatgpt.site` y añade `https://benjaix-cup-liga.equipontek.chatgpt.site/` a Redirect URLs. Para desarrollo, añade la URL local correspondiente.
3. Configura un proveedor SMTP para entregar confirmaciones a usuarios reales. El correo predeterminado de Supabase tiene restricciones de destinatarios y límites; configura y prueba la entrega antes de abrir inscripciones.
4. Solo los capitanes y la administración necesitan cuenta. Los jugadores normales son perfiles creados por su capitán con nombre, dorsal y posición; no reciben acceso ni necesitan registrarse. Las cuentas de capitanes reciben un enlace de confirmación y pueden reenviarlo. El perfil sin permisos administrativos se crea automáticamente con un trigger; el navegador no elige roles.
5. Crea o registra la cuenta administradora y promuévela una vez desde SQL Editor:

```sql
update public.profiles set role='admin' where id='UUID-DE-LA-CUENTA-ADMIN';
```

Si al crear un partido aparece un error de política RLS, la sesión actual no tiene
`role='admin'` en `public.profiles`. Usa el UUID de esa cuenta en el `UPDATE`
anterior y vuelve a iniciar sesión; la política de partidos permite insertar solo
a administradores y solo en la competencia cuyo `format` es `league`. Después de
actualizar instalaciones existentes, ejecuta también
`supabase/006_fix_match_insert_policy.sql`. Si ya aplicaste las migraciones
anteriores, ejecuta también `supabase/007_fix_cup_schedule_interval.sql` y
`supabase/008_allow_admin_match_edits.sql` y
`supabase/009_third_place_match.sql` para corregir la programación de fases,
permitir editar sus partidos desde administración y añadir el partido por el
tercer lugar.

La URL y clave pública ya están en `dist/config.js`. Nunca colocar claves secret/service_role en el frontend. La clave pública no permite instalar migraciones ni configurar Auth/SMTP; esas tareas requieren acceso al dashboard.

## Equipos y permisos

- Una cuenta confirmada puede crear su equipo y pasa a ser su capitán. Un equipo propio por cuenta; el administrador puede gestionar todos.
- El capitán añade jugadores con nombre, dorsal, posición y correo de una cuenta registrada y confirmada. Se crean el jugador y la membresía de forma atómica, sin permisos de gestión.
- Los correos se resuelven en el servidor y no se publican en los planteles. Las membresías solo las leen el usuario correspondiente, su capitán y la administración.
- Un jugador ve sus equipos en el panel. No puede modificar el equipo, plantel, alineación ni marcadores.
- Los permisos son **por equipo**: ser jugador de otro equipo no elimina la gestión de un equipo propio. Registrarse no concede permisos globales de capitán.
- El capitán publica exactamente 7 titulares antes del partido. La base bloquea cambios al comenzar. No puede cambiar su rol, asignación ni resultados.
- Para quitar un jugador usa Quitar. Los jugadores con eventos se conservan por su historial; si están en alineaciones, hay que retirarlos de ellas primero.

## Liga y copas

- En el inicio, **La carrera por la copa** muestra solo los cruces de la primera fase que aún tenga partidos sin finalizar: cuartos, semifinales o final. No salta de fase por terminar un solo cruce. Al completar la copa muestra la final y el campeón. Si hay varias copas, se puede elegir; la tabla de liga aparece separada debajo.

- **Liga:** tabla calculada solo con partidos de liga finalizados. Victoria 3 puntos, empate 1. Desempates por diferencia de gol y goles a favor; nombre para presentar un orden provisional en igualdad total.
- **Copa:** el administrador selecciona 4, 8 o 16 equipos. El orden mostrado define los cruces iniciales. Cada ronda se programa 7 días después de la anterior; fecha y cancha se editan desde Marcadores y eventos.
- Al finalizar un partido de copa, su ganador avanza automáticamente en una transacción. Un empate necesita un marcador de penales con ganador. El campeón se destaca en el cuadro.
- El partido por el tercer lugar lo juegan los dos perdedores de semifinales. Los dos ganadores de semifinales juegan exclusivamente la final.
- Para corregir un ganador, la siguiente fase debe estar programada y sin eventos. Se limpian su resultado y sus alineaciones. Si empezó, hay que reabrirla primero, desde la última fase afectada.
- Marcador y eventos se registran por separado: los eventos alimentan goleadores y tarjetas, pero no incrementan el resultado oficial.
- Realtime actualiza las vistas públicas. Los formularios enfocados se conservan durante una actualización.

## Diseño y ejecución

Iconos SVG locales, transiciones suaves y soporte `prefers-reduced-motion`. Cuadro desplazable horizontalmente en móvil.

Sirve `dist/` con un servidor estático: `python -m http.server 4173 --directory dist`. Supabase y las fuentes necesitan Internet; hay fuentes alternativas del sistema.

Si falta el esquema o falla la carga inicial, se muestra una demo identificada sin escribir en Supabase. Los roles demo son locales. El registro real se habilita al conectar las tablas actualizadas.

Sites conserva su acceso privado original. Para recibir visitantes externos debe configurarse el acceso del alojamiento: registrarse en Supabase no elimina esa restricción.

## Pruebas

- `node tests/check.cjs`: clasificación, aislamiento liga/copa, penales, avance, bloqueos y vistas por rol.
- `python tests/browser.py`: requiere Playwright en `.qa/` y Microsoft Edge. Prueba navegación, SVG, registro, paneles por rol, avance del cuadro, escritorio y móvil. Usa demo, no crea usuarios reales.
- En producción faltan la migración y las verificaciones de entrega/confirmación de correo, permisos con cuentas reales y sincronización entre sesiones.

Referencias oficiales: [registro](https://supabase.com/docs/reference/javascript/auth-signup), [reenvío](https://supabase.com/docs/reference/javascript/auth-resend), [correo y contraseñas](https://supabase.com/docs/guides/auth/passwords), [Realtime](https://supabase.com/docs/guides/realtime/postgres-changes).
