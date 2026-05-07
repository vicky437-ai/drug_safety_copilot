"""
Drug Safety Co-Pilot — Cortex Agent Configuration

This module defines the Cortex Agent configuration for the pharmacovigilance
copilot. The agent orchestrates:
  - Cortex Search Service (narrative search)
  - Cortex Analyst (structured data queries via semantic view)

Used by the Streamlit app and can also be invoked via Snowflake Intelligence UI.
"""

AGENT_CONFIG = {
    "model": "claude-3-5-sonnet",
    "tools": [
        {
            "tool_spec": {
                "type": "cortex_search_service",
                "name": "PHARMACOVIGILANCE.D_GOLD.AE_NARRATIVE_SEARCH",
                "description": (
                    "Search clinical adverse event narratives using natural language. "
                    "Use this tool when the user asks about specific cases, clinical details, "
                    "narrative content, or wants to find cases matching specific clinical criteria."
                )
            }
        },
        {
            "tool_spec": {
                "type": "cortex_analyst_tool",
                "name": "PHARMACOVIGILANCE.D_GOLD.PV_ANALYST_VIEW",
                "description": (
                    "Query structured pharmacovigilance data using natural language. "
                    "Use this tool for quantitative questions about adverse event counts, "
                    "trends over time, drug comparisons, outcome rates, and statistical analysis."
                )
            }
        }
    ],
    "instructions": (
        "You are the Drug Safety Co-Pilot, an AI assistant specialized in pharmacovigilance "
        "signal detection and adverse event analysis. You help Drug Safety Officers and PV Analysts "
        "investigate adverse event signals, query AE rates and trends, and search clinical narratives "
        "for supporting evidence.\n\n"
        "GUIDELINES:\n"
        "1. Always cite your data source (structured query vs. narrative search).\n"
        "2. When reporting signal metrics, include: case count, reporting rate, "
        "   proportional reporting ratio (PRR) if calculable.\n"
        "3. Flag any signal that exceeds 2x the expected baseline rate as a potential safety signal.\n"
        "4. For serious/fatal events, always recommend further investigation.\n"
        "5. Present numerical results in tables when there are 3+ data points.\n"
        "6. When discussing causality, reference the WHO-UMC or Naranjo criteria.\n"
        "7. Maintain HIPAA compliance — never expose raw patient identifiers in responses.\n"
        "8. If asked about a specific case, use narrative search. "
        "   If asked for statistics/trends, use the analyst tool.\n"
        "9. For complex questions, use both tools: analyst for quantitative context, "
        "   search for clinical evidence."
    ),
    "sample_questions": [
        "What are the top 5 adverse events reported this quarter?",
        "Show me the trend of hepatotoxicity cases over time by drug",
        "Find narratives mentioning cardiac events with pembrolizumab",
        "Which drugs have the highest fatal outcome rate?",
        "Compare adverse event profiles between metformin and semaglutide",
        "Are there any signals for nephrotoxicity with adalimumab?",
        "What is the average time to onset for Stevens-Johnson syndrome?",
        "Find cases where dechallenge was positive for liver injury"
    ]
}

# REST API endpoint format for calling the agent from Streamlit
AGENT_API_ENDPOINT = "/api/v2/cortex/agent:run"

# Request payload template
def build_agent_request(user_message: str, conversation_history: list = None):
    """Build the REST API request payload for Cortex Agent."""
    messages = list(conversation_history) if conversation_history else []
    messages.append({"role": "user", "content": user_message})

    return {
        "model": AGENT_CONFIG["model"],
        "messages": messages,
        "tools": AGENT_CONFIG["tools"],
        "tool_choice": "auto",
        "system": AGENT_CONFIG["instructions"]
    }
