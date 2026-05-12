/*
 * PharmaCX Intelligence — Phase 8: Scheduled Tasks
 * 
 * Prerequisites: Phase 2 complete (CX_RAW.CALL_CATALOG, CX_BRONZE.CALL_TRANSCRIPTIONS exist)
 *                Stages: CX_RAW.CALL_RECORDING_STAGE with DIRECTORY enabled
 * 
 * This script creates:
 *   - CX_RAW.CX_REFRESH_CALL_CATALOG: Cron task (every 2 hours) that scans the
 *     stage directory for new call recordings and adds them to the catalog
 *   - CX_RAW.CX_TRANSCRIBE_NEW_CALLS: Dependent task that transcribes newly
 *     cataloged calls using AI_TRANSCRIBE
 *
 * Task chain: CX_REFRESH_CALL_CATALOG → CX_TRANSCRIBE_NEW_CALLS
 * Batch size: LIMIT 10 per run to control AI function costs
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA CX_RAW;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 8.1: CX_REFRESH_CALL_CATALOG — Incremental Stage Scan
-- Runs every 2 hours, inserts new files not yet in catalog
-- ============================================================
CREATE OR REPLACE TASK PHARMACOVIGILANCE.CX_RAW.CX_REFRESH_CALL_CATALOG
    WAREHOUSE = PV_WH
    SCHEDULE = 'USING CRON 0 */2 * * * America/New_York'
AS
    INSERT INTO CX_RAW.CALL_CATALOG (audio_file, file_path, file_name, file_size_bytes, received_at)
    SELECT
        TO_FILE('@CX_RAW.CALL_RECORDING_STAGE', RELATIVE_PATH) AS audio_file,
        RELATIVE_PATH,
        SPLIT_PART(RELATIVE_PATH, '/', -1),
        SIZE,
        LAST_MODIFIED
    FROM DIRECTORY(@CX_RAW.CALL_RECORDING_STAGE)
    WHERE RELATIVE_PATH NOT IN (SELECT file_path FROM CX_RAW.CALL_CATALOG)
    ORDER BY LAST_MODIFIED ASC
    LIMIT 10;

-- ============================================================
-- Step 8.2: CX_TRANSCRIBE_NEW_CALLS — Dependent Transcription
-- Runs after catalog refresh, transcribes new recordings
-- ============================================================
CREATE OR REPLACE TASK PHARMACOVIGILANCE.CX_RAW.CX_TRANSCRIBE_NEW_CALLS
    WAREHOUSE = PV_WH
    AFTER PHARMACOVIGILANCE.CX_RAW.CX_REFRESH_CALL_CATALOG
AS
    INSERT INTO CX_BRONZE.CALL_TRANSCRIPTIONS (file_path, file_name, received_at, transcription_result, transcribed_at)
    SELECT
        c.file_path,
        c.file_name,
        c.received_at,
        AI_TRANSCRIBE(c.audio_file, {'timestamp_granularity': 'speaker'}),
        CURRENT_TIMESTAMP()
    FROM CX_RAW.CALL_CATALOG c
    WHERE c.file_path NOT IN (SELECT file_path FROM CX_BRONZE.CALL_TRANSCRIPTIONS)
    ORDER BY c.received_at ASC
    LIMIT 10;

-- ============================================================
-- Step 8.3: Resume Tasks (child first, then root)
-- ============================================================
ALTER TASK PHARMACOVIGILANCE.CX_RAW.CX_TRANSCRIBE_NEW_CALLS RESUME;
ALTER TASK PHARMACOVIGILANCE.CX_RAW.CX_REFRESH_CALL_CATALOG RESUME;

-- ============================================================
-- Step 8.4: Verification
-- ============================================================

-- Check both tasks exist and are running
SHOW TASKS IN SCHEMA CX_RAW;

-- Verify task chain
SELECT NAME, STATE, SCHEDULE, PREDECESSORS
FROM TABLE(INFORMATION_SCHEMA.TASK_DEPENDENTS(
    TASK_NAME => 'PHARMACOVIGILANCE.CX_RAW.CX_REFRESH_CALL_CATALOG',
    RECURSIVE => TRUE
));
