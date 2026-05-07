/*
 * Drug Safety Co-Pilot — Phase 4: Governance & Data Quality
 * 
 * Prerequisites: Phase 3 complete (D_SILVER dynamic tables populated)
 * 
 * This script implements:
 *   - SYSTEM$CLASSIFY: Auto-detect PII/PHI in patient data
 *   - Dynamic Data Masking: Role-based access to sensitive fields
 *   - Object Tagging: HIPAA compliance labels
 *   - Data Metric Functions: Automated data quality monitoring
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA D_SILVER;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 4.1: Auto PHI Classification
-- SYSTEM$CLASSIFY detects PII/PHI columns automatically
-- ============================================================
SELECT SYSTEM$CLASSIFY('PHARMACOVIGILANCE.D_SILVER.DIM_PATIENT', {'auto_tag': true});

-- Review what was detected
SELECT * FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES('PHARMACOVIGILANCE.D_SILVER.DIM_PATIENT', 'TABLE')
);

-- ============================================================
-- Step 4.2: Dynamic Data Masking
-- DSO sees unmasked data; others see hashed or redacted values
-- ============================================================

-- Masking policy for Patient ID
CREATE OR REPLACE MASKING POLICY D_SILVER.MASK_PATIENT_ID 
AS (val STRING) RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION('DRUG_SAFETY_OFFICER') THEN val
        WHEN IS_ROLE_IN_SESSION('DATA_ENGINEER') THEN SHA2(val)
        ELSE '***REDACTED***'
    END;

-- Masking policy for Date of Birth (PHI)
CREATE OR REPLACE MASKING POLICY D_SILVER.MASK_DOB 
AS (val DATE) RETURNS DATE ->
    CASE
        WHEN IS_ROLE_IN_SESSION('DRUG_SAFETY_OFFICER') THEN val
        ELSE DATE_FROM_PARTS(YEAR(val), 1, 1)  -- Generalize to year only
    END;

-- Masking policy for Patient Weight
CREATE OR REPLACE MASKING POLICY D_SILVER.MASK_WEIGHT 
AS (val FLOAT) RETURNS FLOAT ->
    CASE
        WHEN IS_ROLE_IN_SESSION('DRUG_SAFETY_OFFICER') THEN val
        ELSE NULL
    END;

-- Apply masking policies to DIM_PATIENT
ALTER TABLE D_SILVER.DIM_PATIENT MODIFY COLUMN PATIENT_ID
    SET MASKING POLICY D_SILVER.MASK_PATIENT_ID;

ALTER TABLE D_SILVER.DIM_PATIENT MODIFY COLUMN PATIENT_DOB
    SET MASKING POLICY D_SILVER.MASK_DOB;

ALTER TABLE D_SILVER.DIM_PATIENT MODIFY COLUMN PATIENT_WEIGHT
    SET MASKING POLICY D_SILVER.MASK_WEIGHT;

-- ============================================================
-- Step 4.3: HIPAA Compliance Tags
-- Object tags for regulatory traceability and audit
-- ============================================================
CREATE OR REPLACE TAG D_SILVER.HIPAA_CATEGORY 
    ALLOWED_VALUES 'PHI', 'PII', 'SENSITIVE', 'PUBLIC';

CREATE OR REPLACE TAG D_SILVER.DATA_CLASSIFICATION 
    ALLOWED_VALUES 'CONFIDENTIAL', 'INTERNAL', 'PUBLIC';

-- Apply HIPAA tags to sensitive columns
ALTER TABLE D_SILVER.DIM_PATIENT MODIFY COLUMN PATIENT_DOB 
    SET TAG D_SILVER.HIPAA_CATEGORY = 'PHI';

ALTER TABLE D_SILVER.DIM_PATIENT MODIFY COLUMN PATIENT_ID 
    SET TAG D_SILVER.HIPAA_CATEGORY = 'PII';

ALTER TABLE D_SILVER.DIM_PATIENT MODIFY COLUMN PATIENT_WEIGHT 
    SET TAG D_SILVER.HIPAA_CATEGORY = 'PHI';

ALTER TABLE D_SILVER.DIM_PATIENT MODIFY COLUMN PATIENT_AGE 
    SET TAG D_SILVER.HIPAA_CATEGORY = 'SENSITIVE';

-- Tag the fact table
ALTER TABLE D_SILVER.FACT_ADVERSE_EVENT MODIFY COLUMN CASE_ID 
    SET TAG D_SILVER.DATA_CLASSIFICATION = 'CONFIDENTIAL';

-- ============================================================
-- Step 4.4: Data Metric Functions (DMFs)
-- Automated data quality monitoring
-- ============================================================

-- NULL count monitoring on critical AE field
ALTER TABLE D_SILVER.FACT_ADVERSE_EVENT
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (AE_TERM);

-- Row count tracking for volume monitoring
ALTER TABLE D_SILVER.FACT_ADVERSE_EVENT
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();

-- Freshness monitoring on report date
-- Note: FRESHNESS requires TIMESTAMP; cast if REPORT_DATE is DATE type
ALTER TABLE D_SILVER.FACT_ADVERSE_EVENT
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (REPORT_DATE);

-- ============================================================
-- Step 4.5: Verification
-- ============================================================

-- Test masking with PV_ANALYST role (should see redacted data)
USE ROLE PV_ANALYST;
SELECT PATIENT_ID, PATIENT_DOB, PATIENT_WEIGHT, PATIENT_AGE 
FROM D_SILVER.DIM_PATIENT LIMIT 5;

-- Test with DRUG_SAFETY_OFFICER role (should see clear data)
USE ROLE DRUG_SAFETY_OFFICER;
SELECT PATIENT_ID, PATIENT_DOB, PATIENT_WEIGHT, PATIENT_AGE 
FROM D_SILVER.DIM_PATIENT LIMIT 5;

-- Return to admin
USE ROLE ACCOUNTADMIN;

-- Check tag assignments
SELECT * FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES('PHARMACOVIGILANCE.D_SILVER.DIM_PATIENT', 'TABLE')
);

-- Check DMF status
SELECT * FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
    REF_ENTITY_NAME => 'PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT',
    REF_ENTITY_DOMAIN => 'TABLE'
));
