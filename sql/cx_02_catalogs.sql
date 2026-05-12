/*
 * PharmaCX Intelligence — Phase 2: Call & Video Catalogs
 *
 * Prerequisites: cx_00_setup.sql executed (CX_RAW schema + stages created),
 *                media files uploaded to stages via PUT or Snow CLI
 *
 * This script creates:
 *   - CX_RAW.CALL_CATALOG: File inventory of call recordings with TO_FILE() references
 *   - CX_RAW.HCP_VIDEO_CATALOG: File inventory of HCP video visits with TO_FILE() references
 *
 * Cortex AI Functions Used:
 *   - TO_FILE(): Creates FILE-type references for downstream AI_TRANSCRIBE/AI_COMPLETE
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA CX_RAW;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step CX-2.1: Refresh Stage Directory Metadata
-- Required after uploading files so DIRECTORY() returns current listing
-- ============================================================
ALTER STAGE CX_RAW.CALL_RECORDING_STAGE REFRESH;
ALTER STAGE CX_RAW.HCP_VIDEO_STAGE REFRESH;

-- ============================================================
-- Step CX-2.2: Create Call Recording Catalog
-- Maps staged MP3/WAV files to FILE-type references for AI functions
-- ============================================================
CREATE OR REPLACE TABLE CX_RAW.CALL_CATALOG AS
SELECT
    TO_FILE('@CX_RAW.CALL_RECORDING_STAGE', RELATIVE_PATH) AS audio_file,
    RELATIVE_PATH AS file_path,
    SPLIT_PART(RELATIVE_PATH, '/', -1) AS file_name,
    SIZE AS file_size_bytes,
    LAST_MODIFIED AS received_at
FROM DIRECTORY(@CX_RAW.CALL_RECORDING_STAGE);

-- ============================================================
-- Step CX-2.3: Create HCP Video Catalog
-- Maps staged MP4 files to FILE-type references for AI functions
-- ============================================================
CREATE OR REPLACE TABLE CX_RAW.HCP_VIDEO_CATALOG AS
SELECT
    TO_FILE('@CX_RAW.HCP_VIDEO_STAGE', RELATIVE_PATH) AS video_file,
    RELATIVE_PATH AS file_path,
    SPLIT_PART(RELATIVE_PATH, '/', -1) AS file_name,
    SIZE AS file_size_bytes,
    LAST_MODIFIED AS received_at
FROM DIRECTORY(@CX_RAW.HCP_VIDEO_STAGE);

-- ============================================================
-- Step CX-2.4: Verification
-- ============================================================

-- Call catalog row count (expect 10 files)
SELECT 'CALL_CATALOG' AS catalog, COUNT(*) AS file_count FROM CX_RAW.CALL_CATALOG
UNION ALL
SELECT 'HCP_VIDEO_CATALOG', COUNT(*) FROM CX_RAW.HCP_VIDEO_CATALOG;

-- Inspect call catalog contents
SELECT file_name, file_size_bytes, received_at
FROM CX_RAW.CALL_CATALOG
ORDER BY received_at DESC;

-- Inspect video catalog contents
SELECT file_name, file_size_bytes, received_at
FROM CX_RAW.HCP_VIDEO_CATALOG
ORDER BY received_at DESC;
