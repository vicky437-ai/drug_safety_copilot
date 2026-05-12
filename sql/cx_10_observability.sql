/*
 * PharmaCX Intelligence — Phase 10: AI Observability
 * 
 * Prerequisites: CX_GOLD schema exists (Phase 0)
 * 
 * This script creates:
 *   - CX_GOLD.AI_OBSERVABILITY_EVENTS: Event log for all AI function calls
 *     (AI_TRANSCRIBE, AI_COMPLETE) with latency, token usage, and error tracking
 *   - CX_GOLD.V_AI_FUNCTION_HEALTH: Hourly rollup of call volume, error rates,
 *     and latency metrics per function/model
 *   - CX_GOLD.V_AI_ERROR_ALERT: Alert view showing models with >10% error rate
 *     in the last hour (for operational monitoring)
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA CX_GOLD;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 10.1: AI_OBSERVABILITY_EVENTS — AI Function Call Log
-- Populated by pipeline scripts or external logging processes
-- ============================================================
CREATE OR REPLACE TABLE CX_GOLD.AI_OBSERVABILITY_EVENTS (
    TIMESTAMP       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    FUNCTION_NAME   VARCHAR,
    MODEL_USED      VARCHAR,
    INPUT_FILE      VARCHAR,
    LATENCY_MS      NUMBER,
    TOKEN_COUNT     NUMBER,
    STATUS          VARCHAR,
    ERROR_MESSAGE   VARCHAR
);

-- ============================================================
-- Step 10.2: V_AI_FUNCTION_HEALTH — Hourly Health Rollup
-- Aggregates AI call metrics for dashboard monitoring
-- ============================================================
CREATE OR REPLACE VIEW CX_GOLD.V_AI_FUNCTION_HEALTH AS
SELECT
    DATE_TRUNC('hour', TIMESTAMP)                           AS HOUR,
    FUNCTION_NAME,
    MODEL_USED,
    COUNT(*)                                                AS TOTAL_CALLS,
    COUNT(CASE WHEN STATUS = 'error' THEN 1 END)           AS ERROR_COUNT,
    ROUND(AVG(LATENCY_MS), 0)                               AS AVG_LATENCY_MS,
    SUM(TOKEN_COUNT)                                        AS TOTAL_TOKENS
FROM CX_GOLD.AI_OBSERVABILITY_EVENTS
GROUP BY 1, 2, 3
ORDER BY HOUR DESC;

-- ============================================================
-- Step 10.3: V_AI_ERROR_ALERT — Error Rate Alerting View
-- Shows models exceeding 10% error rate in the last hour
-- Used by operational dashboards and Snowflake alerts
-- ============================================================
CREATE OR REPLACE VIEW CX_GOLD.V_AI_ERROR_ALERT AS
SELECT
    MODEL_USED,
    ERROR_COUNT,
    TOTAL_CALLS,
    ROUND(ERROR_COUNT / NULLIF(TOTAL_CALLS, 0) * 100, 1) AS ERROR_RATE_PCT
FROM CX_GOLD.V_AI_FUNCTION_HEALTH
WHERE HOUR >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
  AND ERROR_COUNT / NULLIF(TOTAL_CALLS, 0) > 0.10;

-- ============================================================
-- Step 10.4: Grant Access to Roles
-- ============================================================

-- Observability events table: write for pipeline, read for analysts
GRANT SELECT ON TABLE CX_GOLD.AI_OBSERVABILITY_EVENTS TO ROLE CX_QUALITY_ANALYST;
GRANT SELECT ON TABLE CX_GOLD.AI_OBSERVABILITY_EVENTS TO ROLE DRUG_SAFETY_OFFICER;
GRANT SELECT ON TABLE CX_GOLD.AI_OBSERVABILITY_EVENTS TO ROLE PV_ANALYST;

-- Health and alert views
GRANT SELECT ON VIEW CX_GOLD.V_AI_FUNCTION_HEALTH TO ROLE CX_AGENT_SUPERVISOR;
GRANT SELECT ON VIEW CX_GOLD.V_AI_FUNCTION_HEALTH TO ROLE CX_QUALITY_ANALYST;
GRANT SELECT ON VIEW CX_GOLD.V_AI_FUNCTION_HEALTH TO ROLE DRUG_SAFETY_OFFICER;
GRANT SELECT ON VIEW CX_GOLD.V_AI_FUNCTION_HEALTH TO ROLE PV_ANALYST;

GRANT SELECT ON VIEW CX_GOLD.V_AI_ERROR_ALERT TO ROLE CX_AGENT_SUPERVISOR;
GRANT SELECT ON VIEW CX_GOLD.V_AI_ERROR_ALERT TO ROLE CX_QUALITY_ANALYST;
GRANT SELECT ON VIEW CX_GOLD.V_AI_ERROR_ALERT TO ROLE DRUG_SAFETY_OFFICER;
GRANT SELECT ON VIEW CX_GOLD.V_AI_ERROR_ALERT TO ROLE PV_ANALYST;

-- ============================================================
-- Step 10.5: Verification
-- ============================================================

-- Check all objects exist
SHOW TABLES LIKE 'AI_OBSERVABILITY%' IN SCHEMA CX_GOLD;
SHOW VIEWS LIKE 'V_AI_%' IN SCHEMA CX_GOLD;

-- Verify table structure
DESCRIBE TABLE CX_GOLD.AI_OBSERVABILITY_EVENTS;

-- Health view (will return empty until events are logged)
SELECT * FROM CX_GOLD.V_AI_FUNCTION_HEALTH LIMIT 5;

-- Error alert view (will return empty until events are logged)
SELECT * FROM CX_GOLD.V_AI_ERROR_ALERT;
