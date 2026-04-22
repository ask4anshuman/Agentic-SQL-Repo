-- Sample DROP TABLE DDL Script
-- This file demonstrates table deletion operations

-- Drop table with cascade (handles foreign key constraints)
DROP TABLE IF EXISTS employees CASCADE;

-- Drop table with restrict (fails if referenced)
DROP TABLE IF EXISTS departments RESTRICT;

-- Drop multiple tables
DROP TABLE IF EXISTS employees, departments;
