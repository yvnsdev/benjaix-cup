# Benjaix Cup

Plataforma responsive en HTML, CSS y JavaScript sin compilación. Código público en `dist/`; esquema de Supabase en `supabase/schema.sql`.

## Activación de la base de datos

1. En el proyecto Supabase, abre **SQL Editor** y ejecuta `supabase/schema.sql` una vez sobre un esquema vacío. No elimina tablas existentes.
2. La URL y clave pública ya están configuradas en `dist/config.js`. La clave pública puede estar en el navegador: los permisos se aplican con RLS. Nunca agregar una clave secret/service_role.
3. En **Authentication → Users**, crea las cuentas con correo y contraseña. Crea sus perfiles desde SQL Editor (reemplaza los UUID):

```sql
insert into public.profiles(id,role) values ('UUID-DEL-ADMIN','admin');
insert into public.profiles(id,role) values ('UUID-DEL-CAPITAN','captain');
```

4. Accede al panel como administrador, crea equipos y asigna el UUID de cada capitán. Después programa los partidos. El capitán puede editar su equipo, inscribir y quitar jugadores y publicar alineaciones antes del inicio.
5. Actualiza marcador, minuto y estado desde el panel administrador. Los eventos individuales (goles, amarillas y rojas) se registran por separado. El marcador oficial no se incrementa automáticamente al agregar eventos. La tabla solo suma partidos finalizados.

## Ejecutar

Sirve `dist/` con cualquier servidor HTTP estático, por ejemplo `python -m http.server 4173 --directory dist`, y abre `http://localhost:4173`. También puede desplegarse en un hosting estático. Se requiere conexión a Internet para el SDK de Supabase y las fuentes; hay fuentes alternativas del sistema.

## Datos de ejemplo

Sin configuración o si la carga inicial falla, la web muestra un modo demo claramente identificado. Los roles demo y sus datos se guardan solo en el navegador; nunca se escriben en Supabase. Al conectarse correctamente, la web usa exclusivamente los datos reales, aunque las tablas estén vacías. No hay cuentas reales predefinidas.

## Acceso y reglas

- Público: lectura de equipos, planteles, partidos, eventos y alineaciones.
- Administrador: gestión de equipos, asignación de capitanes, calendario, marcadores y eventos.
- Capitán: solo su equipo y jugadores; no puede cambiar su asignación, rol ni resultados.
- La base valida participantes, jugadores de cada alineación, dorsales únicos, valores permitidos y bloqueo de alineaciones al iniciar partidos.
- Los jugadores referenciados por eventos o alineaciones no pueden borrarse. Primero quitar de las alineaciones; conservar jugadores con historial de eventos.
- Clasificación: puntos, diferencia de gol, goles a favor y nombre para presentación provisional en empate total.
- Las bases mostradas son una propuesta, pendiente de confirmación de la organización.

## Verificación pendiente en tu proyecto

Tras ejecutar SQL, verificar con cuentas diferentes: público sin escritura; capitán A no modifica equipo B ni resultados; administrador guarda marcador; otra sesión recibe el cambio en tiempo real; alineaciones bloqueadas tras iniciar partido. La clave pública no autoriza ejecutar SQL ni crear cuentas administrativas, por lo que la instalación del esquema requiere acceso al dashboard.

Referencia: [Supabase Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes).
