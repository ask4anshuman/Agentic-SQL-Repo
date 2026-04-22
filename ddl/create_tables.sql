-- Sample CREATE TABLE DDL Script
-- This file demonstrates table creation with constraints

-- Create EMPLOYEES table
CREATE TABLE employees (
    employee_id INT PRIMARY KEY NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE,
    hire_date DATE NOT NULL,
    salary DECIMAL(10, 2),
    department_id INT,
    status VARCHAR(20) DEFAULT 'Active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create DEPARTMENTS table
CREATE TABLE departments (
    department_id INT PRIMARY KEY NOT NULL,
    department_name VARCHAR(100) NOT NULL,
    manager_id INT,
    location VARCHAR(100)
);

-- Create foreign key relationship
ALTER TABLE employees
ADD CONSTRAINT fk_dept_id
FOREIGN KEY (department_id) REFERENCES departments(department_id);
