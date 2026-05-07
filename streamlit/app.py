"""
Drug Safety Co-Pilot — Streamlit Dashboard
Deployed as Streamlit in Snowflake (SiS)

Three tabs:
1. Signal Detection Dashboard — AE frequency, severity heatmaps, trends
2. AI Agent Chat — Ready for Cortex Agent when account is upgraded
3. Narrative Search — Keyword search over clinical narratives
"""

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

# ============================================================
# Session & Config
# ============================================================
session = get_active_session()

st.set_page_config(
    page_title="Drug Safety Co-Pilot",
    layout="wide"
)

st.title("Drug Safety Co-Pilot")
st.caption("Pharmacovigilance Signal Detection & Analysis Platform")

# ============================================================
# Tab Layout
# ============================================================
tab1, tab2, tab3 = st.tabs([
    "Signal Detection Dashboard",
    "AI Agent Chat",
    "Narrative Search"
])

# ============================================================
# Tab 1: Signal Detection Dashboard
# ============================================================
with tab1:
    st.header("Adverse Event Signal Detection")

    # Key metrics row
    col1, col2, col3, col4 = st.columns(4)

    try:
        total_cases = session.sql(
            "SELECT COUNT(DISTINCT CASE_ID) AS CNT FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT"
        ).collect()[0]["CNT"]

        severe_cases = session.sql(
            "SELECT COUNT(*) AS CNT FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT WHERE LOWER(AE_SEVERITY) = 'severe'"
        ).collect()[0]["CNT"]

        fatal_cases = session.sql(
            "SELECT COUNT(*) AS CNT FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT WHERE AE_OUTCOME = 'Fatal'"
        ).collect()[0]["CNT"]

        unique_drugs = session.sql(
            "SELECT COUNT(DISTINCT DRUG_NAME) AS CNT FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT"
        ).collect()[0]["CNT"]

        col1.metric("Total Cases", f"{total_cases:,}")
        col2.metric("Severe Cases", f"{severe_cases:,}", delta=f"{severe_cases*100//max(total_cases,1)}%")
        col3.metric("Fatal Outcomes", f"{fatal_cases:,}")
        col4.metric("Drugs Monitored", f"{unique_drugs:,}")
    except Exception as e:
        st.error(f"Error loading metrics: {str(e)}")

    st.divider()

    # Two-column layout for charts
    left_col, right_col = st.columns(2)

    with left_col:
        st.subheader("Top 10 Drugs by AE Count")
        try:
            df_drugs = session.sql("""
                SELECT DRUG_NAME, COUNT(*) AS CASE_COUNT
                FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
                GROUP BY DRUG_NAME
                ORDER BY CASE_COUNT DESC
                LIMIT 10
            """).to_pandas()
            st.bar_chart(df_drugs.set_index("DRUG_NAME"))
        except Exception as e:
            st.error(f"Error: {str(e)}")

    with right_col:
        st.subheader("Cases by System Organ Class")
        try:
            df_soc = session.sql("""
                SELECT AE_SOC_CLASS, COUNT(*) AS CASE_COUNT
                FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
                WHERE AE_SOC_CLASS IS NOT NULL
                GROUP BY AE_SOC_CLASS
                ORDER BY CASE_COUNT DESC
            """).to_pandas()
            st.bar_chart(df_soc.set_index("AE_SOC_CLASS"))
        except Exception as e:
            st.error(f"Error: {str(e)}")

    st.divider()

    # Severity heatmap (drug x severity)
    st.subheader("Drug x Severity Matrix")
    try:
        df_heatmap = session.sql("""
            SELECT DRUG_NAME, AE_SEVERITY, COUNT(*) AS CNT
            FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
            WHERE DRUG_NAME IN (
                SELECT DRUG_NAME FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
                GROUP BY DRUG_NAME ORDER BY COUNT(*) DESC LIMIT 10
            )
            GROUP BY DRUG_NAME, AE_SEVERITY
        """).to_pandas()

        if not df_heatmap.empty:
            pivot = df_heatmap.pivot(index="DRUG_NAME", columns="AE_SEVERITY", values="CNT").fillna(0)
            st.dataframe(pivot, use_container_width=True)
    except Exception as e:
        st.error(f"Error: {str(e)}")

    # Monthly trend
    st.subheader("Monthly Adverse Event Trend")
    try:
        df_trend = session.sql("""
            SELECT DATE_TRUNC('MONTH', REPORT_DATE) AS MONTH,
                   COUNT(*) AS TOTAL_CASES,
                   COUNT(CASE WHEN LOWER(AE_SEVERITY) = 'severe' THEN 1 END) AS SEVERE_CASES
            FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
            GROUP BY MONTH
            ORDER BY MONTH
        """).to_pandas()

        if not df_trend.empty:
            df_trend["MONTH"] = pd.to_datetime(df_trend["MONTH"])
            st.line_chart(df_trend.set_index("MONTH")[["TOTAL_CASES", "SEVERE_CASES"]])
    except Exception as e:
        st.error(f"Error: {str(e)}")

    # Outcome distribution
    st.subheader("Outcome Distribution")
    try:
        df_outcome = session.sql("""
            SELECT AE_OUTCOME, COUNT(*) AS CNT
            FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
            GROUP BY AE_OUTCOME
            ORDER BY CNT DESC
        """).to_pandas()
        st.bar_chart(df_outcome.set_index("AE_OUTCOME"))
    except Exception as e:
        st.error(f"Error: {str(e)}")

    # Signal Detection: Proportional Reporting Ratio (PRR)
    st.divider()
    st.subheader("Signal Detection: Drug-Event Combinations")
    st.caption("Combinations with PRR > 2.0 may indicate a safety signal")

    try:
        df_prr = session.sql("""
            WITH drug_event AS (
                SELECT DRUG_NAME, AE_SOC_CLASS, COUNT(*) AS DE_COUNT
                FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
                GROUP BY DRUG_NAME, AE_SOC_CLASS
            ),
            drug_total AS (
                SELECT DRUG_NAME, COUNT(*) AS D_TOTAL
                FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
                GROUP BY DRUG_NAME
            ),
            event_total AS (
                SELECT AE_SOC_CLASS, COUNT(*) AS E_TOTAL
                FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
                GROUP BY AE_SOC_CLASS
            ),
            grand_total AS (
                SELECT COUNT(*) AS GRAND_TOTAL FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
            )
            SELECT 
                de.DRUG_NAME,
                de.AE_SOC_CLASS,
                de.DE_COUNT,
                ROUND(
                    (de.DE_COUNT * 1.0 / dt.D_TOTAL) / 
                    NULLIF((et.E_TOTAL * 1.0 / gt.GRAND_TOTAL), 0),
                    2
                ) AS PRR
            FROM drug_event de
            JOIN drug_total dt ON de.DRUG_NAME = dt.DRUG_NAME
            JOIN event_total et ON de.AE_SOC_CLASS = et.AE_SOC_CLASS
            CROSS JOIN grand_total gt
            WHERE de.DE_COUNT >= 3
            ORDER BY PRR DESC
            LIMIT 15
        """).to_pandas()

        if not df_prr.empty:
            st.dataframe(df_prr, use_container_width=True)
    except Exception as e:
        st.error(f"Error: {str(e)}")


# ============================================================
# Tab 2: AI Agent Chat
# ============================================================
with tab2:
    st.header("Drug Safety AI Assistant")

    st.info(
        "**Cortex AI Agent** will be available when the account is upgraded from trial. "
        "The agent combines Cortex Search (narrative search) and Cortex Analyst (structured queries) "
        "to provide intelligent pharmacovigilance analysis."
    )

    st.subheader("Planned Capabilities")
    st.markdown("""
    - **Natural language queries** over adverse event data
    - **Signal detection** with automatic flagging of PRR > 2x baseline
    - **Narrative search** for clinical evidence supporting signals
    - **Trend analysis** with time-series decomposition
    - **Causality assessment** guidance per WHO-UMC criteria
    """)

    st.subheader("Sample Questions (available after upgrade)")
    sample_questions = [
        "What are the top 5 adverse events reported this quarter?",
        "Show me the trend of hepatotoxicity cases over time by drug",
        "Find narratives mentioning cardiac events with pembrolizumab",
        "Which drugs have the highest fatal outcome rate?",
        "Compare adverse event profiles between metformin and semaglutide",
        "Are there any signals for nephrotoxicity with adalimumab?",
    ]
    for q in sample_questions:
        st.code(q, language=None)

    st.divider()
    st.subheader("Quick Analytics (available now)")
    
    query_option = st.selectbox("Select a query:", [
        "Top 5 drugs by AE count",
        "Fatal outcome rate by drug",
        "Average onset time by SOC class",
        "Severe cases by country",
        "Monthly case volume"
    ])

    queries = {
        "Top 5 drugs by AE count": """
            SELECT DRUG_NAME, COUNT(DISTINCT CASE_ID) AS TOTAL_CASES
            FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
            GROUP BY DRUG_NAME ORDER BY TOTAL_CASES DESC LIMIT 5
        """,
        "Fatal outcome rate by drug": """
            SELECT DRUG_NAME, COUNT(*) AS TOTAL,
                   COUNT(CASE WHEN AE_OUTCOME = 'Fatal' THEN 1 END) AS FATAL,
                   ROUND(COUNT(CASE WHEN AE_OUTCOME = 'Fatal' THEN 1 END) * 100.0 / COUNT(*), 1) AS FATAL_PCT
            FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
            GROUP BY DRUG_NAME HAVING COUNT(*) >= 5 ORDER BY FATAL_PCT DESC
        """,
        "Average onset time by SOC class": """
            SELECT AE_SOC_CLASS, ROUND(AVG(ONSET_DAYS), 1) AS AVG_ONSET_DAYS,
                   ROUND(MEDIAN(ONSET_DAYS), 1) AS MEDIAN_ONSET_DAYS, COUNT(*) AS CASES
            FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
            WHERE ONSET_DAYS IS NOT NULL GROUP BY AE_SOC_CLASS ORDER BY AVG_ONSET_DAYS DESC
        """,
        "Severe cases by country": """
            SELECT COUNTRY, COUNT(*) AS SEVERE_CASES
            FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
            WHERE LOWER(AE_SEVERITY) = 'severe' GROUP BY COUNTRY ORDER BY SEVERE_CASES DESC
        """,
        "Monthly case volume": """
            SELECT DATE_TRUNC('MONTH', REPORT_DATE) AS MONTH, COUNT(*) AS CASES
            FROM PHARMACOVIGILANCE.D_SILVER.FACT_ADVERSE_EVENT
            GROUP BY MONTH ORDER BY MONTH
        """
    }

    if st.button("Run Query"):
        try:
            df_result = session.sql(queries[query_option]).to_pandas()
            st.dataframe(df_result, use_container_width=True)
        except Exception as e:
            st.error(f"Query error: {str(e)}")


# ============================================================
# Tab 3: Narrative Search
# ============================================================
with tab3:
    st.header("Clinical Narrative Search")
    st.caption("Search adverse event narratives using keyword matching. "
               "Cortex Search (semantic search) will activate after account upgrade.")

    # Search input
    search_query = st.text_input(
        "Search narratives",
        placeholder="e.g., liver injury, cardiac, kidney, Stevens-Johnson..."
    )

    # Filters
    col_filter1, col_filter2 = st.columns(2)
    with col_filter1:
        max_results = st.slider("Max results", 1, 20, 5)

    if search_query:
        with st.spinner("Searching narratives..."):
            try:
                # Escape single quotes for safe SQL embedding
                safe_query = search_query.replace("'", "''")
                like_pattern = f"%{safe_query}%"
                
                results = session.sql(f"""
                    SELECT CASE_ID, NARRATIVE_TEXT, EXTRACTED_DRUG, EXTRACTED_AE,
                           EXTRACTED_CAUSALITY, NARRATIVE_SENTIMENT
                    FROM PHARMACOVIGILANCE.D_SILVER.FACT_NARRATIVE
                    WHERE LOWER(NARRATIVE_TEXT) LIKE LOWER('{like_pattern}')
                       OR LOWER(EXTRACTED_AE) LIKE LOWER('{like_pattern}')
                       OR LOWER(EXTRACTED_DRUG) LIKE LOWER('{like_pattern}')
                    LIMIT {int(max_results)}
                """).to_pandas()

                if not results.empty:
                    st.success(f"Found {len(results)} matching narratives")

                    for _, row in results.iterrows():
                        with st.expander(
                            f"Case {row['CASE_ID']} | Drug: {row['EXTRACTED_DRUG']} | "
                            f"AE: {row['EXTRACTED_AE']} | Causality: {row['EXTRACTED_CAUSALITY']}"
                        ):
                            st.markdown(f"**Sentiment Score:** {row['NARRATIVE_SENTIMENT']}")
                            st.markdown("---")
                            st.markdown(row["NARRATIVE_TEXT"])
                else:
                    st.info("No matching narratives found. Try different search terms.")

            except Exception as e:
                st.error(f"Search error: {str(e)}")

    else:
        st.info("Enter a search query above to find relevant clinical narratives.")

        # Show some example searches
        st.subheader("Example Searches")
        examples = [
            "liver",
            "cardiac",
            "kidney",
            "Stevens-Johnson",
            "anaphylaxis",
            "neuropathy",
        ]
        cols = st.columns(3)
        for i, ex in enumerate(examples):
            with cols[i % 3]:
                st.code(ex, language=None)

    # Show all narratives overview
    st.divider()
    st.subheader("All Available Narratives")
    try:
        df_all = session.sql("""
            SELECT CASE_ID, EXTRACTED_DRUG, EXTRACTED_AE, 
                   EXTRACTED_SEVERITY, EXTRACTED_CAUSALITY,
                   NARRATIVE_SENTIMENT AS SENTIMENT_SCORE
            FROM PHARMACOVIGILANCE.D_SILVER.FACT_NARRATIVE
            ORDER BY SENTIMENT_SCORE ASC
        """).to_pandas()
        st.dataframe(df_all, use_container_width=True)
    except Exception as e:
        st.error(f"Error: {str(e)}")
