-- Complex and Large SELECT SQL (MySQL 8+)
-- Features used:
--   - Multiple CTEs
--   - Multi-table joins
--   - Column translation / business labels
--   - Window functions
--   - Advanced filters
--
-- Tables referenced:
--   employees, departments, employee_enriched_target, etl_run_audit, etl_employee_rejects

WITH
latest_success_run AS (
    SELECT
        a.run_id,
        a.started_at,
        a.finished_at,
        a.source_row_count,
        a.rejected_row_count,
        a.loaded_row_count,
        ROW_NUMBER() OVER (ORDER BY a.finished_at DESC, a.started_at DESC) AS rn
    FROM etl_run_audit a
    WHERE a.status = 'SUCCESS'
),

latest_enriched AS (
    SELECT
        t.employee_id,
        t.full_name,
        t.normalized_email,
        t.department_id,
        t.department_name,
        t.standardized_status,
        t.salary,
        t.salary_band,
        t.tenure_years,
        t.tenure_bucket,
        t.compensation_index,
        t.source_system,
        t.source_employee_id,
        t.etl_run_id,
        t.loaded_at,
        ROW_NUMBER() OVER (
            PARTITION BY t.employee_id
            ORDER BY t.loaded_at DESC
        ) AS rn
    FROM employee_enriched_target t
),

dept_reference AS (
    SELECT
        d.department_id,
        d.department_name,
        d.location,
        d.manager_id,
        CASE
            WHEN LOWER(d.location) IN ('new york', 'nyc', 'manhattan') THEN 'US-East'
            WHEN LOWER(d.location) IN ('san francisco', 'bay area', 'seattle') THEN 'US-West'
            WHEN LOWER(d.location) IN ('london', 'berlin', 'paris', 'amsterdam') THEN 'Europe'
            WHEN LOWER(d.location) IN ('bangalore', 'pune', 'hyderabad', 'delhi') THEN 'India'
            WHEN d.location IS NULL OR TRIM(d.location) = '' THEN 'Unknown Region'
            ELSE 'Other Region'
        END AS geo_region
    FROM departments d
),

employee_base AS (
    SELECT
        e.employee_id,
        e.first_name,
        e.last_name,
        CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
        LOWER(e.email) AS email,
        e.hire_date,
        e.salary AS current_salary,
        e.department_id,
        e.status,
        e.created_at,
        TIMESTAMPDIFF(YEAR, e.hire_date, CURDATE()) AS service_years,
        TIMESTAMPDIFF(MONTH, e.hire_date, CURDATE()) AS service_months
    FROM employees e
),

reject_stats_90d AS (
    SELECT
        r.source_system,
        r.source_employee_id,
        COUNT(*) AS reject_count_90d,
        MAX(r.rejected_at) AS last_rejected_at,
        GROUP_CONCAT(DISTINCT r.rejection_reason ORDER BY r.rejection_reason SEPARATOR '; ') AS reject_reasons
    FROM etl_employee_rejects r
    WHERE r.rejected_at >= DATE_SUB(NOW(), INTERVAL 90 DAY)
    GROUP BY r.source_system, r.source_employee_id
),

dept_salary_stats AS (
    SELECT
        b.department_id,
        COUNT(*) AS dept_employee_count,
        AVG(b.current_salary) AS dept_avg_salary,
        MIN(b.current_salary) AS dept_min_salary,
        MAX(b.current_salary) AS dept_max_salary,
        STDDEV_POP(b.current_salary) AS dept_salary_stddev
    FROM employee_base b
    GROUP BY b.department_id
),

joined_model AS (
    SELECT
        b.employee_id,
        b.employee_name,
        b.email,
        b.hire_date,
        b.current_salary,
        b.department_id,
        b.status,
        b.service_years,
        b.service_months,

        dr.department_name,
        dr.location,
        dr.geo_region,

        le.full_name AS enriched_full_name,
        le.normalized_email AS enriched_email,
        le.standardized_status,
        le.salary AS enriched_salary,
        le.salary_band,
        le.tenure_years AS enriched_tenure_years,
        le.tenure_bucket,
        le.compensation_index,
        le.source_system,
        le.source_employee_id,
        le.etl_run_id,
        le.loaded_at,

        ds.dept_employee_count,
        ds.dept_avg_salary,
        ds.dept_min_salary,
        ds.dept_max_salary,
        ds.dept_salary_stddev,

        rs.reject_count_90d,
        rs.last_rejected_at,
        rs.reject_reasons,

        CASE
            WHEN UPPER(COALESCE(le.standardized_status, b.status)) = 'ACTIVE' THEN 'Working'
            WHEN UPPER(COALESCE(le.standardized_status, b.status)) = 'INACTIVE' THEN 'Separated'
            WHEN UPPER(COALESCE(le.standardized_status, b.status)) = 'ON LEAVE' THEN 'Temporarily Away'
            ELSE 'Unknown Status'
        END AS status_label,

        CASE
            WHEN COALESCE(le.salary, b.current_salary) < 40000 THEN 'Entry'
            WHEN COALESCE(le.salary, b.current_salary) < 70000 THEN 'Associate'
            WHEN COALESCE(le.salary, b.current_salary) < 100000 THEN 'Specialist'
            WHEN COALESCE(le.salary, b.current_salary) < 150000 THEN 'Lead'
            ELSE 'Executive'
        END AS compensation_tier,

        CASE
            WHEN b.service_years < 2 THEN 'New Hire'
            WHEN b.service_years BETWEEN 2 AND 4 THEN 'Growing Contributor'
            WHEN b.service_years BETWEEN 5 AND 9 THEN 'Experienced Core'
            ELSE 'Long Tenure'
        END AS tenure_classification,

        DENSE_RANK() OVER (
            PARTITION BY b.department_id
            ORDER BY COALESCE(le.salary, b.current_salary) DESC
        ) AS dept_salary_rank,

        NTILE(4) OVER (
            PARTITION BY b.department_id
            ORDER BY COALESCE(le.salary, b.current_salary)
        ) AS dept_salary_quartile,

        ROUND(
            (COALESCE(le.salary, b.current_salary) - ds.dept_avg_salary)
            / NULLIF(ds.dept_avg_salary, 0) * 100,
            2
        ) AS pct_vs_dept_avg,

        CASE
            WHEN rs.reject_count_90d IS NULL THEN 'Clean Feed'
            WHEN rs.reject_count_90d BETWEEN 1 AND 2 THEN 'Minor Data Issues'
            WHEN rs.reject_count_90d BETWEEN 3 AND 5 THEN 'Moderate Data Issues'
            ELSE 'Severe Data Issues'
        END AS source_quality_band

    FROM employee_base b
    LEFT JOIN dept_reference dr
        ON dr.department_id = b.department_id
    LEFT JOIN latest_enriched le
        ON le.employee_id = b.employee_id
       AND le.rn = 1
    LEFT JOIN dept_salary_stats ds
        ON ds.department_id = b.department_id
    LEFT JOIN reject_stats_90d rs
        ON rs.source_system = le.source_system
       AND rs.source_employee_id = le.source_employee_id
)

SELECT
    jm.employee_id AS employee_key,
    jm.employee_name,
    COALESCE(jm.enriched_email, jm.email) AS normalized_email,

    jm.department_id,
    jm.department_name,
    jm.location AS department_location,
    jm.geo_region,

    jm.hire_date,
    jm.service_years,
    jm.service_months,
    jm.tenure_classification,

    COALESCE(jm.enriched_salary, jm.current_salary) AS effective_salary,
    jm.salary_band,
    jm.compensation_tier,
    jm.dept_salary_rank,
    jm.dept_salary_quartile,
    jm.pct_vs_dept_avg,
    jm.dept_avg_salary,
    jm.dept_min_salary,
    jm.dept_max_salary,

    COALESCE(jm.standardized_status, jm.status) AS effective_status,
    jm.status_label,

    jm.compensation_index,
    jm.source_system,
    jm.source_employee_id,
    jm.source_quality_band,
    COALESCE(jm.reject_count_90d, 0) AS reject_count_90d,
    jm.last_rejected_at,
    jm.reject_reasons,

    ls.run_id AS latest_success_run_id,
    ls.started_at AS latest_run_started_at,
    ls.finished_at AS latest_run_finished_at,
    ls.source_row_count AS latest_run_source_rows,
    ls.rejected_row_count AS latest_run_rejected_rows,
    ls.loaded_row_count AS latest_run_loaded_rows,

    CASE
        WHEN jm.dept_salary_rank = 1 THEN 'Top Earner in Department'
        WHEN jm.dept_salary_quartile = 4 THEN 'Upper Salary Quartile'
        WHEN jm.dept_salary_quartile = 1 THEN 'Lower Salary Quartile'
        ELSE 'Mid Salary Band'
    END AS salary_position_label,

    CASE
        WHEN jm.service_years >= 10 AND COALESCE(jm.enriched_salary, jm.current_salary) >= jm.dept_avg_salary THEN 'Retain-HighPriority'
        WHEN jm.service_years < 2 AND COALESCE(jm.enriched_salary, jm.current_salary) < jm.dept_avg_salary THEN 'Develop-NewTalent'
        WHEN jm.source_quality_band IN ('Moderate Data Issues', 'Severe Data Issues') THEN 'Investigate-DataQuality'
        ELSE 'Monitor-Regular'
    END AS recommended_hr_action

FROM joined_model jm
CROSS JOIN (
    SELECT
        run_id,
        started_at,
        finished_at,
        source_row_count,
        rejected_row_count,
        loaded_row_count
    FROM latest_success_run
    WHERE rn = 1
) ls
WHERE
    COALESCE(jm.standardized_status, jm.status) IN ('Active', 'ACTIVE', 'On Leave', 'ON LEAVE')
    AND COALESCE(jm.enriched_salary, jm.current_salary) >= 100
    AND jm.service_months >= 6
    AND (
        jm.geo_region IN ('US-East', 'US-West', 'Europe', 'India')
        OR jm.geo_region = 'Other Region'
    )
    AND (
        jm.reject_count_90d IS NULL
        OR jm.reject_count_90d <= 10
    )
ORDER BY
    jm.geo_region,
    jm.department_name,
    effective_salary DESC,
    jm.employee_name;
