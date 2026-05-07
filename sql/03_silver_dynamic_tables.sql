/*
 * Drug Safety Co-Pilot — Phase 3: Silver Layer (Dynamic Tables)
 * 
 * Prerequisites: Phase 2 complete (D_BRONZE.CLASSIFIED_EVENTS and D_BRONZE.ENRICHED_NARRATIVES exist)
 * 
 * This script creates:
 *   - D_SILVER.DIM_PATIENT: Patient dimension (deduped)
 *   - D_SILVER.DIM_DRUG: Drug dimension with dose/route/indication
 *   - D_SILVER.FACT_ADVERSE_EVENT: Core fact table with classification
 *   - D_SILVER.FACT_NARRATIVE: Enriched narrative fact table
 *
 * Dynamic Tables provide:
 *   - Automatic incremental refresh (CDC) when upstream data changes
 *   - Declarative pipeline definition (no manual orchestration)
 *   - TARGET_LAG controls freshness SLA
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA D_SILVER;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 3.1: DIM_PATIENT — Patient Dimension
-- Deduplicates patients from classified events
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE D_SILVER.DIM_PATIENT
    TARGET_LAG = '60 minutes'
    WAREHOUSE = PV_WH
AS
SELECT DISTINCT
    PATIENT_ID,
    PATIENT_AGE,
    PATIENT_SEX,
    PATIENT_DOB,
    PATIENT_WEIGHT,
    COUNTRY
FROM PHARMACOVIGILANCE.D_BRONZE.CLASSIFIED_EVENTS;

-- ============================================================
-- Step 3.2: DIM_DRUG — Drug Dimension
-- Unique drug + dose + route + indication combinations
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE D_SILVER.DIM_DRUG
    TARGET_LAG = '60 minutes'
    WAREHOUSE = PV_WH
AS
SELECT DISTINCT
    DRUG_NAME,
    DRUG_DOSE,
    DRUG_ROUTE,
    INDICATION,
    MANUFACTURER
FROM PHARMACOVIGILANCE.D_BRONZE.CLASSIFIED_EVENTS;

-- ============================================================
-- Step 3.3: FACT_ADVERSE_EVENT — Core Fact Table
-- Contains one row per adverse event case with classification
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE D_SILVER.FACT_ADVERSE_EVENT
    TARGET_LAG = '60 minutes'
    WAREHOUSE = PV_WH
AS
SELECT
    CASE_ID,
    PATIENT_ID,
    DRUG_NAME,
    DRUG_DOSE,
    DRUG_ROUTE,
    DRUG_START_DATE,
    AE_TERM,
    AE_CLASSIFICATION:label::VARCHAR AS AE_SOC_CLASS,
    AE_CLASSIFICATION:score::FLOAT AS AE_CLASSIFICATION_SCORE,
    AE_SEVERITY,
    AE_SERIOUSNESS,
    AE_OUTCOME,
    AE_ONSET_DATE,
    DATEDIFF('day', DRUG_START_DATE, AE_ONSET_DATE) AS ONSET_DAYS,
    REPORTER_TYPE,
    REPORT_DATE,
    COUNTRY,
    MANUFACTURER
FROM PHARMACOVIGILANCE.D_BRONZE.CLASSIFIED_EVENTS;

-- ============================================================
-- Step 3.4: FACT_NARRATIVE — Enriched Narrative Fact Table
-- Contains extracted fields and sentiment from narratives
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE D_SILVER.FACT_NARRATIVE
    TARGET_LAG = '60 minutes'
    WAREHOUSE = PV_WH
AS
SELECT
    CASE_ID,
    NARRATIVE_TEXT,
    NARRATIVE_TYPE,
    EXTRACTED:primary_drug::VARCHAR AS EXTRACTED_DRUG,
    EXTRACTED:adverse_event::VARCHAR AS EXTRACTED_AE,
    EXTRACTED:severity_assessment::VARCHAR AS EXTRACTED_SEVERITY,
    EXTRACTED:patient_outcome::VARCHAR AS EXTRACTED_OUTCOME,
    EXTRACTED:onset_days::INT AS EXTRACTED_ONSET_DAYS,
    EXTRACTED:causality::VARCHAR AS EXTRACTED_CAUSALITY,
    EXTRACTED:dechallenge_result::VARCHAR AS DECHALLENGE_RESULT,
    EXTRACTED:concomitant_drugs::VARCHAR AS CONCOMITANT_DRUGS,
    NARRATIVE_SENTIMENT,
    GENERATED_AT
FROM PHARMACOVIGILANCE.D_BRONZE.ENRICHED_NARRATIVES;

-- ============================================================
-- Step 3.5: Verification
-- ============================================================

-- Check all 4 dynamic tables exist and show refresh status
SHOW DYNAMIC TABLES IN SCHEMA D_SILVER;

-- Verify data in each table
SELECT 'DIM_PATIENT' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM D_SILVER.DIM_PATIENT
UNION ALL
SELECT 'DIM_DRUG', COUNT(*) FROM D_SILVER.DIM_DRUG
UNION ALL
SELECT 'FACT_ADVERSE_EVENT', COUNT(*) FROM D_SILVER.FACT_ADVERSE_EVENT
UNION ALL
SELECT 'FACT_NARRATIVE', COUNT(*) FROM D_SILVER.FACT_NARRATIVE;

-- Sample fact table data
SELECT CASE_ID, DRUG_NAME, AE_TERM, AE_SOC_CLASS, AE_SEVERITY, ONSET_DAYS
FROM D_SILVER.FACT_ADVERSE_EVENT
LIMIT 10;
