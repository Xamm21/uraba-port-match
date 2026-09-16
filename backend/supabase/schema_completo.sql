-- 001_extensions.sql
-- Habilitar extensión para UUIDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Extensiones útiles para funciones
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
-- 002_profiles.sql

-- Enum para roles de usuario
CREATE TYPE user_role AS ENUM ('COMERCIANTE', 'TRANSPORTADOR', 'ADMIN');

CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    nombre TEXT NOT NULL,
    telefono TEXT,
    documento TEXT,
    rol user_role NOT NULL DEFAULT 'COMERCIANTE',
    activo BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Habilitar RLS en profiles (las politicas las agregaremos en un archivo posterior)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
-- 003_locations.sql

CREATE TABLE locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre TEXT NOT NULL,
    tipo TEXT, -- ej: 'puerto', 'muelle', 'ciudad'
    municipio TEXT,
    descripcion TEXT,
    activo BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indices básicos para busqueda por nombre o municipio
CREATE INDEX idx_locations_nombre ON locations(nombre);
CREATE INDEX idx_locations_municipio ON locations(municipio);

ALTER TABLE locations ENABLE ROW LEVEL SECURITY;
-- 004_trips.sql

CREATE TYPE trip_status AS ENUM (
    'PROGRAMADO',
    'ABIERTO',
    'CUPO_COMPLETO',
    'CERRADO',
    'EN_CURSO',
    'FINALIZADO',
    'CANCELADO'
);

CREATE TABLE trips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transportador_id UUID NOT NULL REFERENCES profiles(id),
    origen_id UUID NOT NULL REFERENCES locations(id),
    destino_id UUID NOT NULL REFERENCES locations(id),
    fecha_zarpe TIMESTAMPTZ NOT NULL,
    hora_limite_recepcion TIMESTAMPTZ NOT NULL,
    
    capacidad_total_kg NUMERIC NOT NULL CHECK (capacidad_total_kg > 0),
    capacidad_disponible_kg NUMERIC NOT NULL CHECK (capacidad_disponible_kg >= 0),
    
    capacidad_total_m3 NUMERIC CHECK (capacidad_total_m3 >= 0),
    capacidad_disponible_m3 NUMERIC CHECK (capacidad_disponible_m3 >= 0),
    
    tarifa_por_kg NUMERIC NOT NULL CHECK (tarifa_por_kg >= 0),
    estado trip_status NOT NULL DEFAULT 'PROGRAMADO',
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    CONSTRAINT check_capacidad_disponible CHECK (capacidad_disponible_kg <= capacidad_total_kg),
    CONSTRAINT check_fechas CHECK (hora_limite_recepcion <= fecha_zarpe),
    CONSTRAINT check_origen_destino CHECK (origen_id != destino_id)
);

-- Indices para buscar viajes rápidamente
CREATE INDEX idx_trips_origen_destino ON trips(origen_id, destino_id);
CREATE INDEX idx_trips_fecha_zarpe ON trips(fecha_zarpe);
CREATE INDEX idx_trips_estado ON trips(estado);
CREATE INDEX idx_trips_transportador ON trips(transportador_id);

ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
-- 005_reservations.sql

CREATE TYPE reservation_status AS ENUM (
    'PENDIENTE',
    'CONFIRMADA',
    'CANCELADA',
    'RECIBIDA',
    'ENTREGADA'
);

CREATE TABLE reservations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    viaje_id UUID NOT NULL REFERENCES trips(id),
    comerciante_id UUID NOT NULL REFERENCES profiles(id),
    
    peso_kg NUMERIC NOT NULL CHECK (peso_kg > 0),
    volumen_m3 NUMERIC CHECK (volumen_m3 >= 0),
    
    tipo_paquete TEXT,
    descripcion_carga TEXT,
    
    costo_total_cop NUMERIC NOT NULL CHECK (costo_total_cop >= 0),
    ahorro_estimado_cop NUMERIC NOT NULL DEFAULT 0,
    
    estado reservation_status NOT NULL DEFAULT 'PENDIENTE',
    fecha_reserva TIMESTAMPTZ NOT NULL DEFAULT now(),
    fecha_cancelacion TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indices
CREATE INDEX idx_reservations_viaje ON reservations(viaje_id);
CREATE INDEX idx_reservations_comerciante ON reservations(comerciante_id);
CREATE INDEX idx_reservations_estado ON reservations(estado);

ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;
-- 006_settings.sql

CREATE TABLE system_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Insertar configuración inicial para la tarifa tradicional base por kg 
-- (para poder calcular el ahorro en el flete compartido)
INSERT INTO system_settings (key, value, description)
VALUES ('tarifa_tradicional_base_kg', '1500', 'Tarifa en COP por KG de un envío expreso tradicional (usado para calcular ahorros)');

ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;
-- 007_audit.sql

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity TEXT NOT NULL,
    entity_id UUID NOT NULL,
    old_data JSONB,
    new_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_entity ON audit_logs(entity, entity_id);

ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
-- 008_functions_reservations.sql

-- Función para calcular el costo de la reserva
CREATE OR REPLACE FUNCTION calculate_reservation_cost(p_peso_kg NUMERIC, p_tarifa_por_kg NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN p_peso_kg * p_tarifa_por_kg;
END;
$$ LANGUAGE plpgsql;

-- Función atómica para crear una reserva
CREATE OR REPLACE FUNCTION create_reservation(
    p_viaje_id UUID,
    p_peso_kg NUMERIC,
    p_tipo_paquete TEXT DEFAULT NULL,
    p_descripcion_carga TEXT DEFAULT NULL,
    p_volumen_m3 NUMERIC DEFAULT 0
) RETURNS UUID AS $$
DECLARE
    v_comerciante_id UUID;
    v_rol user_role;
    v_viaje trips%ROWTYPE;
    v_costo NUMERIC;
    v_tarifa_base NUMERIC;
    v_ahorro NUMERIC;
    v_reserva_id UUID;
BEGIN
    -- 1. Validar usuario y rol
    v_comerciante_id := auth.uid();
    IF v_comerciante_id IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    SELECT rol INTO v_rol FROM profiles WHERE id = v_comerciante_id;
    IF v_rol != 'COMERCIANTE' THEN
        RAISE EXCEPTION 'Solo los comerciantes pueden crear reservas';
    END IF;

    -- 2. Validar peso
    IF p_peso_kg <= 0 THEN
        RAISE EXCEPTION 'El peso debe ser mayor a 0';
    END IF;

    -- 3. Bloquear la fila del viaje para evitar race conditions y sobreventas (ATÓMICO)
    SELECT * INTO v_viaje FROM trips WHERE id = p_viaje_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Viaje no encontrado';
    END IF;

    -- 4. Validar estado y fecha límite
    IF v_viaje.estado != 'PROGRAMADO' AND v_viaje.estado != 'ABIERTO' THEN
        RAISE EXCEPTION 'El viaje no está disponible para reservas';
    END IF;

    IF now() > v_viaje.hora_limite_recepcion THEN
        RAISE EXCEPTION 'Se ha superado la hora límite para reservar en este viaje';
    END IF;

    -- 5. Verificar capacidad suficiente
    IF p_peso_kg > v_viaje.capacidad_disponible_kg THEN
        RAISE EXCEPTION 'No hay suficiente capacidad disponible. Solicitado: %, Disponible: %', p_peso_kg, v_viaje.capacidad_disponible_kg;
    END IF;

    -- 6. Calcular costo y ahorro
    v_costo := calculate_reservation_cost(p_peso_kg, v_viaje.tarifa_por_kg);
    
    SELECT (value->>0)::NUMERIC INTO v_tarifa_base FROM system_settings WHERE key = 'tarifa_tradicional_base_kg';
    IF v_tarifa_base IS NULL THEN v_tarifa_base := 1500; END IF; -- fallback
    
    v_ahorro := (p_peso_kg * v_tarifa_base) - v_costo;
    IF v_ahorro < 0 THEN v_ahorro := 0; END IF;

    -- 7. Actualizar capacidad disponible en el viaje
    UPDATE trips 
    SET capacidad_disponible_kg = capacidad_disponible_kg - p_peso_kg,
        capacidad_disponible_m3 = GREATEST(0, capacidad_disponible_m3 - p_volumen_m3),
        estado = CASE WHEN (capacidad_disponible_kg - p_peso_kg) <= 0 THEN 'CUPO_COMPLETO'::trip_status ELSE estado END
    WHERE id = p_viaje_id;

    -- 8. Crear reserva
    INSERT INTO reservations (
        viaje_id, comerciante_id, peso_kg, volumen_m3, 
        tipo_paquete, descripcion_carga, costo_total_cop, ahorro_estimado_cop
    ) VALUES (
        p_viaje_id, v_comerciante_id, p_peso_kg, p_volumen_m3,
        p_tipo_paquete, p_descripcion_carga, v_costo, v_ahorro
    ) RETURNING id INTO v_reserva_id;

    RETURN v_reserva_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Función atómica para cancelar reserva y devolver cupo
CREATE OR REPLACE FUNCTION cancel_reservation(p_reserva_id UUID) RETURNS BOOLEAN AS $$
DECLARE
    v_reserva reservations%ROWTYPE;
    v_viaje trips%ROWTYPE;
    v_user_id UUID;
    v_rol user_role;
BEGIN
    v_user_id := auth.uid();
    
    -- Bloquear reserva
    SELECT * INTO v_reserva FROM reservations WHERE id = p_reserva_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reserva no encontrada'; END IF;
    
    IF v_reserva.estado = 'CANCELADA' THEN
        RAISE EXCEPTION 'La reserva ya estaba cancelada';
    END IF;
    
    -- Validar propiedad de la reserva o si es ADMIN
    SELECT rol INTO v_rol FROM profiles WHERE id = v_user_id;
    IF v_reserva.comerciante_id != v_user_id AND v_rol != 'ADMIN' THEN
        RAISE EXCEPTION 'No tienes permisos para cancelar esta reserva';
    END IF;

    -- Bloquear viaje
    SELECT * INTO v_viaje FROM trips WHERE id = v_reserva.viaje_id FOR UPDATE;
    
    IF v_viaje.estado IN ('EN_CURSO', 'FINALIZADO', 'CANCELADO') THEN
         RAISE EXCEPTION 'No se puede cancelar una reserva de un viaje en curso o finalizado';
    END IF;

    -- Devolver capacidad
    UPDATE trips 
    SET capacidad_disponible_kg = capacidad_disponible_kg + v_reserva.peso_kg,
        capacidad_disponible_m3 = capacidad_disponible_m3 + COALESCE(v_reserva.volumen_m3, 0),
        estado = CASE WHEN estado = 'CUPO_COMPLETO' THEN 'PROGRAMADO'::trip_status ELSE estado END
    WHERE id = v_viaje.id;

    -- Marcar reserva como cancelada
    UPDATE reservations 
    SET estado = 'CANCELADA', fecha_cancelacion = now()
    WHERE id = p_reserva_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- 009_views.sql

-- Vista del manifiesto consolidado
CREATE OR REPLACE VIEW trip_manifest_view AS
SELECT 
    t.id AS viaje_id,
    t.fecha_zarpe,
    t.estado AS viaje_estado,
    t.transportador_id,
    orig.nombre AS origen,
    dest.nombre AS destino,
    r.id AS reserva_id,
    c.nombre AS comerciante,
    c.telefono AS comerciante_telefono,
    r.peso_kg,
    r.volumen_m3,
    r.tipo_paquete,
    r.descripcion_carga,
    r.costo_total_cop,
    r.estado AS reserva_estado
FROM trips t
JOIN locations orig ON t.origen_id = orig.id
JOIN locations dest ON t.destino_id = dest.id
JOIN reservations r ON r.viaje_id = t.id
JOIN profiles c ON r.comerciante_id = c.id
WHERE r.estado != 'CANCELADA'
ORDER BY r.created_at ASC;


-- Vista para rutas con mayor demanda (Dashboard)
CREATE OR REPLACE VIEW route_demand_stats AS
SELECT 
    orig.nombre AS origen,
    dest.nombre AS destino,
    COUNT(DISTINCT t.id) AS cantidad_viajes,
    COUNT(r.id) AS cantidad_reservas,
    COALESCE(SUM(r.peso_kg), 0) AS total_kg_reservados
FROM trips t
JOIN locations orig ON t.origen_id = orig.id
JOIN locations dest ON t.destino_id = dest.id
LEFT JOIN reservations r ON r.viaje_id = t.id AND r.estado != 'CANCELADA'
GROUP BY orig.nombre, dest.nombre
ORDER BY total_kg_reservados DESC;


-- Funciones RPC para Dashboard (Métricas)
CREATE OR REPLACE FUNCTION get_dashboard_metrics()
RETURNS JSONB AS $$
DECLARE
    v_total_viajes INT;
    v_total_reservas INT;
    v_total_kg NUMERIC;
    v_total_ahorro NUMERIC;
    v_comerciantes_activos INT;
    v_transportadores_activos INT;
BEGIN
    SELECT COUNT(*) INTO v_total_viajes FROM trips;
    SELECT COUNT(*) INTO v_total_reservas FROM reservations WHERE estado != 'CANCELADA';
    SELECT COALESCE(SUM(peso_kg), 0) INTO v_total_kg FROM reservations WHERE estado != 'CANCELADA';
    SELECT COALESCE(SUM(ahorro_estimado_cop), 0) INTO v_total_ahorro FROM reservations WHERE estado != 'CANCELADA';
    
    SELECT COUNT(*) INTO v_comerciantes_activos FROM profiles WHERE rol = 'COMERCIANTE' AND activo = true;
    SELECT COUNT(*) INTO v_transportadores_activos FROM profiles WHERE rol = 'TRANSPORTADOR' AND activo = true;

    RETURN jsonb_build_object(
        'total_viajes', v_total_viajes,
        'total_reservas', v_total_reservas,
        'total_kg_movilizados', v_total_kg,
        'total_toneladas_movilizadas', v_total_kg / 1000,
        'dinero_total_ahorrado_cop', v_total_ahorro,
        'comerciantes_activos', v_comerciantes_activos,
        'transportadores_activos', v_transportadores_activos
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- 010_rls_policies.sql

-- PROFILES
CREATE POLICY "Public profiles are viewable by everyone" ON profiles
FOR SELECT USING (true);

CREATE POLICY "Users can insert their own profile" ON profiles
FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON profiles
FOR UPDATE USING (auth.uid() = id);

-- LOCATIONS
CREATE POLICY "Locations are viewable by everyone" ON locations
FOR SELECT USING (true);
-- Solo admin podría insertar/modificar locations, por simplicidad omitimos insert público.

-- TRIPS
CREATE POLICY "Trips are viewable by everyone" ON trips
FOR SELECT USING (true);

CREATE POLICY "Transportadores can create their own trips" ON trips
FOR INSERT WITH CHECK (
    auth.uid() = transportador_id AND
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND rol = 'TRANSPORTADOR')
);

CREATE POLICY "Transportadores can update their own trips" ON trips
FOR UPDATE USING (auth.uid() = transportador_id);

-- RESERVATIONS
CREATE POLICY "Comerciantes can view their own reservations" ON reservations
FOR SELECT USING (auth.uid() = comerciante_id);

CREATE POLICY "Transportadores can view reservations for their trips" ON reservations
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM trips 
        WHERE trips.id = reservations.viaje_id AND trips.transportador_id = auth.uid()
    )
);

-- (La inserción y actualización crítica de reservas se hace mediante SECURITY DEFINER RPC 
--  por lo que no requiere políticas estrictas de INSERT directo, pero por si acaso:)
CREATE POLICY "Comerciantes can insert their own reservations" ON reservations
FOR INSERT WITH CHECK (auth.uid() = comerciante_id);

-- SYSTEM SETTINGS
CREATE POLICY "Settings are viewable by everyone" ON system_settings
FOR SELECT USING (true);

-- AUDIT LOGS
CREATE POLICY "Admins can view audit logs" ON audit_logs
FOR SELECT USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND rol = 'ADMIN')
);
-- 011_triggers.sql

-- Trigger para updated_at automático
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_profiles_updated_at
BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_trips_updated_at
BEFORE UPDATE ON trips
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_reservations_updated_at
BEFORE UPDATE ON reservations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- Trigger básico para auditoría
CREATE OR REPLACE FUNCTION audit_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_logs(user_id, action, entity, entity_id, new_data)
        VALUES (auth.uid(), 'CREATE', TG_TABLE_NAME, NEW.id, row_to_json(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_logs(user_id, action, entity, entity_id, old_data, new_data)
        VALUES (auth.uid(), 'UPDATE', TG_TABLE_NAME, NEW.id, row_to_json(OLD), row_to_json(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_logs(user_id, action, entity, entity_id, old_data)
        VALUES (auth.uid(), 'DELETE', TG_TABLE_NAME, OLD.id, row_to_json(OLD));
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER audit_trips_changes
AFTER INSERT OR UPDATE OR DELETE ON trips
FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER audit_reservations_changes
AFTER INSERT OR UPDATE OR DELETE ON reservations
FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();
-- seed.sql

-- 1. Crear usuarios de prueba (mockeando auth.users y llenando profiles)
-- Supabase Studio o CLI auto-generan un esquema auth. Insertaremos directamente.

-- Definimos UUIDs fijos para poder relacionar la data fácilmente
DO $$
DECLARE
    transportador1_id UUID := '11111111-1111-1111-1111-111111111111';
    transportador2_id UUID := '22222222-2222-2222-2222-222222222222';
    comerciante1_id UUID := '33333333-3333-3333-3333-333333333333';
    comerciante2_id UUID := '44444444-4444-4444-4444-444444444444';
    admin_id UUID := '55555555-5555-5555-5555-555555555555';
    
    loc_apartado UUID;
    loc_zungo UUID;
    loc_turbo UUID;
    loc_capurgana UUID;
    loc_acandi UUID;
    loc_titumate UUID;
    loc_unguia UUID;
    
    viaje1_id UUID;
    viaje2_id UUID;
    viaje3_id UUID;
    viaje4_id UUID;
BEGIN

    -- Para que el FK a auth.users funcione en local sin registrar manual,
    -- es seguro para Supabase CLI insertar directamente:
    INSERT INTO auth.users (id, email) VALUES 
        (transportador1_id, 'transp1@test.com'),
        (transportador2_id, 'transp2@test.com'),
        (comerciante1_id, 'comer1@test.com'),
        (comerciante2_id, 'comer2@test.com'),
        (admin_id, 'admin@test.com')
    ON CONFLICT DO NOTHING;

    INSERT INTO profiles (id, nombre, telefono, rol) VALUES
        (transportador1_id, 'Juan Pérez (Lancha El Mar)', '3001112222', 'TRANSPORTADOR'),
        (transportador2_id, 'Carlos López (Bote La Brisa)', '3003334444', 'TRANSPORTADOR'),
        (comerciante1_id, 'María Gómez (Frutas)', '3005556666', 'COMERCIANTE'),
        (comerciante2_id, 'Andrés Soto (Ferretería)', '3007778888', 'COMERCIANTE'),
        (admin_id, 'Administrador Urabá', '3000000000', 'ADMIN')
    ON CONFLICT (id) DO NOTHING;

    -- 2. Ubicaciones
    INSERT INTO locations (nombre, tipo, municipio) VALUES 
        ('Apartadó', 'ciudad', 'Apartadó') RETURNING id INTO loc_apartado;
    INSERT INTO locations (nombre, tipo, municipio) VALUES 
        ('Embarcadero Zungo', 'muelle', 'Carepa') RETURNING id INTO loc_zungo;
    INSERT INTO locations (nombre, tipo, municipio) VALUES 
        ('Turbo', 'puerto', 'Turbo') RETURNING id INTO loc_turbo;
    INSERT INTO locations (nombre, tipo, municipio) VALUES 
        ('Capurganá', 'puerto', 'Acandí') RETURNING id INTO loc_capurgana;
    INSERT INTO locations (nombre, tipo, municipio) VALUES 
        ('Acandí', 'puerto', 'Acandí') RETURNING id INTO loc_acandi;
    INSERT INTO locations (nombre, tipo, municipio) VALUES 
        ('Titumate', 'puerto', 'Unguía') RETURNING id INTO loc_titumate;
    INSERT INTO locations (nombre, tipo, municipio) VALUES 
        ('Unguía', 'puerto', 'Unguía') RETURNING id INTO loc_unguia;

    -- 3. Viajes Programados
    -- Viaje 1: Zungo -> Capurganá (1000 kg, $1000/kg)
    INSERT INTO trips (transportador_id, origen_id, destino_id, fecha_zarpe, hora_limite_recepcion, capacidad_total_kg, capacidad_disponible_kg, tarifa_por_kg, estado)
    VALUES (transportador1_id, loc_zungo, loc_capurgana, now() + interval '2 days', now() + interval '1 day', 1000, 1000, 1000, 'ABIERTO')
    RETURNING id INTO viaje1_id;

    -- Viaje 2: Zungo -> Acandí (500 kg, $1200/kg)
    INSERT INTO trips (transportador_id, origen_id, destino_id, fecha_zarpe, hora_limite_recepcion, capacidad_total_kg, capacidad_disponible_kg, tarifa_por_kg, estado)
    VALUES (transportador2_id, loc_zungo, loc_acandi, now() + interval '3 days', now() + interval '2 days', 500, 500, 1200, 'ABIERTO')
    RETURNING id INTO viaje2_id;

    -- Viaje 3: Turbo -> Capurganá (2000 kg, $900/kg)
    INSERT INTO trips (transportador_id, origen_id, destino_id, fecha_zarpe, hora_limite_recepcion, capacidad_total_kg, capacidad_disponible_kg, tarifa_por_kg, estado)
    VALUES (transportador1_id, loc_turbo, loc_capurgana, now() + interval '5 days', now() + interval '4 days', 2000, 2000, 900, 'ABIERTO')
    RETURNING id INTO viaje3_id;

    -- Viaje 4: Turbo -> Unguía (1500 kg, $1100/kg)
    INSERT INTO trips (transportador_id, origen_id, destino_id, fecha_zarpe, hora_limite_recepcion, capacidad_total_kg, capacidad_disponible_kg, tarifa_por_kg, estado)
    VALUES (transportador2_id, loc_turbo, loc_unguia, now() + interval '1 day', now() + interval '12 hours', 1500, 1500, 1100, 'ABIERTO')
    RETURNING id INTO viaje4_id;


    -- 4. Reservas de Prueba usando set_config para mockear auth.uid() en los RPC
    -- (Nota: como el insert directo funciona con admin privileges, aquí lo insertaremos directo
    -- para simular la data, y dejaremos que las pruebas llamen al RPC real)

    -- Capacidad Parcial (Viaje 1: 1000 -> 800 disponibles)
    INSERT INTO reservations (viaje_id, comerciante_id, peso_kg, tipo_paquete, costo_total_cop, ahorro_estimado_cop, estado)
    VALUES (viaje1_id, comerciante1_id, 200, 'Cajas Frutas', 200*1000, 200*(1500-1000), 'CONFIRMADA');
    UPDATE trips SET capacidad_disponible_kg = 800 WHERE id = viaje1_id;

    -- Viaje casi lleno (Viaje 2: 500 -> 50 disponibles)
    INSERT INTO reservations (viaje_id, comerciante_id, peso_kg, tipo_paquete, costo_total_cop, ahorro_estimado_cop, estado)
    VALUES (viaje2_id, comerciante2_id, 450, 'Ferretería', 450*1200, 450*(1500-1200), 'CONFIRMADA');
    UPDATE trips SET capacidad_disponible_kg = 50 WHERE id = viaje2_id;

    -- Viaje lleno (Viaje 4: 1500 -> 0)
    INSERT INTO reservations (viaje_id, comerciante_id, peso_kg, tipo_paquete, costo_total_cop, ahorro_estimado_cop, estado)
    VALUES (viaje4_id, comerciante1_id, 1500, 'Víveres varios', 1500*1100, 1500*(1500-1100), 'CONFIRMADA');
    UPDATE trips SET capacidad_disponible_kg = 0, estado = 'CUPO_COMPLETO' WHERE id = viaje4_id;

END $$;
