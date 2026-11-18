-- Databricks notebook source
-- MAGIC %md # ABAC HR demo walkthrough
-- MAGIC Synthetic HR data. One governed tag (`hr_pii_demo_tag`) with four sensitivity levels, plus a reporting-line scope tag, drives **four policies set once at the catalog level**. Every table, view, metric view and raw extract below is protected by those four policies, with no per-table rules.
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

-- The tags on one table: each column carries a sensitivity tier; employee_id also carries the reporting-line scope tag
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
SELECT current_user() AS user_name, glb_governance.current_persona() AS persona, glb_governance.current_scope_employee() AS scope_employee;

-- COMMAND ----------

-- 1. Employee directory: four tiers side by side
--    internal: name, title, department | restricted: home address, DOB | highly_restricted: SSN
SELECT employee_id, full_name, job_title, dept_name, home_address, date_of_birth, ssn
FROM glb_gold.employee_directory
WHERE employee_id IN ('W00001','W00002','W00030','W00075','W00210','W00041')
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
WHERE w.worker_id IN ('W00001','W00002','W00030','W00075','W00210')
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

-- MAGIC %md ## Persona 2: People manager: Anya Nguyen (Senior Manager, Finance)
-- MAGIC Sees **only the people in her reporting line**: herself, her 3 managers and their teams (46 people), with internal, confidential and restricted data in clear for them. Highly restricted data (SSN, medical, ER) stays masked. Her own boss and the CEO never appear, and in recruiting she only sees requisitions where the hiring manager is in her line.

-- COMMAND ----------

-- Switch persona (demo override)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'people_manager', 'W00030');

-- COMMAND ----------

-- Who am I right now?
SELECT current_user() AS user_name, glb_governance.current_persona() AS persona, glb_governance.current_scope_employee() AS scope_employee;

-- COMMAND ----------

-- 1. Employee directory: four tiers side by side
--    internal: name, title, department | restricted: home address, DOB | highly_restricted: SSN
SELECT employee_id, full_name, job_title, dept_name, home_address, date_of_birth, ssn
FROM glb_gold.employee_directory
WHERE employee_id IN ('W00001','W00002','W00030','W00075','W00210','W00041')
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
WHERE w.worker_id IN ('W00001','W00002','W00030','W00075','W00210')
ORDER BY w.worker_id;

-- COMMAND ----------

-- MAGIC %md ### Pressure tests: People manager: Anya Nguyen
-- MAGIC The SQL equivalents of the riskiest Genie questions. Every row should show `pass = true`.

-- COMMAND ----------

-- Pressure tests for people_manager:W00030
SELECT 'people_manager:W00030' AS persona, 'T01' AS test_id, 'Direct ask: highest total comp = highest in their line, not the CEO' AS description,
       CAST(max(total_comp) AS STRING) AS observed, '216770.00' AS expected, max(total_comp) = 216770 AS pass
  FROM tr_gold.employee_comp
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T03' AS test_id, 'Inference via filter: count with base > 500K (CEO is outside the line)' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM tr_silver.compensation WHERE base_salary > 500000
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T04' AS test_id, 'Small group: CEO office rows reachable' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM tr_silver.compensation WHERE dept_id = 'D00'
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T11a' AS test_id, 'Scope: employees visible = their reporting line (46 incl. self)' AS description,
       CAST(count(*) AS STRING) AS observed, '46' AS expected, count(*) = 46 AS pass
  FROM glb_silver.employees
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T11b' AS test_id, 'Scope: everyone visible is in their line' AS description,
       CAST(count_if(NOT glb_governance.in_reporting_line(employee_id)) AS STRING) AS observed, '0' AS expected, count_if(NOT glb_governance.in_reporting_line(employee_id)) = 0 AS pass
  FROM glb_silver.employees
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T11c' AS test_id, 'Scope: their own manager (Head of Finance) is not visible' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM glb_silver.employees WHERE employee_id = 'W00002'
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T11d' AS test_id, 'Recruiting: only requisitions where the hiring manager is in their line' AS description,
       CAST(count(*) AS STRING) AS observed, '2' AS expected, count(*) = 2 AS pass
  FROM ta_silver.requisitions
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T12' AS test_id, 'Metric view headcount = their line' AS description,
       CAST(MEASURE(headcount) AS STRING) AS observed, '46' AS expected, MEASURE(headcount) = 46 AS pass
  FROM tr_gold.mv_total_comp
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T13' AS test_id, 'Tier 4: SSNs visible in clear' AS description,
       CAST(count_if(ssn <> '****') AS STRING) AS observed, '0' AS expected, count_if(ssn <> '****') = 0 AS pass
  FROM glb_silver.employees
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T13b' AS test_id, 'Tier 4: medical leave reasons visible' AS description,
       CAST(count_if(medical_leave_reason <> '****') AS STRING) AS observed, '0' AS expected, count_if(medical_leave_reason <> '****') = 0 AS pass
  FROM glb_silver.leave_records
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T14' AS test_id, 'Side door: bronze worker rows = their line' AS description,
       CAST(count(*) AS STRING) AS observed, '46' AS expected, count(*) = 46 AS pass
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
SELECT current_user() AS user_name, glb_governance.current_persona() AS persona, glb_governance.current_scope_employee() AS scope_employee;

-- COMMAND ----------

-- 1. Employee directory: four tiers side by side
--    internal: name, title, department | restricted: home address, DOB | highly_restricted: SSN
SELECT employee_id, full_name, job_title, dept_name, home_address, date_of_birth, ssn
FROM glb_gold.employee_directory
WHERE employee_id IN ('W00001','W00002','W00030','W00075','W00210','W00041')
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
WHERE w.worker_id IN ('W00001','W00002','W00030','W00075','W00210')
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
SELECT current_user() AS user_name, glb_governance.current_persona() AS persona, glb_governance.current_scope_employee() AS scope_employee;

-- COMMAND ----------

-- 1. Employee directory: four tiers side by side
--    internal: name, title, department | restricted: home address, DOB | highly_restricted: SSN
SELECT employee_id, full_name, job_title, dept_name, home_address, date_of_birth, ssn
FROM glb_gold.employee_directory
WHERE employee_id IN ('W00001','W00002','W00030','W00075','W00210','W00041')
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
WHERE w.worker_id IN ('W00001','W00002','W00030','W00075','W00210')
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

-- MAGIC %md ## Scenario: copy leakage into BYOD
-- MAGIC An **HR trusted** user can see comp and home addresses, and has CREATE in the BYOD sandbox. They copy data there for a comp review. The copy's columns have **no tags**, so the catalog-level policies don't match them: an analyst reads clear salaries, and the department row filter doesn't apply.
-- MAGIC
-- MAGIC The fix needs **no new policy**: tag the copy from its sources and the existing four policies protect it immediately.

-- COMMAND ----------

-- Step 1: as HR trusted, copy comp + home address into BYOD
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'hr_trusted', NULL);
-- Drop first: CREATE OR REPLACE keeps the old column tags, which would hide the leak on a re-run
DROP TABLE IF EXISTS byod.comp_review_extract;
CREATE TABLE byod.comp_review_extract
COMMENT 'User-made extract for a comp review (copy-leakage scenario)'
AS
SELECT c.employee_id, c.full_name, c.dept_id, c.dept_name, d.home_address,
       c.base_salary, c.bonus_target, c.total_comp
FROM tr_gold.employee_comp c
JOIN glb_gold.employee_directory d ON d.employee_id = c.employee_id;

-- COMMAND ----------

-- Step 2: as HR analyst, read the copy (this is the leak)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'hr_analyst', NULL);
SELECT full_name, dept_name, home_address, base_salary, bonus_target, total_comp
FROM byod.comp_review_extract
ORDER BY total_comp DESC NULLS LAST
LIMIT 5;

-- COMMAND ----------

-- Step 3: as people manager Anya Nguyen, read the copy (the reporting-line row filter doesn't apply either)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'people_manager', 'W00030');
SELECT count(*) AS rows_visible, count(DISTINCT dept_id) AS departments_visible
FROM byod.comp_review_extract;

-- COMMAND ----------

-- MAGIC %md ### Detect the untagged copy
-- MAGIC Two ways to find it: by **column name** (instant, but misses renamed or derived columns like `total_comp`) and by **lineage** (`system.access.column_lineage`, catches derived columns, but can lag by minutes, so production runs it as a scheduled job).

-- COMMAND ----------

-- Reset the override, then detect by column name: untagged BYOD columns matching a tagged bronze/silver column
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
SELECT c.table_name, c.column_name, max(src.tag_value) AS source_tier
FROM information_schema.columns c
JOIN information_schema.column_tags src
  ON src.column_name = c.column_name AND src.tag_name = 'hr_pii_demo_tag'
 AND (src.schema_name LIKE '%\_silver' OR src.schema_name LIKE '%\_bronze')
LEFT JOIN information_schema.column_tags t
  ON t.schema_name = c.table_schema AND t.table_name = c.table_name
 AND t.column_name = c.column_name AND t.tag_name = 'hr_pii_demo_tag'
WHERE c.table_schema = 'byod' AND t.tag_name IS NULL
GROUP BY ALL
ORDER BY 1, 2;

-- COMMAND ----------

-- Detect by lineage: where did each BYOD column come from?
SELECT target_column_name, collect_set(concat(source_table_full_name, '.', source_column_name)) AS sources
FROM system.access.column_lineage
WHERE target_table_full_name = concat(current_catalog(), '.byod.comp_review_extract')
GROUP BY ALL
ORDER BY 1;

-- COMMAND ----------

-- MAGIC %md ### Remediate: tag the copy from its sources
-- MAGIC Walks lineage upstream to the tagged source columns (falling back to name match), takes the highest tier found, carries the scope tag (reporting line) across, and applies the tags. Same logic as `scripts/remediate_untagged_copies.py`, which runs as a scheduled job in production.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC TIER_TAG, SCOPE_TAG = "hr_pii_demo_tag", "hr_scope_demo_tag"
-- MAGIC ORDER = ["internal", "confidential", "restricted", "highly_restricted"]
-- MAGIC cat = spark.sql("SELECT current_catalog()").first()[0]
-- MAGIC
-- MAGIC tags = {}
-- MAGIC for r in spark.sql(f"SELECT schema_name, table_name, column_name, tag_name, tag_value FROM {cat}.information_schema.column_tags WHERE tag_name IN ('{TIER_TAG}', '{SCOPE_TAG}')").collect():
-- MAGIC     tags.setdefault(f"{cat}.{r.schema_name}.{r.table_name}.{r.column_name}", {})[r.tag_name] = r.tag_value
-- MAGIC untagged = [(r.table_name, r.column_name) for r in spark.sql(f"SELECT table_name, column_name FROM {cat}.information_schema.columns WHERE table_schema = 'byod'").collect()
-- MAGIC             if TIER_TAG not in tags.get(f"{cat}.byod.{r.table_name}.{r.column_name}", {})]
-- MAGIC lineage = {}
-- MAGIC for r in spark.sql(f"SELECT DISTINCT target_table_full_name t, target_column_name tc, source_table_full_name s, source_column_name sc FROM system.access.column_lineage WHERE target_table_full_name LIKE '{cat}.%' AND source_column_name IS NOT NULL AND target_column_name IS NOT NULL").collect():
-- MAGIC     lineage.setdefault(f"{r.t}.{r.tc}", set()).add(f"{r.s}.{r.sc}")
-- MAGIC
-- MAGIC def upstream(col, seen, depth=0):
-- MAGIC     out = []
-- MAGIC     for src in lineage.get(col, ()):
-- MAGIC         if src in seen:
-- MAGIC             continue
-- MAGIC         seen.add(src)
-- MAGIC         if TIER_TAG in tags.get(src, {}):
-- MAGIC             out.append(tags[src])
-- MAGIC         elif depth < 5:
-- MAGIC             out += upstream(src, seen, depth + 1)
-- MAGIC     return out
-- MAGIC
-- MAGIC by_name = {}
-- MAGIC for k, v in tags.items():
-- MAGIC     if TIER_TAG in v and (k.split(".")[1].endswith("_silver") or k.split(".")[1].endswith("_bronze")):
-- MAGIC         by_name.setdefault(k.rsplit(".", 1)[1], []).append(v)
-- MAGIC
-- MAGIC plan = []
-- MAGIC for t, c in untagged:
-- MAGIC     found, how = upstream(f"{cat}.byod.{t}.{c}", set()), "lineage"
-- MAGIC     if not found:
-- MAGIC         found, how = by_name.get(c, []), "name match"
-- MAGIC     if not found:
-- MAGIC         plan.append((t, c, None, None, "no source found: review manually"))
-- MAGIC         continue
-- MAGIC     tier = max((f[TIER_TAG] for f in found), key=ORDER.index)
-- MAGIC     scope = next((f[SCOPE_TAG] for f in found if f.get(SCOPE_TAG)), None)
-- MAGIC     spark.sql(f"ALTER TABLE {cat}.byod.{t} ALTER COLUMN {c} SET TAGS ('{TIER_TAG}' = '{tier}')")
-- MAGIC     if scope:
-- MAGIC         spark.sql(f"ALTER TABLE {cat}.byod.{t} ALTER COLUMN {c} SET TAGS ('{SCOPE_TAG}' = '{scope}')")
-- MAGIC     plan.append((t, c, tier, scope, how))
-- MAGIC
-- MAGIC display(spark.createDataFrame(plan, "table STRING, column STRING, tier_applied STRING, scope_applied STRING, found_by STRING"))

-- COMMAND ----------

-- Step 4: re-check as HR analyst (comp and addresses now masked by the same four policies)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'hr_analyst', NULL);
SELECT full_name, dept_name, home_address, base_salary, bonus_target, total_comp
FROM byod.comp_review_extract
ORDER BY employee_id
LIMIT 5;

-- COMMAND ----------

-- Step 5: re-check as Anya Nguyen (the row filter now applies to the copy)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'people_manager', 'W00030');
SELECT count(*) AS rows_visible, count(DISTINCT dept_id) AS departments_visible
FROM byod.comp_review_extract;

-- COMMAND ----------

-- Pressure tests: copy leakage (after remediation)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'hr_analyst', NULL);
SELECT 'hr_analyst' AS persona, 'T06a' AS test_id, 'BYOD copy: clear salaries after remediation' AS description,
       CAST(count(base_salary) AS STRING) AS observed, '0' AS expected, count(base_salary) = 0 AS pass
  FROM byod.comp_review_extract
UNION ALL
SELECT 'hr_analyst', 'T06b', 'BYOD copy: clear home addresses after remediation',
       CAST(count_if(home_address <> '****') AS STRING), '0', count_if(home_address <> '****') = 0
  FROM byod.comp_review_extract
UNION ALL
SELECT 'hr_analyst', 'T06c', 'BYOD copy: derived total_comp visible (caught only via lineage)',
       CAST(count(total_comp) AS STRING), '0', count(total_comp) = 0
  FROM byod.comp_review_extract;

-- COMMAND ----------

DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'people_manager', 'W00030');
SELECT 'people_manager:W00030' AS persona, 'T06d' AS test_id, 'BYOD copy: rows visible after remediation = her reporting line' AS description,
       CAST(count(*) AS STRING) AS observed, '46' AS expected, count(*) = 46 AS pass
  FROM byod.comp_review_extract;

-- COMMAND ----------

DELETE FROM glb_governance.persona_override WHERE user_name = current_user();

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
               ELSE 'own reporting line only' END FROM tr_gold.employee_comp),
  (SELECT CASE WHEN count_if(ssn <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN count_if(medical_leave_reason <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.leave_records);

-- COMMAND ----------

-- Switch persona (demo override)
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'people_manager', 'W00030');
INSERT INTO glb_governance.demo_persona_comparison
SELECT 'people_manager:W00030',
  (SELECT count(*) FROM glb_silver.employees),
  (SELECT count(DISTINCT dept_id) FROM glb_silver.employees),
  (SELECT CASE WHEN max(review_text) = '****' THEN 'masked' ELSE 'clear' END FROM glb_silver.performance),
  (SELECT CASE WHEN max(home_address) = '****' THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN max(total_comp) IS NULL THEN 'masked (NULL)'
               WHEN max(total_comp) = 8000000 THEN 'company max (the CEO)'
               ELSE 'own reporting line only' END FROM tr_gold.employee_comp),
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
               ELSE 'own reporting line only' END FROM tr_gold.employee_comp),
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
               ELSE 'own reporting line only' END FROM tr_gold.employee_comp),
  (SELECT CASE WHEN count_if(ssn <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.employees),
  (SELECT CASE WHEN count_if(medical_leave_reason <> '****') = 0 THEN 'masked' ELSE 'clear' END FROM glb_silver.leave_records);

-- COMMAND ----------

-- Reset the override, then show the comparison
DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
SELECT * FROM glb_governance.demo_persona_comparison
ORDER BY CASE persona WHEN 'hr_analyst' THEN 1 WHEN 'people_manager:W00030' THEN 2 WHEN 'hr_trusted' THEN 3 ELSE 4 END;

-- COMMAND ----------

-- MAGIC %md ## Upcoming features that make this easier
-- MAGIC - **Metastore-level policies (Beta):** one set of policies across every catalog, instead of one set per catalog.
-- MAGIC - **Governed tag propagation (Beta):** tags follow data into copies and derived tables automatically, so a copy into BYOD arrives already protected.
