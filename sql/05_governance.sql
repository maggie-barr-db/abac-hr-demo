-- ============================================================================
-- abac-hr-demo / 05: governance schema - entitlements and policy functions
-- Templated: {{catalog}}
--
-- Personas (most privilege wins when someone matches more than one):
--   er_legal    - all rows; every tier clear
--   hr_trusted  - all rows; internal, confidential, restricted clear; highly_restricted masked
--   dept_head   - only rows in their department subtree; internal, confidential, restricted
--                 clear; highly_restricted masked
--   hr_analyst  - default; all rows; only internal clear
--
-- Identity resolves in this order:
--   1. glb_governance.persona_override  DEMO ONLY. Lets one user switch personas. Anyone who can
--                                       write to this table can grant themselves access, so it
--                                       must be removed in production.
--   2. group membership                 HR-DBX-ER-LEGAL -> er_legal, HR-DBX-TRUSTED -> hr_trusted
--   3. glb_governance.user_dept_scope   a row here -> dept_head (scope = their department)
--   4. otherwise                        hr_analyst
--
-- The glb_governance tables are never tagged, so the catalog-level policies don't
-- apply to the lookups the policy functions make.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Demo persona override (created first so a rebuild can reset it)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS {{catalog}}.glb_governance.persona_override (
  user_name     STRING COMMENT 'Databricks user name (current_user())',
  persona       STRING COMMENT 'er_legal | hr_trusted | dept_head | hr_analyst',
  scope_dept_id STRING COMMENT 'Department for dept_head; NULL otherwise'
) COMMENT 'DEMO ONLY. Persona switch for a single-user workspace. Remove in production.';

-- Reset your own persona before reading policy-protected tables below
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();

-- ----------------------------------------------------------------------------
-- Department closure: every (ancestor, descendant) pair, including self.
-- Derived from the HRIS parent links once in the pipeline, so the row filter is a
-- single lookup instead of a hierarchy walk at query time. The tree is 2 levels deep.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.glb_governance.dept_closure
COMMENT 'Flattened department hierarchy derived from glb_silver.departments'
AS
SELECT dept_id AS ancestor_dept_id, dept_id AS descendant_dept_id FROM {{catalog}}.glb_silver.departments
UNION
SELECT parent_dept_id, dept_id FROM {{catalog}}.glb_silver.departments WHERE parent_dept_id IS NOT NULL
UNION
SELECT p.parent_dept_id, c.dept_id
FROM {{catalog}}.glb_silver.departments c
JOIN {{catalog}}.glb_silver.departments p ON p.dept_id = c.parent_dept_id
WHERE p.parent_dept_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- Department-head entitlements: which user heads which department.
-- Built from the department head's work email. In production this is a scheduled
-- job (run as a service principal) over the HRIS supervisory org.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.glb_governance.user_dept_scope
COMMENT 'Department heads and the department they head (scope covers its subtree via dept_closure)'
AS
SELECT e.work_email AS user_name, d.dept_id
FROM {{catalog}}.glb_silver.departments d
JOIN {{catalog}}.glb_silver.employees e ON e.employee_id = d.head_employee_id;

-- ----------------------------------------------------------------------------
-- Identity helpers
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.current_persona()
RETURNS STRING
COMMENT 'Resolves the caller''s persona: override (demo), then groups, then dept-head entitlements, else hr_analyst'
RETURN coalesce(
  (SELECT lower(persona) FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user() LIMIT 1),
  CASE
    WHEN is_account_group_member('HR-DBX-ER-LEGAL') THEN 'er_legal'
    WHEN is_account_group_member('HR-DBX-TRUSTED')  THEN 'hr_trusted'
    WHEN EXISTS (SELECT 1 FROM {{catalog}}.glb_governance.user_dept_scope WHERE user_name = current_user()) THEN 'dept_head'
    ELSE 'hr_analyst'
  END
);

CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.current_scope_dept()
RETURNS STRING
COMMENT 'Department a dept_head is scoped to (override first, then entitlements)'
RETURN coalesce(
  (SELECT scope_dept_id FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user() LIMIT 1),
  (SELECT dept_id FROM {{catalog}}.glb_governance.user_dept_scope WHERE user_name = current_user() LIMIT 1)
);

CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.in_dept_scope(dept STRING)
RETURNS BOOLEAN
COMMENT 'True when dept is in the caller''s department subtree'
RETURN dept IN (
  SELECT descendant_dept_id FROM {{catalog}}.glb_governance.dept_closure
  WHERE ancestor_dept_id = {{catalog}}.glb_governance.current_scope_dept()
);

-- ----------------------------------------------------------------------------
-- Row filter: dept heads see only their subtree; every other persona sees all rows
-- (their sensitive columns are handled by the tier masks)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.rf_dept_scope(dept STRING)
RETURNS BOOLEAN
COMMENT 'Row filter for columns tagged with the department scope tag'
RETURN {{catalog}}.glb_governance.current_persona() <> 'dept_head'
    OR {{catalog}}.glb_governance.in_dept_scope(dept);

-- ----------------------------------------------------------------------------
-- Tier masks. One VARIANT function per tier covers every column type:
-- text -> '****', any other type -> NULL (so aggregates and comparisons see nothing).
-- Confidential and restricted have the same audience today; they're separate so a
-- tier's audience can change without touching the other.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.mask_confidential(val VARIANT)
RETURNS VARIANT
COMMENT 'Clear for dept_head, hr_trusted, er_legal'
RETURN CASE
  WHEN {{catalog}}.glb_governance.current_persona() IN ('dept_head', 'hr_trusted', 'er_legal') THEN val
  WHEN schema_of_variant(val) = 'STRING' THEN '****'::VARIANT
  ELSE NULL::VARIANT
END;

CREATE OR REPLACE FUNCTION {{catalog}}.glb_governance.mask_restricted(val VARIANT)
RETURNS VARIANT
COMMENT 'Clear for dept_head, hr_trusted, er_legal'
RETURN CASE
  WHEN {{catalog}}.glb_governance.current_persona() IN ('dept_head', 'hr_trusted', 'er_legal') THEN val
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

-- Checks
SELECT
  (SELECT count(*) FROM {{catalog}}.glb_governance.dept_closure)    AS closure_pairs_expect_40,
  (SELECT count(*) FROM {{catalog}}.glb_governance.user_dept_scope) AS dept_heads_expect_16,
  {{catalog}}.glb_governance.current_persona()                      AS my_persona_now;
