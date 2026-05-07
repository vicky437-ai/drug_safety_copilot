/*
 * Drug Safety Co-Pilot — Phase 5: Cortex Search Service (Gold Layer)
 * 
 * Prerequisites: Phase 3 complete (D_SILVER.FACT_NARRATIVE populated)
 * 
 * This script creates:
 *   - D_GOLD.AE_NARRATIVE_SEARCH: Cortex Search Service for semantic search
 *     over clinical narratives
 *
 * Capabilities:
 *   - Natural language search over narrative text
 *   - Hybrid search (semantic + keyword)
 *   - Attribute filtering by CASE_ID
 *   - Real-time index refresh via TARGET_LAG
 *
 * Note: Index build takes ~10-15 minutes after creation.
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA D_GOLD;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 5.1: Create Cortex Search Service
-- Indexes narrative text for semantic search
-- Includes DRUG_NAME and AE_SOC_CLASS as filterable attributes
-- ============================================================
CREATE OR REPLACE CORTEX SEARCH SERVICE D_GOLD.AE_NARRATIVE_SEARCH
    ON NARRATIVE_TEXT
    ATTRIBUTES CASE_ID, DRUG_NAME, AE_SOC_CLASS
    WAREHOUSE = PV_WH
    TARGET_LAG = '1 hour'
AS
SELECT 
    n.CASE_ID, 
    n.NARRATIVE_TEXT,
    f.DRUG_NAME,
    f.AE_SOC_CLASS
FROM PHARMACOVIGILANCE.D_SILVER.FACT_NARRATIVE n
LEFT JOIN PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT f ON n.CASE_ID = f.CASE_ID;

-- ============================================================
-- Step 5.2: Grant access to roles
-- ============================================================
GRANT USAGE ON CORTEX SEARCH SERVICE D_GOLD.AE_NARRATIVE_SEARCH TO ROLE DRUG_SAFETY_OFFICER;
GRANT USAGE ON CORTEX SEARCH SERVICE D_GOLD.AE_NARRATIVE_SEARCH TO ROLE PV_ANALYST;

-- ============================================================
-- Step 5.2: Verification (wait ~10-15 minutes for index to build)
-- ============================================================

-- Check service status
SHOW CORTEX SEARCH SERVICES IN SCHEMA D_GOLD;

-- Test search query (run after index is ready)
-- Example: Find narratives about liver-related events
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'PHARMACOVIGILANCE.D_GOLD.AE_NARRATIVE_SEARCH',
        '{
            "query": "hepatotoxicity liver injury elevated transaminases",
            "columns": ["CASE_ID", "NARRATIVE_TEXT"],
            "limit": 5
        }'
    )
) AS SEARCH_RESULTS;

-- Example: Find cardiac-related narratives
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'PHARMACOVIGILANCE.D_GOLD.AE_NARRATIVE_SEARCH',
        '{
            "query": "cardiac event myocardial troponin elevated",
            "columns": ["CASE_ID", "NARRATIVE_TEXT"],
            "limit": 5
        }'
    )
) AS SEARCH_RESULTS;
