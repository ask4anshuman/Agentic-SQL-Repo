-- Sample UPDATE DML Script
-- This file demonstrates basic UPDATE operations

-- Confluence: https://ask4anshuman.atlassian.net/wiki/pages/viewpage.action?pageId=4653058
-- Update salary for a specific employee
UPDATE employees
SET salary = 505050
WHERE employee_id = 1001;

-- Update multiple columns
UPDATE employees
SET email = 'john.d.doe@company.com', salary = 900000
WHERE employee_id = 1001;

-- Bulk update with condition
UPDATE employees
SET salary = salary * 1.10
WHERE hire_date < '2000-01-01';
