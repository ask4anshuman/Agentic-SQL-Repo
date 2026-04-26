-- Advanced ETL + Enrichment Load Script (MySQL 8+)
-- Purpose:
--   1) Clean, validate, and deduplicate staged employee data
-- Confluence: https://ask4anshuman.atlassian.net/wiki/pages/viewpage.action?pageId=5931010
--   2) Enrich records with business logic and department mapping
--   3) Upsert into employees and into an enriched target table
--
-- Source expected: stg_employee_delta
-- Suggested source columns:
--   source_system, source_employee_id, first_name, last_name, email,
--   hire_date_raw, salary_raw, department_id_raw, department_name_raw,
--   status_raw, ingested_at, updated_at

START TRANSACTION;

SET @run_id = UUID();
SET @started_at = NOW();

-- Run audit table
CREATE TABLE IF NOT EXISTS etl_run_audit (
    run_id VARCHAR(36) PRIMARY KEY,
    process_name VARCHAR(100) NOT NULL,
    started_at DATETIME NOT NULL,
    finished_at DATETIME NULL,
    status VARCHAR(20) NOT NULL,
    source_row_count INT DEFAULT 0,
    rejected_row_count INT DEFAULT 0,
    loaded_row_count INT DEFAULT 0,
    message VARCHAR(500) NULL
);

-- Row-level reject table
CREATE TABLE IF NOT EXISTS etl_employee_rejects (
    reject_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id VARCHAR(36) NOT NULL,
    source_system VARCHAR(50),
    source_employee_id VARCHAR(50),
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    hire_date_raw VARCHAR(50),
    salary_raw VARCHAR(50),
    department_id_raw VARCHAR(50),
    department_name_raw VARCHAR(100),
    status_raw VARCHAR(30),
    rejection_reason VARCHAR(300) NOT NULL,
    rejected_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Target enrichment table
CREATE TABLE IF NOT EXISTS employee_enriched_target (
    employee_id INT PRIMARY KEY,
    full_name VARCHAR(120) NOT NULL,
    normalized_email VARCHAR(100),
    department_id INT,
    department_name VARCHAR(100),
    standardized_status VARCHAR(20) NOT NULL,
    salary DECIMAL(10,2),
    salary_band VARCHAR(20) NOT NULL,
    tenure_years INT NOT NULL,
    tenure_bucket VARCHAR(20) NOT NULL,
    compensation_index DECIMAL(12,4) NOT NULL,
    source_system VARCHAR(50),
    source_employee_id VARCHAR(50),
    etl_run_id VARCHAR(36) NOT NULL,
    loaded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO etl_run_audit (run_id, process_name, started_at, status)
VALUES (@run_id, 'employee_etl_enrichment', @started_at, 'RUNNING');

-- Optional default department for unresolved mappings
INSERT INTO departments (department_id, department_name, manager_id, location)
SELECT 0, 'Unknown', NULL, 'N/A'
WHERE NOT EXISTS (
    SELECT 1
    FROM departments d
    WHERE d.department_id = 0
);

-- Record source row count
UPDATE etl_run_audit
SET source_row_count = (SELECT COUNT(*) FROM stg_employee_delta)
WHERE run_id = @run_id;

-- Normalize, validate, and deduplicate source into a temporary working set.
CREATE TEMPORARY TABLE tmp_employee_survivors AS
WITH src AS (
    SELECT
        s.source_system,
        s.source_employee_id,
        TRIM(s.first_name) AS first_name_raw,
        TRIM(s.last_name) AS last_name_raw,
        LOWER(TRIM(s.email)) AS email_raw,
        TRIM(s.hire_date_raw) AS hire_date_raw,
        TRIM(s.salary_raw) AS salary_raw,
        TRIM(s.department_id_raw) AS department_id_raw,
        TRIM(s.department_name_raw) AS department_name_raw,
        TRIM(s.status_raw) AS status_raw,
        COALESCE(s.updated_at, s.ingested_at, NOW()) AS event_ts,
        s.ingested_at
    FROM stg_employee_delta s
),
normalized AS (
    SELECT
        source_system,
        source_employee_id,
        NULLIF(first_name_raw, '') AS first_name,
        NULLIF(last_name_raw, '') AS last_name,
        NULLIF(email_raw, '') AS email,
        CASE
            WHEN hire_date_raw REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN STR_TO_DATE(hire_date_raw, '%Y-%m-%d')
            WHEN hire_date_raw REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN STR_TO_DATE(hire_date_raw, '%d/%m/%Y')
            WHEN hire_date_raw REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' THEN STR_TO_DATE(hire_date_raw, '%m-%d-%Y')
            ELSE NULL
        END AS hire_date,
        CASE
            WHEN REPLACE(REPLACE(salary_raw, ',', ''), '$', '') REGEXP '^-?[0-9]+(\\.[0-9]{1,2})?$'
                THEN CAST(REPLACE(REPLACE(salary_raw, ',', ''), '$', '') AS DECIMAL(10,2))
            ELSE NULL
        END AS salary,
        CASE
            WHEN department_id_raw REGEXP '^[0-9]+$' THEN CAST(department_id_raw AS UNSIGNED)
            ELSE NULL
        END AS department_id_from_source,
        NULLIF(department_name_raw, '') AS department_name,
        CASE
            WHEN UPPER(status_raw) IN ('ACTIVE', 'A', '1', 'Y', 'TRUE') THEN 'Active'
            WHEN UPPER(status_raw) IN ('INACTIVE', 'I', '0', 'N', 'FALSE') THEN 'Inactive'
            WHEN UPPER(status_raw) IN ('ON_LEAVE', 'LEAVE', 'PAUSED') THEN 'On Leave'
            ELSE 'Active'
        END AS standardized_status,
        event_ts,
        ingested_at,
        CONCAT_WS('|',
            COALESCE(source_system, 'NA'),
            COALESCE(source_employee_id, 'NA'),
            COALESCE(email, 'NA'),
            COALESCE(first_name, 'NA'),
            COALESCE(last_name, 'NA')
        ) AS business_key
    FROM src
),
validated AS (
    SELECT
        n.*,
        CASE
            WHEN n.first_name IS NULL OR n.last_name IS NULL THEN 'Missing required name fields'
            WHEN n.hire_date IS NULL THEN 'Invalid or missing hire date'
            WHEN n.salary IS NULL THEN 'Invalid salary format'
            WHEN n.salary < 0 THEN 'Salary cannot be negative'
            WHEN n.email IS NOT NULL AND n.email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN 'Invalid email format'
            ELSE NULL
        END AS reject_reason
    FROM normalized n
),
dedup AS (
    SELECT
        v.*,
        ROW_NUMBER() OVER (
            PARTITION BY v.business_key
            ORDER BY v.event_ts DESC, v.ingested_at DESC
        ) AS rn
    FROM validated v
)
SELECT
    d.source_system,
    d.source_employee_id,
    d.first_name,
    d.last_name,
    d.email,
    d.hire_date,
    d.salary,
    d.department_id_from_source,
    d.department_name,
    d.standardized_status,
    d.event_ts,
    d.ingested_at,
    d.business_key
FROM dedup d
WHERE d.reject_reason IS NULL
  AND d.rn = 1;

-- Persist rejected rows for observability.
INSERT INTO etl_employee_rejects (
    run_id,
    source_system,
    source_employee_id,
    first_name,
    last_name,
    email,
    hire_date_raw,
    salary_raw,
    department_id_raw,
    department_name_raw,
    status_raw,
    rejection_reason
)
WITH src AS (
    SELECT
        s.source_system,
        s.source_employee_id,
        TRIM(s.first_name) AS first_name_raw,
        TRIM(s.last_name) AS last_name_raw,
        LOWER(TRIM(s.email)) AS email_raw,
        TRIM(s.hire_date_raw) AS hire_date_raw,
        TRIM(s.salary_raw) AS salary_raw,
        TRIM(s.department_id_raw) AS department_id_raw,
        TRIM(s.department_name_raw) AS department_name_raw,
        TRIM(s.status_raw) AS status_raw,
        COALESCE(s.updated_at, s.ingested_at, NOW()) AS event_ts,
        s.ingested_at
    FROM stg_employee_delta s
),
normalized AS (
    SELECT
        source_system,
        source_employee_id,
        NULLIF(first_name_raw, '') AS first_name,
        NULLIF(last_name_raw, '') AS last_name,
        NULLIF(email_raw, '') AS email,
        CASE
            WHEN hire_date_raw REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN STR_TO_DATE(hire_date_raw, '%Y-%m-%d')
            WHEN hire_date_raw REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN STR_TO_DATE(hire_date_raw, '%d/%m/%Y')
            WHEN hire_date_raw REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' THEN STR_TO_DATE(hire_date_raw, '%m-%d-%Y')
            ELSE NULL
        END AS hire_date,
        CASE
            WHEN REPLACE(REPLACE(salary_raw, ',', ''), '$', '') REGEXP '^-?[0-9]+(\\.[0-9]{1,2})?$'
                THEN CAST(REPLACE(REPLACE(salary_raw, ',', ''), '$', '') AS DECIMAL(10,2))
            ELSE NULL
        END AS salary,
        CASE
            WHEN department_id_raw REGEXP '^[0-9]+$' THEN CAST(department_id_raw AS UNSIGNED)
            ELSE NULL
        END AS department_id_from_source,
        NULLIF(department_name_raw, '') AS department_name,
        status_raw,
        event_ts,
        ingested_at,
        CONCAT_WS('|',
            COALESCE(source_system, 'NA'),
            COALESCE(source_employee_id, 'NA'),
            COALESCE(email, 'NA'),
            COALESCE(first_name, 'NA'),
            COALESCE(last_name, 'NA')
        ) AS business_key,
        first_name_raw,
        last_name_raw,
        email_raw,
        hire_date_raw,
        salary_raw,
        department_id_raw,
        department_name_raw
    FROM src
),
validated AS (
    SELECT
        n.*,
        CASE
            WHEN n.first_name IS NULL OR n.last_name IS NULL THEN 'Missing required name fields'
            WHEN n.hire_date IS NULL THEN 'Invalid or missing hire date'
            WHEN n.salary IS NULL THEN 'Invalid salary format'
            WHEN n.salary < 0 THEN 'Salary cannot be negative'
            WHEN n.email IS NOT NULL AND n.email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN 'Invalid email format'
            ELSE NULL
        END AS reject_reason
    FROM normalized n
),
dedup AS (
    SELECT
        v.*,
        ROW_NUMBER() OVER (
            PARTITION BY v.business_key
            ORDER BY v.event_ts DESC, v.ingested_at DESC
        ) AS rn
    FROM validated v
)
SELECT
    @run_id,
    d.source_system,
    d.source_employee_id,
    d.first_name_raw,
    d.last_name_raw,
    d.email_raw,
    d.hire_date_raw,
    d.salary_raw,
    d.department_id_raw,
    d.department_name_raw,
    d.status_raw,
    CASE
        WHEN d.reject_reason IS NOT NULL THEN d.reject_reason
        WHEN d.rn > 1 THEN 'Duplicate source record in batch'
        ELSE 'Unknown rejection'
    END AS rejection_reason
FROM dedup d
WHERE d.reject_reason IS NOT NULL
   OR d.rn > 1;

-- Insert previously unseen departments from the batch.
INSERT INTO departments (department_id, department_name, manager_id, location)
SELECT
    (SELECT IFNULL(MAX(x.department_id), 0) FROM departments x) + seq.seq_id AS new_department_id,
    seq.department_name,
    NULL,
    'Auto-Discovered'
FROM (
    SELECT
        ROW_NUMBER() OVER (ORDER BY t.department_name) AS seq_id,
        t.department_name
    FROM (
        SELECT DISTINCT department_name
        FROM tmp_employee_survivors
        WHERE department_name IS NOT NULL
    ) t
    LEFT JOIN departments d
      ON LOWER(d.department_name) = LOWER(t.department_name)
    WHERE d.department_id IS NULL
) seq;

-- Compute resolved department, existing employee linkage, and surrogate IDs.
CREATE TEMPORARY TABLE tmp_employee_final AS
WITH max_emp AS (
    SELECT IFNULL(MAX(employee_id), 0) AS max_employee_id
    FROM employees
),
resolved AS (
    SELECT
        s.source_system,
        s.source_employee_id,
        s.first_name,
        s.last_name,
        s.email,
        s.hire_date,
        s.salary,
        s.standardized_status,
        COALESCE(did.department_id, dname.department_id, 0) AS resolved_department_id,
        COALESCE(did.department_name, dname.department_name, 'Unknown') AS resolved_department_name,
        e_existing.employee_id AS existing_employee_id,
        ROW_NUMBER() OVER (ORDER BY s.business_key) AS seq_for_new_ids
    FROM tmp_employee_survivors s
    LEFT JOIN departments did
        ON did.department_id = s.department_id_from_source
    LEFT JOIN departments dname
        ON s.department_name IS NOT NULL
       AND LOWER(dname.department_name) = LOWER(s.department_name)
    LEFT JOIN employees e_existing
        ON (s.email IS NOT NULL AND e_existing.email = s.email)
)
SELECT
    COALESCE(r.existing_employee_id, m.max_employee_id + r.seq_for_new_ids) AS employee_id,
    r.first_name,
    r.last_name,
    r.email,
    r.hire_date,
    r.salary,
    r.resolved_department_id AS department_id,
    r.standardized_status,
    r.source_system,
    r.source_employee_id,
    r.resolved_department_name AS department_name,
    TIMESTAMPDIFF(YEAR, r.hire_date, CURDATE()) AS tenure_years,
    CASE
        WHEN r.salary < 40000 THEN 'L1'
        WHEN r.salary < 70000 THEN 'L2'
        WHEN r.salary < 100000 THEN 'L3'
        WHEN r.salary < 150000 THEN 'L4'
        ELSE 'L5'
    END AS salary_band,
    CASE
        WHEN TIMESTAMPDIFF(YEAR, r.hire_date, CURDATE()) < 2 THEN '0-1y'
        WHEN TIMESTAMPDIFF(YEAR, r.hire_date, CURDATE()) < 5 THEN '2-4y'
        WHEN TIMESTAMPDIFF(YEAR, r.hire_date, CURDATE()) < 10 THEN '5-9y'
        ELSE '10y+'
    END AS tenure_bucket,
    CASE
        WHEN r.salary IS NULL THEN 0
        ELSE ROUND(
            r.salary /
            NULLIF(AVG(r.salary) OVER (PARTITION BY r.resolved_department_id), 0),
            4
        )
    END AS compensation_index
FROM resolved r
CROSS JOIN max_emp m;

-- Upsert into canonical employee table.
INSERT INTO employees (
    employee_id,
    first_name,
    last_name,
    email,
    hire_date,
    salary,
    department_id,
    status,
    created_at
)
SELECT
    f.employee_id,
    f.first_name,
    f.last_name,
    f.email,
    f.hire_date,
    f.salary,
    f.department_id,
    f.standardized_status,
    NOW()
FROM tmp_employee_final f
ON DUPLICATE KEY UPDATE
    first_name = VALUES(first_name),
    last_name = VALUES(last_name),
    hire_date = VALUES(hire_date),
    salary = VALUES(salary),
    department_id = VALUES(department_id),
    status = VALUES(status);

-- Upsert enriched analytics-ready target.
INSERT INTO employee_enriched_target (
    employee_id,
    full_name,
    normalized_email,
    department_id,
    department_name,
    standardized_status,
    salary,
    salary_band,
    tenure_years,
    tenure_bucket,
    compensation_index,
    source_system,
    source_employee_id,
    etl_run_id,
    loaded_at
)
SELECT
    f.employee_id,
    CONCAT(f.first_name, ' ', f.last_name) AS full_name,
    f.email,
    f.department_id,
    f.department_name,
    f.standardized_status,
    f.salary,
    f.salary_band,
    f.tenure_years,
    f.tenure_bucket,
    f.compensation_index,
    f.source_system,
    f.source_employee_id,
    @run_id,
    NOW()
FROM tmp_employee_final f
ON DUPLICATE KEY UPDATE
    full_name = VALUES(full_name),
    normalized_email = VALUES(normalized_email),
    department_id = VALUES(department_id),
    department_name = VALUES(department_name),
    standardized_status = VALUES(standardized_status),
    salary = VALUES(salary),
    salary_band = VALUES(salary_band),
    tenure_years = VALUES(tenure_years),
    tenure_bucket = VALUES(tenure_bucket),
    compensation_index = VALUES(compensation_index),
    source_system = VALUES(source_system),
    source_employee_id = VALUES(source_employee_id),
    etl_run_id = VALUES(etl_run_id),
    loaded_at = VALUES(loaded_at);

-- Final run stats + completion.
UPDATE etl_run_audit
SET
    rejected_row_count = (
        SELECT COUNT(*)
        FROM etl_employee_rejects r
        WHERE r.run_id = @run_id
    ),
    loaded_row_count = (SELECT COUNT(*) FROM tmp_employee_final),
    finished_at = NOW(),
    status = 'SUCCESS',
    message = 'ETL completed with cleansing, dedupe, enrichment, and upsert.'
WHERE run_id = @run_id;

COMMIT;

-- Optional verification queries:
-- SELECT * FROM etl_run_audit WHERE run_id = @run_id;
-- SELECT * FROM etl_employee_rejects WHERE run_id = @run_id ORDER BY reject_id;
-- SELECT * FROM employee_enriched_target ORDER BY loaded_at DESC;
