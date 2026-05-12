/*
 * PharmaCX Intelligence — Phase 6: Silver Layer (Dynamic Tables)
 * 
 * Prerequisites: Phase 5 complete (CX_BRONZE.CALL_AE_EXTRACTIONS and
 *                CX_BRONZE.CALL_AUDIO_INTELLIGENCE populated)
 * 
 * This script creates:
 *   - CX_SILVER.FACT_AE_CALLS: One row per detected AE from call recordings
 *     (LATERAL FLATTEN on adverse_events array)
 *   - CX_SILVER.FACT_AGENT_COMPLIANCE: Agent compliance metrics per call
 *
 * Dynamic Tables provide:
 *   - Automatic incremental refresh when upstream Bronze data changes
 *   - TARGET_LAG = 30 minutes (tighter than Phase 1 since AE triage is time-sensitive)
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA CX_SILVER;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 6.1: FACT_AE_CALLS — One Row Per Detected Adverse Event
-- Flattens the adverse_events array from AI extraction output
-- Only includes calls where ae_detected = TRUE
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE CX_SILVER.FACT_AE_CALLS
    TARGET_LAG = '30 minutes'
    WAREHOUSE = PV_WH
AS
SELECT
    ae.file_name                                                    AS SOURCE_CALL_ID,
    'CALL_CENTER'                                                   AS DATA_SOURCE,
    ae.ae_extraction_json:suspect_drug:drug_name::VARCHAR           AS DRUG_NAME,
    ae.ae_extraction_json:suspect_drug:drug_dose::VARCHAR           AS DRUG_DOSE,
    ae.ae_extraction_json:suspect_drug:drug_route::VARCHAR          AS DRUG_ROUTE,
    s.value:meddra_preferred_term::VARCHAR                          AS AE_PREFERRED_TERM,
    s.value:meddra_soc_class::VARCHAR                               AS AE_SOC_CLASS,
    ARRAY_TO_STRING(s.value:seriousness_criteria, ', ')             AS AE_SERIOUSNESS,
    s.value:outcome::VARCHAR                                        AS AE_OUTCOME,
    s.value:causality_who_umc::VARCHAR                              AS CAUSALITY,
    ae.ae_extraction_json:patient:age::VARCHAR                      AS PATIENT_AGE,
    ae.ae_extraction_json:patient:sex::VARCHAR                      AS PATIENT_SEX,
    ae.ae_extraction_json:reporting_deadline::VARCHAR                AS REPORTING_DEADLINE,
    ae.ae_extraction_json:narrative_summary::VARCHAR                 AS CASE_NARRATIVE,
    ae.extracted_at                                                  AS REPORT_DATE
FROM PHARMACOVIGILANCE.CX_BRONZE.CALL_AE_EXTRACTIONS ae,
    LATERAL FLATTEN(input => ae.ae_extraction_json:adverse_events) s
WHERE ae.ae_extraction_json IS NOT NULL
  AND ae.ae_extraction_json:ae_detected::BOOLEAN = TRUE;

-- ============================================================
-- Step 6.2: FACT_AGENT_COMPLIANCE — Agent Compliance Metrics
-- One row per call with audio intelligence scores
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE CX_SILVER.FACT_AGENT_COMPLIANCE
    TARGET_LAG = '30 minutes'
    WAREHOUSE = PV_WH
AS
SELECT
    ai.file_name                                                    AS CALL_ID,
    ai.audio_intelligence_json:agent_compliance_score::FLOAT        AS COMPLIANCE_SCORE,
    ai.audio_intelligence_json:agent_tone_professional::BOOLEAN     AS TONE_PROFESSIONAL,
    ai.audio_intelligence_json:caller_emotional_state::VARCHAR      AS CALLER_STATE,
    ai.audio_intelligence_json:caller_urgency_level::VARCHAR        AS URGENCY_LEVEL,
    ai.audio_intelligence_json:call_type_inferred::VARCHAR          AS CALL_TYPE,
    ai.audio_intelligence_json:escalation_recommended::BOOLEAN      AS ESCALATION_NEEDED,
    ai.audio_intelligence_json:escalation_reason::VARCHAR           AS ESCALATION_REASON,
    ai.analyzed_at
FROM PHARMACOVIGILANCE.CX_BRONZE.CALL_AUDIO_INTELLIGENCE ai
WHERE ai.audio_intelligence_json IS NOT NULL;

-- ============================================================
-- Step 6.3: Verification
-- ============================================================

-- Check both dynamic tables exist and show refresh status
SHOW DYNAMIC TABLES IN SCHEMA CX_SILVER;

-- Row counts
SELECT 'FACT_AE_CALLS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM CX_SILVER.FACT_AE_CALLS
UNION ALL
SELECT 'FACT_AGENT_COMPLIANCE', COUNT(*) FROM CX_SILVER.FACT_AGENT_COMPLIANCE;

-- Sample AE data
SELECT SOURCE_CALL_ID, DRUG_NAME, AE_PREFERRED_TERM, AE_SOC_CLASS, REPORTING_DEADLINE
FROM CX_SILVER.FACT_AE_CALLS
LIMIT 10;

-- Sample compliance data
SELECT CALL_ID, COMPLIANCE_SCORE, CALLER_STATE, URGENCY_LEVEL, ESCALATION_NEEDED
FROM CX_SILVER.FACT_AGENT_COMPLIANCE
LIMIT 10;
