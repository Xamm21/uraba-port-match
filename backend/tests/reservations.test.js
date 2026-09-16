require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

// Configuración del cliente con Service Role para saltar políticas RLS si es necesario en los tests de admin
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const supabase = createClient(supabaseUrl, supabaseKey);

// IDs de prueba que insertamos en seed.sql
const comerciante1_id = '33333333-3333-3333-3333-333333333333';
const comerciante2_id = '44444444-4444-4444-4444-444444444444';

describe('Reservaciones en UrabáPort Match', () => {

    test('El usuario debe estar autenticado para reservar (Fallo esperado sin Auth)', async () => {
        // Al probar RPC que requieren auth.uid(), necesitamos estar autenticados.
        // Como estamos haciendo pruebas de integración sin contraseña, comprobaremos que 
        // la función de DB maneja el error de "Usuario no autenticado"
        
        const { data, error } = await supabase.rpc('create_reservation', {
            p_viaje_id: '00000000-0000-0000-0000-000000000000', // Un ID falso
            p_peso_kg: 100
        });

        expect(error).not.toBeNull();
        expect(error.message).toMatch(/autenticado/i);
    });

    test('Debe obtener las estadísticas del dashboard', async () => {
        const { data, error } = await supabase.rpc('get_dashboard_metrics');
        
        expect(error).toBeNull();
        expect(data).toHaveProperty('total_viajes');
        expect(data).toHaveProperty('total_reservas');
        expect(data).toHaveProperty('dinero_total_ahorrado_cop');
        expect(Number(data.total_viajes)).toBeGreaterThanOrEqual(0);
    });

    test('Debe poder leer los viajes públicos', async () => {
        const { data, error } = await supabase.from('trips').select('*');
        
        expect(error).toBeNull();
        expect(Array.isArray(data)).toBe(true);
    });
    
    // NOTA: Para probar los casos atómicos completos (Casos 1 al 9), 
    // se requeriría iniciar sesión con auth.signInWithPassword o mockear auth.uid() 
    // en la base de datos usando set_config().
    
});
