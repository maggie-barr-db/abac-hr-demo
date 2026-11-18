-- Databricks notebook source
-- MAGIC %md # ABAC HR demo walkthrough
-- MAGIC Synthetic HR data. One governed tag (`hr_pii_demo_tag`) with four sensitivity levels, plus a department scope tag, drives **four policies set once at the catalog level**. Every table, view, metric view and raw extract below is protected by those four policies, with no per-table rules.
-- MAGIC
-- MAGIC **How to use:** set the catalog in the next cell, then **Run all** and scroll. Each section switches to one persona, runs the same queries, then runs that persona's pressure tests. The last section compares all four personas side by side.
-- MAGIC
-- MAGIC Personas are switched with a demo-only override table (`glb_governance.persona_override`). In production, group membership and the department-head entitlements decide the persona, and the override table doesn't exist (anyone who can write to it could grant themselves access).

-- COMMAND ----------

-- Set the demo catalog for this session
USE CATALOG mbarrett_hr_demo_aws_sandbox_catalog;

-- COMMAND ----------

-- MAGIC %md ## How it works: four policies, set once
-- MAGIC The policies match columns by tag, not by name. A new table is protected as soon as its columns are tagged.

-- COMMAND ----------

SHOW POLICIES ON CATALOG mbarrett_hr_demo_aws_sandbox_catalog;

-- COMMAND ----------

-- The tags on one table: each column carries a sensitivity tier; dept_id also carries the scope tag
SELECT column_name, tag_name, tag_value
FROM information_schema.column_tags
WHERE schema_name = 'glb_silver' AND table_name = 'employees'
ORDER BY tag_name, tag_value, column_name;

-- COMMAND ----------

-- MAGIC %md ## Persona 1: HR analyst (non-trusted, the default)
-- MAGIC Sees every row, but only **internal** data in clear. Confidential, restricted and highly restricted columns are masked: text shows `****`, numbers and dates show NULL, so aggregates and filters return nothing.

-- COMMAND ----------

-- Switch persona (demo override)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'hr_analyst', NULL);

-- COMMAND ----------

-- Who am I right now?
SELECT current_user() AS user_name, glb_governance.current_persona() AS persona, glb_governance.current_scope_dept() AS scope_dept;

-- COMMAND ----------

-- 1. Employee directory: four tiers side by side
--    internal: name, title, department | restricted: home address, DOB | highly_restricted: SSN
SELECT employee_id, full_name, job_title, dept_name, home_address, date_of_birth, ssn
FROM glb_gold.employee_directory
WHERE employee_id IN ('W00001','W00002','W00004','W00025','W00040','W00103')
ORDER BY employee_id;

-- COMMAND ----------

-- 2. Compensation: who earns the most, and how much? (the question Genie gets asked)
SELECT full_name, job_title, dept_name, base_salary, bonus_target, equity_grant, total_comp
FROM tr_gold.employee_comp
ORDER BY total_comp DESC NULLS LAST
LIMIT 5;

-- COMMAND ----------

-- 3. Average total comp by department (what can this persona see in aggregate?)
SELECT dept_name, count(*) AS headcount, round(avg(total_comp), 0) AS avg_total_comp, max(total_comp) AS max_total_comp
FROM tr_gold.employee_comp
GROUP BY dept_name
ORDER BY dept_name;

-- COMMAND ----------

-- 4. Highly restricted: medical leave reasons and employee-relations case notes
SELECT 'leave' AS source, employee_id, dept_id, leave_type, medical_leave_reason AS detail
FROM glb_silver.leave_records WHERE leave_type LIKE 'FMLA%'
UNION ALL
SELECT 'er_case', employee_id, dept_id, case_type, investigation_notes
FROM glb_silver.employee_relations
ORDER BY source, employee_id
LIMIT 8;

-- COMMAND ----------

-- 5. Metric view: governed total comp metrics (protected entirely by the policies on its sources)
SELECT department, MEASURE(headcount) AS headcount, MEASURE(avg_total_comp) AS avg_total_comp, MEASURE(max_total_comp) AS max_total_comp
FROM tr_gold.mv_total_comp
GROUP BY department
ORDER BY department;

-- COMMAND ----------

-- 6. Side door: the same data straight from the raw bronze extract
SELECT w.worker_id, w.first_name, w.last_name, w.org_id, w.ssn, c.base_salary
FROM glb_bronze.hris_workers_raw w
JOIN tr_bronze.hris_comp_raw c ON c.worker_id = w.worker_id
WHERE w.worker_id IN ('W00001','W00002','W00004','W00025')
ORDER BY w.worker_id;

-- COMMAND ----------

-- MAGIC %md ### Pressure tests: HR analyst (non-trusted, the default)
-- MAGIC The SQL equivalents of the riskiest Genie questions. Every row should show `pass = true`.

-- COMMAND ----------

-- Pressure tests for hr_analyst
SELECT 'hr_analyst' AS persona, 'T01' AS test_id, 'Direct ask: highest total comp' AS description,
       CAST(max(total_comp) AS STRING) AS observed, 'NULL' AS expected, max(total_comp) IS NULL AS pass
  FROM tr_gold.employee_comp
UNION ALL
SELECT 'hr_analyst' AS persona, 'T02' AS test_id, 'Aggregate: departments with a visible avg base' AS description,
       CAST(count_if(a IS NOT NULL) AS STRING) AS observed, '0' AS expected, count_if(a IS NOT NULL) = 0 AS pass
  FROM (SELECT dept_id, avg(base_salary) a FROM tr_silver.compensation GROUP BY dept_id)
UNION ALL
SELECT 'hr_analyst' AS persona, 'T03' AS test_id, 'Inference via filter: count with base > 500K' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM tr_silver.compensation WHERE base_salary > 500000
UNION ALL
SELECT 'hr_analyst' AS persona, 'T04' AS test_id, 'Small group: avg base in CEO office (n=3)' AS description,
       CAST(avg(base_salary) AS STRING) AS observed, 'NULL' AS expected, avg(base_salary) IS NULL AS pass
  FROM tr_silver.compensation WHERE dept_id = 'D00'
UNION ALL
SELECT 'hr_analyst' AS persona, 'T05' AS test_id, 'Top-N: visible bonus values among top 10' AS description,
       CAST(count(bonus_target) AS STRING) AS observed, '0' AS expected, count(bonus_target) = 0 AS pass
  FROM (SELECT bonus_target FROM tr_silver.compensation ORDER BY bonus_target DESC NULLS LAST LIMIT 10)
UNION ALL
SELECT 'hr_analyst' AS persona, 'T07' AS test_id, 'Metadata: comp column names visible (expected, names are not data)' AS description,
       CAST(count(*) AS STRING) AS observed, '4' AS expected, count(*) = 4 AS pass
  FROM information_schema.columns WHERE table_schema = 'tr_silver' AND table_name = 'compensation' AND column_name IN ('base_salary','bonus_target','equity_grant','comp_grade')
UNION ALL
SELECT 'hr_analyst' AS persona, 'T11' AS test_id, 'Scope: rows visible (analyst sees all rows, masked)' AS description,
       CAST(count(*) AS STRING) AS observed, '2000' AS expected, count(*) = 2000 AS pass
  FROM glb_silver.employees
UNION ALL
SELECT 'hr_analyst' AS persona, 'T12' AS test_id, 'Metric view: max total comp measure' AS description,
       CAST(MEASURE(max_total_comp) AS STRING) AS observed, 'NULL' AS expected, MEASURE(max_total_comp) IS NULL AS pass
  FROM tr_gold.mv_total_comp
UNION ALL
SELECT 'hr_analyst' AS persona, 'T13' AS test_id, 'Tier 4: SSNs visible in clear' AS description,
       CAST(count_if(ssn <> '****') AS STRING) AS observed, '0' AS expected, count_if(ssn <> '****') = 0 AS pass
  FROM glb_silver.employees
UNION ALL
SELECT 'hr_analyst' AS persona, 'T14' AS test_id, 'Side door: bronze raw comp visible' AS description,
       CAST(count_if(base_salary <> '****') AS STRING) AS observed, '0' AS expected, count_if(base_salary <> '****') = 0 AS pass
  FROM tr_bronze.hris_comp_raw
ORDER BY test_id;

-- COMMAND ----------

-- MAGIC %md ## Persona 2: Department head: Finance (D10)
-- MAGIC Sees **only their department subtree** (Finance, FP&A, Treasury), with internal, confidential and restricted data in clear for their own people. Highly restricted data (SSN, medical, ER) stays masked. The CEO never appears.

-- COMMAND ----------

-- Switch persona (demo override)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'dept_head', 'D10');

-- COMMAND ----------

-- Who am I right now?
SELECT current_user() AS user_name, glb_governance.current_persona() AS persona, glb_governance.current_scope_dept() AS scope_dept;

-- COMMAND ----------

-- 1. Employee directory: four tiers side by side
--    internal: name, title, department | restricted: home address, DOB | highly_restricted: SSN
SELECT employee_id, full_name, job_title, dept_name, home_address, date_of_birth, ssn
FROM glb_gold.employee_directory
WHERE employee_id IN ('W00001','W00002','W00004','W00025','W00040','W00103')
ORDER BY employee_id;

-- COMMAND ----------

-- 2. Compensation: who earns the most, and how much? (the question Genie gets asked)
SELECT full_name, job_title, dept_name, base_salary, bonus_target, equity_grant, total_comp
FROM tr_gold.employee_comp
ORDER BY total_comp DESC NULLS LAST
LIMIT 5;

-- COMMAND ----------

-- 3. Average total comp by department (what can this persona see in aggregate?)
SELECT dept_name, count(*) AS headcount, round(avg(total_comp), 0) AS avg_total_comp, max(total_comp) AS max_total_comp
FROM tr_gold.employee_comp
GROUP BY dept_name
ORDER BY dept_name;

-- COMMAND ----------

-- 4. Highly restricted: medical leave reasons and employee-relations case notes
SELECT 'leave' AS source, employee_id, dept_id, leave_type, medical_leave_reason AS detail
FROM glb_silver.leave_records WHERE leave_type LIKE 'FMLA%'
UNION ALL
SELECT 'er_case', employee_id, dept_id, case_type, investigation_notes
FROM glb_silver.employee_relations
ORDER BY source, employee_id
LIMIT 8;

-- COMMAND ----------

-- 5. Metric view: governed total comp metrics (protected entirely by the policies on its sources)
SELECT department, MEASURE(headcount) AS headcount, MEASURE(avg_total_comp) AS avg_total_comp, MEASURE(max_total_comp) AS max_total_comp
FROM tr_gold.mv_total_comp
GROUP BY department
ORDER BY department;

-- COMMAND ----------

-- 6. Side door: the same data straight from the raw bronze extract
SELECT w.worker_id, w.first_name, w.last_name, w.org_id, w.ssn, c.base_salary
FROM glb_bronze.hris_workers_raw w
JOIN tr_bronze.hris_comp_raw c ON c.worker_id = w.worker_id
WHERE w.worker_id IN ('W00001','W00002','W00004','W00025')
ORDER BY w.worker_id;

-- COMMAND ----------

-- MAGIC %md ### Pressure tests: Department head: Finance (D10)
-- MAGIC The SQL equivalents of the riskiest Genie questions. Every row should show `pass = true`.

-- COMMAND ----------

-- Pressure tests for dept_head:D10
SELECT 'dept_head:D10' AS persona, 'T01' AS test_id, 'Direct ask: highest total comp = Finance max, not the CEO' AS description,
       CAST(max(total_comp) AS STRING) AS observed, '820052.00' AS expected, max(total_comp) = 820052 AS pass
  FROM tr_gold.employee_comp
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T03' AS test_id, 'Inference via filter: count with base > 500K (CEO is outside scope)' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM tr_silver.compensation WHERE base_salary > 500000
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T04' AS test_id, 'Small group: CEO office rows reachable' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM tr_silver.compensation WHERE dept_id = 'D00'
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T11a' AS test_id, 'Scope: departments visible' AS description,
       CAST(array_join(array_sort(collect_set(dept_id)), ',') AS STRING) AS observed, 'D10,D11,D12' AS expected, array_join(array_sort(collect_set(dept_id)), ',') = 'D10,D11,D12' AS pass
  FROM glb_silver.employees
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T11b' AS test_id, 'Scope: global payroll equals subtree payroll' AS description,
       CAST(sum(base_salary) AS STRING) AS observed, '= sum for D10,D11,D12' AS expected, sum(base_salary) = sum(CASE WHEN dept_id IN ('D10','D11','D12') THEN base_salary END) AS pass
  FROM tr_silver.compensation
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T12' AS test_id, 'Metric view headcount = visible employees' AS description,
       CAST(MEASURE(headcount) AS STRING) AS observed, '= employees visible' AS expected, MEASURE(headcount) = (SELECT count(*) FROM glb_silver.employees) AS pass
  FROM tr_gold.mv_total_comp
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T13' AS test_id, 'Tier 4: SSNs visible in clear' AS description,
       CAST(count_if(ssn <> '****') AS STRING) AS observed, '0' AS expected, count_if(ssn <> '****') = 0 AS pass
  FROM glb_silver.employees
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T13b' AS test_id, 'Tier 4: medical leave reasons visible' AS description,
       CAST(count_if(medical_leave_reason <> '****') AS STRING) AS observed, '0' AS expected, count_if(medical_leave_reason <> '****') = 0 AS pass
  FROM glb_silver.leave_records
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T14' AS test_id, 'Side door: bronze rows outside subtree' AS description,
       CAST(count_if(org_id NOT IN ('D10','D11','D12')) AS STRING) AS observed, '0' AS expected, count_if(org_id NOT IN ('D10','D11','D12')) = 0 AS pass
  FROM glb_bronze.hris_workers_raw
ORDER BY test_id;

-- COMMAND ----------

-- MAGIC %md ## Persona 3: HR trusted (HR business partner)
-- MAGIC Sees every row with internal, confidential and restricted data in clear, including comp. **Highly restricted data is still masked**: trust isn't all-or-nothing.

-- COMMAND ----------

-- Switch persona (demo override)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'hr_trusted', NULL);

-- COMMAND ----------

-- Who am I right now?
SELECT current_user() AS user_name, glb_governance.current_persona() AS persona, glb_governance.current_scope_dept() AS scope_dept;

-- COMMAND ----------

-- 1. Employee directory: four tiers side by side
--    internal: name, title, department | restricted: home address, DOB | highly_restricted: SSN
SELECT employee_id, full_name, job_title, dept_name, home_address, date_of_birth, ssn
FROM glb_gold.employee_directory
WHERE employee_id IN ('W00001','W00002','W00004','W00025','W00040','W00103')
ORDER BY employee_id;

-- COMMAND ----------

-- 2. Compensation: who earns the most, and how much? (the question Genie gets asked)
SELECT full_name, job_title, dept_name, base_salary, bonus_target, equity_grant, total_comp
FROM tr_gold.employee_comp
ORDER BY total_comp DESC NULLS LAST
LIMIT 5;

-- COMMAND ----------

-- 3. Average total comp by department (what can this persona see in aggregate?)
SELECT dept_name, count(*) AS headcount, round(avg(total_comp), 0) AS avg_total_comp, max(total_comp) AS max_total_comp
FROM tr_gold.employee_comp
GROUP BY dept_name
ORDER BY dept_name;

-- COMMAND ----------

-- 4. Highly restricted: medical leave reasons and employee-relations case notes
SELECT 'leave' AS source, employee_id, dept_id, leave_type, medical_leave_reason AS detail
FROM glb_silver.leave_records WHERE leave_type LIKE 'FMLA%'
UNION ALL
SELECT 'er_case', employee_id, dept_id, case_type, investigation_notes
FROM glb_silver.employee_relations
ORDER BY source, employee_id
LIMIT 8;

-- COMMAND ----------

-- 5. Metric view: governed total comp metrics (protected entirely by the policies on its sources)
SELECT department, MEASURE(headcount) AS headcount, MEASURE(avg_total_comp) AS avg_total_comp, MEASURE(max_total_comp) AS max_total_comp
FROM tr_gold.mv_total_comp
GROUP BY department
ORDER BY department;

-- COMMAND ----------

-- 6. Side door: the same data straight from the raw bronze extract
SELECT w.worker_id, w.first_name, w.last_name, w.org_id, w.ssn, c.base_salary
FROM glb_bronze.hris_workers_raw w
JOIN tr_bronze.hris_comp_raw c ON c.worker_id = w.worker_id
WHERE w.worker_id IN ('W00001','W00002','W00004','W00025')
ORDER BY w.worker_id;

-- COMMAND ----------

-- MAGIC %md ### Pressure tests: HR trusted (HR business partner)
-- MAGIC The SQL equivalents of the riskiest Genie questions. Every row should show `pass = true`.

-- COMMAND ----------

-- Pressure tests for hr_trusted
SELECT 'hr_trusted' AS persona, 'T01' AS test_id, 'Control: highest total comp is the CEO' AS description,
       CAST(max(total_comp) AS STRING) AS observed, '8000000.00' AS expected, max(total_comp) = 8000000 AS pass
  FROM tr_gold.employee_comp
UNION ALL
SELECT 'hr_trusted' AS persona, 'T03' AS test_id, 'Control: count with base > 500K' AS description,
       CAST(count(*) AS STRING) AS observed, '1' AS expected, count(*) = 1 AS pass
  FROM tr_silver.compensation WHERE base_salary > 500000
UNION ALL
SELECT 'hr_trusted' AS persona, 'T13' AS test_id, 'Tier 4 still masked for HR trusted: SSNs in clear' AS description,
       CAST(count_if(ssn <> '****') AS STRING) AS observed, '0' AS expected, count_if(ssn <> '****') = 0 AS pass
  FROM glb_silver.employees
UNION ALL
SELECT 'hr_trusted' AS persona, 'T13b' AS test_id, 'Tier 4 still masked: medical leave reasons' AS description,
       CAST(count_if(medical_leave_reason <> '****') AS STRING) AS observed, '0' AS expected, count_if(medical_leave_reason <> '****') = 0 AS pass
  FROM glb_silver.leave_records
ORDER BY test_id;

-- COMMAND ----------

-- MAGIC %md ## Persona 4: ER / Legal / Benefits
-- MAGIC Sees everything, including SSNs, medical leave reasons and employee-relations case notes.

-- COMMAND ----------

-- Switch persona (demo override)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'er_legal', NULL);

-- COMMAND ----------

-- Who am I right now?
SELECT current_user() AS user_name, glb_governance.current_persona() AS persona, glb_governance.current_scope_dept() AS scope_dept;

-- COMMAND ----------

-- 1. Employee directory: four tiers side by side
--    internal: name, title, department | restricted: home address, DOB | highly_restricted: SSN
SELECT employee_id, full_name, job_title, dept_name, home_address, date_of_birth, ssn
FROM glb_gold.employee_directory
WHERE employee_id IN ('W00001','W00002','W00004','W00025','W00040','W00103')
ORDER BY employee_id;

-- COMMAND ----------

-- 2. Compensation: who earns the most, and how much? (the question Genie gets asked)
SELECT full_name, job_title, dept_name, base_salary, bonus_target, equity_grant, total_comp
FROM tr_gold.employee_comp
ORDER BY total_comp DESC NULLS LAST
LIMIT 5;

-- COMMAND ----------

-- 3. Average total comp by department (what can this persona see in aggregate?)
SELECT dept_name, count(*) AS headcount, round(avg(total_comp), 0) AS avg_total_comp, max(total_comp) AS max_total_comp
FROM tr_gold.employee_comp
GROUP BY dept_name
ORDER BY dept_name;

-- COMMAND ----------

-- 4. Highly restricted: medical leave reasons and employee-relations case notes
SELECT 'leave' AS source, employee_id, dept_id, leave_type, medical_leave_reason AS detail
FROM glb_silver.leave_records WHERE leave_type LIKE 'FMLA%'
UNION ALL
SELECT 'er_case', employee_id, dept_id, case_type, investigation_notes
FROM glb_silver.employee_relations
ORDER BY source, employee_id
LIMIT 8;

-- COMMAND ----------

-- 5. Metric view: governed total comp metrics (protected entirely by the policies on its sources)
SELECT department, MEASURE(headcount) AS headcount, MEASURE(avg_total_comp) AS avg_total_comp, MEASURE(max_total_comp) AS max_total_comp
FROM tr_gold.mv_total_comp
GROUP BY department
ORDER BY department;

-- COMMAND ----------

-- 6. Side door: the same data straight from the raw bronze extract
SELECT w.worker_id, w.first_name, w.last_name, w.org_id, w.ssn, c.base_salary
FROM glb_bronze.hris_workers_raw w
JOIN tr_bronze.hris_comp_raw c ON c.worker_id = w.worker_id
WHERE w.worker_id IN ('W00001','W00002','W00004','W00025')
ORDER BY w.worker_id;

-- COMMAND ----------

-- MAGIC %md ### Pressure tests: ER / Legal / Benefits
-- MAGIC The SQL equivalents of the riskiest Genie questions. Every row should show `pass = true`.

-- COMMAND ----------

-- Pressure tests for er_legal
SELECT 'er_legal' AS persona, 'T13' AS test_id, 'Control: SSNs in clear for ER/Legal' AS description,
       CAST(count_if(ssn <> '****') AS STRING) AS observed, '2000' AS expected, count_if(ssn <> '****') = 2000 AS pass
  FROM glb_silver.employees
UNION ALL
SELECT 'er_legal' AS persona, 'T13b' AS test_id, 'Control: medical leave reasons visible' AS description,
       CAST(count_if(medical_leave_reason IS NOT NULL AND medical_leave_reason <> '****') AS STRING) AS observed, '> 0' AS expected, count_if(medical_leave_reason IS NOT NULL AND medical_leave_reason <> '****') > 0 AS pass
  FROM glb_silver.leave_records
ORDER BY test_id;

-- COMMAND ----------

-- MAGIC %md ## Side by side: all four personas
-- MAGIC Runs the same checks as each persona and records **labels only** (not the sensitive values themselves), so the comparison table holds nothing that needs protecting.

-- COMMAND ----------

CREATE OR REPLACE TABLE glb_governance.demo_persona_comparison (
  persona STRING, employee_rows BIGINT, departments_visible BIGINT,
  t2_performance_review STRING, t3_home_address STRING, t3_highest_total_comp STRING,
  t4_ssn STRING, t4_medical_leave STRING
) COMMENT 'Demo only: visibility labels per persona (no sensitive values stored)';

-- COMMAND ----------

-- Switch persona (demo override)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'hr_analyst', NULL);
INSERT INTO glb_governance.demo_persona_comparison
SELECT 'hr_analyst',
  (SELECT count(*) FROM glb_silver.employees),
  (SELECT count(DISTINCT dept_id) FROM glb_silver.employees),
  (SELECT CASE WHEN max(review_text) = '****' THEN 'masked' ELSE 'clear' END FROM glb_silver.performance),
  (SELECT CASE WHEN max(home_address) = '****' THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN max(total_comp) IS NULL THEN 'masked (NULL)'
               WHEN max(total_comp) = 8000000 THEN 'company max (the CEO)'
               ELSE 'own subtree only' END FROM tr_gold.employee_comp),
  (SELECT CASE WHEN count_if(ssn <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN count_if(medical_leave_reason <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.leave_records);

-- COMMAND ----------

-- Switch persona (demo override)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'dept_head', 'D10');
INSERT INTO glb_governance.demo_persona_comparison
SELECT 'dept_head:D10',
  (SELECT count(*) FROM glb_silver.employees),
  (SELECT count(DISTINCT dept_id) FROM glb_silver.employees),
  (SELECT CASE WHEN max(review_text) = '****' THEN 'masked' ELSE 'clear' END FROM glb_silver.performance),
  (SELECT CASE WHEN max(home_address) = '****' THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN max(total_comp) IS NULL THEN 'masked (NULL)'
               WHEN max(total_comp) = 8000000 THEN 'company max (the CEO)'
               ELSE 'own subtree only' END FROM tr_gold.employee_comp),
  (SELECT CASE WHEN count_if(ssn <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN count_if(medical_leave_reason <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.leave_records);

-- COMMAND ----------

-- Switch persona (demo override)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'hr_trusted', NULL);
INSERT INTO glb_governance.demo_persona_comparison
SELECT 'hr_trusted',
  (SELECT count(*) FROM glb_silver.employees),
  (SELECT count(DISTINCT dept_id) FROM glb_silver.employees),
  (SELECT CASE WHEN max(review_text) = '****' THEN 'masked' ELSE 'clear' END FROM glb_silver.performance),
  (SELECT CASE WHEN max(home_address) = '****' THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN max(total_comp) IS NULL THEN 'masked (NULL)'
               WHEN max(total_comp) = 8000000 THEN 'company max (the CEO)'
               ELSE 'own subtree only' END FROM tr_gold.employee_comp),
  (SELECT CASE WHEN count_if(ssn <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN count_if(medical_leave_reason <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.leave_records);

-- COMMAND ----------

-- Switch persona (demo override)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'er_legal', NULL);
INSERT INTO glb_governance.demo_persona_comparison
SELECT 'er_legal',
  (SELECT count(*) FROM glb_silver.employees),
  (SELECT count(DISTINCT dept_id) FROM glb_silver.employees),
  (SELECT CASE WHEN max(review_text) = '****' THEN 'masked' ELSE 'clear' END FROM glb_silver.performance),
  (SELECT CASE WHEN max(home_address) = '****' THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN max(total_comp) IS NULL THEN 'masked (NULL)'
               WHEN max(total_comp) = 8000000 THEN 'company max (the CEO)'
               ELSE 'own subtree only' END FROM tr_gold.employee_comp),
  (SELECT CASE WHEN count_if(ssn <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN count_if(medical_leave_reason <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.leave_records);

-- COMMAND ----------

-- Reset the override, then show the comparison
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
SELECT * FROM glb_governance.demo_persona_comparison
ORDER BY CASE persona WHEN 'hr_analyst' THEN 1 WHEN 'dept_head:D10' THEN 2 WHEN 'hr_trusted' THEN 3 ELSE 4 END;

-- COMMAND ----------

-- MAGIC %md ## Upcoming features that make this easier
-- MAGIC - **Metastore-level policies (Beta):** one set of policies across every catalog, instead of one set per catalog.
-- MAGIC - **Governed tag propagation (Beta):** tags follow data into copies and derived tables automatically, so a copy into BYOD arrives already protected.
