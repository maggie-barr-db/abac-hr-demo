-- ============================================================================
-- abac-hr-demo / 09: automated pressure tests (SQL equivalents of the Genie prompts)
-- Templated: {{catalog}}
--
-- Each block switches persona through the demo override, then returns one row per
-- test with observed / expected / pass. Test IDs map to tests/genie_pressure_test.md.
-- Ground truth (synthetic): CEO total comp 8,000,000 (base 2,500,000); exactly 1 base
-- above 500K; CEO office n = 3; Anya Nguyen (W00030, Senior Manager, Finance) has a reporting line
-- of 46 people incl. herself, max total comp 216,770, and 2 requisitions.
-- T06 (copies), T08 (Genie Code side doors), T09 (shared artifacts) and T10 (prompt
-- manipulation) are covered by later phases, the Genie script, or manual steps.
-- ============================================================================

-- ---------------------------------------------------------------- hr_analyst
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'hr_analyst', NULL);

SELECT 'hr_analyst' AS persona, 'T01' AS test_id, 'Direct ask: highest total comp' AS description,
       CAST(max(total_comp) AS STRING) AS observed, 'NULL' AS expected, max(total_comp) IS NULL AS pass
  FROM {{catalog}}.tr_gold.employee_comp
UNION ALL
SELECT 'hr_analyst' AS persona, 'T02' AS test_id, 'Aggregate: departments with a visible avg base' AS description,
       CAST(count_if(a IS NOT NULL) AS STRING) AS observed, '0' AS expected, count_if(a IS NOT NULL) = 0 AS pass
  FROM (SELECT dept_id, avg(base_salary) a FROM {{catalog}}.tr_silver.compensation GROUP BY dept_id)
UNION ALL
SELECT 'hr_analyst' AS persona, 'T03' AS test_id, 'Inference via filter: count with base > 500K' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM {{catalog}}.tr_silver.compensation WHERE base_salary > 500000
UNION ALL
SELECT 'hr_analyst' AS persona, 'T04' AS test_id, 'Small group: avg base in CEO office (n=3)' AS description,
       CAST(avg(base_salary) AS STRING) AS observed, 'NULL' AS expected, avg(base_salary) IS NULL AS pass
  FROM {{catalog}}.tr_silver.compensation WHERE dept_id = 'D00'
UNION ALL
SELECT 'hr_analyst' AS persona, 'T05' AS test_id, 'Top-N: visible bonus values among top 10' AS description,
       CAST(count(bonus_target) AS STRING) AS observed, '0' AS expected, count(bonus_target) = 0 AS pass
  FROM (SELECT bonus_target FROM {{catalog}}.tr_silver.compensation ORDER BY bonus_target DESC NULLS LAST LIMIT 10)
UNION ALL
SELECT 'hr_analyst' AS persona, 'T07' AS test_id, 'Metadata: comp column names visible (expected, names are not data)' AS description,
       CAST(count(*) AS STRING) AS observed, '4' AS expected, count(*) = 4 AS pass
  FROM {{catalog}}.information_schema.columns WHERE table_schema = 'tr_silver' AND table_name = 'compensation' AND column_name IN ('base_salary','bonus_target','equity_grant','comp_grade')
UNION ALL
SELECT 'hr_analyst' AS persona, 'T11' AS test_id, 'Scope: rows visible (analyst sees all rows, masked)' AS description,
       CAST(count(*) AS STRING) AS observed, '2000' AS expected, count(*) = 2000 AS pass
  FROM {{catalog}}.glb_silver.employees
UNION ALL
SELECT 'hr_analyst' AS persona, 'T12' AS test_id, 'Metric view: max total comp measure' AS description,
       CAST(MEASURE(max_total_comp) AS STRING) AS observed, 'NULL' AS expected, MEASURE(max_total_comp) IS NULL AS pass
  FROM {{catalog}}.tr_gold.mv_total_comp
UNION ALL
SELECT 'hr_analyst' AS persona, 'T13' AS test_id, 'Tier 4: SSNs visible in clear' AS description,
       CAST(count_if(ssn <> '****') AS STRING) AS observed, '0' AS expected, count_if(ssn <> '****') = 0 AS pass
  FROM {{catalog}}.glb_silver.employees
UNION ALL
SELECT 'hr_analyst' AS persona, 'T14' AS test_id, 'Side door: bronze raw comp visible' AS description,
       CAST(count_if(base_salary <> '****') AS STRING) AS observed, '0' AS expected, count_if(base_salary <> '****') = 0 AS pass
  FROM {{catalog}}.tr_bronze.hris_comp_raw
ORDER BY test_id;

-- ---------------------------------------------------------------- people_manager:W00030  (Anya Nguyen, Senior Manager, Finance)
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'people_manager', 'W00030');

SELECT 'people_manager:W00030' AS persona, 'T01' AS test_id, 'Direct ask: highest total comp = highest in their line, not the CEO' AS description,
       CAST(max(total_comp) AS STRING) AS observed, '216770.00' AS expected, max(total_comp) = 216770 AS pass
  FROM {{catalog}}.tr_gold.employee_comp
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T03' AS test_id, 'Inference via filter: count with base > 500K (CEO is outside the line)' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM {{catalog}}.tr_silver.compensation WHERE base_salary > 500000
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T04' AS test_id, 'Small group: CEO office rows reachable' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM {{catalog}}.tr_silver.compensation WHERE dept_id = 'D00'
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T11a' AS test_id, 'Scope: employees visible = their reporting line (46 incl. self)' AS description,
       CAST(count(*) AS STRING) AS observed, '46' AS expected, count(*) = 46 AS pass
  FROM {{catalog}}.glb_silver.employees
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T11b' AS test_id, 'Scope: everyone visible is in their line' AS description,
       CAST(count_if(NOT {{catalog}}.glb_governance.in_reporting_line(employee_id)) AS STRING) AS observed, '0' AS expected, count_if(NOT {{catalog}}.glb_governance.in_reporting_line(employee_id)) = 0 AS pass
  FROM {{catalog}}.glb_silver.employees
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T11c' AS test_id, 'Scope: their own manager (Head of Finance) is not visible' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM {{catalog}}.glb_silver.employees WHERE employee_id = 'W00002'
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T11d' AS test_id, 'Recruiting: only requisitions where the hiring manager is in their line' AS description,
       CAST(count(*) AS STRING) AS observed, '2' AS expected, count(*) = 2 AS pass
  FROM {{catalog}}.ta_silver.requisitions
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T12' AS test_id, 'Metric view headcount = their line' AS description,
       CAST(MEASURE(headcount) AS STRING) AS observed, '46' AS expected, MEASURE(headcount) = 46 AS pass
  FROM {{catalog}}.tr_gold.mv_total_comp
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T13' AS test_id, 'Tier 4: SSNs visible in clear' AS description,
       CAST(count_if(ssn <> '****') AS STRING) AS observed, '0' AS expected, count_if(ssn <> '****') = 0 AS pass
  FROM {{catalog}}.glb_silver.employees
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T13b' AS test_id, 'Tier 4: medical leave reasons visible' AS description,
       CAST(count_if(medical_leave_reason <> '****') AS STRING) AS observed, '0' AS expected, count_if(medical_leave_reason <> '****') = 0 AS pass
  FROM {{catalog}}.glb_silver.leave_records
UNION ALL
SELECT 'people_manager:W00030' AS persona, 'T14' AS test_id, 'Side door: bronze worker rows = their line' AS description,
       CAST(count(*) AS STRING) AS observed, '46' AS expected, count(*) = 46 AS pass
  FROM {{catalog}}.glb_bronze.hris_workers_raw
ORDER BY test_id;

-- ---------------------------------------------------------------- hr_trusted
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'hr_trusted', NULL);

SELECT 'hr_trusted' AS persona, 'T01' AS test_id, 'Control: highest total comp is the CEO' AS description,
       CAST(max(total_comp) AS STRING) AS observed, '8000000.00' AS expected, max(total_comp) = 8000000 AS pass
  FROM {{catalog}}.tr_gold.employee_comp
UNION ALL
SELECT 'hr_trusted' AS persona, 'T03' AS test_id, 'Control: count with base > 500K' AS description,
       CAST(count(*) AS STRING) AS observed, '1' AS expected, count(*) = 1 AS pass
  FROM {{catalog}}.tr_silver.compensation WHERE base_salary > 500000
UNION ALL
SELECT 'hr_trusted' AS persona, 'T13' AS test_id, 'Tier 4 still masked for HR trusted: SSNs in clear' AS description,
       CAST(count_if(ssn <> '****') AS STRING) AS observed, '0' AS expected, count_if(ssn <> '****') = 0 AS pass
  FROM {{catalog}}.glb_silver.employees
UNION ALL
SELECT 'hr_trusted' AS persona, 'T13b' AS test_id, 'Tier 4 still masked: medical leave reasons' AS description,
       CAST(count_if(medical_leave_reason <> '****') AS STRING) AS observed, '0' AS expected, count_if(medical_leave_reason <> '****') = 0 AS pass
  FROM {{catalog}}.glb_silver.leave_records
ORDER BY test_id;

-- ---------------------------------------------------------------- er_legal
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'er_legal', NULL);

SELECT 'er_legal' AS persona, 'T13' AS test_id, 'Control: SSNs in clear for ER/Legal' AS description,
       CAST(count_if(ssn <> '****') AS STRING) AS observed, '2000' AS expected, count_if(ssn <> '****') = 2000 AS pass
  FROM {{catalog}}.glb_silver.employees
UNION ALL
SELECT 'er_legal' AS persona, 'T13b' AS test_id, 'Control: medical leave reasons visible' AS description,
       CAST(count_if(medical_leave_reason IS NOT NULL AND medical_leave_reason <> '****') AS STRING) AS observed, '> 0' AS expected, count_if(medical_leave_reason IS NOT NULL AND medical_leave_reason <> '****') > 0 AS pass
  FROM {{catalog}}.glb_silver.leave_records
ORDER BY test_id;

-- reset
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
