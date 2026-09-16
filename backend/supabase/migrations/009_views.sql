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
