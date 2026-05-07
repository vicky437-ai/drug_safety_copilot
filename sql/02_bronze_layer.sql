/*
 * Drug Safety Co-Pilot — Phase 2: Bronze Layer (AI Enrichment)
 * 
 * Prerequisites: Phase 1 complete (D_RAW.AE_REPORTS and D_RAW.AE_NARRATIVES populated)
 * 
 * This script creates:
 *   - D_BRONZE.CLASSIFIED_EVENTS: AE reports enriched with AI_CLASSIFY (SOC mapping)
 *   - D_BRONZE.ENRICHED_NARRATIVES: Narratives with AI_EXTRACT + AI_SENTIMENT
 *
 * Cortex AI Functions Used:
 *   - SNOWFLAKE.CORTEX.AI_CLASSIFY: Maps AE terms to System Organ Classes
 *   - SNOWFLAKE.CORTEX.AI_EXTRACT: Extracts structured fields from narratives
 *   - SNOWFLAKE.CORTEX.AI_SENTIMENT: Scores narrative severity tone
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA D_BRONZE;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 2.1: Test AI_CLASSIFY on a single row first
-- This confirms the function works and reveals output format
-- ============================================================
SELECT 
    AE_TERM,
    SNOWFLAKE.CORTEX.AI_CLASSIFY(
        AE_TERM,
        ['Hepatotoxicity','Cardiotoxicity','Nephrotoxicity','Dermatologic','Neurologic','Gastrointestinal','Hematologic','Immunologic','Musculoskeletal','Respiratory']
    ) AS CLASSIFICATION_RESULT
FROM PHARMACOVIGILANCE.D_RAW.AE_REPORTS
LIMIT 3;

-- ============================================================
-- Step 2.2: Create CLASSIFIED_EVENTS table
-- Enriches all AE reports with SOC classification
-- ============================================================
CREATE OR REPLACE TABLE D_BRONZE.CLASSIFIED_EVENTS AS
SELECT 
    r.*,
    SNOWFLAKE.CORTEX.AI_CLASSIFY(
        r.AE_TERM,
        ['Hepatotoxicity','Cardiotoxicity','Nephrotoxicity','Dermatologic','Neurologic','Gastrointestinal','Hematologic','Immunologic','Musculoskeletal','Respiratory']
    ) AS AE_CLASSIFICATION
FROM PHARMACOVIGILANCE.D_RAW.AE_REPORTS r;

-- Verify classification results
SELECT AE_TERM, AE_CLASSIFICATION 
FROM D_BRONZE.CLASSIFIED_EVENTS 
LIMIT 10;

-- Check classification distribution
SELECT AE_CLASSIFICATION:label::VARCHAR AS SOC_CLASS, COUNT(*) AS CNT
FROM D_BRONZE.CLASSIFIED_EVENTS
GROUP BY 1
ORDER BY CNT DESC;

-- ============================================================
-- Step 2.3: Test AI_EXTRACT on a single narrative first
-- Confirms output schema before running on full dataset
-- ============================================================
SELECT 
    CASE_ID,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        NARRATIVE_TEXT,
        OBJECT_CONSTRUCT(
            'primary_drug', 'The primary suspect drug name',
            'adverse_event', 'The main adverse event or reaction described',
            'severity_assessment', 'Clinical severity: mild, moderate, or severe',
            'patient_outcome', 'Final patient outcome',
            'onset_days', 'Number of days from drug start to event onset',
            'causality', 'Causality assessment mentioned (e.g., probable, possible, unlikely)',
            'dechallenge_result', 'Result of stopping the drug (positive, negative, not done)',
            'concomitant_drugs', 'Other medications the patient was taking'
        )
    ) AS EXTRACTED
FROM PHARMACOVIGILANCE.D_RAW.AE_NARRATIVES
LIMIT 1;

-- ============================================================
-- Step 2.4: Create ENRICHED_NARRATIVES table
-- Combines AI_EXTRACT for structured fields + AI_SENTIMENT for tone
-- ============================================================
CREATE OR REPLACE TABLE D_BRONZE.ENRICHED_NARRATIVES AS
SELECT
    n.CASE_ID,
    n.NARRATIVE_TEXT,
    n.NARRATIVE_TYPE,
    n.GENERATED_AT,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        n.NARRATIVE_TEXT,
        OBJECT_CONSTRUCT(
            'primary_drug', 'The primary suspect drug name',
            'adverse_event', 'The main adverse event or reaction described',
            'severity_assessment', 'Clinical severity: mild, moderate, or severe',
            'patient_outcome', 'Final patient outcome',
            'onset_days', 'Number of days from drug start to event onset',
            'causality', 'Causality assessment mentioned (e.g., probable, possible, unlikely)',
            'dechallenge_result', 'Result of stopping the drug (positive, negative, not done)',
            'concomitant_drugs', 'Other medications the patient was taking'
        )
    ) AS EXTRACTED,
    SNOWFLAKE.CORTEX.AI_SENTIMENT(n.NARRATIVE_TEXT) AS NARRATIVE_SENTIMENT
FROM PHARMACOVIGILANCE.D_RAW.AE_NARRATIVES n;

-- ============================================================
-- Step 2.5: Verification
-- ============================================================

-- Check extraction quality
SELECT 
    CASE_ID,
    EXTRACTED:primary_drug::VARCHAR AS DRUG,
    EXTRACTED:adverse_event::VARCHAR AS AE,
    EXTRACTED:causality::VARCHAR AS CAUSALITY,
    NARRATIVE_SENTIMENT
FROM D_BRONZE.ENRICHED_NARRATIVES
LIMIT 10;

-- Confirm no NULLs in critical fields
SELECT 
    COUNT(*) AS TOTAL,
    COUNT(EXTRACTED) AS HAS_EXTRACTION,
    COUNT(NARRATIVE_SENTIMENT) AS HAS_SENTIMENT,
    COUNT(*) - COUNT(EXTRACTED) AS MISSING_EXTRACTION,
    COUNT(*) - COUNT(NARRATIVE_SENTIMENT) AS MISSING_SENTIMENT
FROM D_BRONZE.ENRICHED_NARRATIVES;
