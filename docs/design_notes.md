# Design notes

## Layout (single-catalog mirror)
Sub-domains are mirrored as schema prefixes inside one catalog: `glb_` (global), `tr_` (total rewards), `ta_` (talent acquisition), `lrn_` (learning), each with `bronze`, `silver` and `gold` schemas, plus `glb_governance` (policy functions and entitlements, never tagged) and `byod` (user sandbox). In a multi-catalog layout each prefix becomes its own catalog and the policies are created once per catalog; metastore-level policies (Beta) would reduce that to one set.

## Governed tags
- `hr_pii_demo_tag`: sensitivity tier. Allowed values `internal`, `confidential`, `restricted`, `highly_restricted`.
- `hr_scope_demo_tag`: marks the column the row-filter policy scopes on. Allowed values `reporting_line` (used: `employee_id` on employee tables, `hiring_manager_id` on recruiting tables) and `department` (kept for future use).

## Tier mapping (silver; bronze mirrors it with raw column names)
| Table | Column | Tier |
|---|---|---|
| glb_silver.departments | dept_id | internal |
| glb_silver.departments | dept_name | internal |
| glb_silver.departments | parent_dept_id | internal |
| glb_silver.departments | head_employee_id | internal |
| glb_silver.employees | employee_id | internal |
| glb_silver.employees | full_name | internal |
| glb_silver.employees | work_email | internal |
| glb_silver.employees | job_title | internal |
| glb_silver.employees | job_level | internal |
| glb_silver.employees | dept_id | internal |
| glb_silver.employees | manager_id | internal |
| glb_silver.employees | country | internal |
| glb_silver.employees | hire_date | internal |
| glb_silver.employees | home_address | restricted |
| glb_silver.employees | personal_phone | restricted |
| glb_silver.employees | date_of_birth | restricted |
| glb_silver.employees | emergency_contact | restricted |
| glb_silver.employees | ssn | highly_restricted |
| glb_silver.employees | bank_routing_number | highly_restricted |
| glb_silver.performance | employee_id | internal |
| glb_silver.performance | dept_id | internal |
| glb_silver.performance | review_year | internal |
| glb_silver.performance | rating | confidential |
| glb_silver.performance | review_text | confidential |
| glb_silver.performance | promotion_history | confidential |
| glb_silver.leave_records | employee_id | internal |
| glb_silver.leave_records | dept_id | internal |
| glb_silver.leave_records | leave_type | internal |
| glb_silver.leave_records | leave_balance_hours | confidential |
| glb_silver.leave_records | medical_leave_reason | highly_restricted |
| glb_silver.leave_records | ada_accommodation | highly_restricted |
| glb_silver.employee_relations | case_id | internal |
| glb_silver.employee_relations | employee_id | internal |
| glb_silver.employee_relations | dept_id | internal |
| glb_silver.employee_relations | case_type | highly_restricted |
| glb_silver.employee_relations | investigation_notes | highly_restricted |
| glb_silver.employee_relations | background_check_result | highly_restricted |
| tr_silver.compensation | employee_id | internal |
| tr_silver.compensation | dept_id | internal |
| tr_silver.compensation | country | internal |
| tr_silver.compensation | currency | internal |
| tr_silver.compensation | comp_grade | restricted |
| tr_silver.compensation | base_salary | restricted |
| tr_silver.compensation | bonus_target | restricted |
| tr_silver.compensation | equity_grant | restricted |
| ta_silver.requisitions | requisition_id | internal |
| ta_silver.requisitions | dept_id | internal |
| ta_silver.requisitions | hiring_manager_id | internal |
| ta_silver.requisitions | job_title | internal |
| ta_silver.requisitions | status | internal |
| ta_silver.applications | application_id | internal |
| ta_silver.applications | requisition_id | internal |
| ta_silver.applications | dept_id | internal |
| ta_silver.applications | hiring_manager_id | internal |
| ta_silver.applications | stage | internal |
| ta_silver.applications | candidate_name | confidential |
| ta_silver.applications | interview_notes | confidential |
| ta_silver.applications | resume_text | confidential |
| lrn_silver.training_records | employee_id | internal |
| lrn_silver.training_records | dept_id | internal |
| lrn_silver.training_records | course_name | internal |
| lrn_silver.training_records | completion_status | confidential |
| lrn_silver.training_records | assessment_score | confidential |

## Reporting-line access (people managers)
- A manager sees everyone below them in the manager hierarchy, at any depth, plus their own row. Their own manager and the CEO are never visible to them.
- `glb_governance.reporting_closure` holds every (manager, report) pair, flattened once from `employees.manager_id`, so the row filter is a single lookup.
- Anyone with at least one report resolves to `people_manager`; no list to maintain. `glb_governance.user_employee_map` links a Databricks user to their employee record by work email.
- Recruiting tables carry `hiring_manager_id`; managers see requisitions and applications where the hiring manager is in their line.
- Demo managers (Finance): Priya Nguyen W00002 (Head of Finance, 399 in line), Anya Nguyen W00030 (Senior Manager, 46), Omar Patel W00075 (Manager, 15).

## Gotchas found while building
- Once policies exist they also protect bronze, so rebuilds must run as an identity exempt from the masks (the pipeline SP in production; the `er_legal` override in the demo), or silver is built from masked values.
- The masks call `current_persona()`; any object it reads must exist while policy-protected tables are rebuilt (see the bootstrap function in `05_governance.sql`).
- `CREATE OR REPLACE TABLE` keeps existing column tags. Drop the table first when you need it to start untagged (the copy-leakage scenario does this).
- `DROP POLICY` doesn't accept `IF EXISTS`.
