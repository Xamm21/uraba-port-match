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
