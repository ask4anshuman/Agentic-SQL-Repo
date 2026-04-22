-- Sample ALTER TABLE DDL Script
-- This file demonstrates table modification operations

-- Add new column to employees table
ALTER TABLE employees
ADD COLUMN phone_number VARCHAR(15);

-- Add new column with default value
ALTER TABLE employees
ADD COLUMN performance_rating INT DEFAULT 0;

-- Drop a column
ALTER TABLE employees
DROP COLUMN performance_rating;

-- Modify column properties
ALTER TABLE employees
MODIFY COLUMN salary DECIMAL(12, 2);

-- Add index for performance optimization
CREATE INDEX idx_employee_department
ON employees(department_id);

-- Create composite index
CREATE INDEX idx_name_hire_date
ON employees(last_name, hire_date);
