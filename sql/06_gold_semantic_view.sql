/*
 * Drug Safety Co-Pilot — Phase 6: Semantic View + Cortex Analyst (Gold)
 * 
 * Prerequisites: Phase 3 complete (D_SILVER dynamic tables populated)
 * 
 * This script creates:
 *   - D_GOLD.PV_ANALYST_VIEW: Semantic view for Cortex Analyst
 *     enabling natural language queries over pharmacovigilance data
 *
 * The semantic model (semantic_model.yaml) must be validated first with:
 *   cortex reflect semantic_model.yaml --target-schema PHARMACOVIGILANCE.D_GOLD
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA D_GOLD;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 6.1: Create Semantic View
-- Deploy after validating semantic_model.yaml with cortex reflect
-- ============================================================

-- Note: The actual semantic view creation uses the validated YAML.
-- The command below is a placeholder — the actual DDL is generated
-- by `cortex reflect` or via Snowsight UI.

-- If using SQL DDL directly:
CREATE OR REPLACE SEMANTIC VIEW D_GOLD.PV_ANALYST_VIEW
    FROM @PHARMACOVIGILANCE.D_GOLD.SEMANTIC_STAGE/semantic_model.yaml;

-- Alternative: Upload YAML to a stage first
CREATE OR REPLACE STAGE D_GOLD.SEMANTIC_STAGE;

-- PUT file to stage (run from SnowSQL/CLI):
-- PUT file://semantic_model.yaml @PHARMACOVIGILANCE.D_GOLD.SEMANTIC_STAGE AUTO_COMPRESS=FALSE;

-- ============================================================
-- Step 6.2: Grant access to semantic view
-- ============================================================
GRANT SELECT ON SEMANTIC VIEW D_GOLD.PV_ANALYST_VIEW TO ROLE DRUG_SAFETY_OFFICER;
GRANT SELECT ON SEMANTIC VIEW D_GOLD.PV_ANALYST_VIEW TO ROLE PV_ANALYST;

-- ============================================================
-- Step 6.3: Verification
-- Test natural language queries via Cortex Analyst
-- ============================================================

-- Test via SQL (Cortex Analyst function)
-- These can also be tested via: cortex analyst query "..." --view=PV_ANALYST_VIEW

-- Example queries to test:
-- "What are the top 5 drugs by total adverse event count?"
-- "Show monthly trend of severe adverse events in 2024"
-- "Which drugs have the highest fatal outcome rate?"
-- "Compare AE counts between male and female patients for pembrolizumab"
-- "What is the average onset time for hepatotoxicity events?"
