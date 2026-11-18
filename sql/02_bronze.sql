-- ============================================================================
-- abac-hr-demo / 02: bronze (synthetic raw extracts, all STRING columns)
-- Templated: {{catalog}}
--
-- Fully synthetic. 2,000 workers across a 2-level department tree.
-- Built-in test hooks:
--   - W00001 is the CEO and the comp outlier (base 2,500,000)
--   - D00 (Office of the CEO) has exactly 3 people (small-group test)
--   - exactly 1 worker earns more than 500,000 base (inference test)
-- ============================================================================

-- Pipeline identity: once the ABAC policies exist, they also protect bronze. A rebuild must run
-- as an identity exempt from the masks, or silver gets built from masked values. In production that's
-- the pipeline service principal (in the policies' EXCEPT list). In this demo, set the override to
-- er_legal for the rebuild; 04_tags.sql resets it.
CREATE TABLE IF NOT EXISTS {{catalog}}.glb_governance.persona_override (user_name STRING, persona STRING, scope_dept_id STRING);
DELETE FROM {{catalog}}.glb_governance.persona_override WHERE user_name = current_user();
INSERT INTO {{catalog}}.glb_governance.persona_override VALUES (current_user(), 'er_legal', NULL);

-- ----------------------------------------------------------------------------
-- Supervisory orgs (department tree). head_worker_id = W000NN, NN = position.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.glb_bronze.hris_supervisory_orgs_raw (
  org_id STRING, org_name STRING, parent_org_id STRING, head_worker_id STRING, extract_ts STRING
);

INSERT INTO {{catalog}}.glb_bronze.hris_supervisory_orgs_raw VALUES
  ('D00', 'Office of the CEO',   NULL,  'W00001', '2026-11-18T06:00:00'),
  ('D10', 'Finance',             'D00', 'W00002', '2026-11-18T06:00:00'),
  ('D11', 'FP&A',                'D10', 'W00003', '2026-11-18T06:00:00'),
  ('D12', 'Treasury',            'D10', 'W00004', '2026-11-18T06:00:00'),
  ('D20', 'Human Resources',     'D00', 'W00005', '2026-11-18T06:00:00'),
  ('D21', 'Total Rewards',       'D20', 'W00006', '2026-11-18T06:00:00'),
  ('D22', 'Talent Acquisition',  'D20', 'W00007', '2026-11-18T06:00:00'),
  ('D30', 'R&D',                 'D00', 'W00008', '2026-11-18T06:00:00'),
  ('D31', 'Discovery',           'D30', 'W00009', '2026-11-18T06:00:00'),
  ('D32', 'Clinical Operations', 'D30', 'W00010', '2026-11-18T06:00:00'),
  ('D40', 'Supply Chain',        'D00', 'W00011', '2026-11-18T06:00:00'),
  ('D41', 'Manufacturing',       'D40', 'W00012', '2026-11-18T06:00:00'),
  ('D42', 'Logistics',           'D40', 'W00013', '2026-11-18T06:00:00'),
  ('D50', 'Legal',               'D00', 'W00014', '2026-11-18T06:00:00'),
  ('D60', 'Technology',          'D00', 'W00015', '2026-11-18T06:00:00'),
  ('D61', 'Data Platform',       'D60', 'W00016', '2026-11-18T06:00:00');

-- ----------------------------------------------------------------------------
-- Workers
--   ids 1-16  : department heads (department order above)
--   ids 17-18 : chiefs of staff in D00 (so D00 has n = 3)
--   ids 19+   : spread across the 15 non-root departments
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.glb_bronze.hris_workers_raw AS
WITH ids AS (SELECT id FROM range(1, 2001)),
a AS (
  SELECT
    id,
    CASE
      WHEN id <= 16 THEN element_at(array('D00','D10','D11','D12','D20','D21','D22','D30','D31','D32','D40','D41','D42','D50','D60','D61'), CAST(id AS INT))
      WHEN id <= 18 THEN 'D00'
      ELSE element_at(array('D10','D11','D12','D20','D21','D22','D30','D31','D32','D40','D41','D42','D50','D60','D61'), CAST(id % 15 AS INT) + 1)
    END AS org_id,
    element_at(array('Avery','Jordan','Priya','Mateo','Sofia','Wei','Amara','Liam','Noor','Diego','Hana','Owen','Zara','Ravi','Elena','Kofi','Mia','Arjun','Chloe','Tomas','Ines','Marcus','Leila','Felix','Yuki','Omar','Clara','Dev','Freya','Hugo','Anya','Caleb','Rosa','Ivan','Maya','Theo','Lena','Kai','Nadia','Sami','Greta','Rafael','Asha','Bruno','Talia','Emeka','Vera','Luca','Ingrid','Jonah'), CAST(id % 50 AS INT) + 1) AS first_name,
    element_at(array('Nguyen','Patel','Garcia','Smith','Okafor','Kim','Rossi','Murphy','Silva','Cohen','Tanaka','Dubois','Haddad','Larsen','Mendes','Shah','Novak','Reyes','Walsh','Iyer','Becker','Osei','Lund','Moreau','Fischer','Kowalski','Andersen','Costa','Varga','Brennan','Sato','Ortiz','Hughes','Bauer','Nair','Lindqvist','Abara','Petrov','Quinn','Yamada','Duarte','Keller','Mensah','Horvat','Ali','Fitzgerald','Ivanova','Russo','Sandoval','Thorne'), CAST(floor(id / 50) % 50 AS INT) + 1) AS last_name,
    CASE
      WHEN id = 1   THEN 'L10'
      WHEN id <= 16 THEN 'L9'
      WHEN id <= 18 THEN 'L8'
      ELSE element_at(array('L3','L4','L4','L5','L5','L6','L7'), CAST(id % 7 AS INT) + 1)
    END AS job_level
  FROM ids
)
SELECT
  format_string('W%05d', a.id)                                                       AS worker_id,
  a.first_name                                                                       AS first_name,
  a.last_name                                                                        AS last_name,
  lower(concat(a.first_name, '.', a.last_name, a.id, '@example.com'))                AS work_email,
  CASE
    WHEN a.id = 1   THEN 'Chief Executive Officer'
    WHEN a.id <= 16 THEN concat('Head of ', o.org_name)
    WHEN a.id <= 18 THEN 'Chief of Staff'
    ELSE element_at(array('Analyst','Associate','Engineer','Scientist','Specialist','Manager','Senior Manager'), CAST(a.id % 7 AS INT) + 1)
  END                                                                                AS job_title,
  a.job_level                                                                        AS job_level,
  a.org_id                                                                           AS org_id,
  CASE WHEN a.id = 1 THEN NULL WHEN a.id <= 16 THEN p.head_worker_id ELSE o.head_worker_id END AS manager_worker_id,
  element_at(array('US','US','US','US','BE','IE','IN','JP','BR','DE'), CAST(a.id % 10 AS INT) + 1) AS country,
  cast(date_add(DATE'2008-01-01', CAST((a.id * 53) % 6200 AS INT)) AS STRING)        AS hire_date,
  format_string('%d %s St, %s', 10 + a.id % 990,
    element_at(array('Oak','Maple','Cedar','Elm','Pine','Birch','Willow'), CAST(a.id % 7 AS INT) + 1),
    element_at(array('Springfield','Riverton','Lakeside','Fairview','Georgetown'), CAST(a.id % 5 AS INT) + 1)) AS home_address,
  format_string('+1-555-%03d-%04d', a.id % 1000, (a.id * 31) % 10000)                 AS personal_phone,
  cast(date_add(DATE'1960-01-01', CAST((a.id * 37) % 14000 AS INT)) AS STRING)       AS date_of_birth,
  format_string('%s %s (+1-555-%03d-%04d)',
    element_at(array('Sam','Alex','Robin','Casey','Jamie'), CAST(a.id % 5 AS INT) + 1), a.last_name,
    (a.id * 3) % 1000, (a.id * 17) % 10000)                                          AS emergency_contact,
  format_string('%03d-%02d-%04d', 100 + a.id % 800, 10 + a.id % 89, 1000 + (a.id * 7) % 9000) AS ssn,
  format_string('%09d', 21000000 + (a.id * 7919) % 9000000)                          AS bank_routing_number,
  '2026-11-18T06:00:00'                                                              AS extract_ts
FROM a
JOIN {{catalog}}.glb_bronze.hris_supervisory_orgs_raw o ON o.org_id = a.org_id
LEFT JOIN {{catalog}}.glb_bronze.hris_supervisory_orgs_raw p ON p.org_id = o.parent_org_id;

-- ----------------------------------------------------------------------------
-- Performance reviews (2026 cycle)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.glb_bronze.hris_performance_raw AS
SELECT
  w.worker_id,
  w.org_id,
  '2026' AS review_year,
  element_at(array('Exceeds','Meets','Meets','Meets','Partially Meets','Exceptional'), CAST(CAST(substr(w.worker_id, 2) AS INT) % 6 AS INT) + 1) AS rating,
  element_at(array(
    'Consistently delivers on goals; strong collaborator.',
    'Meets expectations; opportunity to grow stakeholder management.',
    'Solid technical work; needs to improve planning.',
    'Reliable contributor; ready for broader scope next year.',
    'Missed two key milestones; improvement plan discussed.',
    'Outstanding year; led a critical cross-functional launch.'), CAST(CAST(substr(w.worker_id, 2) AS INT) % 6 AS INT) + 1) AS review_text,
  CASE WHEN CAST(substr(w.worker_id, 2) AS INT) % 9 = 0 THEN 'Promoted 2025' ELSE 'None' END AS promotion_history,
  w.extract_ts
FROM {{catalog}}.glb_bronze.hris_workers_raw w;

-- ----------------------------------------------------------------------------
-- Leave (about 20% of workers have a leave record; some are FMLA / medical / ADA)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.glb_bronze.hris_leave_raw AS
SELECT
  w.worker_id,
  w.org_id,
  cast(8 + (CAST(substr(w.worker_id, 2) AS INT) * 3) % 120 AS STRING) AS leave_balance_hours,
  element_at(array('Vacation','Vacation','FMLA - medical','Parental','FMLA - family care'), CAST(CAST(substr(w.worker_id, 2) AS INT) % 5 AS INT) + 1) AS leave_type,
  CASE WHEN CAST(substr(w.worker_id, 2) AS INT) % 5 IN (2, 4)
       THEN element_at(array('Surgery recovery','Chronic condition','Caring for a parent','Mental health'), CAST(CAST(substr(w.worker_id, 2) AS INT) % 4 AS INT) + 1)
  END AS medical_leave_reason,
  CASE WHEN CAST(substr(w.worker_id, 2) AS INT) % 25 = 0 THEN 'Ergonomic workstation; flexible schedule' END AS ada_accommodation,
  w.extract_ts
FROM {{catalog}}.glb_bronze.hris_workers_raw w
WHERE CAST(substr(w.worker_id, 2) AS INT) % 5 <> 0 OR CAST(substr(w.worker_id, 2) AS INT) % 25 = 0;

-- ----------------------------------------------------------------------------
-- Employee relations cases (about 3% of workers)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.glb_bronze.hris_er_cases_raw AS
SELECT
  format_string('ER%05d', CAST(substr(w.worker_id, 2) AS INT)) AS case_id,
  w.worker_id,
  w.org_id,
  element_at(array('Conduct','Policy violation','Harassment complaint','Performance dispute'), CAST(CAST(substr(w.worker_id, 2) AS INT) % 4 AS INT) + 1) AS case_type,
  element_at(array(
    'Interviewed reporting party and two witnesses; findings pending.',
    'Reviewed access logs; policy breach confirmed, written warning issued.',
    'External investigator engaged; interim measures in place.',
    'Mediation scheduled between employee and manager.'), CAST(CAST(substr(w.worker_id, 2) AS INT) % 4 AS INT) + 1) AS investigation_notes,
  element_at(array('Clear','Clear','Clear','Discrepancy - education'), CAST(CAST(substr(w.worker_id, 2) AS INT) % 4 AS INT) + 1) AS background_check_result,
  w.extract_ts
FROM {{catalog}}.glb_bronze.hris_workers_raw w
WHERE CAST(substr(w.worker_id, 2) AS INT) % 33 = 0;

-- ----------------------------------------------------------------------------
-- Compensation (total rewards)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.tr_bronze.hris_comp_raw AS
SELECT
  w.worker_id,
  w.org_id,
  w.country,
  w.job_level AS comp_grade,
  cast(
    CASE w.job_level
      WHEN 'L10' THEN 2500000 WHEN 'L9' THEN 400000 WHEN 'L8' THEN 260000 WHEN 'L7' THEN 210000
      WHEN 'L6' THEN 160000 WHEN 'L5' THEN 120000 WHEN 'L4' THEN 90000 ELSE 70000
    END + CASE WHEN w.job_level = 'L10' THEN 0 ELSE (CAST(substr(w.worker_id, 2) AS INT) * 13) % 15000 END
  AS STRING) AS base_salary,
  cast(
    CASE w.job_level WHEN 'L10' THEN 1500000 WHEN 'L9' THEN 120000 WHEN 'L8' THEN 50000
      ELSE 5000 + (CAST(substr(w.worker_id, 2) AS INT) * 17) % 20000 END
  AS STRING) AS bonus_target,
  cast(
    CASE w.job_level WHEN 'L10' THEN 4000000 WHEN 'L9' THEN 300000 WHEN 'L8' THEN 80000
      ELSE (CAST(substr(w.worker_id, 2) AS INT) * 29) % 40000 END
  AS STRING) AS equity_grant,
  'USD' AS currency,
  w.extract_ts
FROM {{catalog}}.glb_bronze.hris_workers_raw w;

-- ----------------------------------------------------------------------------
-- Recruiting (talent acquisition): requisitions + applications
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.ta_bronze.ats_requisitions_raw AS
SELECT
  format_string('R%04d', id) AS requisition_id,
  element_at(array('D10','D11','D12','D20','D21','D22','D30','D31','D32','D40','D41','D42','D50','D60','D61'), CAST(id % 15 AS INT) + 1) AS org_id,
  element_at(array('Data Engineer','Financial Analyst','Clinical Research Associate','HR Business Partner','Supply Planner','Counsel'), CAST(id % 6 AS INT) + 1) AS job_title,
  element_at(array('Open','Open','Filled','On hold'), CAST(id % 4 AS INT) + 1) AS status,
  '2026-11-18T06:00:00' AS extract_ts
FROM range(1, 61);

CREATE OR REPLACE TABLE {{catalog}}.ta_bronze.ats_applications_raw AS
SELECT
  format_string('A%05d', id) AS application_id,
  format_string('R%04d', 1 + id % 60) AS requisition_id,
  element_at(array('D10','D11','D12','D20','D21','D22','D30','D31','D32','D40','D41','D42','D50','D60','D61'), CAST((1 + id % 60) % 15 AS INT) + 1) AS org_id,
  concat(element_at(array('Taylor','Morgan','Riley','Quinn','Drew','Parker'), CAST(id % 6 AS INT) + 1), ' ',
         element_at(array('Brooks','Hayes','Ellis','Foster','Grant','Lane','Price'), CAST(id % 7 AS INT) + 1)) AS candidate_name,
  element_at(array('Applied','Phone screen','Onsite','Offer','Rejected'), CAST(id % 5 AS INT) + 1) AS stage,
  element_at(array(
    'Strong SQL; weak on system design. Lean no-hire.',
    'Great communicator; asked thoughtful questions about the team.',
    'Salary expectations above band; otherwise a strong fit.',
    'Concern about short tenure at last two roles.'), CAST(id % 4 AS INT) + 1) AS interview_notes,
  concat('Summary: ', element_at(array('8 years data engineering','5 years FP&A','PhD, 3 years clinical research','10 years HR generalist'), CAST(id % 4 AS INT) + 1),
         '. Prior employer: ', element_at(array('Acme Corp','Globex','Initech','Umbrella Health'), CAST(id % 4 AS INT) + 1), '.') AS resume_text,
  '2026-11-18T06:00:00' AS extract_ts
FROM range(1, 401);

-- ----------------------------------------------------------------------------
-- Learning (training records, about 3 per worker)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE {{catalog}}.lrn_bronze.lms_training_raw AS
SELECT
  w.worker_id,
  w.org_id,
  element_at(array('Code of Conduct','Data Privacy Basics','GxP Fundamentals','Leading Teams','Advanced SQL','Anti-Bribery'), CAST((CAST(substr(w.worker_id, 2) AS INT) + k) % 6 AS INT) + 1) AS course_name,
  element_at(array('Completed','Completed','In progress','Overdue'), CAST((CAST(substr(w.worker_id, 2) AS INT) + k) % 4 AS INT) + 1) AS completion_status,
  cast(60 + (CAST(substr(w.worker_id, 2) AS INT) * (k + 3)) % 41 AS STRING) AS assessment_score,
  w.extract_ts
FROM {{catalog}}.glb_bronze.hris_workers_raw w
LATERAL VIEW explode(array(0, 1, 2)) t AS k;

-- Sanity checks
SELECT
  (SELECT count(*) FROM {{catalog}}.glb_bronze.hris_workers_raw)                            AS workers_expect_2000,
  (SELECT count(*) FROM {{catalog}}.glb_bronze.hris_workers_raw WHERE org_id = 'D00')       AS d00_expect_3,
  (SELECT max(CAST(base_salary AS INT)) FROM {{catalog}}.tr_bronze.hris_comp_raw)            AS max_base_expect_2500000,
  (SELECT count(*) FROM {{catalog}}.tr_bronze.hris_comp_raw WHERE CAST(base_salary AS INT) > 500000) AS over_500k_expect_1,
  (SELECT count(*) FROM {{catalog}}.glb_bronze.hris_er_cases_raw)                           AS er_cases,
  (SELECT count(*) FROM {{catalog}}.glb_bronze.hris_leave_raw)                              AS leave_rows,
  (SELECT count(*) FROM {{catalog}}.ta_bronze.ats_applications_raw)                         AS applications,
  (SELECT count(*) FROM {{catalog}}.lrn_bronze.lms_training_raw)                            AS training_rows,
  (SELECT count(DISTINCT first_name, last_name) FROM {{catalog}}.glb_bronze.hris_workers_raw) AS unique_names_expect_2000;
