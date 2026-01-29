"""
Just Now - FastAPI Backend
Walking Skeleton for Intent-Driven GenUI Demo.
"""

import json
import uuid
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from schemas import (
    ProcessIntentRequest,
    GenUIResponse,
    ErrorResponse,
)

# Initialize FastAPI app
app = FastAPI(
    title="Just Now API",
    description="Intent-Driven GenUI Backend (PoC)",
    version="1.0.0",
)

# CORS middleware for Flutter web/emulator access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load mock scenarios at startup (simulating Config Center pull)
MOCK_DATA_PATH = Path(__file__).parent / "data" / "mock_scenarios.json"
MOCK_SCENARIOS: dict = {}


@app.on_event("startup")
async def load_mock_scenarios():
    """Load mock scenarios from JSON file at startup."""
    global MOCK_SCENARIOS
    try:
        with open(MOCK_DATA_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            MOCK_SCENARIOS = data.get("scenarios", {})
            print(f"Loaded {len(MOCK_SCENARIOS)} mock scenarios: {list(MOCK_SCENARIOS.keys())}")
    except FileNotFoundError:
        print(f"Warning: Mock data file not found at {MOCK_DATA_PATH}")
        MOCK_SCENARIOS = {}


def detect_scenario_from_text(text: str) -> str:
    """
    Simple keyword matching to detect scenario from input text.
    Production would use LLM for intent classification.
    """
    text_lower = text.lower()

    # Keyword mappings
    if any(kw in text_lower for kw in ["taxi", "cab", "car", "ride", "打车", "叫车", "出租"]):
        return "taxi_default"
    elif any(kw in text_lower for kw in ["code", "python", "程序", "代码", "编程"]):
        return "code_demo"

    # Default to taxi scenario
    return "taxi_default"


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

    - For demo: HMAC signature check is skipped per guardrails.
    - Mock scenario can be forced via X-Mock-Scenario header or request body.
    """
    # Determine which scenario to use
    # Priority: Header > Body > Auto-detect from text
    scenario_key = (
        x_mock_scenario
        or request.mock_scenario
        or detect_scenario_from_text(request.text_input)
    )

    # Fetch scenario data
    scenario_data = MOCK_SCENARIOS.get(scenario_key)

    if not scenario_data:
        # Fallback to taxi_default if scenario not found
        scenario_data = MOCK_SCENARIOS.get("taxi_default")
        if not scenario_data:
            raise HTTPException(
                status_code=422,
                detail={
                    "error_code": "E-4071",
                    "message": f"Scenario '{scenario_key}' not found and no fallback available",
                    "trace_id": str(uuid.uuid4()),
                    "action": "TOAST",
                    "user_tip": "无法处理您的请求，请稍后再试",
                },
            )

    # Validate and return response using Pydantic
    # This ensures the response matches GenUIResponse schema
    response = GenUIResponse.model_validate(scenario_data)

    return response


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "scenarios_loaded": len(MOCK_SCENARIOS),
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
