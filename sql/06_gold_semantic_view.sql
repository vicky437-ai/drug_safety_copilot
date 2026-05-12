/*
 * Drug Safety Co-Pilot — Phase 6: Semantic View + Analytical View (Gold)
 * 
 * Prerequisites: Phase 3 complete (D_SILVER dynamic tables populated)
 * 
 * This script creates:
 *   - D_GOLD.PV_ANALYST_VIEW: Semantic view for Cortex Analyst (DDL syntax)
 *   - D_GOLD.V_ADVERSE_EVENT_ANALYTICS: Standard analytical view (fallback)
 *   - D_GOLD.SEMANTIC_STAGE: Stage for uploading semantic_model.yaml
 *
 * Note: The FROM @stage/yaml syntax does NOT work. Use DDL syntax instead.
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA D_GOLD;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 6.1: Create Stage for Semantic Model YAML
-- ============================================================
CREATE OR REPLACE STAGE D_GOLD.SEMANTIC_STAGE;

-- Upload YAML to stage (run from CLI):
-- PUT file://semantic_model.yaml @PHARMACOVIGILANCE.D_GOLD.SEMANTIC_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ============================================================
-- Step 6.2: Create Semantic View (DDL syntax)
-- ============================================================
CREATE OR REPLACE SEMANTIC VIEW D_GOLD.PV_ANALYST_VIEW
  TABLES (
    fact_ae AS PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
      PRIMARY KEY (CASE_ID)
      COMMENT = 'Core fact table - one row per adverse event case report',
    dim_patient AS PHARMACOVIGILANCE.D_SILVER.DIM_PATIENT
      PRIMARY KEY (PATIENT_ID)
      COMMENT = 'Patient dimension with demographics',
    dim_drug AS PHARMACOVIGILANCE.D_SILVER.DIM_DRUG
      UNIQUE (DRUG_NAME, DRUG_DOSE, DRUG_ROUTE)
      COMMENT = 'Drug dimension with dose, route, indication'
  )
  RELATIONSHIPS (
    fact_ae (PATIENT_ID) REFERENCES dim_patient (PATIENT_ID),
    fact_ae (DRUG_NAME, DRUG_DOSE, DRUG_ROUTE) REFERENCES dim_drug (DRUG_NAME, DRUG_DOSE, DRUG_ROUTE)
  )
  FACTS (
    fact_ae.onset_days AS ONSET_DAYS COMMENT = 'Days from drug start to adverse event onset'
  )
  DIMENSIONS (
    fact_ae.drug_name AS DRUG_NAME COMMENT = 'Suspect drug name',
    fact_ae.drug_dose AS DRUG_DOSE COMMENT = 'Drug dose with unit',
    fact_ae.drug_route AS DRUG_ROUTE COMMENT = 'Route of administration',
    fact_ae.ae_term AS AE_TERM COMMENT = 'MedDRA preferred term',
    fact_ae.ae_soc_class AS AE_SOC_CLASS COMMENT = 'System Organ Class',
    fact_ae.ae_severity AS AE_SEVERITY COMMENT = 'Severity: mild, moderate, severe',
    fact_ae.ae_seriousness AS AE_SERIOUSNESS COMMENT = 'Seriousness criteria',
    fact_ae.ae_outcome AS AE_OUTCOME COMMENT = 'Patient outcome',
    fact_ae.reporter_type AS REPORTER_TYPE COMMENT = 'Reporter type',
    fact_ae.country AS COUNTRY COMMENT = 'Country',
    fact_ae.manufacturer AS MANUFACTURER COMMENT = 'Drug manufacturer',
    fact_ae.report_date AS REPORT_DATE COMMENT = 'Report date',
    fact_ae.ae_onset_date AS AE_ONSET_DATE COMMENT = 'Onset date',
    fact_ae.drug_start_date AS DRUG_START_DATE COMMENT = 'Drug start date',
    dim_patient.patient_age AS PATIENT_AGE COMMENT = 'Patient age',
    dim_patient.patient_sex AS PATIENT_SEX COMMENT = 'Patient sex',
    dim_drug.indication AS INDICATION COMMENT = 'Drug indication'
  )
  METRICS (
    fact_ae.total_cases AS COUNT(DISTINCT CASE_ID) COMMENT = 'Total unique cases',
    fact_ae.total_patients AS COUNT(DISTINCT PATIENT_ID) COMMENT = 'Total unique patients',
    fact_ae.fatal_cases AS COUNT(CASE WHEN AE_OUTCOME = 'Fatal' THEN 1 END) COMMENT = 'Fatal cases',
    fact_ae.severe_cases AS COUNT(CASE WHEN LOWER(AE_SEVERITY) = 'severe' THEN 1 END) COMMENT = 'Severe cases',
    fact_ae.fatal_rate AS COUNT(CASE WHEN AE_OUTCOME = 'Fatal' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0) COMMENT = 'Fatal rate %',
    fact_ae.avg_onset_days AS AVG(ONSET_DAYS) COMMENT = 'Avg onset days',
    fact_ae.median_onset_days AS MEDIAN(ONSET_DAYS) COMMENT = 'Median onset days',
    dim_patient.avg_patient_age AS AVG(PATIENT_AGE) COMMENT = 'Avg patient age'
  )
  COMMENT = 'Pharmacovigilance signal detection - Drug Safety Co-Pilot'
  AI_VERIFIED_QUERIES (
    top_drugs AS (
      QUESTION 'What are the top 5 drugs by total adverse event count?'
      SQL 'SELECT DRUG_NAME, COUNT(DISTINCT CASE_ID) AS total_cases FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT GROUP BY DRUG_NAME ORDER BY total_cases DESC LIMIT 5'
    ),
    fatal_rate_by_drug AS (
      QUESTION 'Which drugs have the highest fatal outcome rate?'
      SQL 'SELECT DRUG_NAME, COUNT(*) AS total_cases, COUNT(CASE WHEN AE_OUTCOME = ''Fatal'' THEN 1 END) AS fatal_cases, ROUND(COUNT(CASE WHEN AE_OUTCOME = ''Fatal'' THEN 1 END) * 100.0 / COUNT(*), 2) AS fatal_rate_pct FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT GROUP BY DRUG_NAME HAVING COUNT(*) >= 5 ORDER BY fatal_rate_pct DESC'
    ),
    soc_distribution AS (
      QUESTION 'What is the distribution of adverse events by system organ class?'
      SQL 'SELECT AE_SOC_CLASS, COUNT(*) AS case_count, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT GROUP BY AE_SOC_CLASS ORDER BY case_count DESC'
    ),
    onset_by_drug AS (
      QUESTION 'What is the average time to onset for each drug?'
      SQL 'SELECT DRUG_NAME, ROUND(AVG(ONSET_DAYS), 1) AS avg_onset_days, ROUND(MEDIAN(ONSET_DAYS), 1) AS median_onset_days, COUNT(*) AS cases FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT WHERE ONSET_DAYS IS NOT NULL GROUP BY DRUG_NAME ORDER BY avg_onset_days DESC'
    )
  );

-- ============================================================
-- Step 6.3: Grant access to semantic view
-- ============================================================
GRANT SELECT ON SEMANTIC VIEW D_GOLD.PV_ANALYST_VIEW TO ROLE DRUG_SAFETY_OFFICER;
GRANT SELECT ON SEMANTIC VIEW D_GOLD.PV_ANALYST_VIEW TO ROLE PV_ANALYST;

-- ============================================================
-- Step 6.4: Analytical View (fallback / standard SQL access)
-- ============================================================
CREATE OR REPLACE VIEW PHARMACOVIGILANCE.D_GOLD.V_ADVERSE_EVENT_ANALYTICS AS
SELECT
    f.CASE_ID, f.PATIENT_ID, f.DRUG_NAME, f.DRUG_DOSE, f.DRUG_ROUTE,
    f.DRUG_START_DATE, f.AE_TERM, f.AE_SOC_CLASS, f.AE_CLASSIFICATION_SCORE,
    f.AE_SEVERITY, f.AE_SERIOUSNESS, f.AE_OUTCOME, f.AE_ONSET_DATE,
    f.ONSET_DAYS, f.REPORTER_TYPE, f.REPORT_DATE, f.COUNTRY, f.MANUFACTURER,
    p.PATIENT_AGE, p.PATIENT_SEX, d.INDICATION
FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT f
LEFT JOIN PHARMACOVIGILANCE.D_SILVER.DIM_PATIENT p ON f.PATIENT_ID = p.PATIENT_ID
LEFT JOIN PHARMACOVIGILANCE.D_SILVER.DIM_DRUG d
    ON f.DRUG_NAME = d.DRUG_NAME AND f.DRUG_DOSE = d.DRUG_DOSE AND f.DRUG_ROUTE = d.DRUG_ROUTE;

-- ============================================================
-- Step 6.5: Verification
-- ============================================================

-- Verify semantic view exists
SHOW SEMANTIC VIEWS IN SCHEMA D_GOLD;

-- Verify analytical view works
SELECT DRUG_NAME, COUNT(*) AS CASES FROM D_GOLD.V_ADVERSE_EVENT_ANALYTICS GROUP BY DRUG_NAME LIMIT 5;

-- Upload semantic_model.yaml to stage for Snowsight UI reference:
-- PUT file:///Users/vicky/Documents/poc_project/drug_safety_copilot/semantic_model.yaml
--     @PHARMACOVIGILANCE.D_GOLD.SEMANTIC_STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
