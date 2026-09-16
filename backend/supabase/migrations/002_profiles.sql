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
