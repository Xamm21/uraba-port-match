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
