-- Sample CREATE VIEW Script
-- This file demonstrates view creation for simplified data access

-- Confluence: https://ask4anshuman.atlassian.net/wiki/pages/viewpage.action?pageId=4718593
-- Create view for active employees with department info
CREATE VIEW active_employees_view AS
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    e.email,
    e.salary,
    d.department_name,
    e.hire_date
FROM employees e
INNER JOIN departments d ON e.department_id = d.department_id
WHERE e.status = 'In-progress'
ORDER BY e.last_name, e.first_name;

-- Create view for employee salary summary
CREATE VIEW employee_salary_summary AS
SELECT 
    d.department_name,
    COUNT(e.employee_id) as employee_count,
    AVG(e.salary) as avg_salary,
    MIN(e.salary) as min_salary,
    MAX(e.salary) as max_salary,
    SUM(e.salary) as total_salary
FROM employees e
INNER JOIN departments d ON e.department_id = d.department_id
GROUP BY d.department_id, d.department_name;

-- Create view for employee details with tenure
CREATE VIEW employee_details_with_tenure AS
SELECT 
    e.employee_id,
    CONCAT(e.first_name, ' ', e.last_name) as full_name,
    e.email,
    e.salary,
    YEAR(CURDATE()) - YEAR(e.hire_date) as tenure_years,
    d.department_name
FROM employees e
INNER JOIN departments d ON e.department_id = d.department_id;
