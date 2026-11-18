-- ============================================================================
-- abac-hr-demo / 03: silver (curated, typed). Every table carries dept_id so one
-- row-filter policy covers all of them.
-- Templated: {{catalog}}
-- ============================================================================

CREATE OR REPLACE TABLE {{catalog}}.glb_silver.departments AS
SELECT org_id AS dept_id, org_name AS dept_name, parent_org_id AS parent_dept_id, head_worker_id AS head_employee_id
FROM {{catalog}}.glb_bronze.hris_supervisory_orgs_raw;

CREATE OR REPLACE TABLE {{catalog}}.glb_silver.employees AS
SELECT
  worker_id                    AS employee_id,
  concat(first_name, ' ', last_name) AS full_name,
  work_email,
  job_title,
  job_level,
  org_id                       AS dept_id,
  manager_worker_id            AS manager_id,
  country,
  CAST(hire_date AS DATE)      AS hire_date,
  home_address,
  personal_phone,
  CAST(date_of_birth AS DATE)  AS date_of_birth,
  emergency_contact,
  ssn,
  bank_routing_number
FROM {{catalog}}.glb_bronze.hris_workers_raw;

CREATE OR REPLACE TABLE {{catalog}}.glb_silver.performance AS
SELECT worker_id AS employee_id, org_id AS dept_id, CAST(review_year AS INT) AS review_year,
       rating, review_text, promotion_history
FROM {{catalog}}.glb_bronze.hris_performance_raw;

CREATE OR REPLACE TABLE {{catalog}}.glb_silver.leave_records AS
SELECT worker_id AS employee_id, org_id AS dept_id, CAST(leave_balance_hours AS INT) AS leave_balance_hours,
       leave_type, medical_leave_reason, ada_accommodation
FROM {{catalog}}.glb_bronze.hris_leave_raw;

CREATE OR REPLACE TABLE {{catalog}}.glb_silver.employee_relations AS
SELECT case_id, worker_id AS employee_id, org_id AS dept_id, case_type, investigation_notes, background_check_result
FROM {{catalog}}.glb_bronze.hris_er_cases_raw;

CREATE OR REPLACE TABLE {{catalog}}.tr_silver.compensation AS
SELECT
  worker_id                              AS employee_id,
  org_id                                 AS dept_id,
  country,
  comp_grade,
  CAST(base_salary  AS DECIMAL(12,2))    AS base_salary,
  CAST(bonus_target AS DECIMAL(12,2))    AS bonus_target,
  CAST(equity_grant AS DECIMAL(12,2))    AS equity_grant,
  currency
FROM {{catalog}}.tr_bronze.hris_comp_raw;

CREATE OR REPLACE TABLE {{catalog}}.ta_silver.requisitions AS
SELECT requisition_id, org_id AS dept_id, job_title, status
FROM {{catalog}}.ta_bronze.ats_requisitions_raw;

CREATE OR REPLACE TABLE {{catalog}}.ta_silver.applications AS
SELECT application_id, requisition_id, org_id AS dept_id, candidate_name, stage, interview_notes, resume_text
FROM {{catalog}}.ta_bronze.ats_applications_raw;

CREATE OR REPLACE TABLE {{catalog}}.lrn_silver.training_records AS
SELECT worker_id AS employee_id, org_id AS dept_id, course_name, completion_status,
       CAST(assessment_score AS INT) AS assessment_score
FROM {{catalog}}.lrn_bronze.lms_training_raw;

SELECT
  (SELECT count(*) FROM {{catalog}}.glb_silver.employees)        AS employees,
  (SELECT count(*) FROM {{catalog}}.glb_silver.departments)      AS departments,
  (SELECT count(*) FROM {{catalog}}.glb_silver.performance)      AS performance,
  (SELECT count(*) FROM {{catalog}}.glb_silver.leave_records)    AS leave_records,
  (SELECT count(*) FROM {{catalog}}.glb_silver.employee_relations) AS er_cases,
  (SELECT count(*) FROM {{catalog}}.tr_silver.compensation)      AS compensation,
  (SELECT count(*) FROM {{catalog}}.ta_silver.requisitions)      AS requisitions,
  (SELECT count(*) FROM {{catalog}}.ta_silver.applications)      AS applications,
  (SELECT count(*) FROM {{catalog}}.lrn_silver.training_records) AS training_records;
