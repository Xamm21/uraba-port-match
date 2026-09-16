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
