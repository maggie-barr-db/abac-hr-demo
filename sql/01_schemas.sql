-- ============================================================================
-- abac-hr-demo / 01: schemas
-- Templated: {{catalog}}
--
-- Sub-domains are mirrored as schema prefixes inside one catalog:
--   glb = global (workers, org, performance, leave, employee relations)
--   tr  = total rewards (compensation)
--   ta  = talent acquisition (requisitions, applications)
--   lrn = learning (training records)
--   byod = user sandbox (bring your own data)
-- In a multi-catalog layout, each prefix becomes its own catalog with
-- bronze/silver/gold schemas; the SQL is otherwise the same.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS {{catalog}}.glb_bronze     COMMENT 'Global: raw HRIS extracts';
CREATE SCHEMA IF NOT EXISTS {{catalog}}.glb_silver     COMMENT 'Global: curated worker, org, performance, leave and ER tables';
CREATE SCHEMA IF NOT EXISTS {{catalog}}.glb_gold       COMMENT 'Global: business-facing views';
CREATE SCHEMA IF NOT EXISTS {{catalog}}.glb_governance COMMENT 'Policy functions and entitlements. Never tagged; governance-owned.';

CREATE SCHEMA IF NOT EXISTS {{catalog}}.tr_bronze  COMMENT 'Total rewards: raw comp extracts';
CREATE SCHEMA IF NOT EXISTS {{catalog}}.tr_silver  COMMENT 'Total rewards: curated compensation';
CREATE SCHEMA IF NOT EXISTS {{catalog}}.tr_gold    COMMENT 'Total rewards: comp views and metric views';

CREATE SCHEMA IF NOT EXISTS {{catalog}}.ta_bronze  COMMENT 'Talent acquisition: raw recruiting extracts';
CREATE SCHEMA IF NOT EXISTS {{catalog}}.ta_silver  COMMENT 'Talent acquisition: curated requisitions and applications';
CREATE SCHEMA IF NOT EXISTS {{catalog}}.ta_gold    COMMENT 'Talent acquisition: business-facing views';

CREATE SCHEMA IF NOT EXISTS {{catalog}}.lrn_bronze COMMENT 'Learning: raw LMS extracts';
CREATE SCHEMA IF NOT EXISTS {{catalog}}.lrn_silver COMMENT 'Learning: curated training records';
CREATE SCHEMA IF NOT EXISTS {{catalog}}.lrn_gold   COMMENT 'Learning: business-facing views';

CREATE SCHEMA IF NOT EXISTS {{catalog}}.byod       COMMENT 'User sandbox (bring your own data). Used for the copy-leakage scenario.';

SHOW SCHEMAS IN {{catalog}};
