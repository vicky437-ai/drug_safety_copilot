/*
 * PharmaCX Intelligence — Phase 5: Adverse Event Extraction (PV)
 *
 * Prerequisites: cx_03_transcription.sql executed (CALL_TRANSCRIPTIONS + HCP_VIDEO_TRANSCRIPTIONS populated)
 *
 * This script creates:
 *   - CX_BRONZE.CALL_AE_EXTRACTIONS: ICH E2A-compliant AE extraction from call transcripts
 *   - CX_BRONZE.HCP_VIDEO_AE_EXTRACTIONS: AE extraction from HCP video transcripts
 *
 * Cortex AI Functions Used:
 *   - AI_COMPLETE (4-arg text form): claude-sonnet-4-6 for medical NLP
 *     Syntax: AI_COMPLETE(model, prompt, model_params, response_format)
 *     Note: claude does NOT support audio/video — processes transcript TEXT only
 *     Claude chosen for superior MedDRA coding and pharmacovigilance reasoning
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA CX_BRONZE;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step CX-5.1: Extract AEs from Call Transcripts
-- Uses claude-sonnet-4-6 on transcript text per ICH E2A guidelines
-- ============================================================
CREATE OR REPLACE TABLE CX_BRONZE.CALL_AE_EXTRACTIONS AS
SELECT
    t.file_path,
    t.file_name,
    AI_COMPLETE(
        'claude-sonnet-4-6',
        CONCAT(
            'You are a pharmacovigilance specialist. Analyze this medical information call transcript for adverse event reports per ICH E2A guidelines.\n\nTRANSCRIPT:\n',
            t.transcription_result:text::VARCHAR,
            '\n\nExtract all pharmacovigilance data. A valid ICSR requires: identifiable patient, suspect drug, adverse event. Apply WHO-UMC causality criteria. Respond in JSON only.'
        ),
        {},
        {
            'type': 'json',
            'schema': {
                'type': 'object',
                'properties': {
                    'ae_detected': {'type': 'boolean'},
                    'icsr_completeness': {'type': 'string', 'enum': ['complete', 'minimum_criteria_met', 'incomplete', 'no_ae']},
                    'adverse_events': {
                        'type': 'array',
                        'items': {
                            'type': 'object',
                            'properties': {
                                'ae_description_verbatim': {'type': 'string'},
                                'meddra_preferred_term': {'type': 'string'},
                                'meddra_soc_class': {'type': 'string'},
                                'seriousness_criteria': {
                                    'type': 'array',
                                    'items': {
                                        'type': 'string',
                                        'enum': ['death', 'life_threatening', 'hospitalization', 'disability', 'congenital_anomaly', 'medically_significant', 'none']
                                    }
                                },
                                'outcome': {'type': 'string', 'enum': ['recovered', 'recovering', 'not_recovered', 'fatal', 'sequelae', 'unknown']},
                                'causality_who_umc': {'type': 'string', 'enum': ['certain', 'probable', 'possible', 'unlikely', 'conditional', 'unassessable']}
                            },
                            'required': ['ae_description_verbatim', 'meddra_preferred_term', 'seriousness_criteria', 'outcome']
                        }
                    },
                    'suspect_drug': {
                        'type': 'object',
                        'properties': {
                            'drug_name': {'type': 'string'},
                            'drug_dose': {'type': 'string'},
                            'drug_route': {'type': 'string'},
                            'indication': {'type': 'string'}
                        }
                    },
                    'patient': {
                        'type': 'object',
                        'properties': {
                            'age': {'type': 'string'},
                            'sex': {'type': 'string'},
                            'identifier': {'type': 'string'}
                        }
                    },
                    'product_quality_complaint': {'type': 'boolean'},
                    'off_label_use_mentioned': {'type': 'boolean'},
                    'reporting_deadline': {'type': 'string', 'enum': ['15_day_expedited', '90_day_periodic', 'no_report_required']},
                    'narrative_summary': {'type': 'string'}
                },
                'required': ['ae_detected', 'icsr_completeness', 'adverse_events', 'suspect_drug', 'reporting_deadline']
            }
        }
    ) AS ae_extraction_json,
    CURRENT_TIMESTAMP() AS extracted_at
FROM CX_BRONZE.CALL_TRANSCRIPTIONS t;

-- ============================================================
-- Step CX-5.2: Extract AEs from HCP Video Transcripts
-- Same PV extraction logic applied to video transcripts
-- ============================================================
CREATE OR REPLACE TABLE CX_BRONZE.HCP_VIDEO_AE_EXTRACTIONS AS
SELECT
    t.file_path,
    t.file_name,
    AI_COMPLETE(
        'claude-sonnet-4-6',
        CONCAT(
            'You are a pharmacovigilance specialist. Analyze this healthcare provider (HCP) video visit transcript for adverse event reports per ICH E2A guidelines.\n\nTRANSCRIPT:\n',
            t.transcription_result:text::VARCHAR,
            '\n\nExtract all pharmacovigilance data. A valid ICSR requires: identifiable patient, suspect drug, adverse event. Apply WHO-UMC causality criteria. Respond in JSON only.'
        ),
        {},
        {
            'type': 'json',
            'schema': {
                'type': 'object',
                'properties': {
                    'ae_detected': {'type': 'boolean'},
                    'icsr_completeness': {'type': 'string', 'enum': ['complete', 'minimum_criteria_met', 'incomplete', 'no_ae']},
                    'adverse_events': {
                        'type': 'array',
                        'items': {
                            'type': 'object',
                            'properties': {
                                'ae_description_verbatim': {'type': 'string'},
                                'meddra_preferred_term': {'type': 'string'},
                                'meddra_soc_class': {'type': 'string'},
                                'seriousness_criteria': {
                                    'type': 'array',
                                    'items': {
                                        'type': 'string',
                                        'enum': ['death', 'life_threatening', 'hospitalization', 'disability', 'congenital_anomaly', 'medically_significant', 'none']
                                    }
                                },
                                'outcome': {'type': 'string', 'enum': ['recovered', 'recovering', 'not_recovered', 'fatal', 'sequelae', 'unknown']},
                                'causality_who_umc': {'type': 'string', 'enum': ['certain', 'probable', 'possible', 'unlikely', 'conditional', 'unassessable']}
                            },
                            'required': ['ae_description_verbatim', 'meddra_preferred_term', 'seriousness_criteria', 'outcome']
                        }
                    },
                    'suspect_drug': {
                        'type': 'object',
                        'properties': {
                            'drug_name': {'type': 'string'},
                            'drug_dose': {'type': 'string'},
                            'drug_route': {'type': 'string'},
                            'indication': {'type': 'string'}
                        }
                    },
                    'patient': {
                        'type': 'object',
                        'properties': {
                            'age': {'type': 'string'},
                            'sex': {'type': 'string'},
                            'identifier': {'type': 'string'}
                        }
                    },
                    'product_quality_complaint': {'type': 'boolean'},
                    'off_label_use_mentioned': {'type': 'boolean'},
                    'reporting_deadline': {'type': 'string', 'enum': ['15_day_expedited', '90_day_periodic', 'no_report_required']},
                    'narrative_summary': {'type': 'string'}
                },
                'required': ['ae_detected', 'icsr_completeness', 'adverse_events', 'suspect_drug', 'reporting_deadline']
            }
        }
    ) AS ae_extraction_json,
    CURRENT_TIMESTAMP() AS extracted_at
FROM CX_BRONZE.HCP_VIDEO_TRANSCRIPTIONS t;

-- ============================================================
-- Step CX-5.3: Verification
-- ============================================================

-- Preview call AE extractions
SELECT
    file_name,
    ae_extraction_json:ae_detected::BOOLEAN AS ae_detected,
    ae_extraction_json:icsr_completeness::VARCHAR AS icsr_status,
    ae_extraction_json:suspect_drug:drug_name::VARCHAR AS drug_name,
    ae_extraction_json:reporting_deadline::VARCHAR AS deadline,
    LEFT(ae_extraction_json:narrative_summary::VARCHAR, 150) AS narrative_preview
FROM CX_BRONZE.CALL_AE_EXTRACTIONS;

-- Preview video AE extractions
SELECT
    file_name,
    ae_extraction_json:ae_detected::BOOLEAN AS ae_detected,
    ae_extraction_json:icsr_completeness::VARCHAR AS icsr_status,
    ae_extraction_json:suspect_drug:drug_name::VARCHAR AS drug_name,
    ae_extraction_json:reporting_deadline::VARCHAR AS deadline
FROM CX_BRONZE.HCP_VIDEO_AE_EXTRACTIONS;

-- AE detection summary across both sources
SELECT
    'CALL_CENTER' AS source,
    COUNT(*) AS total,
    SUM(CASE WHEN ae_extraction_json:ae_detected::BOOLEAN THEN 1 ELSE 0 END) AS ae_detected_count,
    SUM(CASE WHEN ae_extraction_json:reporting_deadline::VARCHAR = '15_day_expedited' THEN 1 ELSE 0 END) AS expedited_reports
FROM CX_BRONZE.CALL_AE_EXTRACTIONS
UNION ALL
SELECT
    'HCP_VIDEO',
    COUNT(*),
    SUM(CASE WHEN ae_extraction_json:ae_detected::BOOLEAN THEN 1 ELSE 0 END),
    SUM(CASE WHEN ae_extraction_json:reporting_deadline::VARCHAR = '15_day_expedited' THEN 1 ELSE 0 END)
FROM CX_BRONZE.HCP_VIDEO_AE_EXTRACTIONS;

-- Check for NULL extractions (indicates AI_COMPLETE failure)
SELECT 'CALL_AE_EXTRACTIONS' AS table_name, COUNT(*) AS null_count
FROM CX_BRONZE.CALL_AE_EXTRACTIONS WHERE ae_extraction_json IS NULL
UNION ALL
SELECT 'HCP_VIDEO_AE_EXTRACTIONS', COUNT(*)
FROM CX_BRONZE.HCP_VIDEO_AE_EXTRACTIONS WHERE ae_extraction_json IS NULL;
