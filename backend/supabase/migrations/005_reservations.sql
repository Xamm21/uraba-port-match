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
