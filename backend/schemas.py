"""
Just Now - Pydantic V2 Schemas
Strictly follows LLD Section 2.2 specification.
"""

from typing import Literal, List, Union, Optional, Annotated, Dict, Any
from pydantic import BaseModel, Field


# --- Base Component Models ---

class ActionModel(BaseModel):
    """Action definition for interactive elements."""
    type: Literal["deep_link", "api_call", "toast"]
    url: Optional[str] = None
    payload: Optional[dict] = None


class ActionItem(BaseModel):
    """Individual item in an ActionList."""
    id: str
    title: str
    subtitle: Optional[str] = None
    action: ActionModel


class LatLng(BaseModel):
    """Geographic coordinates."""
    lat: float
    lng: float


class Marker(LatLng):
    """Map marker with optional title."""
    title: Optional[str] = None


# --- UI Component Definitions ---
# Strictly follows Pydantic V2 Discriminated Union best practices

class InfoCard(BaseModel):
    """Information card for displaying content with Markdown support."""
    type: Literal["InfoCard"]
    widget_id: str
    title: str
    content_md: str
    style: Literal["standard", "highlight", "warning"] = "standard"


class ActionList(BaseModel):
    """Interactive list with actionable items."""
    type: Literal["ActionList"]
    widget_id: str
    title: str
    items: List[ActionItem]


class MapView(BaseModel):
    """Map component for location display."""
    type: Literal["MapView"]
    widget_id: str
    center: LatLng
    zoom: float = 14.0
    # Use default_factory to avoid mutable default value pitfall
    markers: List[Marker] = Field(default_factory=list)


# --- Component Container Wrapper ---

# Define the discriminated union type for UI components
UIComponent = Annotated[
    Union[InfoCard, ActionList, MapView],
    Field(discriminator="type")
]


class UIPayload(BaseModel):
    """Container for the UI component tree."""
    components: List[UIComponent]


# --- Final Response Structure (HLD Aligned) ---

class GenUIResponse(BaseModel):
    """Main API response containing the GenUI widget tree."""
    intent_id: str
    category: Literal["SERVICE", "CHAT"] = "SERVICE"
    ui_schema_version: Literal["1.0"] = "1.0"
    slots: Dict[str, Any] = Field(default_factory=dict)
    ui_payload: UIPayload


# --- Request Models ---

class ProcessIntentRequest(BaseModel):
    """Request body for the /intent/process endpoint."""
    text_input: str
    mock_scenario: Optional[str] = None


# --- Error Response Model ---

class ErrorResponse(BaseModel):
    """Standard error response format per HLD contract."""
    error_code: str
    message: str
    trace_id: str
    action: Literal["RETRY", "REBIND", "TOAST", "NONE"]
    user_tip: str
