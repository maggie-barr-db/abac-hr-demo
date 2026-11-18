-- ============================================================================
-- abac-hr-demo / 06: ABAC policies, set once at the catalog level
-- Templated: {{catalog}}, {{tier_tag}}, {{scope_tag}}
--
-- Four policies cover every table in the catalog, current and future, through tags:
--   1 row filter  on columns tagged {{scope_tag}} = reporting_line
--   3 tier masks  on columns tagged {{tier_tag}} = confidential | restricted | highly_restricted
-- ('internal' has no policy: it's clear for everyone.)
--
-- Multi-catalog layout: run this file once per catalog (only {{catalog}} changes).
-- Metastore-level policies (Beta) would reduce that to one set across all catalogs.
-- ============================================================================

CREATE OR REPLACE POLICY hr_demo_reporting_line_row_filter
ON CATALOG {{catalog}}
COMMENT 'People managers see only rows for people in their reporting line'
ROW FILTER {{catalog}}.glb_governance.rf_reporting_line
TO `account users`
FOR TABLES
MATCH COLUMNS has_tag_value('{{scope_tag}}', 'reporting_line') AS e
USING COLUMNS (e);

CREATE OR REPLACE POLICY hr_demo_mask_confidential
ON CATALOG {{catalog}}
COMMENT 'Masks {{tier_tag}} = confidential unless people_manager, hr_trusted or er_legal'
COLUMN MASK {{catalog}}.glb_governance.mask_confidential
TO `account users`
FOR TABLES
MATCH COLUMNS has_tag_value('{{tier_tag}}', 'confidential') AS c
ON COLUMN c;

CREATE OR REPLACE POLICY hr_demo_mask_restricted
ON CATALOG {{catalog}}
COMMENT 'Masks {{tier_tag}} = restricted unless people_manager, hr_trusted or er_legal'
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
