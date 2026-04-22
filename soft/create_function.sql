-- Sample CREATE FUNCTION Script
-- This file demonstrates function creation for reusable logic

-- Create a function to calculate employee tenure
CREATE FUNCTION get_employee_tenure(p_hire_date DATE)
RETURNS INT
DETERMINISTIC
LANGUAGE SQL
BEGIN
    DECLARE v_tenure INT;
    SET v_tenure = YEAR(CURDATE()) - YEAR(p_hire_date);
    RETURN v_tenure;
END;

-- Create a scalar function to calculate annual bonus
CREATE FUNCTION calculate_bonus(p_salary DECIMAL, p_performance_rating INT)
RETURNS DECIMAL
DETERMINISTIC
LANGUAGE SQL
BEGIN
    DECLARE v_bonus DECIMAL;
    IF p_performance_rating >= 4 THEN
        SET v_bonus = p_salary * 0.15;
    ELSEIF p_performance_rating >= 3 THEN
        SET v_bonus = p_salary * 0.10;
    ELSE
        SET v_bonus = p_salary * 0.05;
    END IF;
    RETURN v_bonus;
END;
