-- Sample CREATE PROCEDURE Script
-- This file demonstrates stored procedure creation for complex operations

-- Create procedure to add new employee
CREATE PROCEDURE add_new_employee(
    IN p_first_name VARCHAR(50),
    IN p_last_name VARCHAR(50),
    IN p_email VARCHAR(100),
    IN p_salary DECIMAL(10, 2),
    IN p_department_id INT,
    OUT p_employee_id INT
)
BEGIN
    DECLARE v_max_id INT;
    
    -- Get the next employee ID
    SELECT IFNULL(MAX(employee_id), 0) + 1 INTO v_max_id FROM employees;
    
    -- Insert new employee
    INSERT INTO employees (employee_id, first_name, last_name, email, hire_date, salary, department_id)
    VALUES (v_max_id, p_first_name, p_last_name, p_email, CURDATE(), p_salary, p_department_id);
    
    -- Return the new employee ID
    SET p_employee_id = v_max_id;
END;

-- Create procedure to update employee salary with audit log
CREATE PROCEDURE update_employee_salary(
    IN p_employee_id INT,
    IN p_new_salary DECIMAL(10, 2)
)
BEGIN
    DECLARE v_old_salary DECIMAL(10, 2);
    
    -- Get old salary
    SELECT salary INTO v_old_salary FROM employees WHERE employee_id = p_employee_id;
    
    -- Update salary
    UPDATE employees SET salary = p_new_salary WHERE employee_id = p_employee_id;
    
    -- Insert audit log
    INSERT INTO salary_audit_log (employee_id, old_salary, new_salary, change_date)
    VALUES (p_employee_id, v_old_salary, p_new_salary, NOW());
END;
