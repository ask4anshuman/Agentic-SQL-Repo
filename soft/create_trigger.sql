-- Sample CREATE TRIGGER Script
-- This file demonstrates trigger creation for automated actions

-- Create trigger to update modified timestamp on employee update
CREATE TRIGGER trg_update_employee_timestamp
BEFORE UPDATE ON employees
FOR EACH ROW
BEGIN
    SET NEW.updated_at = NOW();
END;

-- Create trigger to maintain employee count in departments table
CREATE TRIGGER trg_insert_employee_count
AFTER INSERT ON employees
FOR EACH ROW
BEGIN
    UPDATE departments 
    SET employee_count = employee_count + 1
    WHERE department_id = NEW.department_id;
END;

-- Create trigger to log employee deletions
CREATE TRIGGER trg_log_employee_deletion
BEFORE DELETE ON employees
FOR EACH ROW
BEGIN
    INSERT INTO deleted_employees_log (employee_id, name, deleted_date)
    VALUES (OLD.employee_id, CONCAT(OLD.first_name, ' ', OLD.last_name), NOW());
END;
