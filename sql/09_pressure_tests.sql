-- ============================================================================
-- abac-hr-demo / 09: automated pressure tests (SQL equivalents of the Genie prompts)
-- Templated: {{catalog}}
--
-- Each block switches persona through the demo override, then returns one row per
-- test with observed / expected / pass. Test IDs map to tests/genie_pressure_test.md.
-- Ground truth (synthetic): CEO total comp 8,000,000 (base 2,500,000); exactly 1 base
-- above 500K; CEO office n = 3; D10 subtree = D10, D11, D12 with max total comp 820,052.
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

-- ---------------------------------------------------------------- dept_head:D10
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'dept_head', 'D10');

SELECT 'dept_head:D10' AS persona, 'T01' AS test_id, 'Direct ask: highest total comp = Finance max, not the CEO' AS description,
       CAST(max(total_comp) AS STRING) AS observed, '820052.00' AS expected, max(total_comp) = 820052 AS pass
  FROM {{catalog}}.tr_gold.employee_comp
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T03' AS test_id, 'Inference via filter: count with base > 500K (CEO is outside scope)' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM {{catalog}}.tr_silver.compensation WHERE base_salary > 500000
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T04' AS test_id, 'Small group: CEO office rows reachable' AS description,
       CAST(count(*) AS STRING) AS observed, '0' AS expected, count(*) = 0 AS pass
  FROM {{catalog}}.tr_silver.compensation WHERE dept_id = 'D00'
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T11a' AS test_id, 'Scope: departments visible' AS description,
       CAST(array_join(array_sort(collect_set(dept_id)), ',') AS STRING) AS observed, 'D10,D11,D12' AS expected, array_join(array_sort(collect_set(dept_id)), ',') = 'D10,D11,D12' AS pass
  FROM {{catalog}}.glb_silver.employees
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T11b' AS test_id, 'Scope: global payroll equals subtree payroll' AS description,
       CAST(sum(base_salary) AS STRING) AS observed, '= sum for D10,D11,D12' AS expected, sum(base_salary) = sum(CASE WHEN dept_id IN ('D10','D11','D12') THEN base_salary END) AS pass
  FROM {{catalog}}.tr_silver.compensation
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T12' AS test_id, 'Metric view headcount = visible employees' AS description,
       CAST(MEASURE(headcount) AS STRING) AS observed, '= employees visible' AS expected, MEASURE(headcount) = (SELECT count(*) FROM {{catalog}}.glb_silver.employees) AS pass
  FROM {{catalog}}.tr_gold.mv_total_comp
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T13' AS test_id, 'Tier 4: SSNs visible in clear' AS description,
       CAST(count_if(ssn <> '****') AS STRING) AS observed, '0' AS expected, count_if(ssn <> '****') = 0 AS pass
  FROM {{catalog}}.glb_silver.employees
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T13b' AS test_id, 'Tier 4: medical leave reasons visible' AS description,
       CAST(count_if(medical_leave_reason <> '****') AS STRING) AS observed, '0' AS expected, count_if(medical_leave_reason <> '****') = 0 AS pass
  FROM {{catalog}}.glb_silver.leave_records
UNION ALL
SELECT 'dept_head:D10' AS persona, 'T14' AS test_id, 'Side door: bronze rows outside subtree' AS description,
       CAST(count_if(org_id NOT IN ('D10','D11','D12')) AS STRING) AS observed, '0' AS expected, count_if(org_id NOT IN ('D10','D11','D12')) = 0 AS pass
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
