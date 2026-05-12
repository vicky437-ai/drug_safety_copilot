/*
 * PharmaCX Intelligence — Phase 7: Gold Layer (Analytical Views)
 * 
 * Prerequisites: Phase 6 complete (CX_SILVER.FACT_AE_CALLS and
 *                CX_SILVER.FACT_AGENT_COMPLIANCE populated)
 * 
 * This script creates:
 *   - CX_GOLD.V_AE_TRIAGE_QUEUE: Operational view for PV team with priority flags
 *     and submission deadline calculations
 *   - CX_GOLD.V_UNIFIED_AE_SIGNAL: Cross-source view combining FAERS + Call Center
 *     data for PRR (Proportional Reporting Ratio) signal detection
 *
 * Integration:
 *   - V_UNIFIED_AE_SIGNAL bridges the existing Drug Safety Co-Pilot (D_SILVER)
 *     with PharmaCX call center data (CX_SILVER)
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA CX_GOLD;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 7.1: V_AE_TRIAGE_QUEUE — Operational Triage View
-- Joins AE facts with compliance scores, calculates deadlines
-- and priority flags for the PV team's daily workflow
-- ============================================================
CREATE OR REPLACE VIEW CX_GOLD.V_AE_TRIAGE_QUEUE AS
SELECT
    c.SOURCE_CALL_ID,
    c.DRUG_NAME,
    c.AE_PREFERRED_TERM,
    c.AE_SOC_CLASS,
    c.AE_SERIOUSNESS,
    c.AE_OUTCOME,
    c.REPORTING_DEADLINE,
    c.CASE_NARRATIVE,
    c.PATIENT_AGE,
    c.PATIENT_SEX,
    a.COMPLIANCE_SCORE,
    a.CALLER_STATE,
    a.URGENCY_LEVEL,
    CASE c.REPORTING_DEADLINE
        WHEN '15_day_expedited' THEN DATEADD('day', 15, c.REPORT_DATE::DATE)
        WHEN '90_day_periodic'  THEN DATEADD('day', 90, c.REPORT_DATE::DATE)
        ELSE NULL
    END AS SUBMISSION_DEADLINE,
    CASE
        WHEN c.REPORTING_DEADLINE = '15_day_expedited'
         AND DATEADD('day', 15, c.REPORT_DATE::DATE) <= DATEADD('day', 3, CURRENT_DATE())
        THEN 'URGENT'
        WHEN c.REPORTING_DEADLINE = '15_day_expedited' THEN 'ACTION_REQUIRED'
        ELSE 'STANDARD'
    END AS PRIORITY_FLAG,
    c.REPORT_DATE
FROM CX_SILVER.FACT_AE_CALLS c
LEFT JOIN CX_SILVER.FACT_AGENT_COMPLIANCE a ON c.SOURCE_CALL_ID = a.CALL_ID
ORDER BY PRIORITY_FLAG, SUBMISSION_DEADLINE;

-- ============================================================
-- Step 7.2: V_UNIFIED_AE_SIGNAL — Cross-Source Signal Detection
-- Combines FAERS data (existing Drug Safety Co-Pilot) with
-- call center AE data for proportional reporting ratio analysis
-- ============================================================
CREATE OR REPLACE VIEW CX_GOLD.V_UNIFIED_AE_SIGNAL AS
SELECT DRUG_NAME, AE_SOC_CLASS, DATA_SOURCE, COUNT(*) AS CASE_COUNT
FROM (
    SELECT DRUG_NAME, AE_SOC_CLASS, 'FAERS' AS DATA_SOURCE
    FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT

    UNION ALL

    SELECT DRUG_NAME, AE_SOC_CLASS, 'CALL_CENTER' AS DATA_SOURCE
    FROM PHARMACOVIGILANCE.CX_SILVER.FACT_AE_CALLS
)
GROUP BY DRUG_NAME, AE_SOC_CLASS, DATA_SOURCE;

-- ============================================================
-- Step 7.3: Grant Access to Roles
-- ============================================================

-- V_AE_TRIAGE_QUEUE: PV operational roles
GRANT SELECT ON VIEW CX_GOLD.V_AE_TRIAGE_QUEUE TO ROLE CX_AGENT_SUPERVISOR;
GRANT SELECT ON VIEW CX_GOLD.V_AE_TRIAGE_QUEUE TO ROLE CX_QUALITY_ANALYST;
GRANT SELECT ON VIEW CX_GOLD.V_AE_TRIAGE_QUEUE TO ROLE DRUG_SAFETY_OFFICER;
GRANT SELECT ON VIEW CX_GOLD.V_AE_TRIAGE_QUEUE TO ROLE PV_ANALYST;

-- V_UNIFIED_AE_SIGNAL: Signal detection roles
GRANT SELECT ON VIEW CX_GOLD.V_UNIFIED_AE_SIGNAL TO ROLE CX_AGENT_SUPERVISOR;
GRANT SELECT ON VIEW CX_GOLD.V_UNIFIED_AE_SIGNAL TO ROLE CX_QUALITY_ANALYST;
GRANT SELECT ON VIEW CX_GOLD.V_UNIFIED_AE_SIGNAL TO ROLE DRUG_SAFETY_OFFICER;
GRANT SELECT ON VIEW CX_GOLD.V_UNIFIED_AE_SIGNAL TO ROLE PV_ANALYST;

-- ============================================================
-- Step 7.4: Verification
-- ============================================================

-- Check views exist
SHOW VIEWS IN SCHEMA CX_GOLD;

-- Triage queue sample
SELECT SOURCE_CALL_ID, DRUG_NAME, AE_PREFERRED_TERM, PRIORITY_FLAG, SUBMISSION_DEADLINE
FROM CX_GOLD.V_AE_TRIAGE_QUEUE
LIMIT 10;

-- Unified signal — verify both data sources appear
SELECT DATA_SOURCE, COUNT(*) AS TOTAL_ROWS, COUNT(DISTINCT DRUG_NAME) AS UNIQUE_DRUGS
FROM CX_GOLD.V_UNIFIED_AE_SIGNAL
GROUP BY DATA_SOURCE;
