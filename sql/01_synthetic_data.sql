/*
 * Drug Safety Co-Pilot — Phase 1: Realistic Synthetic Data Generation
 * 
 * Prerequisites: Phase 0 complete (database, schemas, warehouse exist)
 * 
 * This script creates:
 *   - D_RAW.AE_REPORTS: Structured adverse event case reports (~500 records)
 *   - D_RAW.AE_NARRATIVES: Clinical narrative texts (~20 records)
 *   - Stored procedures for batch generation using Cortex COMPLETE
 *
 * Data Realism:
 *   - FAERS-style case IDs (e.g., US-PFIZER-2024-001234)
 *   - Actual MedDRA preferred terms for adverse events
 *   - Real drug names with clinical doses and routes
 *   - Demographic distributions matching FDA reporting patterns
 *   - Reporter types weighted per real-world ratios
 */

USE DATABASE PHARMACOVIGILANCE;
USE SCHEMA D_RAW;
USE WAREHOUSE PV_WH;

-- ============================================================
-- Step 1.1: Create AE_REPORTS Table
-- FAERS-aligned schema for structured case reports
-- ============================================================
CREATE OR REPLACE TABLE D_RAW.AE_REPORTS (
    CASE_ID         VARCHAR(50)     NOT NULL,
    PATIENT_ID      VARCHAR(30)     NOT NULL,
    PATIENT_AGE     INT,
    PATIENT_SEX     VARCHAR(10),
    PATIENT_DOB     DATE,
    PATIENT_WEIGHT  FLOAT,
    DRUG_NAME       VARCHAR(100)    NOT NULL,
    DRUG_DOSE       VARCHAR(50),
    DRUG_ROUTE      VARCHAR(30),
    DRUG_START_DATE DATE,
    INDICATION      VARCHAR(200),
    AE_TERM         VARCHAR(200)    NOT NULL,
    AE_SEVERITY     VARCHAR(20),
    AE_SERIOUSNESS  VARCHAR(50),
    AE_OUTCOME      VARCHAR(50),
    AE_ONSET_DATE   DATE,
    REPORTER_TYPE   VARCHAR(30),
    REPORT_DATE     DATE            NOT NULL,
    COUNTRY         VARCHAR(50),
    MANUFACTURER    VARCHAR(100),
    CREATED_AT      TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- Step 1.2: Stored Procedure — Generate Realistic AE Records
-- Uses Cortex COMPLETE with detailed prompting for realism
-- ============================================================
CREATE OR REPLACE PROCEDURE D_RAW.GENERATE_AE_RECORDS(BATCH_COUNT INT)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    i INT DEFAULT 0;
    llm_result VARCHAR;
    inserted_count INT DEFAULT 0;
    batch_inserted INT;
BEGIN
    WHILE (i < :BATCH_COUNT) DO
        llm_result := (SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-3-5-haiku',
'You are a pharmacovigilance data specialist generating realistic FDA FAERS-style adverse event records.

Generate exactly 50 synthetic adverse event case reports as a JSON array. Each record must follow these rules:

CASE_ID FORMAT: [COUNTRY_CODE]-[MANUFACTURER]-[YEAR]-[6-DIGIT-SEQ]
Examples: US-PFIZER-2024-001234, UK-NOVARTIS-2024-005678, JP-ASTRAZENECA-2023-012345

DRUG NAMES (use only these real medications with realistic doses):
- Metformin 500mg, 850mg, 1000mg (oral) for Type 2 Diabetes
- Lisinopril 5mg, 10mg, 20mg (oral) for Hypertension
- Atorvastatin 10mg, 20mg, 40mg, 80mg (oral) for Hyperlipidemia
- Omeprazole 20mg, 40mg (oral) for GERD
- Amlodipine 5mg, 10mg (oral) for Hypertension
- Sertraline 50mg, 100mg (oral) for Major Depressive Disorder
- Apixaban 2.5mg, 5mg (oral) for Atrial Fibrillation
- Pembrolizumab 200mg (IV) for Non-Small Cell Lung Cancer
- Adalimumab 40mg (subcutaneous) for Rheumatoid Arthritis
- Ozempic (Semaglutide) 0.25mg, 0.5mg, 1mg (subcutaneous) for Type 2 Diabetes
- Dupilumab 300mg (subcutaneous) for Atopic Dermatitis
- Rivaroxaban 10mg, 20mg (oral) for DVT Prevention
- Methotrexate 7.5mg, 15mg, 25mg (oral/IM) for Rheumatoid Arthritis
- Doxorubicin 60mg/m2 (IV) for Breast Cancer
- Nivolumab 240mg (IV) for Melanoma

ADVERSE EVENT TERMS (use real MedDRA Preferred Terms):
Hepatotoxicity: Hepatocellular injury, Drug-induced liver injury, Hepatic failure, Jaundice, Transaminases increased
Cardiotoxicity: Myocardial infarction, QT prolongation, Torsade de pointes, Heart failure, Cardiomyopathy
Nephrotoxicity: Acute kidney injury, Renal failure, Nephritis interstitial, Proteinuria
Dermatologic: Stevens-Johnson syndrome, Toxic epidermal necrolysis, Drug reaction with eosinophilia, Angioedema, Urticaria
Neurologic: Seizure, Peripheral neuropathy, Guillain-Barre syndrome, Progressive multifocal leukoencephalopathy
Gastrointestinal: Pancreatitis acute, Gastrointestinal haemorrhage, Intestinal perforation, Colitis
Hematologic: Pancytopenia, Thrombocytopenia, Neutropenia febrile, Disseminated intravascular coagulation
Immunologic: Anaphylaxis, Cytokine release syndrome, Immune-mediated hepatitis, Pneumonitis

DEMOGRAPHICS:
- Age: normal distribution centered 55, range 18-89 (match real FAERS)
- Sex: 55% Female, 45% Male
- Weight: realistic for age/sex (kg)
- DOB: calculated from age, year range 1935-2006

GEOGRAPHIC DISTRIBUTION:
- US: 60%, UK: 10%, Germany: 8%, Japan: 7%, France: 5%, Canada: 5%, Australia: 5%

REPORTER TYPES: Physician (40%), Pharmacist (15%), Consumer/Patient (30%), Nurse (10%), Other HCP (5%)

SEVERITY: Mild (30%), Moderate (45%), Severe (25%)
SERIOUSNESS: Non-serious (40%), Hospitalization (25%), Life-threatening (15%), Disability (10%), Death (5%), Required Intervention (5%)
OUTCOMES: Recovered (35%), Recovering (25%), Not recovered (20%), Fatal (5%), Unknown (15%)

TEMPORAL RULES:
- drug_start_date: between 2023-01-01 and 2025-12-31
- ae_onset_date: 1-120 days after drug_start_date
- report_date: 1-30 days after ae_onset_date

MANUFACTURERS (match to drug): Pfizer, Novartis, AstraZeneca, Merck, Roche, AbbVie, Eli Lilly, Novo Nordisk, Sanofi, Bristol-Myers Squibb

Return ONLY a valid JSON array with these exact fields per object:
case_id, patient_id, patient_age, patient_sex, patient_dob, patient_weight, drug_name, drug_dose, drug_route, drug_start_date, indication, ae_term, ae_severity, ae_seriousness, ae_outcome, ae_onset_date, reporter_type, report_date, country, manufacturer

patient_id format: PAT-[8 random alphanumeric chars]
Dates in YYYY-MM-DD format. No markdown, no explanation — only the JSON array.'
        ));

        INSERT INTO D_RAW.AE_REPORTS (
            CASE_ID, PATIENT_ID, PATIENT_AGE, PATIENT_SEX, PATIENT_DOB, PATIENT_WEIGHT,
            DRUG_NAME, DRUG_DOSE, DRUG_ROUTE, DRUG_START_DATE, INDICATION,
            AE_TERM, AE_SEVERITY, AE_SERIOUSNESS, AE_OUTCOME, AE_ONSET_DATE,
            REPORTER_TYPE, REPORT_DATE, COUNTRY, MANUFACTURER
        )
        SELECT
            f.value:case_id::VARCHAR,
            f.value:patient_id::VARCHAR,
            f.value:patient_age::INT,
            f.value:patient_sex::VARCHAR,
            f.value:patient_dob::DATE,
            f.value:patient_weight::FLOAT,
            f.value:drug_name::VARCHAR,
            f.value:drug_dose::VARCHAR,
            f.value:drug_route::VARCHAR,
            f.value:drug_start_date::DATE,
            f.value:indication::VARCHAR,
            f.value:ae_term::VARCHAR,
            f.value:ae_severity::VARCHAR,
            f.value:ae_seriousness::VARCHAR,
            f.value:ae_outcome::VARCHAR,
            f.value:ae_onset_date::DATE,
            f.value:reporter_type::VARCHAR,
            f.value:report_date::DATE,
            f.value:country::VARCHAR,
            f.value:manufacturer::VARCHAR
        FROM TABLE(FLATTEN(TRY_PARSE_JSON(:llm_result))) f
        WHERE TRY_PARSE_JSON(:llm_result) IS NOT NULL;

        batch_inserted := (SELECT COUNT(*) FROM D_RAW.AE_REPORTS) - :inserted_count;
        inserted_count := (SELECT COUNT(*) FROM D_RAW.AE_REPORTS);
        i := i + 1;
    END WHILE;

    RETURN 'Completed ' || :BATCH_COUNT || ' batches. Total records: ' || :inserted_count;
END;
$$;

-- ============================================================
-- Step 1.3: Generate Records (10 batches × ~50 records = ~500)
-- ============================================================
CALL D_RAW.GENERATE_AE_RECORDS(10);

-- Verify record count and sample data quality
SELECT COUNT(*) AS TOTAL_RECORDS FROM D_RAW.AE_REPORTS;
SELECT * FROM D_RAW.AE_REPORTS LIMIT 10;

-- Check distribution realism
SELECT COUNTRY, COUNT(*) AS CNT, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS PCT
FROM D_RAW.AE_REPORTS GROUP BY COUNTRY ORDER BY CNT DESC;

SELECT AE_SEVERITY, COUNT(*) AS CNT FROM D_RAW.AE_REPORTS GROUP BY AE_SEVERITY;
SELECT DRUG_NAME, COUNT(*) AS CNT FROM D_RAW.AE_REPORTS GROUP BY DRUG_NAME ORDER BY CNT DESC LIMIT 10;

-- ============================================================
-- Step 1.4: Create AE_NARRATIVES Table
-- Clinical narrative texts for unstructured data processing
-- ============================================================
CREATE OR REPLACE TABLE D_RAW.AE_NARRATIVES (
    CASE_ID         VARCHAR(50)     NOT NULL,
    NARRATIVE_TEXT   VARCHAR(65000)  NOT NULL,
    NARRATIVE_TYPE   VARCHAR(30)     DEFAULT 'INITIAL',
    GENERATED_AT     TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- Step 1.5: Stored Procedure — Generate Clinical Narratives
-- Produces realistic medical narratives with clinical detail
-- ============================================================
CREATE OR REPLACE PROCEDURE D_RAW.GENERATE_NARRATIVES(BATCH_SIZE INT)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    i INT DEFAULT 0;
    total_generated INT DEFAULT 0;
BEGIN
    WHILE (i < :BATCH_SIZE) DO
        INSERT INTO D_RAW.AE_NARRATIVES (CASE_ID, NARRATIVE_TEXT)
        SELECT CASE_ID,
            SNOWFLAKE.CORTEX.COMPLETE('claude-3-5-haiku',
'You are a clinical safety physician writing a formal CIOMS-style adverse event narrative for an Individual Case Safety Report (ICSR).

Write a 250-350 word clinical narrative for this case:
- Patient: ' || PATIENT_SEX || ', age ' || PATIENT_AGE || ', weight ' || COALESCE(PATIENT_WEIGHT::VARCHAR, 'unknown') || 'kg
- Drug: ' || DRUG_NAME || ' ' || DRUG_DOSE || ' (' || DRUG_ROUTE || ')
- Indication: ' || INDICATION || '
- Adverse Event: ' || AE_TERM || ' (Severity: ' || AE_SEVERITY || ', Seriousness: ' || AE_SERIOUSNESS || ')
- Onset: ' || DATEDIFF(''day'', DRUG_START_DATE, AE_ONSET_DATE) || ' days after drug initiation
- Outcome: ' || AE_OUTCOME || '

The narrative MUST include:
1. Patient medical history and relevant comorbidities
2. Drug therapy details (start date, dose adjustments, concomitant medications)
3. Temporal relationship between drug exposure and event onset
4. Clinical presentation with specific symptoms, vital signs, and lab values (include realistic values like AST/ALT for liver events, creatinine for renal, troponin for cardiac)
5. Diagnostic workup performed (imaging, labs, biopsies as appropriate)
6. Treatment/intervention for the adverse event
7. Dechallenge/rechallenge information if applicable
8. Causality assessment (WHO-UMC or Naranjo score reference)
9. Reporter assessment and follow-up plan

Write in formal medical prose. Use specific lab values, dates, and clinical terminology. Do NOT use bullet points or headers — write as continuous narrative paragraphs. Do NOT include any preamble or explanation.'
            ) AS NARRATIVE_TEXT
        FROM D_RAW.AE_REPORTS
        WHERE CASE_ID NOT IN (SELECT CASE_ID FROM D_RAW.AE_NARRATIVES)
        LIMIT 10;

        total_generated := (SELECT COUNT(*) FROM D_RAW.AE_NARRATIVES);
        i := i + 1;
    END WHILE;

    RETURN 'Generated ' || :total_generated || ' total narratives';
END;
$$;

-- ============================================================
-- Step 1.6: Generate Narratives (2 batches × 10 = ~20 narratives)
-- ============================================================
CALL D_RAW.GENERATE_NARRATIVES(2);

-- Verify narratives
SELECT COUNT(*) AS TOTAL_NARRATIVES FROM D_RAW.AE_NARRATIVES;
SELECT CASE_ID, LEFT(NARRATIVE_TEXT, 200) AS PREVIEW FROM D_RAW.AE_NARRATIVES LIMIT 5;
