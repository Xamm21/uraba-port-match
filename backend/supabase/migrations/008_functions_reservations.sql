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
