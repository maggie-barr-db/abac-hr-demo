-- ============================================================================
-- abac-hr-demo / 08: gold views + comp metric view (what Genie and the app query)
-- Templated: {{catalog}}
--
-- Gold objects are NOT tagged and carry no policies of their own. Protection comes
-- from the ABAC policies on the silver tables they read, evaluated for the person
-- querying. ABAC policies can't attach to a metric view, and tags don't flow down
-- to it, so the metric view is protected entirely by its sources.
-- ============================================================================

-- Directory: one row per employee with department name (mix of tiers)
CREATE OR REPLACE VIEW {{catalog}}.glb_gold.employee_directory
COMMENT 'Employee directory with department names. Sensitive columns are masked by policies on glb_silver.'
AS
SELECT
  e.employee_id, e.full_name, e.work_email, e.job_title, e.job_level,
  e.dept_id, d.dept_name, e.manager_id, e.country, e.hire_date,
  e.home_address, e.personal_phone, e.date_of_birth, e.ssn
FROM {{catalog}}.glb_silver.employees e
JOIN {{catalog}}.glb_silver.departments d ON d.dept_id = e.dept_id;

-- Workforce summary: headcount by department, country, level (internal data only)
CREATE OR REPLACE VIEW {{catalog}}.glb_gold.workforce_summary
COMMENT 'Headcount by department, country and job level'
AS
SELECT d.dept_name, e.dept_id, e.country, e.job_level, count(*) AS headcount
FROM {{catalog}}.glb_silver.employees e
JOIN {{catalog}}.glb_silver.departments d ON d.dept_id = e.dept_id
GROUP BY ALL;

-- Comp detail: one row per employee with total comp (crosses the tr and glb sub-domains)
CREATE OR REPLACE VIEW {{catalog}}.tr_gold.employee_comp
COMMENT 'Per-employee compensation with total comp = base + bonus target + equity grant'
AS
SELECT
  c.employee_id, e.full_name, e.job_title, e.job_level, c.dept_id, d.dept_name, c.country,
  c.base_salary, c.bonus_target, c.equity_grant,
  c.base_salary + c.bonus_target + c.equity_grant AS total_comp,
  c.currency
FROM {{catalog}}.tr_silver.compensation c
JOIN {{catalog}}.glb_silver.employees e   ON e.employee_id = c.employee_id
JOIN {{catalog}}.glb_silver.departments d ON d.dept_id = c.dept_id;

-- Metric view: governed comp metrics (VERIFY: YAML version; use 0.1 if 1.1 is rejected)
CREATE OR REPLACE VIEW {{catalog}}.tr_gold.mv_total_comp
WITH METRICS
LANGUAGE YAML
COMMENT 'Total compensation metrics (base + bonus target + equity). Comp measures respect the masks on tr_silver.compensation.'
AS $$
version: 1.1
source: {{catalog}}.tr_silver.compensation
joins:
  - name: emp
    source: {{catalog}}.glb_silver.employees
    on: source.employee_id = emp.employee_id
  - name: dept
    source: {{catalog}}.glb_silver.departments
    on: source.dept_id = dept.dept_id
dimensions:
  - name: department
    expr: dept.dept_name
  - name: dept_id
    expr: source.dept_id
  - name: country
    expr: source.country
  - name: job_level
    expr: emp.job_level
  - name: hire_year_band
    expr: "CASE WHEN year(emp.hire_date) < 2015 THEN 'Before 2015' WHEN year(emp.hire_date) < 2020 THEN '2015-2019' ELSE '2020 or later' END"
measures:
  - name: headcount
    expr: COUNT(1)
  - name: total_base_salary
    expr: SUM(source.base_salary)
  - name: avg_base_salary
    expr: AVG(source.base_salary)
  - name: total_bonus_target
    expr: SUM(source.bonus_target)
  - name: total_comp
    expr: SUM(source.base_salary + source.bonus_target + source.equity_grant)
  - name: avg_total_comp
    expr: AVG(source.base_salary + source.bonus_target + source.equity_grant)
  - name: max_total_comp
    expr: MAX(source.base_salary + source.bonus_target + source.equity_grant)
$$;

-- Check (as whoever runs this; with no override that's hr_analyst, so comp measures are NULL)
SELECT department,
       MEASURE(headcount)      AS headcount,
       MEASURE(avg_total_comp) AS avg_total_comp,
       MEASURE(max_total_comp) AS max_total_comp
FROM {{catalog}}.tr_gold.mv_total_comp
GROUP BY department
ORDER BY department;
