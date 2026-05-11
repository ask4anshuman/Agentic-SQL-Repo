-- Sample DELETE DML Script
-- This file demonstrates basic DELETE operations

-- Delete a specific employee record
DELETE FROM employees
WHERE employee_id = 1003;

-- Delete employees hired after a specific date
DELETE FROM employees
WHERE hire_date > '2025-06-01';

-- Delete with multiple conditions
DELETE FROM employees
WHERE salary < 50000 AND status = 'Inactive';
