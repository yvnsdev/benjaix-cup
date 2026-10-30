# Benjaix Cup

HTML, CSS y JavaScript sin compilación. Frontend en `dist/`; Supabase con RLS, Auth y Realtime.

## Actualizar una instalación existente

Ejecuta **solo** `supabase/002_accounts_and_cups.sql` en SQL Editor. Conserva equipos y resultados y añade cuentas, membresías y copas. Ejecutar una vez; no volver a ejecutar `schema.sql` si ya está instalado.

Si el proyecto todavía no tiene tablas, ejecuta primero `supabase/schema.sql` y luego `supabase/002_accounts_and_cups.sql`.

## Registro y confirmación de correo

1. En Supabase → Authentication → Providers → Email, habilita el registro por correo y **Confirm email**.
2. En Authentication → URL Configuration establece Site URL como `https://benjaix-cup-liga.equipontek.chatgpt.site` y añade `https://benjaix-cup-liga.equipontek.chatgpt.site/` a Redirect URLs. Para desarrollo, añade la URL local correspondiente.
3. Configura un proveedor SMTP para entregar confirmaciones a usuarios reales. El correo predeterminado de Supabase tiene restricciones de destinatarios y límites; configura y prueba la entrega antes de abrir inscripciones.
4. Las personas se registran desde la web, reciben el enlace de confirmación e ingresan. Pueden reenviar la confirmación. El perfil sin permisos administrativos se crea automáticamente con un trigger; el navegador no elige roles.
5. Crea o registra la cuenta administradora y promuévela una vez desde SQL Editor:

```sql
update public.profiles set role='admin' where id='UUID-DE-LA-CUENTA-ADMIN';
```

La URL y clave pública ya están en `dist/config.js`. Nunca colocar claves secret/service_role en el frontend. La clave pública no permite instalar migraciones ni configurar Auth/SMTP; esas tareas requieren acceso al dashboard.

## Equipos y permisos

- Una cuenta confirmada puede crear su equipo y pasa a ser su capitán. Un equipo propio por cuenta; el administrador puede gestionar todos.
- El capitán añade jugadores con nombre, dorsal, posición y correo de una cuenta registrada y confirmada. Se crean el jugador y la membresía de forma atómica, sin permisos de gestión.
- Los correos se resuelven en el servidor y no se publican en los planteles. Las membresías solo las leen el usuario correspondiente, su capitán y la administración.
- Un jugador ve sus equipos en el panel. No puede modificar el equipo, plantel, alineación ni marcadores.
- Los permisos son **por equipo**: ser jugador de otro equipo no elimina la gestión de un equipo propio. Registrarse no concede permisos globales de capitán.
- El capitán publica de 1 a 11 titulares antes del partido. La base bloquea cambios al comenzar. No puede cambiar su rol, asignación ni resultados.
- Para quitar un jugador usa Quitar. Los jugadores con eventos se conservan por su historial; si están en alineaciones, hay que retirarlos de ellas primero.

## Liga y copas

- **Liga:** tabla calculada solo con partidos de liga finalizados. Victoria 3 puntos, empate 1. Desempates por diferencia de gol y goles a favor; nombre para presentar un orden provisional en igualdad total.
- **Copa:** el administrador selecciona 4, 8 o 16 equipos. El orden mostrado define los cruces iniciales. Cada ronda se programa 7 días después de la anterior; fecha y cancha se editan desde Marcadores y eventos.
- Al finalizar un partido de copa, su ganador avanza automáticamente en una transacción. Un empate necesita un marcador de penales con ganador. El campeón se destaca en el cuadro.
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
