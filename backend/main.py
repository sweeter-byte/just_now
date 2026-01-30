"""
Just Now - FastAPI Backend
Intent-Driven GenUI with LLM-powered UI generation.
"""

import json
import os
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

    return OpenAI(api_key=api_key, base_url=base_url)


# System prompt defining the Just Now UI Protocol
SYSTEM_PROMPT = """You are an AI assistant for "Just Now", a mobile app that dynamically generates UI components based on user intent.

Your task is to analyze user requests and generate a JSON response that defines the UI to be displayed.

## Response Schema (GenUIResponse)

You MUST return ONLY valid JSON matching this exact structure:

```json
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
```

## Available UI Components

### 1. MapView - For location/map display
```json
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
```

### 2. ActionList - For interactive options/choices
```json
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
```

For ride-hailing actions, use the special URL format: `api:order_ride?params` to trigger in-app confirmation dialogs.

### 3. InfoCard - For displaying information/content
```json
{
  "type": "InfoCard",
  "widget_id": "string (unique identifier)",
  "title": "string",
  "content_md": "string (Markdown supported)",
  "style": "standard" | "highlight" | "warning"
}
```

## Guidelines

1. **Category Selection**:
   - Use "SERVICE" for actionable requests (taxi, food delivery, bookings, etc.)
   - Use "CHAT" for informational/conversational requests (questions, code help, etc.)

2. **Component Selection**:
   - Taxi/ride requests → MapView + ActionList with ride options
   - Information/coding questions → InfoCard with content_md
   - Multiple options to choose from → ActionList

3. **Action URLs**:
   - For ride ordering: use `api:order_ride?destination=xxx&type=xxx`
   - For external apps: use appropriate deep links (e.g., `didi://app?action=...`)

4. **Localization**: Match the user's language (Chinese input → Chinese response)

5. **CRITICAL**: Return ONLY the JSON object. No markdown code blocks, no explanations, no additional text.

## Example

User: "I need a taxi to the airport"

Response:
{
  "intent_id": "550e8400-e29b-41d4-a716-446655440000",
  "category": "SERVICE",
  "ui_schema_version": "1.0",
  "slots": {
    "destination": "Airport",
    "service_type": "taxi"
  },
  "ui_payload": {
    "components": [
      {
        "type": "MapView",
        "widget_id": "map_airport_01",
        "center": {"lat": 40.0799, "lng": 116.6031},
        "zoom": 12.0,
        "markers": [{"lat": 40.0799, "lng": 116.6031, "title": "Airport"}]
      },
      {
        "type": "ActionList",
        "widget_id": "ride_options_01",
        "title": "Available Rides",
        "items": [
          {
            "id": "ride_economy",
            "title": "Economy - Est. $25",
            "subtitle": "4 min away",
            "action": {"type": "deep_link", "url": "api:order_ride?type=economy&dest=airport"}
          },
          {
            "id": "ride_premium",
            "title": "Premium - Est. $45",
            "subtitle": "2 min away",
            "action": {"type": "deep_link", "url": "api:order_ride?type=premium&dest=airport"}
          }
        ]
      }
    ]
  }
}
"""

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

    # Determine model based on API being used
    model = os.getenv("LLM_MODEL", "deepseek-chat")
    if os.getenv("OPENAI_API_KEY") and not os.getenv("DEEPSEEK_API_KEY"):
        model = os.getenv("LLM_MODEL", "gpt-4o-mini")

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_text}
            ],
            temperature=0.7,
            max_tokens=2000,
            response_format={"type": "json_object"},  # Ensure JSON output
        )

        content = response.choices[0].message.content
        if not content:
            raise ValueError("Empty response from LLM")

        # Parse the JSON response
        result = json.loads(content)

        # Ensure intent_id is present and valid
        if "intent_id" not in result or not result["intent_id"]:
            result["intent_id"] = str(uuid.uuid4())

        return result

    except json.JSONDecodeError as e:
        raise ValueError(f"LLM returned invalid JSON: {e}")
    except Exception as e:
        raise ValueError(f"LLM generation failed: {e}")


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

    try:
        # Generate UI using LLM
        ui_data = await generate_ui_with_llm(request.text_input)

        # Validate and return response using Pydantic
        response = GenUIResponse.model_validate(ui_data)
        return response

    except ValueError as e:
        # LLM or parsing error
        raise HTTPException(
            status_code=500,
            detail={
                "error_code": "E-5001",
                "message": str(e),
                "trace_id": trace_id,
                "action": "RETRY",
                "user_tip": "AI generation failed. Please try again.",
            },
        )
    except Exception as e:
        # Unexpected error
        raise HTTPException(
            status_code=500,
            detail={
                "error_code": "E-5000",
                "message": f"Internal server error: {e}",
                "trace_id": trace_id,
                "action": "RETRY",
                "user_tip": "Something went wrong. Please try again later.",
            },
        )


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    has_api_key = bool(os.getenv("DEEPSEEK_API_KEY") or os.getenv("OPENAI_API_KEY"))
    return {
        "status": "healthy",
        "llm_configured": has_api_key,
        "model": os.getenv("LLM_MODEL", "deepseek-chat" if os.getenv("DEEPSEEK_API_KEY") else "gpt-4o-mini"),
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
