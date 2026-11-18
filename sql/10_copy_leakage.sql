-- ============================================================================
-- abac-hr-demo / 10: copy leakage into BYOD - the leak and how to detect it
-- Templated: {{catalog}}, {{tier_tag}}, {{scope_tag}}
--
-- Scenario: an HR trusted user (sees comp and home address in clear) copies data into
-- the BYOD sandbox, where they have CREATE. The copy's columns carry no tags, so the
-- catalog-level policies don't match them: anyone who can read the copy sees clear
-- values, and the department row filter doesn't apply either.
--
-- Remediation (tag the copy from its sources) is scripts/remediate_untagged_copies.py
-- and the notebook's remediation cell. Once tagged, the existing four policies protect
-- the copy immediately; no new policy is needed.
-- Not used here: governed tag propagation (Beta), which would carry the tags into the
-- copy automatically.
-- ============================================================================

-- 1. As hr_trusted, copy comp + home address into BYOD
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'hr_trusted', NULL);

-- Drop first: CREATE OR REPLACE keeps the old column tags, which would hide the leak on a re-run
DROP TABLE IF EXISTS {{catalog}}.byod.comp_review_extract;
CREATE TABLE {{catalog}}.byod.comp_review_extract
COMMENT 'User-made extract for a comp review (copy-leakage scenario)'
AS
SELECT c.employee_id, c.full_name, c.dept_id, c.dept_name, d.home_address,
       c.base_salary, c.bonus_target, c.total_comp
FROM {{catalog}}.tr_gold.employee_comp c
JOIN {{catalog}}.glb_gold.employee_directory d ON d.employee_id = c.employee_id;

-- 2. As hr_analyst, read the copy: clear comp and addresses = the leak
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'hr_analyst', NULL);

SELECT 'hr_analyst reads BYOD copy' AS check_name,
       count(*)                       AS rows_visible,
       count_if(base_salary IS NOT NULL)  AS clear_salaries,
       count_if(home_address <> '****')   AS clear_addresses,
       max(total_comp)                    AS max_total_comp
FROM {{catalog}}.byod.comp_review_extract;

-- 3. As people manager Anya Nguyen (W00030), read the copy: the row filter doesn't apply either
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'people_manager', 'W00030');

SELECT 'people_manager:W00030 reads BYOD copy' AS check_name,
       count(*) AS rows_visible,
       count(DISTINCT dept_id) AS departments_visible
FROM {{catalog}}.byod.comp_review_extract;

DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();

-- 4a. Detection by column name (instant): untagged columns outside bronze/silver whose
--     name matches a tagged bronze/silver column. Misses renamed or derived columns.
SELECT c.table_schema, c.table_name, c.column_name, max(src.tag_value) AS source_tier
FROM {{catalog}}.information_schema.columns c
JOIN {{catalog}}.information_schema.column_tags src
  ON src.column_name = c.column_name
 AND src.tag_name = '{{tier_tag}}'
 AND (src.schema_name LIKE '%\_silver' OR src.schema_name LIKE '%\_bronze')
LEFT JOIN {{catalog}}.information_schema.column_tags t
  ON t.schema_name = c.table_schema AND t.table_name = c.table_name
 AND t.column_name = c.column_name AND t.tag_name = '{{tier_tag}}'
WHERE c.table_schema = 'byod' AND t.tag_name IS NULL
GROUP BY ALL
ORDER BY 1, 2, 3;

-- 4b. Detection by lineage (catches derived columns such as total_comp; system tables
--     can lag by minutes, so run this from a scheduled job rather than live)
SELECT l.target_table_full_name, l.target_column_name,
       collect_set(concat(l.source_table_full_name, '.', l.source_column_name)) AS sources
FROM system.access.column_lineage l
WHERE l.target_table_full_name = '{{catalog}}.byod.comp_review_extract'
GROUP BY ALL
ORDER BY 1, 2;
