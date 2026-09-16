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
