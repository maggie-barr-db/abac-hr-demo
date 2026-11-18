-- ============================================================================
-- abac-hr-demo / 05: governance schema - entitlements and policy functions
-- Templated: {{catalog}}
--
-- Personas (most privilege wins when someone matches more than one):
--   er_legal        - all rows; every tier clear
--   hr_trusted      - all rows; internal, confidential, restricted clear; highly_restricted masked
--   people_manager  - only rows for people in their reporting line (everyone below them, at any
--                     depth, plus themselves); internal, confidential, restricted clear;
--                     highly_restricted masked. Recruiting rows: only their own requisitions.
--   hr_analyst      - default; all rows; only internal clear
--
-- Identity resolves in this order:
--   1. glb_governance.persona_override  DEMO ONLY. Lets one user switch personas. Anyone who can
--                                       write to this table can grant themselves access, so it
--                                       must be removed in production.
--   2. group membership                 HR-DBX-ER-LEGAL -> er_legal, HR-DBX-TRUSTED -> hr_trusted
--   3. the hierarchy                    the user's employee record has at least one report -> people_manager
--   4. otherwise                        hr_analyst
--
-- The glb_governance tables are never tagged, so the catalog-level policies don't
-- apply to the lookups the policy functions make.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo persona override
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.glb_governance.persona_override (
  user_name         STRING COMMENT 'Databricks user name (current_user())',
  persona           STRING COMMENT 'er_legal | hr_trusted | people_manager | hr_analyst',
  scope_employee_id STRING COMMENT 'For people_manager: the employee whose reporting line to use'
) COMMENT 'DEMO ONLY. Persona switch for a single-user workspace. Remove in production.';


-- Bootstrap persona function. The tier masks call current_persona(), so it must resolve
-- while the tables below are (re)built from policy-protected silver tables. The full
-- definition (with the manager check) replaces it further down.
CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.current_persona()
RETURNS STRING
RETURN coalesce(
  (SELECT lower(persona) FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user() LIMIT 1),
  CASE WHEN is_account_group_member('HR-DBX-ER-LEGAL') THEN 'er_legal'
       WHEN is_account_group_member('HR-DBX-TRUSTED')  THEN 'hr_trusted'
       ELSE 'hr_analyst' END
);

-- ----------------------------------------------------------------------------
-- Reporting closure: every (manager, report) pair at any depth, plus (self, self).
-- Derived once in the pipeline from employees.manager_id, so the row filter is a single
-- lookup instead of walking the hierarchy at query time. The tree is at most 6 levels deep
-- (CEO -> function head -> sub-function head -> senior manager -> manager -> IC).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.glb_governance.reporting_closure
COMMENT 'Flattened manager hierarchy: manager_id sees report_id (includes self)'
AS
WITH e AS (SELECT employee_id, manager_id FROM {{catalog}}.glb_silver.employees),
l1 AS (SELECT manager_id AS m, employee_id AS r FROM e WHERE manager_id IS NOT NULL),
l2 AS (SELECT a.m, b.r FROM l1 a JOIN l1 b ON b.m = a.r),
l3 AS (SELECT a.m, b.r FROM l2 a JOIN l1 b ON b.m = a.r),
l4 AS (SELECT a.m, b.r FROM l3 a JOIN l1 b ON b.m = a.r),
l5 AS (SELECT a.m, b.r FROM l4 a JOIN l1 b ON b.m = a.r),
l6 AS (SELECT a.m, b.r FROM l5 a JOIN l1 b ON b.m = a.r)
SELECT employee_id AS manager_id, employee_id AS report_id FROM e
UNION SELECT m, r FROM l1
UNION SELECT m, r FROM l2
UNION SELECT m, r FROM l3
UNION SELECT m, r FROM l4
UNION SELECT m, r FROM l5
UNION SELECT m, r FROM l6;

-- ----------------------------------------------------------------------------
-- User -> employee mapping (by work email). In production, built from the HRIS worker
-- record by a scheduled job running as a service principal.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.glb_governance.user_employee_map
COMMENT 'Maps a Databricks user to their employee record'
AS
SELECT work_email AS user_name, employee_id FROM {{catalog}}.glb_silver.employees;

-- ----------------------------------------------------------------------------
-- Identity helpers
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.current_scope_employee()
RETURNS STRING
COMMENT 'The employee whose reporting line scopes the caller (override first, then own record)'
RETURN coalesce(
  (SELECT scope_employee_id FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user() LIMIT 1),
  (SELECT employee_id FROM {{catalog}}.glb_governance.user_employee_map WHERE user_name = current_user() LIMIT 1)
);

CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.current_persona()
RETURNS STRING
COMMENT 'Resolves the caller''s persona: override (demo), then groups, then manager-by-hierarchy, else hr_analyst'
RETURN coalesce(
  (SELECT lower(persona) FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user() LIMIT 1),
  CASE
    WHEN is_account_group_member('HR-DBX-ER-LEGAL') THEN 'er_legal'
    WHEN is_account_group_member('HR-DBX-TRUSTED')  THEN 'hr_trusted'
    WHEN EXISTS (SELECT 1 FROM {{catalog}}.glb_governance.reporting_closure
                 WHERE manager_id = {{catalog}}.glb_governance.current_scope_employee()
                   AND report_id <> manager_id) THEN 'people_manager'
    ELSE 'hr_analyst'
  END
);

CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.in_reporting_line(emp STRING)
RETURNS BOOLEAN
COMMENT 'True when emp is the caller or anyone below the caller in the manager hierarchy'
RETURN emp IN (
  SELECT report_id FROM {{catalog}}.glb_governance.reporting_closure
  WHERE manager_id = {{catalog}}.glb_governance.current_scope_employee()
);

-- ----------------------------------------------------------------------------
-- Row filter: managers see only their reporting line; every other persona sees all rows
-- (their sensitive columns are handled by the tier masks)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.rf_reporting_line(emp STRING)
RETURNS BOOLEAN
COMMENT 'Row filter for columns tagged with the reporting_line scope tag'
RETURN {{catalog}}.glb_governance.current_persona() <> 'people_manager'
    OR {{catalog}}.glb_governance.in_reporting_line(emp);

-- ----------------------------------------------------------------------------
-- Tier masks. One VARIANT function per tier covers every column type:
-- text -> '****', any other type -> NULL (so aggregates and comparisons see nothing).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.mask_confidential(val VARIANT)
RETURNS VARIANT
COMMENT 'Clear for people_manager, hr_trusted, er_legal'
RETURN CASE
  WHEN {{catalog}}.glb_governance.current_persona() IN ('people_manager', 'hr_trusted', 'er_legal') THEN val
  WHEN schema_of_variant(val) = 'STRING' THEN '****'::VARIANT
  ELSE NULL::VARIANT
END;

CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.mask_restricted(val VARIANT)
RETURNS VARIANT
COMMENT 'Clear for people_manager, hr_trusted, er_legal'
RETURN CASE
  WHEN {{catalog}}.glb_governance.current_persona() IN ('people_manager', 'hr_trusted', 'er_legal') THEN val
  WHEN schema_of_variant(val) = 'STRING' THEN '****'::VARIANT
  ELSE NULL::VARIANT
END;

CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.mask_highly_restricted(val VARIANT)
RETURNS VARIANT
COMMENT 'Clear for er_legal only'
RETURN CASE
  WHEN {{catalog}}.glb_governance.current_persona() = 'er_legal' THEN val
  WHEN schema_of_variant(val) = 'STRING' THEN '****'::VARIANT
  ELSE NULL::VARIANT
END;

-- Remove the earlier department-scope objects (replaced by reporting line). The old
-- hr_demo_dept_row_filter policy was dropped once by hand (DROP POLICY doesn't accept IF EXISTS).
DROP FUNCTION IF EXISTS {{catalog}}.glb_governance.rf_dept_scope;
DROP FUNCTION IF EXISTS {{catalog}}.glb_governance.in_dept_scope;
DROP FUNCTION IF EXISTS {{catalog}}.glb_governance.current_scope_dept;
DROP TABLE IF EXISTS {{catalog}}.glb_governance.dept_closure;
DROP TABLE IF EXISTS {{catalog}}.glb_governance.user_dept_scope;


-- Checks
SELECT
  (SELECT count(*) FROM {{catalog}}.glb_governance.reporting_closure)                                  AS closure_pairs,
  (SELECT count(DISTINCT manager_id) FROM {{catalog}}.glb_governance.reporting_closure WHERE manager_id <> report_id) AS managers,
  (SELECT count(*) - 1 FROM {{catalog}}.glb_governance.reporting_closure WHERE manager_id = 'W00001') AS ceo_line_expect_1999,
  {{catalog}}.glb_governance.current_persona()                                                         AS my_persona_now;
