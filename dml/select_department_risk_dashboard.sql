-- Department Performance + Risk Dashboard (MySQL 8+)
-- One large SELECT using multiple CTEs, joins, translations, and filters.
-- Tables: employees, departments, employee_enriched_target, etl_run_audit, etl_employee_rejects

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

active_run AS (
    SELECT
        l.run_id,
        l.started_at,
        l.finished_at,
        l.source_row_count,
        l.rejected_row_count,
        l.loaded_row_count
    FROM latest_success_run l
    WHERE l.rn = 1
),

enriched_latest AS (
    SELECT
        t.employee_id,
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

employee_profile AS (
    SELECT
        e.employee_id,
        e.first_name,
        e.last_name,
        CONCAT(e.first_name, ' ', e.last_name) AS employee_name,
        LOWER(e.email) AS normalized_email,
        e.department_id,
        e.hire_date,
        e.salary AS base_salary,
        e.status AS base_status,
        TIMESTAMPDIFF(YEAR, e.hire_date, CURDATE()) AS years_of_service,
        TIMESTAMPDIFF(MONTH, e.hire_date, CURDATE()) AS months_of_service
    FROM employees e
),

dept_geo AS (
    SELECT
        d.department_id,
        d.department_name,
        d.location,
        CASE
            WHEN LOWER(d.location) IN ('new york', 'nyc', 'manhattan') THEN 'North America - East'
            WHEN LOWER(d.location) IN ('san francisco', 'bay area', 'seattle') THEN 'North America - West'
            WHEN LOWER(d.location) IN ('london', 'berlin', 'paris', 'amsterdam') THEN 'Europe Cluster'
            WHEN LOWER(d.location) IN ('bangalore', 'pune', 'hyderabad', 'delhi') THEN 'India Cluster'
            WHEN d.location IS NULL OR TRIM(d.location) = '' THEN 'Unknown Geography'
            ELSE 'Other Geography'
        END AS geo_cluster
    FROM departments d
),

rejects_180d AS (
    SELECT
        r.source_system,
        r.source_employee_id,
        COUNT(*) AS reject_count_180d,
        MAX(r.rejected_at) AS last_reject_time,
        GROUP_CONCAT(DISTINCT r.rejection_reason ORDER BY r.rejection_reason SEPARATOR '; ') AS reject_reason_list
    FROM etl_employee_rejects r
    WHERE r.rejected_at >= DATE_SUB(NOW(), INTERVAL 180 DAY)
    GROUP BY r.source_system, r.source_employee_id
),

employee_fact AS (
    SELECT
        p.employee_id,
        p.employee_name,
        p.normalized_email,
        p.department_id,
        g.department_name,
        g.location,
        g.geo_cluster,
        p.hire_date,
        p.years_of_service,
        p.months_of_service,

        COALESCE(el.salary, p.base_salary) AS effective_salary,
        COALESCE(el.standardized_status, p.base_status) AS effective_status,
        COALESCE(el.salary_band,
            CASE
                WHEN p.base_salary < 40000 THEN 'L1'
                WHEN p.base_salary < 70000 THEN 'L2'
                WHEN p.base_salary < 100000 THEN 'L3'
                WHEN p.base_salary < 150000 THEN 'L4'
                ELSE 'L5'
            END
        ) AS effective_salary_band,
        COALESCE(el.tenure_bucket,
            CASE
                WHEN p.years_of_service < 2 THEN '0-1y'
                WHEN p.years_of_service < 5 THEN '2-4y'
                WHEN p.years_of_service < 10 THEN '5-9y'
                ELSE '10y+'
            END
        ) AS effective_tenure_bucket,

        el.compensation_index,
        el.source_system,
        el.source_employee_id,
        rj.reject_count_180d,
        rj.last_reject_time,
        rj.reject_reason_list,

        CASE
            WHEN UPPER(COALESCE(el.standardized_status, p.base_status)) IN ('ACTIVE') THEN 'Employee is Active'
            WHEN UPPER(COALESCE(el.standardized_status, p.base_status)) IN ('INACTIVE') THEN 'Employee is Inactive'
            WHEN UPPER(COALESCE(el.standardized_status, p.base_status)) IN ('ON LEAVE') THEN 'Employee is on Leave'
            ELSE 'Employee status Unknown'
        END AS translated_status,

        CASE
            WHEN p.years_of_service < 2 THEN 'Early Career'
            WHEN p.years_of_service BETWEEN 2 AND 6 THEN 'Mid Career'
            WHEN p.years_of_service BETWEEN 7 AND 12 THEN 'Senior Core'
            ELSE 'Legacy Expert'
        END AS translated_tenure_stage

    FROM employee_profile p
    LEFT JOIN dept_geo g
        ON g.department_id = p.department_id
    LEFT JOIN enriched_latest el
        ON el.employee_id = p.employee_id
       AND el.rn = 1
    LEFT JOIN rejects_180d rj
        ON rj.source_system = el.source_system
       AND rj.source_employee_id = el.source_employee_id
),

department_agg AS (
    SELECT
        ef.department_id,
        COALESCE(MAX(ef.department_name), 'Unknown') AS department_name,
        COALESCE(MAX(ef.location), 'N/A') AS location,
        COALESCE(MAX(ef.geo_cluster), 'Unknown Geography') AS geo_cluster,

        COUNT(*) AS total_employees,
        SUM(CASE WHEN UPPER(ef.effective_status) = 'ACTIVE' THEN 1 ELSE 0 END) AS active_employees,
        SUM(CASE WHEN UPPER(ef.effective_status) = 'ON LEAVE' THEN 1 ELSE 0 END) AS on_leave_employees,
        SUM(CASE WHEN UPPER(ef.effective_status) = 'INACTIVE' THEN 1 ELSE 0 END) AS inactive_employees,

        AVG(ef.effective_salary) AS avg_salary,
        MIN(ef.effective_salary) AS min_salary,
        MAX(ef.effective_salary) AS max_salary,
        STDDEV_POP(ef.effective_salary) AS salary_stddev,

        AVG(ef.years_of_service) AS avg_years_of_service,

        SUM(CASE WHEN ef.effective_salary_band IN ('L4', 'L5') THEN 1 ELSE 0 END) AS high_band_count,
        SUM(CASE WHEN ef.effective_tenure_bucket IN ('0-1y', '2-4y') THEN 1 ELSE 0 END) AS early_tenure_count,

        SUM(COALESCE(ef.reject_count_180d, 0)) AS total_rejects_180d,
        MAX(ef.last_reject_time) AS last_reject_time,

        ROUND(100 * SUM(CASE WHEN UPPER(ef.effective_status) = 'ACTIVE' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS active_ratio_pct,
        ROUND(100 * SUM(CASE WHEN ef.effective_salary_band IN ('L4', 'L5') THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS high_salary_band_pct,
        ROUND(100 * SUM(CASE WHEN ef.effective_tenure_bucket IN ('0-1y', '2-4y') THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS early_tenure_pct

    FROM employee_fact ef
    GROUP BY ef.department_id
),

department_scored AS (
    SELECT
        da.*,

        DENSE_RANK() OVER (ORDER BY da.avg_salary DESC) AS rank_by_avg_salary,
        DENSE_RANK() OVER (ORDER BY da.total_rejects_180d DESC) AS rank_by_data_rejects,
        DENSE_RANK() OVER (ORDER BY da.active_ratio_pct ASC) AS rank_by_low_activity,

        CASE
            WHEN da.total_rejects_180d >= 20 THEN 40
            WHEN da.total_rejects_180d BETWEEN 10 AND 19 THEN 25
            WHEN da.total_rejects_180d BETWEEN 5 AND 9 THEN 15
            ELSE 5
        END
        + CASE
            WHEN da.active_ratio_pct < 65 THEN 30
            WHEN da.active_ratio_pct < 80 THEN 20
            WHEN da.active_ratio_pct < 90 THEN 10
            ELSE 2
        END
        + CASE
            WHEN da.early_tenure_pct > 60 THEN 20
            WHEN da.early_tenure_pct > 40 THEN 12
            WHEN da.early_tenure_pct > 25 THEN 7
            ELSE 3
        END
        + CASE
            WHEN da.salary_stddev > 35000 THEN 15
            WHEN da.salary_stddev > 20000 THEN 10
            WHEN da.salary_stddev > 10000 THEN 5
            ELSE 2
        END AS risk_score_raw

    FROM department_agg da
),

final_dashboard AS (
    SELECT
        ds.department_id,
        ds.department_name,
        ds.location,
        ds.geo_cluster,

        ds.total_employees,
        ds.active_employees,
        ds.on_leave_employees,
        ds.inactive_employees,
        ds.active_ratio_pct,

        ROUND(ds.avg_salary, 2) AS avg_salary,
        ROUND(ds.min_salary, 2) AS min_salary,
        ROUND(ds.max_salary, 2) AS max_salary,
        ROUND(ds.salary_stddev, 2) AS salary_stddev,

        ROUND(ds.avg_years_of_service, 2) AS avg_years_of_service,
        ds.high_band_count,
        ds.high_salary_band_pct,
        ds.early_tenure_count,
        ds.early_tenure_pct,

        ds.total_rejects_180d,
        ds.last_reject_time,

        ds.rank_by_avg_salary,
        ds.rank_by_data_rejects,
        ds.rank_by_low_activity,

        ds.risk_score_raw,
        CASE
            WHEN ds.risk_score_raw >= 85 THEN 'Critical Risk'
            WHEN ds.risk_score_raw >= 60 THEN 'High Risk'
            WHEN ds.risk_score_raw >= 35 THEN 'Medium Risk'
            ELSE 'Low Risk'
        END AS risk_band,

        CASE
            WHEN ds.rank_by_data_rejects <= 3 THEN 'Audit ETL Mapping + Source Data Contracts'
            WHEN ds.rank_by_low_activity <= 3 THEN 'Workforce Stabilization Plan'
            WHEN ds.early_tenure_pct > 50 THEN 'Strengthen Onboarding and Mentoring'
            ELSE 'Maintain Current Governance'
        END AS recommended_action

    FROM department_scored ds
)

SELECT
    fd.department_id,
    fd.department_name,
    fd.location,
    fd.geo_cluster,

    fd.total_employees,
    fd.active_employees,
    fd.on_leave_employees,
    fd.inactive_employees,
    fd.active_ratio_pct,

    fd.avg_salary,
    fd.min_salary,
    fd.max_salary,
    fd.salary_stddev,
    fd.avg_years_of_service,

    fd.high_band_count,
    fd.high_salary_band_pct,
    fd.early_tenure_count,
    fd.early_tenure_pct,

    fd.total_rejects_180d,
    fd.last_reject_time,

    fd.rank_by_avg_salary,
    fd.rank_by_data_rejects,
    fd.rank_by_low_activity,

    fd.risk_score_raw,
    fd.risk_band,
    fd.recommended_action,

    ar.run_id AS latest_run_id,
    ar.started_at AS latest_run_start,
    ar.finished_at AS latest_run_end,
    ar.source_row_count,
    ar.rejected_row_count,
    ar.loaded_row_count,

    CASE
        WHEN ar.source_row_count > 0
            THEN ROUND(ar.rejected_row_count / ar.source_row_count * 100, 2)
        ELSE 0
    END AS latest_reject_rate_pct

FROM final_dashboard fd
CROSS JOIN active_run ar
WHERE
    fd.total_employees >= 2
    AND fd.active_ratio_pct >= 400
    AND fd.risk_band IN ('Medium Risk', 'High Risk', 'Critical Risk')
ORDER BY
    fd.risk_score_raw DESC,
    fd.total_rejects_180d DESC,
    fd.avg_salary DESC,
    fd.department_name;
