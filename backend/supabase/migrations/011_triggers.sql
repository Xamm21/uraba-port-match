-- 011_triggers.sql

-- Trigger para updated_at automático
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_profiles_updated_at
BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_trips_updated_at
BEFORE UPDATE ON trips
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_reservations_updated_at
BEFORE UPDATE ON reservations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- Trigger básico para auditoría
CREATE OR REPLACE FUNCTION audit_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_logs(user_id, action, entity, entity_id, new_data)
        VALUES (auth.uid(), 'CREATE', TG_TABLE_NAME, NEW.id, row_to_json(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_logs(user_id, action, entity, entity_id, old_data, new_data)
        VALUES (auth.uid(), 'UPDATE', TG_TABLE_NAME, NEW.id, row_to_json(OLD), row_to_json(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_logs(user_id, action, entity, entity_id, old_data)
        VALUES (auth.uid(), 'DELETE', TG_TABLE_NAME, OLD.id, row_to_json(OLD));
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER audit_trips_changes
AFTER INSERT OR UPDATE OR DELETE ON trips
FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER audit_reservations_changes
AFTER INSERT OR UPDATE OR DELETE ON reservations
FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();
