# SQL Project Structure

This SQL project is organized into three main folders for different types of SQL operations:

## Folder Structure

### 📊 DML (Data Manipulation Language) - `/dml`
Contains SQL scripts for data manipulation operations:
- **insert_sample.sql** - INSERT statements for adding new data
- **update_sample.sql** - UPDATE statements for modifying existing data
- **delete_sample.sql** - DELETE statements for removing data
- **select_sample.sql** - SELECT queries for retrieving data

### 🏗️ DDL (Data Definition Language) - `/ddl`
Contains SQL scripts for database structure definition:
- **create_tables.sql** - CREATE TABLE statements with constraints
- **alter_tables.sql** - ALTER TABLE statements for modifying structure
- **drop_tables.sql** - DROP TABLE statements for removing tables

### ⚙️ SOFT (Functions/Procedures/Packages) - `/soft`
Contains SQL scripts for database objects and procedural logic:
- **create_function.sql** - User-defined functions for reusable logic
- **create_procedure.sql** - Stored procedures for complex operations
- **create_trigger.sql** - Triggers for automated actions
- **create_view.sql** - Views for simplified data access

## Getting Started

1. Start with DDL scripts to create your database structure
2. Use DML scripts to insert and manage data
3. Add SOFT objects (functions, procedures, triggers, views) to enhance functionality

## Notes

- All sample files use generic table structures (employees, departments)
- Modify SQL syntax as needed for your specific database system
- Always test scripts in a development environment first
