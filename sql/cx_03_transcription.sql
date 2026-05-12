/*
 * PharmaCX Intelligence — Phase 3: Audio & Video Transcription
 *
 * Prerequisites: cx_02_catalogs.sql executed (CALL_CATALOG + HCP_VIDEO_CATALOG populated)
 *
 * This script creates:
 *   - CX_BRONZE.CALL_TRANSCRIPTIONS: Speaker-diarized transcripts of call recordings
 *   - CX_BRONZE.HCP_VIDEO_TRANSCRIPTIONS: Transcripts extracted from HCP video audio tracks
 *
 * Cortex AI Functions Used:
 *   - AI_TRANSCRIBE(file, options): Speech-to-text with speaker diarization
 *     Output: VARIANT with :text (full text), :segments[] (per-speaker segments)
 *     Speaker access: transcription_result:segments[N]:speaker_label
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA CX_BRONZE;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step CX-3.1: Transcribe Call Recordings
-- Speaker diarization enabled to distinguish caller vs agent
-- ============================================================
CREATE OR REPLACE TABLE CX_BRONZE.CALL_TRANSCRIPTIONS AS
SELECT
    file_path,
    file_name,
    received_at,
    AI_TRANSCRIBE(audio_file, {'timestamp_granularity': 'speaker'}) AS transcription_result,
    CURRENT_TIMESTAMP() AS transcribed_at
FROM CX_RAW.CALL_CATALOG;

-- ============================================================
-- Step CX-3.2: Transcribe HCP Video Visits
-- AI_TRANSCRIBE supports MP4 — extracts audio track automatically
-- ============================================================
CREATE OR REPLACE TABLE CX_BRONZE.HCP_VIDEO_TRANSCRIPTIONS AS
SELECT
    file_path,
    file_name,
    received_at,
    AI_TRANSCRIBE(video_file) AS transcription_result,
    CURRENT_TIMESTAMP() AS transcribed_at
FROM CX_RAW.HCP_VIDEO_CATALOG;

-- ============================================================
-- Step CX-3.3: Verification
-- ============================================================

-- Preview call transcriptions (first 200 chars of text)
SELECT
    file_name,
    LEFT(transcription_result:text::VARCHAR, 200) AS transcript_preview,
    transcribed_at
FROM CX_BRONZE.CALL_TRANSCRIPTIONS
LIMIT 3;

-- Preview video transcriptions
SELECT
    file_name,
    LEFT(transcription_result:text::VARCHAR, 200) AS transcript_preview,
    transcribed_at
FROM CX_BRONZE.HCP_VIDEO_TRANSCRIPTIONS
LIMIT 3;

-- Row counts
SELECT 'CALL_TRANSCRIPTIONS' AS table_name, COUNT(*) AS row_count FROM CX_BRONZE.CALL_TRANSCRIPTIONS
UNION ALL
SELECT 'HCP_VIDEO_TRANSCRIPTIONS', COUNT(*) FROM CX_BRONZE.HCP_VIDEO_TRANSCRIPTIONS;

-- Check for any NULL transcriptions (indicates AI_TRANSCRIBE failure)
SELECT 'CALL_TRANSCRIPTIONS' AS table_name, COUNT(*) AS null_count
FROM CX_BRONZE.CALL_TRANSCRIPTIONS WHERE transcription_result IS NULL
UNION ALL
SELECT 'HCP_VIDEO_TRANSCRIPTIONS', COUNT(*)
FROM CX_BRONZE.HCP_VIDEO_TRANSCRIPTIONS WHERE transcription_result IS NULL;
