"""
PharmaCX Intelligence — Streamlit Dashboard
Deployed as Streamlit in Snowflake (SiS)

Three tabs:
1. AE Triage Queue — Priority-sorted detected AEs from call recordings
2. Agent Compliance — Call center agent compliance scoring
3. Call Search — Keyword search over call transcripts
"""

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

# ============================================================
# Session & Config
# ============================================================
session = get_active_session()

st.set_page_config(
    page_title="PharmaCX Intelligence",
    layout="wide"
)

st.title("PharmaCX Intelligence")
st.caption("Multimodal Adverse Event Detection from Medical Information Calls")

# ============================================================
# Metrics Bar
# ============================================================
col1, col2, col3, col4 = st.columns(4)

try:
    total_calls = session.sql(
        "SELECT COUNT(*) AS CNT FROM PHARMACOVIGILANCE.CX_SILVER.FACT_AGENT_COMPLIANCE"
    ).collect()[0]["CNT"]
    col1.metric("Total Calls Processed", f"{total_calls:,}")
except Exception as e:
    col1.metric("Total Calls Processed", "N/A")
    st.error(f"Error loading total calls: {str(e)}")

try:
    ae_cases = session.sql(
        "SELECT COUNT(*) AS CNT FROM PHARMACOVIGILANCE.CX_SILVER.FACT_AE_CALLS"
    ).collect()[0]["CNT"]
    col2.metric("AE Cases Detected", f"{ae_cases:,}")
except Exception as e:
    col2.metric("AE Cases Detected", "N/A")
    st.error(f"Error loading AE cases: {str(e)}")

try:
    pending_15day = session.sql(
        "SELECT COUNT(*) AS CNT FROM PHARMACOVIGILANCE.CX_GOLD.V_AE_TRIAGE_QUEUE "
        "WHERE REPORTING_DEADLINE = '15_day_expedited'"
    ).collect()[0]["CNT"]
    col3.metric("15-Day Cases Pending", f"{pending_15day:,}")
except Exception as e:
    col3.metric("15-Day Cases Pending", "N/A")
    st.error(f"Error loading 15-day cases: {str(e)}")

try:
    avg_compliance = session.sql(
        "SELECT ROUND(AVG(COMPLIANCE_SCORE), 1) AS AVG_SCORE "
        "FROM PHARMACOVIGILANCE.CX_SILVER.FACT_AGENT_COMPLIANCE"
    ).collect()[0]["AVG_SCORE"]
    col4.metric("Avg Compliance Score", f"{avg_compliance}")
except Exception as e:
    col4.metric("Avg Compliance Score", "N/A")
    st.error(f"Error loading compliance score: {str(e)}")

st.divider()

# ============================================================
# Tab Layout
# ============================================================
tab1, tab2, tab3 = st.tabs([
    "AE Triage Queue",
    "Agent Compliance",
    "Call Search"
])

# ============================================================
# Tab 1: AE Triage Queue
# ============================================================
with tab1:
    st.header("Adverse Event Triage Queue")
    st.caption(
        "Priority-sorted detected AEs from call recordings. "
        "URGENT = 15-day deadline within 3 days."
    )

    try:
        df_triage = session.sql("""
            SELECT
                SOURCE_CALL_ID,
                DRUG_NAME,
                AE_PREFERRED_TERM,
                AE_SOC_CLASS,
                AE_SERIOUSNESS,
                AE_OUTCOME,
                REPORTING_DEADLINE,
                PATIENT_AGE,
                PATIENT_SEX,
                COMPLIANCE_SCORE,
                CALLER_STATE,
                URGENCY_LEVEL,
                SUBMISSION_DEADLINE,
                PRIORITY_FLAG,
                REPORT_DATE,
                CASE_NARRATIVE
            FROM PHARMACOVIGILANCE.CX_GOLD.V_AE_TRIAGE_QUEUE
            ORDER BY
                CASE WHEN PRIORITY_FLAG = 'URGENT' THEN 1
                     WHEN PRIORITY_FLAG = 'ACTION_REQUIRED' THEN 2
                     ELSE 3 END,
                SUBMISSION_DEADLINE ASC NULLS LAST
        """).to_pandas()

        if not df_triage.empty:
            urgent_count = len(df_triage[df_triage["PRIORITY_FLAG"] == "URGENT"])
            if urgent_count > 0:
                st.warning(f"URGENT: {urgent_count} case(s) with 15-day deadline within 3 days")
            else:
                st.success("No urgent cases at this time")

            # Display table without CASE_NARRATIVE (shown in expanders below)
            display_cols = [
                c for c in df_triage.columns if c != "CASE_NARRATIVE"
            ]
            st.dataframe(df_triage[display_cols], use_container_width=True)

            # Expandable narrative sections
            st.subheader("Case Narratives")
            for _, row in df_triage.iterrows():
                label = (
                    f"{row['PRIORITY_FLAG']} | {row['SOURCE_CALL_ID']} | "
                    f"{row['DRUG_NAME']} | {row['AE_PREFERRED_TERM']}"
                )
                with st.expander(label):
                    st.markdown(f"**Seriousness:** {row['AE_SERIOUSNESS']}")
                    st.markdown(f"**Outcome:** {row['AE_OUTCOME']}")
                    st.markdown(f"**Deadline:** {row['SUBMISSION_DEADLINE']}")
                    st.markdown("---")
                    st.markdown(
                        row["CASE_NARRATIVE"]
                        if pd.notna(row["CASE_NARRATIVE"])
                        else "_No narrative available_"
                    )
        else:
            st.info("No adverse events detected in call recordings yet.")
    except Exception as e:
        st.error(f"Error loading triage queue: {str(e)}")


# ============================================================
# Tab 2: Agent Compliance
# ============================================================
with tab2:
    st.header("Call Center Agent Compliance")

    left_col, right_col = st.columns(2)

    with left_col:
        st.subheader("Compliance Score Distribution")
        try:
            df_dist = session.sql("""
                SELECT
                    CASE
                        WHEN COMPLIANCE_SCORE <= 50 THEN '0-50'
                        WHEN COMPLIANCE_SCORE <= 70 THEN '51-70'
                        WHEN COMPLIANCE_SCORE <= 90 THEN '71-90'
                        ELSE '91-100'
                    END AS SCORE_BUCKET,
                    COUNT(*) AS CALL_COUNT
                FROM PHARMACOVIGILANCE.CX_SILVER.FACT_AGENT_COMPLIANCE
                GROUP BY SCORE_BUCKET
                ORDER BY SCORE_BUCKET
            """).to_pandas()

            if not df_dist.empty:
                st.bar_chart(df_dist.set_index("SCORE_BUCKET"))
            else:
                st.info("No compliance data available.")
        except Exception as e:
            st.error(f"Error loading compliance distribution: {str(e)}")

    with right_col:
        st.subheader("Flagged Calls (Score < 70)")
        try:
            df_flagged = session.sql("""
                SELECT
                    CALL_ID,
                    COMPLIANCE_SCORE,
                    TONE_PROFESSIONAL,
                    CALLER_STATE,
                    URGENCY_LEVEL,
                    CALL_TYPE,
                    ANALYZED_AT
                FROM PHARMACOVIGILANCE.CX_SILVER.FACT_AGENT_COMPLIANCE
                WHERE COMPLIANCE_SCORE < 70
                ORDER BY COMPLIANCE_SCORE ASC
            """).to_pandas()

            if not df_flagged.empty:
                st.warning(f"{len(df_flagged)} call(s) below compliance threshold")
                st.dataframe(df_flagged, use_container_width=True)
            else:
                st.success("All calls meet compliance threshold.")
        except Exception as e:
            st.error(f"Error loading flagged calls: {str(e)}")

    st.divider()
    st.subheader("Escalation Summary")
    try:
        df_esc = session.sql("""
            SELECT
                CALL_ID,
                COMPLIANCE_SCORE,
                URGENCY_LEVEL,
                ESCALATION_REASON,
                ANALYZED_AT
            FROM PHARMACOVIGILANCE.CX_SILVER.FACT_AGENT_COMPLIANCE
            WHERE ESCALATION_NEEDED = TRUE
            ORDER BY ANALYZED_AT DESC
        """).to_pandas()

        if not df_esc.empty:
            st.warning(f"{len(df_esc)} call(s) flagged for escalation")
            st.dataframe(df_esc, use_container_width=True)
        else:
            st.success("No escalations required.")
    except Exception as e:
        st.error(f"Error loading escalation summary: {str(e)}")


# ============================================================
# Tab 3: Call Search
# ============================================================
with tab3:
    st.header("Call Transcript Search")
    st.caption("Keyword search across call transcripts with linked AE information.")

    search_query = st.text_input(
        "Search transcripts",
        placeholder="e.g., chest pain, nausea, dizziness, liver..."
    )

    max_results = st.slider("Max results", 1, 20, 5)

    if search_query:
        with st.spinner("Searching transcripts..."):
            try:
                safe_query = search_query.replace("'", "''")
                like_pattern = f"%{safe_query}%"

                df_search = session.sql(f"""
                    SELECT
                        t.FILE_NAME,
                        t.RECEIVED_AT,
                        t.TRANSCRIPTION_RESULT:text::VARCHAR AS TRANSCRIPT_TEXT
                    FROM PHARMACOVIGILANCE.CX_BRONZE.CALL_TRANSCRIPTIONS t
                    WHERE LOWER(t.TRANSCRIPTION_RESULT:text::VARCHAR)
                          LIKE LOWER('{like_pattern}')
                    LIMIT {int(max_results)}
                """).to_pandas()

                if not df_search.empty:
                    st.success(f"Found {len(df_search)} matching transcript(s)")

                    for _, row in df_search.iterrows():
                        file_name = row["FILE_NAME"]
                        with st.expander(f"{file_name} | Received: {row['RECEIVED_AT']}"):
                            # Show transcript text
                            st.markdown("**Transcript:**")
                            transcript = row["TRANSCRIPT_TEXT"] or ""
                            st.text(transcript[:2000] + ("..." if len(transcript) > 2000 else ""))

                            # Look up linked AE info
                            safe_file = file_name.replace("'", "''")
                            try:
                                df_ae = session.sql(f"""
                                    SELECT
                                        DRUG_NAME,
                                        AE_PREFERRED_TERM,
                                        AE_SOC_CLASS,
                                        AE_SERIOUSNESS,
                                        AE_OUTCOME,
                                        CAUSALITY,
                                        REPORTING_DEADLINE
                                    FROM PHARMACOVIGILANCE.CX_SILVER.FACT_AE_CALLS
                                    WHERE SOURCE_CALL_ID = '{safe_file}'
                                """).to_pandas()

                                if not df_ae.empty:
                                    st.markdown("**Linked Adverse Events:**")
                                    st.dataframe(df_ae, use_container_width=True)
                                else:
                                    st.info("No adverse events linked to this call.")
                            except Exception as ae_err:
                                st.error(f"Error loading AE data: {str(ae_err)}")
                else:
                    st.info("No matching transcripts found. Try different search terms.")
            except Exception as e:
                st.error(f"Search error: {str(e)}")
    else:
        st.info("Enter a search query above to find relevant call transcripts.")

        st.subheader("Example Searches")
        examples = [
            "chest pain", "nausea", "rash",
            "headache", "liver", "anaphylaxis"
        ]
        cols = st.columns(3)
        for i, ex in enumerate(examples):
            with cols[i % 3]:
                st.code(ex, language=None)
