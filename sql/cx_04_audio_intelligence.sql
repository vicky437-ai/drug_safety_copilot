/*
 * PharmaCX Intelligence — Phase 4: Audio & Video Intelligence
 *
 * Prerequisites: cx_02_catalogs.sql executed (CALL_CATALOG + HCP_VIDEO_CATALOG populated)
 *
 * This script creates:
 *   - CX_BRONZE.CALL_AUDIO_INTELLIGENCE: Multimodal analysis of call recordings
 *   - CX_BRONZE.HCP_VIDEO_INTELLIGENCE: Multimodal analysis of HCP video visits
 *
 * Cortex AI Functions Used:
 *   - AI_COMPLETE (5-arg multimodal form): gemini-3.1-pro processes raw audio/video
 *     Syntax: AI_COMPLETE(model, prompt, file, model_params, response_format)
 *     Analyzes acoustic signals (tone, pace, emotion) that transcription alone cannot capture
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA CX_BRONZE;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step CX-4.1: Call Recording Audio Intelligence
-- Gemini multimodal analysis of acoustic signals, compliance, urgency
-- ============================================================
CREATE OR REPLACE TABLE CX_BRONZE.CALL_AUDIO_INTELLIGENCE AS
SELECT
    c.file_path,
    c.file_name,
    AI_COMPLETE(
        'gemini-3.1-pro',
        'You are a pharmaceutical contact center quality analyst. Listen to this medical information call recording and analyze the following dimensions. Focus on acoustic signals (tone, pace, pauses, emotional state) that cannot be derived from text alone. Respond in JSON only.',
        c.audio_file,
        {},
        {
            'type': 'json',
            'schema': {
                'type': 'object',
                'properties': {
                    'caller_emotional_state': {'type': 'string', 'enum': ['calm', 'concerned', 'distressed', 'confused', 'angry']},
                    'caller_urgency_level': {'type': 'string', 'enum': ['routine', 'elevated', 'urgent', 'emergency']},
                    'ae_acoustic_signals': {'type': 'array', 'items': {'type': 'string'}},
                    'agent_compliance_score': {'type': 'number'},
                    'agent_tone_professional': {'type': 'boolean'},
                    'call_duration_category': {'type': 'string', 'enum': ['brief_under_2min', 'standard_2_to_8min', 'extended_over_8min']},
                    'call_type_inferred': {'type': 'string', 'enum': ['adverse_event_report', 'product_quality_complaint', 'off_label_inquiry', 'standard_drug_info', 'unknown']},
                    'escalation_recommended': {'type': 'boolean'},
                    'escalation_reason': {'type': 'string'}
                },
                'required': ['caller_emotional_state', 'caller_urgency_level', 'agent_compliance_score', 'call_type_inferred', 'escalation_recommended']
            }
        }
    ) AS audio_intelligence_json,
    CURRENT_TIMESTAMP() AS analyzed_at
FROM CX_RAW.CALL_CATALOG c;

-- ============================================================
-- Step CX-4.2: HCP Video Visit Intelligence
-- Same multimodal analysis applied to video files (gemini supports MP4)
-- ============================================================
CREATE OR REPLACE TABLE CX_BRONZE.HCP_VIDEO_INTELLIGENCE AS
SELECT
    v.file_path,
    v.file_name,
    AI_COMPLETE(
        'gemini-3.1-pro',
        'You are a pharmaceutical medical affairs analyst. Watch this healthcare provider (HCP) video visit and analyze the following dimensions. Focus on visual and acoustic signals: speaker body language, tone, clinical discussion quality, and any mention of adverse events or product complaints. Respond in JSON only.',
        v.video_file,
        {},
        {
            'type': 'json',
            'schema': {
                'type': 'object',
                'properties': {
                    'caller_emotional_state': {'type': 'string', 'enum': ['calm', 'concerned', 'distressed', 'confused', 'angry']},
                    'caller_urgency_level': {'type': 'string', 'enum': ['routine', 'elevated', 'urgent', 'emergency']},
                    'ae_acoustic_signals': {'type': 'array', 'items': {'type': 'string'}},
                    'agent_compliance_score': {'type': 'number'},
                    'agent_tone_professional': {'type': 'boolean'},
                    'call_duration_category': {'type': 'string', 'enum': ['brief_under_2min', 'standard_2_to_8min', 'extended_over_8min']},
                    'call_type_inferred': {'type': 'string', 'enum': ['adverse_event_report', 'product_quality_complaint', 'off_label_inquiry', 'standard_drug_info', 'unknown']},
                    'escalation_recommended': {'type': 'boolean'},
                    'escalation_reason': {'type': 'string'}
                },
                'required': ['caller_emotional_state', 'caller_urgency_level', 'agent_compliance_score', 'call_type_inferred', 'escalation_recommended']
            }
        }
    ) AS audio_intelligence_json,
    CURRENT_TIMESTAMP() AS analyzed_at
FROM CX_RAW.HCP_VIDEO_CATALOG v;

-- ============================================================
-- Step CX-4.3: Verification
-- ============================================================

-- Preview call audio intelligence results
SELECT
    file_name,
    audio_intelligence_json:caller_emotional_state::VARCHAR AS emotional_state,
    audio_intelligence_json:caller_urgency_level::VARCHAR AS urgency,
    audio_intelligence_json:agent_compliance_score::NUMBER AS compliance_score,
    audio_intelligence_json:call_type_inferred::VARCHAR AS call_type,
    audio_intelligence_json:escalation_recommended::BOOLEAN AS escalation_flag
FROM CX_BRONZE.CALL_AUDIO_INTELLIGENCE;

-- Preview video intelligence results
SELECT
    file_name,
    audio_intelligence_json:caller_emotional_state::VARCHAR AS emotional_state,
    audio_intelligence_json:caller_urgency_level::VARCHAR AS urgency,
    audio_intelligence_json:call_type_inferred::VARCHAR AS call_type,
    audio_intelligence_json:escalation_recommended::BOOLEAN AS escalation_flag
FROM CX_BRONZE.HCP_VIDEO_INTELLIGENCE;

-- Row counts
SELECT 'CALL_AUDIO_INTELLIGENCE' AS table_name, COUNT(*) AS row_count FROM CX_BRONZE.CALL_AUDIO_INTELLIGENCE
UNION ALL
SELECT 'HCP_VIDEO_INTELLIGENCE', COUNT(*) FROM CX_BRONZE.HCP_VIDEO_INTELLIGENCE;

-- Check for NULL results (indicates AI_COMPLETE failure)
SELECT 'CALL_AUDIO_INTELLIGENCE' AS table_name, COUNT(*) AS null_count
FROM CX_BRONZE.CALL_AUDIO_INTELLIGENCE WHERE audio_intelligence_json IS NULL
UNION ALL
SELECT 'HCP_VIDEO_INTELLIGENCE', COUNT(*)
FROM CX_BRONZE.HCP_VIDEO_INTELLIGENCE WHERE audio_intelligence_json IS NULL;
