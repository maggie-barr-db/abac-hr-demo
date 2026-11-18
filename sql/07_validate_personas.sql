-- ============================================================================
-- abac-hr-demo / 07: persona check across every silver table (plus one bronze table)
-- Templated: {{catalog}}
--
-- Switches your persona through the demo override, then shows what that persona sees.
-- Expected (synthetic data): 2,000 employees, 16 departments; D10 subtree = D10, D11, D12;
-- max base 2,500,000 (CEO); medical leave reasons exist for some rows.
-- ============================================================================

-- ---------------------------------------------------------------- hr_analyst
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'hr_analyst', NULL);

SELECT 'hr_analyst' AS persona,
  (SELECT count(*) FROM {{catalog}}.glb_silver.employees)                                   AS employee_rows,
  (SELECT count(DISTINCT dept_id) FROM {{catalog}}.glb_silver.employees)                    AS depts_visible,
  (SELECT max(full_name) FROM {{catalog}}.glb_silver.employees)                             AS t1_full_name,
  (SELECT max(review_text) FROM {{catalog}}.glb_silver.performance)                         AS t2_review_text,
  (SELECT max(home_address) FROM {{catalog}}.glb_silver.employees)                          AS t3_home_address,
  (SELECT max(base_salary) FROM {{catalog}}.tr_silver.compensation)                         AS t3_max_base,
  (SELECT max(ssn) FROM {{catalog}}.glb_silver.employees)                                   AS t4_ssn,
  (SELECT count(medical_leave_reason) FILTER (WHERE medical_leave_reason <> '****') FROM {{catalog}}.glb_silver.leave_records) AS t4_medical_visible,
  (SELECT max(ssn) FROM {{catalog}}.glb_bronze.hris_workers_raw)                            AS bronze_t4_ssn;

-- ---------------------------------------------------------------- dept_head (Finance, D10)
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'dept_head', 'D10');

SELECT 'dept_head:D10' AS persona,
  (SELECT count(*) FROM {{catalog}}.glb_silver.employees)                                   AS employee_rows,
  (SELECT array_join(array_sort(collect_set(dept_id)), ',') FROM {{catalog}}.glb_silver.employees) AS depts_visible,
  (SELECT max(full_name) FROM {{catalog}}.glb_silver.employees)                             AS t1_full_name,
  (SELECT max(review_text) FROM {{catalog}}.glb_silver.performance)                         AS t2_review_text,
  (SELECT max(home_address) FROM {{catalog}}.glb_silver.employees)                          AS t3_home_address,
  (SELECT max(base_salary) FROM {{catalog}}.tr_silver.compensation)                         AS t3_max_base,
  (SELECT max(ssn) FROM {{catalog}}.glb_silver.employees)                                   AS t4_ssn,
  (SELECT count(medical_leave_reason) FILTER (WHERE medical_leave_reason <> '****') FROM {{catalog}}.glb_silver.leave_records) AS t4_medical_visible,
  (SELECT count(*) FROM {{catalog}}.ta_silver.applications)                                 AS ta_applications_rows,
  (SELECT count(*) FROM {{catalog}}.lrn_silver.training_records)                            AS lrn_training_rows;

-- ---------------------------------------------------------------- hr_trusted
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'hr_trusted', NULL);

SELECT 'hr_trusted' AS persona,
  (SELECT count(*) FROM {{catalog}}.glb_silver.employees)                                   AS employee_rows,
  (SELECT count(DISTINCT dept_id) FROM {{catalog}}.glb_silver.employees)                    AS depts_visible,
  (SELECT max(review_text) FROM {{catalog}}.glb_silver.performance)                         AS t2_review_text,
  (SELECT max(home_address) FROM {{catalog}}.glb_silver.employees)                          AS t3_home_address,
  (SELECT max(base_salary) FROM {{catalog}}.tr_silver.compensation)                         AS t3_max_base,
  (SELECT max(ssn) FROM {{catalog}}.glb_silver.employees)                                   AS t4_ssn,
  (SELECT count(medical_leave_reason) FILTER (WHERE medical_leave_reason <> '****') FROM {{catalog}}.glb_silver.leave_records) AS t4_medical_visible;

-- ---------------------------------------------------------------- er_legal
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'er_legal', NULL);

SELECT 'er_legal' AS persona,
  (SELECT count(*) FROM {{catalog}}.glb_silver.employees)                                   AS employee_rows,
  (SELECT max(base_salary) FROM {{catalog}}.tr_silver.compensation)                         AS t3_max_base,
  (SELECT max(ssn) FROM {{catalog}}.glb_silver.employees)                                   AS t4_ssn,
  (SELECT count(medical_leave_reason) FILTER (WHERE medical_leave_reason <> '****') FROM {{catalog}}.glb_silver.leave_records) AS t4_medical_visible,
  (SELECT max(investigation_notes) FROM {{catalog}}.glb_silver.employee_relations)          AS t4_er_notes;

-- ---------------------------------------------------------------- reset
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
