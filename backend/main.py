"""
Just Now - FastAPI Backend
Intent-Driven GenUI with LLM-powered UI generation.
"""

import json
import logging
import os
import re
import uuid
from typing import Optional

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI

from schemas import (
    ProcessIntentRequest,
    GenUIResponse,
    ErrorResponse,
)

# --- Logging Configuration ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("just_now")

# Initialize FastAPI app
app = FastAPI(
    title="Just Now API",
    description="Intent-Driven GenUI Backend with LLM Integration",
    version="2.0.0",
)

# CORS middleware for Flutter web/emulator access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- LLM Client Configuration ---
# Supports both OpenAI and DeepSeek APIs via environment variables

def get_llm_client() -> OpenAI:
    """
    Initialize OpenAI client with support for DeepSeek.

    Environment variables:
    - DEEPSEEK_API_KEY: DeepSeek API key (preferred)
    - OPENAI_API_KEY: OpenAI API key (fallback)
    - LLM_BASE_URL: Custom base URL for API (e.g., DeepSeek's endpoint)
    """
    api_key = os.getenv("DEEPSEEK_API_KEY") or os.getenv("OPENAI_API_KEY")
    base_url = os.getenv("LLM_BASE_URL")

    # Default to DeepSeek endpoint if DEEPSEEK_API_KEY is set
    if os.getenv("DEEPSEEK_API_KEY") and not base_url:
        base_url = "https://api.deepseek.com"

    if not api_key:
        raise ValueError(
            "No API key found. Set DEEPSEEK_API_KEY or OPENAI_API_KEY environment variable."
        )

    logger.info(f"Initializing LLM client with base_url: {base_url or 'default OpenAI'}")
    return OpenAI(api_key=api_key, base_url=base_url)


def clean_llm_response(raw_content: str) -> str:
    """
    Clean LLM response by removing markdown code blocks and extra formatting.

    DeepSeek and other LLMs often wrap JSON in markdown code blocks like:
    ```json
    { ... }
    ```

    This function strips all that away to get pure JSON.
    """
    if not raw_content:
        return raw_content

    content = raw_content.strip()

    # Remove markdown code blocks with language specifier (```json, ```JSON, etc.)
    # Pattern matches: ```json or ```JSON or ``` at the start
    content = re.sub(r'^```(?:json|JSON)?\s*\n?', '', content)

    # Remove trailing ```
    content = re.sub(r'\n?```\s*$', '', content)

    # Strip any remaining whitespace
    content = content.strip()

    # If content still doesn't start with { or [, try to find JSON within the text
    if not content.startswith(('{', '[')):
        # Try to extract JSON object from the text
        json_match = re.search(r'(\{[\s\S]*\})', content)
        if json_match:
            content = json_match.group(1)

    return content


def create_fallback_response(error_message: str, user_text: str) -> dict:
    """
    Create a fallback UI response when LLM fails.
    Returns an InfoCard with error information.
    """
    return {
        "intent_id": str(uuid.uuid4()),
        "category": "CHAT",
        "ui_schema_version": "1.0",
        "slots": {
            "error": "llm_generation_failed",
            "original_query": user_text[:100]  # Truncate for safety
        },
        "ui_payload": {
            "components": [
                {
                    "type": "InfoCard",
                    "widget_id": "error_card_01",
                    "title": "Unable to Process Request",
                    "content_md": f"Sorry, I couldn't process your request at this time.\n\n**Your request:** {user_text[:100]}{'...' if len(user_text) > 100 else ''}\n\nPlease try again or rephrase your request.",
                    "style": "warning"
                }
            ]
        }
    }


# System prompt defining the Just Now UI Protocol
SYSTEM_PROMPT = """You are an AI assistant for "Just Now", a mobile app that dynamically generates UI components based on user intent.

Your task is to analyze user requests and generate a JSON response that defines the UI to be displayed.

## CRITICAL OUTPUT REQUIREMENT

You MUST return ONLY raw JSON.
- NO markdown code blocks (no ```json or ```)
- NO explanatory text before or after the JSON
- NO conversational filler
- ONLY the pure JSON object, nothing else

## Response Schema (GenUIResponse)

Return ONLY valid JSON matching this exact structure:

{
  "intent_id": "string (UUID format)",
  "category": "SERVICE" | "CHAT",
  "ui_schema_version": "1.0",
  "slots": {
    // Key-value pairs extracted from user intent
    // e.g., "destination": "Beijing Airport", "service_type": "taxi"
  },
  "ui_payload": {
    "components": [
      // Array of UI components (see below)
    ]
  }
}

## Available UI Components

### 1. MapView - For location/map display
{
  "type": "MapView",
  "widget_id": "string (unique identifier)",
  "center": {
    "lat": number,
    "lng": number
  },
  "zoom": number (default: 14.0),
  "markers": [
    {
      "lat": number,
      "lng": number,
      "title": "string (optional)"
    }
  ]
}

### 2. ActionList - For interactive options/choices
{
  "type": "ActionList",
  "widget_id": "string (unique identifier)",
  "title": "string",
  "items": [
    {
      "id": "string (unique item ID)",
      "title": "string",
      "subtitle": "string (optional)",
      "action": {
        "type": "deep_link" | "api_call" | "toast",
        "url": "string (for deep_link/toast)",
        "payload": {} (for api_call)
      }
    }
  ]
}

For ride-hailing actions, use the special URL format: api:order_ride?params to trigger in-app confirmation dialogs.

### 3. InfoCard - For displaying information/content
{
  "type": "InfoCard",
  "widget_id": "string (unique identifier)",
  "title": "string",
  "content_md": "string (Markdown supported)",
  "style": "standard" | "highlight" | "warning"
}

## Guidelines

1. **Category Selection**:
   - Use "SERVICE" for actionable requests (taxi, food delivery, bookings, etc.)
   - Use "CHAT" for informational/conversational requests (questions, code help, etc.)

2. **Component Selection**:
   - Taxi/ride requests → MapView + ActionList with ride options
   - Information/coding questions → InfoCard with content_md
   - Multiple options to choose from → ActionList

3. **Action URLs**:
   - For ride ordering: use api:order_ride?destination=xxx&type=xxx
   - For external apps: use appropriate deep links (e.g., didi://app?action=...)

4. **Localization**: Match the user's language (Chinese input → Chinese response)

## Example

User: "I need a taxi to the airport"

Your response (ONLY this JSON, nothing else):
{"intent_id":"550e8400-e29b-41d4-a716-446655440000","category":"SERVICE","ui_schema_version":"1.0","slots":{"destination":"Airport","service_type":"taxi"},"ui_payload":{"components":[{"type":"MapView","widget_id":"map_airport_01","center":{"lat":40.0799,"lng":116.6031},"zoom":12.0,"markers":[{"lat":40.0799,"lng":116.6031,"title":"Airport"}]},{"type":"ActionList","widget_id":"ride_options_01","title":"Available Rides","items":[{"id":"ride_economy","title":"Economy - Est. $25","subtitle":"4 min away","action":{"type":"deep_link","url":"api:order_ride?type=economy&dest=airport"}},{"id":"ride_premium","title":"Premium - Est. $45","subtitle":"2 min away","action":{"type":"deep_link","url":"api:order_ride?type=premium&dest=airport"}}]}]}}

REMEMBER: Output ONLY raw JSON. No markdown. No explanation. Just the JSON object."""

# LLM client instance (initialized on first use)
_llm_client: Optional[OpenAI] = None


def get_client() -> OpenAI:
    """Get or create the LLM client singleton."""
    global _llm_client
    if _llm_client is None:
        _llm_client = get_llm_client()
    return _llm_client


async def generate_ui_with_llm(user_text: str) -> dict:
    """
    Call LLM to generate UI components based on user intent.

    Args:
        user_text: The user's natural language input

    Returns:
        Parsed JSON dictionary matching GenUIResponse schema
    """
    client = get_client()

    # Hardcode model name for DeepSeek API compatibility
    # DeepSeek requires "deepseek-chat" as the model name
    if os.getenv("DEEPSEEK_API_KEY"):
        model = "deepseek-chat"
    else:
        model = os.getenv("LLM_MODEL", "gpt-4o-mini")

    logger.info(f"Using model: {model}")
    logger.info(f"Processing user input: {user_text[:100]}...")

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_text}
            ],
            temperature=0.7,
            max_tokens=2000,
        )

        raw_content = response.choices[0].message.content

        # Log the RAW response for debugging
        logger.info("=" * 50)
        logger.info("RAW LLM RESPONSE:")
        logger.info(raw_content)
        logger.info("=" * 50)

        if not raw_content:
            logger.error("Empty response from LLM")
            return create_fallback_response("Empty response from LLM", user_text)

        # Clean the response to remove markdown formatting
        cleaned_content = clean_llm_response(raw_content)

        logger.info("CLEANED CONTENT:")
        logger.info(cleaned_content[:500] + "..." if len(cleaned_content) > 500 else cleaned_content)

        # Parse the JSON response
        try:
            result = json.loads(cleaned_content)
        except json.JSONDecodeError as e:
            logger.error(f"JSON parsing failed after cleaning: {e}")
            logger.error(f"Cleaned content was: {cleaned_content[:500]}")
            return create_fallback_response(f"Invalid JSON response: {e}", user_text)

        # Ensure intent_id is present and valid
        if "intent_id" not in result or not result["intent_id"]:
            result["intent_id"] = str(uuid.uuid4())

        logger.info("Successfully parsed LLM response")
        return result

    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return create_fallback_response(f"JSON parsing error: {e}", user_text)
    except Exception as e:
        logger.error(f"LLM generation failed: {e}", exc_info=True)
        return create_fallback_response(f"LLM error: {e}", user_text)


@app.post(
    "/api/v1/intent/process",
    response_model=GenUIResponse,
    responses={
        422: {"model": ErrorResponse, "description": "Semantic Mismatch"},
        500: {"model": ErrorResponse, "description": "Server Error"},
    },
)
async def process_intent(
    request: ProcessIntentRequest,
    x_device_id: Optional[str] = Header(None, alias="X-Device-Id"),
    x_mock_scenario: Optional[str] = Header(None, alias="X-Mock-Scenario"),
):
    """
    Process user intent and return GenUI widget tree.

    Uses LLM to dynamically generate UI based on user's natural language input.
    """
    trace_id = str(uuid.uuid4())
    logger.info(f"[{trace_id}] Received request: {request.text_input[:100]}...")

    try:
        # Generate UI using LLM (with fallback on errors)
        ui_data = await generate_ui_with_llm(request.text_input)

        # Validate and return response using Pydantic
        response = GenUIResponse.model_validate(ui_data)
        logger.info(f"[{trace_id}] Successfully generated response")
        return response

    except Exception as e:
        # This should rarely happen now since generate_ui_with_llm handles errors
        logger.error(f"[{trace_id}] Unexpected error: {e}", exc_info=True)

        # Return fallback response instead of crashing
        fallback = create_fallback_response(str(e), request.text_input)
        return GenUIResponse.model_validate(fallback)


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    has_api_key = bool(os.getenv("DEEPSEEK_API_KEY") or os.getenv("OPENAI_API_KEY"))

    if os.getenv("DEEPSEEK_API_KEY"):
        model = "deepseek-chat"
        provider = "DeepSeek"
    else:
        model = os.getenv("LLM_MODEL", "gpt-4o-mini")
        provider = "OpenAI"

    return {
        "status": "healthy",
        "llm_configured": has_api_key,
        "provider": provider if has_api_key else "not configured",
        "model": model if has_api_key else "not configured",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
