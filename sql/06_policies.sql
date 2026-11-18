-- ============================================================================
-- abac-hr-demo / 06: ABAC policies, set once at the catalog level
-- Templated: {{catalog}}, {{tier_tag}}, {{scope_tag}}
--
-- Four policies cover every table in the catalog, current and future, through tags:
--   1 row filter  on columns tagged {{scope_tag}} = department
--   3 tier masks  on columns tagged {{tier_tag}} = confidential | restricted | highly_restricted
-- ('internal' has no policy: it's clear for everyone.)
--
-- Multi-catalog layout: run this file once per catalog (only {{catalog}} changes).
-- Metastore-level policies (Beta) would reduce that to one set across all catalogs.
-- ============================================================================

CREATE OR REPLACE POLICY hr_demo_dept_row_filter
ON CATALOG {{catalog}}
COMMENT 'Department heads see only rows in their department subtree'
ROW FILTER {{catalog}}.glb_governance.rf_dept_scope
TO `account users`
FOR TABLES
MATCH COLUMNS has_tag_value('{{scope_tag}}', 'department') AS d
USING COLUMNS (d);

CREATE OR REPLACE POLICY hr_demo_mask_confidential
ON CATALOG {{catalog}}
COMMENT 'Masks {{tier_tag}} = confidential unless dept_head, hr_trusted or er_legal'
COLUMN MASK {{catalog}}.glb_governance.mask_confidential
TO `account users`
FOR TABLES
MATCH COLUMNS has_tag_value('{{tier_tag}}', 'confidential') AS c
ON COLUMN c;

CREATE OR REPLACE POLICY hr_demo_mask_restricted
ON CATALOG {{catalog}}
COMMENT 'Masks {{tier_tag}} = restricted unless dept_head, hr_trusted or er_legal'
COLUMN MASK {{catalog}}.glb_governance.mask_restricted
TO `account users`
FOR TABLES
MATCH COLUMNS has_tag_value('{{tier_tag}}', 'restricted') AS c
ON COLUMN c;

CREATE OR REPLACE POLICY hr_demo_mask_highly_restricted
ON CATALOG {{catalog}}
COMMENT 'Masks {{tier_tag}} = highly_restricted unless er_legal'
COLUMN MASK {{catalog}}.glb_governance.mask_highly_restricted
TO `account users`
FOR TABLES
MATCH COLUMNS has_tag_value('{{tier_tag}}', 'highly_restricted') AS c
ON COLUMN c;

SHOW POLICIES ON CATALOG {{catalog}};
