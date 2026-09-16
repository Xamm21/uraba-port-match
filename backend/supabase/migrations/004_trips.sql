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
