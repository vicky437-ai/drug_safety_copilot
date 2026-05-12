"""
Tests for CX SQL correctness — validates Dynamic Table FLATTEN patterns,
LATERAL joins, TRY_PARSE_JSON guards, and cross-schema references.

These tests parse the SQL source files and verify SQL patterns are correct
*before* deployment. They do NOT require a Snowflake connection.

Targets:
  - sql/cx_06_silver_dynamic_tables.sql  (Dynamic Tables with FLATTEN)
  - sql/cx_07_gold_views.sql             (Gold views with cross-schema JOINs)
"""

import os
import re
import pytest

SQL_DIR = os.path.join(os.path.dirname(__file__), "..", "sql")

CX_06_PATH = os.path.join(SQL_DIR, "cx_06_silver_dynamic_tables.sql")
CX_07_PATH = os.path.join(SQL_DIR, "cx_07_gold_views.sql")


@pytest.fixture
def cx_06_sql():
    """Load the silver dynamic tables SQL file."""
    assert os.path.isfile(CX_06_PATH), (
        f"cx_06_silver_dynamic_tables.sql not found at {CX_06_PATH}. "
        "Implementation must create this file."
    )
    with open(CX_06_PATH) as f:
        return f.read()


@pytest.fixture
def cx_07_sql():
    """Load the gold views SQL file."""
    assert os.path.isfile(CX_07_PATH), (
        f"cx_07_gold_views.sql not found at {CX_07_PATH}. "
        "Implementation must create this file."
    )
    with open(CX_07_PATH) as f:
        return f.read()


# ── cx_06: Dynamic Table DDL correctness ──────────────────────────


class TestDynamicTableDDL:
    """Verify Dynamic Table CREATE statements have required clauses."""

    def test_fact_ae_calls_is_dynamic_table(self, cx_06_sql):
        """FACT_AE_CALLS must be created as a DYNAMIC TABLE, not a regular TABLE or VIEW."""
        pattern = re.compile(
            r"CREATE\s+(OR\s+REPLACE\s+)?DYNAMIC\s+TABLE\s+.*FACT_AE_CALLS",
            re.IGNORECASE,
        )
        assert pattern.search(cx_06_sql), (
            "FACT_AE_CALLS must be a DYNAMIC TABLE (CREATE [OR REPLACE] DYNAMIC TABLE)"
        )

    def test_fact_agent_compliance_is_dynamic_table(self, cx_06_sql):
        """FACT_AGENT_COMPLIANCE must be created as a DYNAMIC TABLE."""
        pattern = re.compile(
            r"CREATE\s+(OR\s+REPLACE\s+)?DYNAMIC\s+TABLE\s+.*FACT_AGENT_COMPLIANCE",
            re.IGNORECASE,
        )
        assert pattern.search(cx_06_sql), (
            "FACT_AGENT_COMPLIANCE must be a DYNAMIC TABLE"
        )

    def test_target_lag_specified(self, cx_06_sql):
        """Both dynamic tables must specify TARGET_LAG."""
        # Count TARGET_LAG occurrences — should be at least 2 (one per DT)
        lags = re.findall(r"TARGET_LAG\s*=", cx_06_sql, re.IGNORECASE)
        assert len(lags) >= 2, (
            f"Expected at least 2 TARGET_LAG clauses (one per DT), found {len(lags)}"
        )

    def test_warehouse_specified(self, cx_06_sql):
        """Both dynamic tables must specify a WAREHOUSE."""
        warehouses = re.findall(
            r"WAREHOUSE\s*=\s*\w+", cx_06_sql, re.IGNORECASE
        )
        assert len(warehouses) >= 2, (
            f"Expected at least 2 WAREHOUSE clauses, found {len(warehouses)}"
        )


# ── cx_06: LATERAL FLATTEN patterns ──────────────────────────────


class TestLateralFlatten:
    """Verify FLATTEN on ae_extraction_json:adverse_events uses correct syntax."""

    def test_flatten_on_adverse_events_array(self, cx_06_sql):
        """FACT_AE_CALLS must FLATTEN the ae_extraction_json:adverse_events array."""
        # Accept both LATERAL FLATTEN and just FLATTEN (Snowflake supports both)
        pattern = re.compile(
            r"(LATERAL\s+)?FLATTEN\s*\(\s*(INPUT\s*=>)?\s*(\w+\.)?\s*ae_extraction_json\s*:\s*adverse_events",
            re.IGNORECASE,
        )
        assert pattern.search(cx_06_sql), (
            "FACT_AE_CALLS must contain FLATTEN on ae_extraction_json:adverse_events. "
            "Expected pattern: LATERAL FLATTEN(input => ae_extraction_json:adverse_events)"
        )

    def test_flatten_has_alias(self, cx_06_sql):
        """FLATTEN must have a table alias for referencing flattened values."""
        # After FLATTEN(...) there should be an alias like "ae" or "f"
        pattern = re.compile(
            r"FLATTEN\s*\([^)]+\)\s+(\w+)",
            re.IGNORECASE,
        )
        assert pattern.search(cx_06_sql), (
            "FLATTEN expression must have a table alias (e.g., FLATTEN(...) ae)"
        )

    def test_flatten_value_access(self, cx_06_sql):
        """Flattened values should be accessed via alias.VALUE: path notation."""
        # Look for VALUE:some_field pattern — this is how you access flattened elements
        pattern = re.compile(r"VALUE\s*:\s*\w+", re.IGNORECASE)
        assert pattern.search(cx_06_sql), (
            "Flattened array elements should be accessed via VALUE:field_name notation "
            "(e.g., ae.VALUE:ae_description_verbatim)"
        )


# ── cx_06: TRY_PARSE_JSON guards ────────────────────────────────


class TestTryParseJsonGuards:
    """Verify JSON columns are protected with TRY_PARSE_JSON or IS NOT NULL guards."""

    def test_ae_extraction_json_guarded(self, cx_06_sql):
        """ae_extraction_json must have a NULL/parse guard before FLATTEN.

        The plan specifies: WHERE ae_detected = TRUE and ae_extraction_json IS NOT NULL
        (TRY_PARSE_JSON guard). Either TRY_PARSE_JSON or IS NOT NULL is acceptable.
        """
        has_try_parse = re.search(
            r"TRY_PARSE_JSON", cx_06_sql, re.IGNORECASE
        )
        has_is_not_null = re.search(
            r"ae_extraction_json\s+IS\s+NOT\s+NULL", cx_06_sql, re.IGNORECASE
        )
        assert has_try_parse or has_is_not_null, (
            "ae_extraction_json must be guarded against NULL/malformed JSON. "
            "Use TRY_PARSE_JSON or 'ae_extraction_json IS NOT NULL' in WHERE clause."
        )

    def test_ae_detected_filter(self, cx_06_sql):
        """FACT_AE_CALLS must filter for ae_detected = TRUE."""
        pattern = re.compile(
            r"ae_detected\s*=\s*(TRUE|'TRUE'|'true')",
            re.IGNORECASE,
        )
        assert pattern.search(cx_06_sql), (
            "FACT_AE_CALLS must filter WHERE ae_detected = TRUE per plan"
        )

    def test_audio_intelligence_json_guarded(self, cx_06_sql):
        """FACT_AGENT_COMPLIANCE should guard against NULL audio_intelligence_json."""
        has_try_parse = re.search(
            r"TRY_PARSE_JSON", cx_06_sql, re.IGNORECASE
        )
        has_is_not_null = re.search(
            r"audio_intelligence_json\s+IS\s+NOT\s+NULL",
            cx_06_sql,
            re.IGNORECASE,
        )
        # At least one guard somewhere for audio_intelligence_json
        assert has_try_parse or has_is_not_null, (
            "audio_intelligence_json should be guarded with TRY_PARSE_JSON or IS NOT NULL"
        )


# ── cx_06 & cx_07: Cross-schema references ──────────────────────


class TestCrossSchemaReferences:
    """Verify all cross-schema references are fully qualified."""

    def test_cx_06_references_cx_bronze(self, cx_06_sql):
        """Silver DTs must reference CX_BRONZE tables with full DB.SCHEMA.TABLE paths."""
        # Should reference CX_BRONZE tables (CALL_TRANSCRIPTIONS, CALL_AUDIO_INTELLIGENCE, etc.)
        pattern = re.compile(
            r"(PHARMACOVIGILANCE\.)?CX_BRONZE\.\w+",
            re.IGNORECASE,
        )
        matches = pattern.findall(cx_06_sql)
        assert len(matches) >= 1, (
            "cx_06 must reference CX_BRONZE tables (e.g., CX_BRONZE.CALL_AE_EXTRACTIONS). "
            "Dynamic Tables require schema-qualified references."
        )

    def test_cx_06_targets_cx_silver(self, cx_06_sql):
        """Dynamic Tables should be created in CX_SILVER schema."""
        pattern = re.compile(
            r"(PHARMACOVIGILANCE\.)?CX_SILVER\.\w+",
            re.IGNORECASE,
        )
        assert pattern.search(cx_06_sql), (
            "Dynamic tables should be created in CX_SILVER schema"
        )

    def test_cx_07_references_cx_silver(self, cx_07_sql):
        """Gold views must reference CX_SILVER tables."""
        pattern = re.compile(
            r"(PHARMACOVIGILANCE\.)?CX_SILVER\.\w+",
            re.IGNORECASE,
        )
        assert pattern.search(cx_07_sql), (
            "Gold views must reference CX_SILVER fact tables"
        )

    def test_cx_07_references_d_silver_for_unified_view(self, cx_07_sql):
        """V_UNIFIED_AE_SIGNAL must reference D_SILVER for FAERS data."""
        pattern = re.compile(
            r"(PHARMACOVIGILANCE\.)?D_SILVER\.FACT_ADVERSE_EVENT",
            re.IGNORECASE,
        )
        assert pattern.search(cx_07_sql), (
            "V_UNIFIED_AE_SIGNAL must reference D_SILVER.FACT_ADVERSE_EVENT for FAERS data"
        )

    def test_cx_07_targets_cx_gold(self, cx_07_sql):
        """Gold views should be created in CX_GOLD schema."""
        pattern = re.compile(
            r"(PHARMACOVIGILANCE\.)?CX_GOLD\.\w+",
            re.IGNORECASE,
        )
        assert pattern.search(cx_07_sql), (
            "Gold views should be created in CX_GOLD schema"
        )


# ── cx_07: Gold view SQL patterns ───────────────────────────────


class TestGoldViewPatterns:
    """Verify gold view SQL patterns for correctness."""

    def test_v_ae_triage_queue_exists(self, cx_07_sql):
        """V_AE_TRIAGE_QUEUE view must be created."""
        pattern = re.compile(
            r"CREATE\s+(OR\s+REPLACE\s+)?VIEW\s+.*V_AE_TRIAGE_QUEUE",
            re.IGNORECASE,
        )
        assert pattern.search(cx_07_sql), "V_AE_TRIAGE_QUEUE view must be created"

    def test_v_unified_ae_signal_exists(self, cx_07_sql):
        """V_UNIFIED_AE_SIGNAL view must be created."""
        pattern = re.compile(
            r"CREATE\s+(OR\s+REPLACE\s+)?VIEW\s+.*V_UNIFIED_AE_SIGNAL",
            re.IGNORECASE,
        )
        assert pattern.search(cx_07_sql), "V_UNIFIED_AE_SIGNAL view must be created"

    def test_unified_view_uses_union_all(self, cx_07_sql):
        """V_UNIFIED_AE_SIGNAL must use UNION ALL to combine FAERS + CALL_CENTER data."""
        assert re.search(r"UNION\s+ALL", cx_07_sql, re.IGNORECASE), (
            "V_UNIFIED_AE_SIGNAL must use UNION ALL to combine data sources"
        )

    def test_triage_queue_has_priority_flag(self, cx_07_sql):
        """V_AE_TRIAGE_QUEUE must calculate PRIORITY_FLAG."""
        assert re.search(r"PRIORITY_FLAG", cx_07_sql, re.IGNORECASE), (
            "V_AE_TRIAGE_QUEUE must include PRIORITY_FLAG column"
        )

    def test_triage_queue_joins_compliance(self, cx_07_sql):
        """V_AE_TRIAGE_QUEUE must JOIN FACT_AE_CALLS with FACT_AGENT_COMPLIANCE."""
        has_ae_calls = re.search(r"FACT_AE_CALLS", cx_07_sql, re.IGNORECASE)
        has_compliance = re.search(
            r"FACT_AGENT_COMPLIANCE", cx_07_sql, re.IGNORECASE
        )
        assert has_ae_calls and has_compliance, (
            "V_AE_TRIAGE_QUEUE must JOIN FACT_AE_CALLS with FACT_AGENT_COMPLIANCE"
        )

    def test_unified_view_has_data_source_column(self, cx_07_sql):
        """V_UNIFIED_AE_SIGNAL must include DATA_SOURCE to distinguish FAERS vs CALL_CENTER."""
        # Look for either a literal 'FAERS' or 'CALL_CENTER' string
        has_faers = re.search(r"'FAERS'", cx_07_sql, re.IGNORECASE)
        has_call_center = re.search(
            r"'CALL_CENTER'", cx_07_sql, re.IGNORECASE
        )
        assert has_faers and has_call_center, (
            "V_UNIFIED_AE_SIGNAL must label DATA_SOURCE as 'FAERS' and 'CALL_CENTER'"
        )
