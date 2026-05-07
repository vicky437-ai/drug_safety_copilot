/*
 * Drug Safety Co-Pilot — Phase 7 & 8: Streamlit Deployment
 * 
 * Prerequisites: Phases 5-6 complete (Cortex Search + Semantic View exist)
 * 
 * This script creates:
 *   - Stage for Streamlit app files
 *   - Streamlit app deployment in Snowflake
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA D_GOLD;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 7.1: Create Stage for Streamlit Files
-- ============================================================
CREATE OR REPLACE STAGE D_GOLD.STREAMLIT_STAGE
    DIRECTORY = (ENABLE = TRUE);

-- Upload files (run from CLI):
-- PUT file://streamlit/app.py @PHARMACOVIGILANCE.D_GOLD.STREAMLIT_STAGE/streamlit/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- ============================================================
-- Step 7.2: Create Streamlit App
-- ============================================================
CREATE OR REPLACE STREAMLIT D_GOLD.PV_SIGNAL_DASHBOARD
    ROOT_LOCATION = '@PHARMACOVIGILANCE.D_GOLD.STREAMLIT_STAGE/streamlit'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = PV_WH
    TITLE = 'Drug Safety Co-Pilot';

-- ============================================================
-- Step 7.3: Grant Access
-- ============================================================
GRANT USAGE ON STREAMLIT D_GOLD.PV_SIGNAL_DASHBOARD TO ROLE DRUG_SAFETY_OFFICER;
GRANT USAGE ON STREAMLIT D_GOLD.PV_SIGNAL_DASHBOARD TO ROLE PV_ANALYST;

-- ============================================================
-- Step 7.4: Verification
-- ============================================================
SHOW STREAMLITS IN SCHEMA D_GOLD;
