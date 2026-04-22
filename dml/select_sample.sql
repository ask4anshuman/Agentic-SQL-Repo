-- Sample SELECT DML Script
-- This file demonstrates basic SELECT queries

-- Simple SELECT all
SELECT * FROM employees;

-- SELECT with specific columns and WHERE clause
SELECT employee_id, first_name, last_name, salary
FROM employees
WHERE salary > 70000
ORDER BY salary DESC;

-- SELECT with aggregation
SELECT department, COUNT(*) as employee_count, AVG(salary) as avg_salary
FROM employees
GROUP BY department
HAVING COUNT(*) > 5;

-- SELECT with JOIN
SELECT e.employee_id, e.first_name, d.department_name
FROM employees e
INNER JOIN departments d ON e.department_id = d.department_id;
