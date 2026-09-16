# UrabáPort Match

## 1. ¿Qué es UrabáPort Match?
UrabáPort Match es una plataforma de consolidación de fletes y capacidad de carga fraccionada para el Golfo de Urabá. Conecta a transportadores y patrones de embarcaciones (que tienen capacidad ociosa) con comerciantes que necesitan transportar mercancías. El objetivo es maximizar la ocupación de las embarcaciones, reducir costos (flete compartido) y dinamizar la economía local.

## 2. Arquitectura
La arquitectura sigue un enfoque **Backend-as-a-Service (BaaS)** muy adecuado para MVP rápidos y escalables:
- **Frontend**: React (o Next.js) que consumirá los servicios.
- **Backend/Base de Datos**: Supabase (PostgreSQL).
- **Lógica de Negocio**: Implementada a través de Funciones RPC (Remote Procedure Calls) de PostgreSQL y Triggers.
- **Seguridad**: Row Level Security (RLS) en la base de datos y Supabase Auth para la gestión de identidades.

Flujo: `React -> Supabase Client -> Supabase Auth -> PostgreSQL + RLS + RPC`

## 3. Tecnologías
- **Base de Datos**: PostgreSQL (Supabase)
- **Autenticación**: Supabase Auth
- **Lógica**: PL/pgSQL (Migraciones y Funciones)
- **Pruebas**: pgTAP o scripts de prueba en Node.js (Jest) contra el entorno local de Supabase.

## 4. Modelo de Datos
Las entidades principales son:
- **users / profiles**: Usuarios del sistema y sus roles.
- **locations**: Orígenes y destinos (Apartadó, Zungo, Capurganá, etc.)
- **trips (viajes)**: Itinerarios publicados por los transportadores con capacidad y tarifas.
- **reservations (reservas)**: Solicitudes de los comerciantes para ocupar capacidad en un viaje.
- **audit_logs**: Registro de acciones críticas para trazabilidad.
*(Ver `backend/docs/database.md` para detalles de relaciones y campos)*

## 5. Roles
1. **COMERCIANTE**: Busca viajes, cotiza y reserva capacidad.
2. **TRANSPORTADOR**: Publica viajes, visualiza el manifiesto consolidado y confirma recepción de mercancía.
3. **ADMIN**: Monitorea métricas (ahorro, ocupación, rutas demandadas) en el dashboard.

## 6. Flujo de una Reserva
1. El **Transportador** publica un viaje (`trips`) con capacidad disponible (kg/m3) y fecha límite.
2. El **Comerciante** busca viajes activos y simula el costo de enviar `X` kg.
3. El **Comerciante** confirma la reserva.
4. El sistema (mediante RPC atómico) descuenta la capacidad disponible del viaje y registra la reserva.
5. Si la capacidad llega a 0, el viaje pasa a estado `CUPO_COMPLETO`.
6. Al zarpe, el transportador valida el manifiesto y confirma recepción de la carga.

## 7. Cómo ejecutar Supabase localmente
Requisitos: [Supabase CLI](https://supabase.com/docs/guides/cli) y Docker instalados.
1. Navega a la carpeta del backend: `cd backend`
2. Inicia los contenedores: `supabase start`
3. Supabase Studio estará disponible en `http://localhost:54323`

## 8. Cómo ejecutar migraciones
Las migraciones definen el esquema y están en `backend/supabase/migrations/`.
Se aplican automáticamente al hacer `supabase start`. 
Si creas una migración nueva, aplícala con:
```bash
cd backend
supabase db reset
```

## 9. Cómo cargar datos semilla (Seed)
Los datos de demostración están en `backend/supabase/seed.sql`.
Se insertan automáticamente tras las migraciones al ejecutar `supabase start` o `supabase db reset`.

## 10. Variables de Entorno
Crea un archivo `.env` en tu frontend (o donde consumas la API) basándote en el `.env.example`:
```env
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=tu_anon_key_aqui
```
*(Nota: Nunca subas el archivo `.env` con secretos reales al repositorio)*

## 11. Cómo ejecutar pruebas
Para correr las pruebas de la lógica de base de datos (descuentos atómicos, validaciones de capacidad):
```bash
cd backend
npm test 
# (o el comando configurado según el runner de tests que uses, ej: jest tests/)
```

## 12. RPC Disponibles (Remote Procedure Calls)
- `create_reservation(viaje_id, peso_kg, ...)`: Transacción atómica que valida, descuenta capacidad y crea la reserva.
- `search_trips(...)`: Buscador filtrado.
- `calculate_reservation_cost(...)`: Simulación de costos.
- `get_trip_manifest(...)`: Obtiene el manifiesto para el transportador.
- `get_dashboard_metrics()`: Métricas para admin.

## 13. Políticas RLS (Row Level Security)
- **trips**: Visibles por todos si están `PROGRAMADO/ABIERTO`. Solo modificables por su `transportador_id`.
- **reservations**: Comerciantes ven las suyas, Transportadores ven las de sus viajes.
*(La seguridad recae en la DB, un usuario no puede manipular IDs para ver/modificar datos ajenos).*

## 14. Cómo conectar React con Supabase
Instala el cliente de supabase en tu proyecto frontend:
```bash
npm install @supabase/supabase-js
```
Inicialízalo:
```javascript
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
```
Y consúmelo:
```javascript
const { data, error } = await supabase.from('trips').select('*')
```
