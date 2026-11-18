-- ============================================================================
-- abac-hr-demo / 04: governed tags on columns (bronze + silver)
-- Templated: {{catalog}}, {{tier_tag}}, {{scope_tag}}
--
-- {{tier_tag}} values:  internal | confidential | restricted | highly_restricted
-- {{scope_tag}} value:  department  (marks the department column the row filter uses)
--
-- Tier assignments:
--   internal          names, titles, work email, department, manager, country, IDs
--   confidential      performance, interview notes, resumes, candidate names,
--                     leave balance, training completion and scores
--   restricted        comp (base, bonus, equity, grade), home address, personal
--                     phone, date of birth, emergency contact
--   highly_restricted SSN, bank routing number, medical/FMLA reason, ADA
--                     accommodation, ER case type, investigation notes, background checks
-- Bronze is tagged too: raw extracts hold the same sensitive data.
-- Gold views are not tagged; they inherit protection from these base tables.
-- Generated from the mapping in docs/design_notes.md; edit both together.
-- ============================================================================


-- glb_silver.departments
ALTER TABLE {{catalog}}.glb_silver.departments ALTER COLUMN dept_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.departments ALTER COLUMN dept_name SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.departments ALTER COLUMN parent_dept_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.departments ALTER COLUMN head_employee_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.departments ALTER COLUMN dept_id SET TAGS ('{{scope_tag}}' = 'department');

-- glb_silver.employees
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN employee_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN full_name SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN work_email SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN job_title SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN job_level SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN dept_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN manager_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN country SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN hire_date SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN home_address SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN personal_phone SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN date_of_birth SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN emergency_contact SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN ssn SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN bank_routing_number SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_silver.employees ALTER COLUMN dept_id SET TAGS ('{{scope_tag}}' = 'department');

-- glb_silver.performance
ALTER TABLE {{catalog}}.glb_silver.performance ALTER COLUMN employee_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.performance ALTER COLUMN dept_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.performance ALTER COLUMN review_year SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.performance ALTER COLUMN rating SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.glb_silver.performance ALTER COLUMN review_text SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.glb_silver.performance ALTER COLUMN promotion_history SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.glb_silver.performance ALTER COLUMN dept_id SET TAGS ('{{scope_tag}}' = 'department');

-- glb_silver.leave_records
ALTER TABLE {{catalog}}.glb_silver.leave_records ALTER COLUMN employee_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.leave_records ALTER COLUMN dept_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.leave_records ALTER COLUMN leave_type SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.leave_records ALTER COLUMN leave_balance_hours SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.glb_silver.leave_records ALTER COLUMN medical_leave_reason SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_silver.leave_records ALTER COLUMN ada_accommodation SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_silver.leave_records ALTER COLUMN dept_id SET TAGS ('{{scope_tag}}' = 'department');

-- glb_silver.employee_relations
ALTER TABLE {{catalog}}.glb_silver.employee_relations ALTER COLUMN case_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employee_relations ALTER COLUMN employee_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employee_relations ALTER COLUMN dept_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_silver.employee_relations ALTER COLUMN case_type SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_silver.employee_relations ALTER COLUMN investigation_notes SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_silver.employee_relations ALTER COLUMN background_check_result SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_silver.employee_relations ALTER COLUMN dept_id SET TAGS ('{{scope_tag}}' = 'department');

-- tr_silver.compensation
ALTER TABLE {{catalog}}.tr_silver.compensation ALTER COLUMN employee_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.tr_silver.compensation ALTER COLUMN dept_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.tr_silver.compensation ALTER COLUMN country SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.tr_silver.compensation ALTER COLUMN currency SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.tr_silver.compensation ALTER COLUMN comp_grade SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.tr_silver.compensation ALTER COLUMN base_salary SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.tr_silver.compensation ALTER COLUMN bonus_target SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.tr_silver.compensation ALTER COLUMN equity_grant SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.tr_silver.compensation ALTER COLUMN dept_id SET TAGS ('{{scope_tag}}' = 'department');

-- ta_silver.requisitions
ALTER TABLE {{catalog}}.ta_silver.requisitions ALTER COLUMN requisition_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_silver.requisitions ALTER COLUMN dept_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_silver.requisitions ALTER COLUMN job_title SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_silver.requisitions ALTER COLUMN status SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_silver.requisitions ALTER COLUMN dept_id SET TAGS ('{{scope_tag}}' = 'department');

-- ta_silver.applications
ALTER TABLE {{catalog}}.ta_silver.applications ALTER COLUMN application_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_silver.applications ALTER COLUMN requisition_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_silver.applications ALTER COLUMN dept_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_silver.applications ALTER COLUMN stage SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_silver.applications ALTER COLUMN candidate_name SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.ta_silver.applications ALTER COLUMN interview_notes SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.ta_silver.applications ALTER COLUMN resume_text SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.ta_silver.applications ALTER COLUMN dept_id SET TAGS ('{{scope_tag}}' = 'department');

-- lrn_silver.training_records
ALTER TABLE {{catalog}}.lrn_silver.training_records ALTER COLUMN employee_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.lrn_silver.training_records ALTER COLUMN dept_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.lrn_silver.training_records ALTER COLUMN course_name SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.lrn_silver.training_records ALTER COLUMN completion_status SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.lrn_silver.training_records ALTER COLUMN assessment_score SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.lrn_silver.training_records ALTER COLUMN dept_id SET TAGS ('{{scope_tag}}' = 'department');

-- glb_bronze.hris_supervisory_orgs_raw
ALTER TABLE {{catalog}}.glb_bronze.hris_supervisory_orgs_raw ALTER COLUMN org_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_supervisory_orgs_raw ALTER COLUMN org_name SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_supervisory_orgs_raw ALTER COLUMN parent_org_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_supervisory_orgs_raw ALTER COLUMN head_worker_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_supervisory_orgs_raw ALTER COLUMN org_id SET TAGS ('{{scope_tag}}' = 'department');

-- glb_bronze.hris_workers_raw
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN worker_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN first_name SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN last_name SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN work_email SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN job_title SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN job_level SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN org_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN manager_worker_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN country SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN hire_date SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN home_address SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN personal_phone SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN date_of_birth SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN emergency_contact SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN ssn SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN bank_routing_number SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_workers_raw ALTER COLUMN org_id SET TAGS ('{{scope_tag}}' = 'department');

-- glb_bronze.hris_performance_raw
ALTER TABLE {{catalog}}.glb_bronze.hris_performance_raw ALTER COLUMN worker_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_performance_raw ALTER COLUMN org_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_performance_raw ALTER COLUMN review_year SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_performance_raw ALTER COLUMN rating SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.glb_bronze.hris_performance_raw ALTER COLUMN review_text SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.glb_bronze.hris_performance_raw ALTER COLUMN promotion_history SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.glb_bronze.hris_performance_raw ALTER COLUMN org_id SET TAGS ('{{scope_tag}}' = 'department');

-- glb_bronze.hris_leave_raw
ALTER TABLE {{catalog}}.glb_bronze.hris_leave_raw ALTER COLUMN worker_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_leave_raw ALTER COLUMN org_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_leave_raw ALTER COLUMN leave_type SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_leave_raw ALTER COLUMN leave_balance_hours SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.glb_bronze.hris_leave_raw ALTER COLUMN medical_leave_reason SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_leave_raw ALTER COLUMN ada_accommodation SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_leave_raw ALTER COLUMN org_id SET TAGS ('{{scope_tag}}' = 'department');

-- glb_bronze.hris_er_cases_raw
ALTER TABLE {{catalog}}.glb_bronze.hris_er_cases_raw ALTER COLUMN case_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_er_cases_raw ALTER COLUMN worker_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_er_cases_raw ALTER COLUMN org_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.glb_bronze.hris_er_cases_raw ALTER COLUMN case_type SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_er_cases_raw ALTER COLUMN investigation_notes SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_er_cases_raw ALTER COLUMN background_check_result SET TAGS ('{{tier_tag}}' = 'highly_restricted');
ALTER TABLE {{catalog}}.glb_bronze.hris_er_cases_raw ALTER COLUMN org_id SET TAGS ('{{scope_tag}}' = 'department');

-- tr_bronze.hris_comp_raw
ALTER TABLE {{catalog}}.tr_bronze.hris_comp_raw ALTER COLUMN worker_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.tr_bronze.hris_comp_raw ALTER COLUMN org_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.tr_bronze.hris_comp_raw ALTER COLUMN country SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.tr_bronze.hris_comp_raw ALTER COLUMN currency SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.tr_bronze.hris_comp_raw ALTER COLUMN comp_grade SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.tr_bronze.hris_comp_raw ALTER COLUMN base_salary SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.tr_bronze.hris_comp_raw ALTER COLUMN bonus_target SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.tr_bronze.hris_comp_raw ALTER COLUMN equity_grant SET TAGS ('{{tier_tag}}' = 'restricted');
ALTER TABLE {{catalog}}.tr_bronze.hris_comp_raw ALTER COLUMN org_id SET TAGS ('{{scope_tag}}' = 'department');

-- ta_bronze.ats_requisitions_raw
ALTER TABLE {{catalog}}.ta_bronze.ats_requisitions_raw ALTER COLUMN requisition_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_bronze.ats_requisitions_raw ALTER COLUMN org_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_bronze.ats_requisitions_raw ALTER COLUMN job_title SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_bronze.ats_requisitions_raw ALTER COLUMN status SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_bronze.ats_requisitions_raw ALTER COLUMN org_id SET TAGS ('{{scope_tag}}' = 'department');

-- ta_bronze.ats_applications_raw
ALTER TABLE {{catalog}}.ta_bronze.ats_applications_raw ALTER COLUMN application_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_bronze.ats_applications_raw ALTER COLUMN requisition_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_bronze.ats_applications_raw ALTER COLUMN org_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_bronze.ats_applications_raw ALTER COLUMN stage SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.ta_bronze.ats_applications_raw ALTER COLUMN candidate_name SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.ta_bronze.ats_applications_raw ALTER COLUMN interview_notes SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.ta_bronze.ats_applications_raw ALTER COLUMN resume_text SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.ta_bronze.ats_applications_raw ALTER COLUMN org_id SET TAGS ('{{scope_tag}}' = 'department');

-- lrn_bronze.lms_training_raw
ALTER TABLE {{catalog}}.lrn_bronze.lms_training_raw ALTER COLUMN worker_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.lrn_bronze.lms_training_raw ALTER COLUMN org_id SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.lrn_bronze.lms_training_raw ALTER COLUMN course_name SET TAGS ('{{tier_tag}}' = 'internal');
ALTER TABLE {{catalog}}.lrn_bronze.lms_training_raw ALTER COLUMN completion_status SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.lrn_bronze.lms_training_raw ALTER COLUMN assessment_score SET TAGS ('{{tier_tag}}' = 'confidential');
ALTER TABLE {{catalog}}.lrn_bronze.lms_training_raw ALTER COLUMN org_id SET TAGS ('{{scope_tag}}' = 'department');

-- Reset the pipeline persona set in 02_bronze.sql
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();

-- Verify: count of tagged columns per schema and tier
SELECT schema_name, tag_name, tag_value, count(*) AS columns
FROM {{catalog}}.information_schema.column_tags
WHERE tag_name IN ('{{tier_tag}}', '{{scope_tag}}')
GROUP BY ALL
ORDER BY schema_name, tag_name, tag_value;
