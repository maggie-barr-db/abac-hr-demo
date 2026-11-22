-- Databricks notebook source
-- MAGIC %md # ABAC HR demo: one query, four personas
-- MAGIC Synthetic HR data. Every column carries one governed tag, `hr_pii_demo_tag`, with four sensitivity tiers. Employee ID columns also carry a reporting-line scope tag. **Four policies set once on the catalog** (three column masks and one row filter) protect every table, view and metric view below.
-- MAGIC
-- MAGIC | Tier | Examples |
-- MAGIC |---|---|
-- MAGIC | 1 Internal | name, title, department |
-- MAGIC | 2 Confidential | performance rating, review text |
-- MAGIC | 3 Restricted | salary, home address |
-- MAGIC | 4 Highly restricted | SSN, medical leave reason |
-- MAGIC
-- MAGIC Each persona cell switches persona, then runs **the same query** on the same six people:
-- MAGIC
-- MAGIC | ID | Person | Why they're in the sample |
-- MAGIC |---|---|---|
-- MAGIC | W00001 | Jordan Nguyen, CEO | top of the company |
-- MAGIC | W00002 | Priya Nguyen, Head of Finance | Anya's own manager |
-- MAGIC | W00030 | Anya Nguyen, Senior Manager, Finance | our people manager |
-- MAGIC | W00075 | Omar Patel, Manager, Finance | reports to Anya |
-- MAGIC | W00210 | Hana Okafor, Analyst, Finance | reports to Omar |
-- MAGIC | W00041 | Rafael Nguyen, Senior Manager, Logistics | another department |
-- MAGIC
-- MAGIC _Personas switch through a demo-only override table (`glb_governance.persona_override`). In production, group membership and the HR hierarchy decide the persona, and the override table doesn't exist._

-- COMMAND ----------

USE CATALOG mbarrett_hr_demo_aws_sandbox_catalog;

-- COMMAND ----------

-- MAGIC %md ## 1. HR analyst
-- MAGIC The default persona for anyone in HR without extra entitlements. Sees **everyone**, but only **Tier 1** data in clear.
-- MAGIC
-- MAGIC | Data | Tier | Sees it? |
-- MAGIC |---|---|---|
-- MAGIC | Name, title, department | 1 | Visible |
-- MAGIC | Performance rating | 2 | Masked (`****`) |
-- MAGIC | Base salary | 3 | Masked (NULL) |
-- MAGIC | Home address | 3 | Masked (`****`) |
-- MAGIC | SSN | 4 | Masked (`****`) |
-- MAGIC | Rows | | All 6 people (2,000 in total) |

-- COMMAND ----------

DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'hr_analyst', NULL);

SELECT glb_governance.current_persona() AS viewing_as,
       e.employee_id, e.full_name, e.job_title, d.dept_name,
       p.rating, c.base_salary, e.home_address, e.ssn,
       (SELECT count(*) FROM glb_silver.employees) AS total_rows_you_can_see
FROM glb_silver.employees e
JOIN glb_silver.departments d ON d.dept_id = e.dept_id
LEFT JOIN glb_silver.performance p ON p.employee_id = e.employee_id AND p.review_year = 2026
LEFT JOIN tr_silver.compensation c ON c.employee_id = e.employee_id
WHERE e.employee_id IN ('W00001', 'W00002', 'W00030', 'W00075', 'W00210', 'W00041')
ORDER BY e.employee_id;

-- COMMAND ----------

-- MAGIC %md ## 2. People manager: Anya Nguyen (W00030)
-- MAGIC Anyone with at least one report. Sees **Tiers 1-3**, but **only for people in her reporting line**: everyone below her at any depth, plus herself (46 people). Her own manager, the CEO and other departments drop out.
-- MAGIC
-- MAGIC | Data | Tier | Sees it? |
-- MAGIC |---|---|---|
-- MAGIC | Name, title, department | 1 | Visible |
-- MAGIC | Performance rating | 2 | Visible |
-- MAGIC | Base salary | 3 | Visible |
-- MAGIC | Home address | 3 | Visible |
-- MAGIC | SSN | 4 | Masked (`****`) |
-- MAGIC | Rows | | 3 of 6: Anya, Omar and Hana (46 in total). Jordan, Priya and Rafael are filtered out |

-- COMMAND ----------

DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'people_manager', 'W00030');

SELECT glb_governance.current_persona() AS viewing_as,
       e.employee_id, e.full_name, e.job_title, d.dept_name,
       p.rating, c.base_salary, e.home_address, e.ssn,
       (SELECT count(*) FROM glb_silver.employees) AS total_rows_you_can_see
FROM glb_silver.employees e
JOIN glb_silver.departments d ON d.dept_id = e.dept_id
LEFT JOIN glb_silver.performance p ON p.employee_id = e.employee_id AND p.review_year = 2026
LEFT JOIN tr_silver.compensation c ON c.employee_id = e.employee_id
WHERE e.employee_id IN ('W00001', 'W00002', 'W00030', 'W00075', 'W00210', 'W00041')
ORDER BY e.employee_id;

-- COMMAND ----------

-- MAGIC %md ## 3. HR trusted (HRBP)
-- MAGIC HR business partners in the trusted group. Sees **everyone** with **Tiers 1-3** in clear. Tier 4 stays masked.
-- MAGIC
-- MAGIC | Data | Tier | Sees it? |
-- MAGIC |---|---|---|
-- MAGIC | Name, title, department | 1 | Visible |
-- MAGIC | Performance rating | 2 | Visible |
-- MAGIC | Base salary | 3 | Visible (including the CEO's 2,500,000) |
-- MAGIC | Home address | 3 | Visible |
-- MAGIC | SSN | 4 | Masked (`****`) |
-- MAGIC | Rows | | All 6 people (2,000 in total) |

-- COMMAND ----------

DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'hr_trusted', NULL);

SELECT glb_governance.current_persona() AS viewing_as,
       e.employee_id, e.full_name, e.job_title, d.dept_name,
       p.rating, c.base_salary, e.home_address, e.ssn,
       (SELECT count(*) FROM glb_silver.employees) AS total_rows_you_can_see
FROM glb_silver.employees e
JOIN glb_silver.departments d ON d.dept_id = e.dept_id
LEFT JOIN glb_silver.performance p ON p.employee_id = e.employee_id AND p.review_year = 2026
LEFT JOIN tr_silver.compensation c ON c.employee_id = e.employee_id
WHERE e.employee_id IN ('W00001', 'W00002', 'W00030', 'W00075', 'W00210', 'W00041')
ORDER BY e.employee_id;

-- COMMAND ----------

-- MAGIC %md ## 4. ER / Legal / Benefits
-- MAGIC Employee relations, legal and benefits administration. The only persona that sees **all four tiers**.
-- MAGIC
-- MAGIC | Data | Tier | Sees it? |
-- MAGIC |---|---|---|
-- MAGIC | Name, title, department | 1 | Visible |
-- MAGIC | Performance rating | 2 | Visible |
-- MAGIC | Base salary | 3 | Visible |
-- MAGIC | Home address | 3 | Visible |
-- MAGIC | SSN | 4 | Visible |
-- MAGIC | Rows | | All 6 people (2,000 in total) |

-- COMMAND ----------

DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'er_legal', NULL);

SELECT glb_governance.current_persona() AS viewing_as,
       e.employee_id, e.full_name, e.job_title, d.dept_name,
       p.rating, c.base_salary, e.home_address, e.ssn,
       (SELECT count(*) FROM glb_silver.employees) AS total_rows_you_can_see
FROM glb_silver.employees e
JOIN glb_silver.departments d ON d.dept_id = e.dept_id
LEFT JOIN glb_silver.performance p ON p.employee_id = e.employee_id AND p.review_year = 2026
LEFT JOIN tr_silver.compensation c ON c.employee_id = e.employee_id
WHERE e.employee_id IN ('W00001', 'W00002', 'W00030', 'W00075', 'W00210', 'W00041')
ORDER BY e.employee_id;

-- COMMAND ----------

-- MAGIC %md ## 5. The same rules flow into the metric view and the gold views
-- MAGIC Switch back to **Anya**. The comp metric view (`tr_gold.mv_total_comp`) and the gold view (`tr_gold.employee_comp`) have **no policies of their own**: ABAC policies can't attach to a metric view, and tags don't flow down to views. They're protected because Unity Catalog applies the policies on the silver tables they read, for the person querying.
-- MAGIC
-- MAGIC | Query | What Anya should get |
-- MAGIC |---|---|
-- MAGIC | Metric view, comp by department and level | Finance only, 46 people. Highest total comp 216,770 (her own) |
-- MAGIC | Gold view, top 5 by total comp | Anya first at 216,770. No CEO (8,000,000) and no Priya |

-- COMMAND ----------

DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO glb_governance.persona_override VALUES (current_user(), 'people_manager', 'W00030');

-- Metric view: governed comp measures
SELECT department, job_level,
       MEASURE(headcount)      AS headcount,
       round(MEASURE(avg_total_comp), 0) AS avg_total_comp,
       MEASURE(max_total_comp) AS max_total_comp
FROM tr_gold.mv_total_comp
GROUP BY ALL
ORDER BY job_level DESC;

-- COMMAND ----------

-- Gold view: per-employee comp (base + bonus + equity)
SELECT employee_id, full_name, job_title, dept_name, total_comp
FROM tr_gold.employee_comp
ORDER BY total_comp DESC
LIMIT 5;

-- COMMAND ----------

-- MAGIC %md ## Reset, then over to the app
-- MAGIC The next cell removes your demo persona. The **People Insights** app uses the same four policies: every page and every Genie answer runs on behalf of the signed-in user.
-- MAGIC
-- MAGIC https://abac-hr-genie-demo-7474644859656496.aws.databricksapps.com

-- COMMAND ----------

DELETE FROM glb_governance.persona_override WHERE user_name = current_user();
SELECT glb_governance.current_persona() AS my_real_persona;
