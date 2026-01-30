"""
Just Now - FastAPI Backend
Intent-Driven GenUI with LLM-powered UI generation.
Integrated with Real-World LBS: Nominatim (search) + OSRM (routing).
"""

import json
import logging
import os
import re
import uuid
import math
import tempfile
from typing import Optional, List, Tuple

import httpx
import whisper
from fastapi import FastAPI, Header, HTTPException, File, UploadFile
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
    description="Intent-Driven GenUI Backend with LLM + Real LBS Integration",
    version="3.0.0",
)

# CORS middleware for Flutter web/emulator access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Constants ---
# Default location: Nanjing, China (used when user location unavailable)
DEFAULT_LAT = 32.0603
DEFAULT_LNG = 118.7969

# Nominatim API (OpenStreetMap search)
NOMINATIM_BASE_URL = "https://nominatim.openstreetmap.org"
NOMINATIM_USER_AGENT = "JustNowApp/3.0 (contact@justnow.app)"

# OSRM API (Open Source Routing Machine)
OSRM_BASE_URL = "http://router.project-osrm.org"

# Disambiguation threshold: if top results have similar relevance, ask user to choose
DISAMBIGUATION_DISTANCE_THRESHOLD_METERS = 500
MAX_DISAMBIGUATION_RESULTS = 5


# --- LLM Client Configuration ---

def get_llm_client() -> OpenAI:
    """
    Initialize OpenAI client with support for DeepSeek.
    """
    api_key = os.getenv("DEEPSEEK_API_KEY") or os.getenv("OPENAI_API_KEY")
    base_url = os.getenv("LLM_BASE_URL")

    if os.getenv("DEEPSEEK_API_KEY") and not base_url:
        base_url = "https://api.deepseek.com"

    if not api_key:
        raise ValueError(
            "No API key found. Set DEEPSEEK_API_KEY or OPENAI_API_KEY environment variable."
        )

    logger.info(f"Initializing LLM client with base_url: {base_url or 'default OpenAI'}")
    return OpenAI(api_key=api_key, base_url=base_url)


# LLM client singleton
_llm_client: Optional[OpenAI] = None


def get_client() -> OpenAI:
    """Get or create the LLM client singleton."""
    global _llm_client
    if _llm_client is None:
        _llm_client = get_llm_client()
    return _llm_client


# --- Whisper Model Singleton ---

_whisper_model = None


def get_whisper_model():
    """
    Get or load the Whisper model (singleton pattern).
    Uses 'base' model for balance between speed and accuracy.
    """
    global _whisper_model
    if _whisper_model is None:
        logger.info("Loading Whisper model (base)...")
        _whisper_model = whisper.load_model("base")
        logger.info("Whisper model loaded successfully")
    return _whisper_model


# --- Utility Functions ---

def haversine_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Calculate distance between two points in meters using Haversine formula."""
    R = 6371000  # Earth's radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lng2 - lng1)

    a = math.sin(delta_phi / 2) ** 2 + \
        math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c


def clean_llm_response(raw_content: str) -> str:
    """Clean LLM response by removing markdown code blocks and extra formatting."""
    if not raw_content:
        return raw_content

    content = raw_content.strip()
    content = re.sub(r'^```(?:json|JSON)?\s*\n?', '', content)
    content = re.sub(r'\n?```\s*$', '', content)
    content = content.strip()

    if not content.startswith(('{', '[')):
        json_match = re.search(r'(\{[\s\S]*\})', content)
        if json_match:
            content = json_match.group(1)

    return content


# --- LBS Integration: Nominatim Search ---

async def search_location(
    query: str,
    user_lat: Optional[float] = None,
    user_lng: Optional[float] = None,
    limit: int = 5
) -> List[dict]:
    """
    Search for locations using OpenStreetMap Nominatim API.

    Args:
        query: Search query (e.g., "南京南站", "Duck blood soup near Confucius Temple")
        user_lat: User's current latitude for proximity sorting
        user_lng: User's current longitude for proximity sorting
        limit: Maximum number of results

    Returns:
        List of location dictionaries with name, address, lat, lng, distance
    """
    logger.info(f"Searching location: '{query}' near ({user_lat}, {user_lng})")

    params = {
        "q": query,
        "format": "json",
        "addressdetails": 1,
        "limit": limit,
        "accept-language": "zh,en",  # Prefer Chinese names
    }

    # Add viewbox bias if user location is available (search near user)
    if user_lat is not None and user_lng is not None:
        # Create a ~20km bounding box around user
        delta = 0.18  # ~20km in degrees
        params["viewbox"] = f"{user_lng - delta},{user_lat + delta},{user_lng + delta},{user_lat - delta}"
        params["bounded"] = 0  # Don't strictly limit to viewbox, just prefer it

    headers = {"User-Agent": NOMINATIM_USER_AGENT}

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                f"{NOMINATIM_BASE_URL}/search",
                params=params,
                headers=headers
            )
            response.raise_for_status()
            results = response.json()
    except Exception as e:
        logger.error(f"Nominatim search failed: {e}")
        return []

    # Process and enrich results
    locations = []
    for item in results:
        lat = float(item.get("lat", 0))
        lng = float(item.get("lon", 0))

        # Calculate distance from user if location available
        distance = None
        if user_lat is not None and user_lng is not None:
            distance = haversine_distance(user_lat, user_lng, lat, lng)

        # Build readable address
        address_parts = item.get("address", {})
        address = item.get("display_name", "")

        # Extract a cleaner name
        name = item.get("name") or item.get("display_name", "").split(",")[0]

        locations.append({
            "id": f"loc_{item.get('place_id', uuid.uuid4().hex[:8])}",
            "name": name,
            "address": address,
            "lat": lat,
            "lng": lng,
            "distance_meters": distance,
            "importance": float(item.get("importance", 0)),
            "type": item.get("type", "unknown"),
            "class": item.get("class", "unknown"),
        })

    # Sort by distance if user location available, otherwise by importance
    if user_lat is not None and user_lng is not None:
        locations.sort(key=lambda x: x.get("distance_meters") or float('inf'))
    else:
        locations.sort(key=lambda x: -x.get("importance", 0))

    logger.info(f"Found {len(locations)} locations for '{query}'")
    return locations


# --- LBS Integration: OSRM Routing ---

async def get_route(
    start_lat: float,
    start_lng: float,
    end_lat: float,
    end_lng: float,
    profile: str = "driving"
) -> Optional[dict]:
    """
    Get route between two points using OSRM API.

    Args:
        start_lat, start_lng: Origin coordinates
        end_lat, end_lng: Destination coordinates
        profile: Routing profile ("driving", "walking", "cycling")

    Returns:
        Dictionary with route info including polyline coordinates, or None on failure
    """
    logger.info(f"Getting route: ({start_lat},{start_lng}) -> ({end_lat},{end_lng})")

    # OSRM uses lng,lat order (not lat,lng!)
    url = f"{OSRM_BASE_URL}/route/v1/{profile}/{start_lng},{start_lat};{end_lng},{end_lat}"

    params = {
        "overview": "full",       # Get full route geometry
        "geometries": "geojson",  # Return as GeoJSON (easier to parse)
        "steps": "false",
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json()
    except Exception as e:
        logger.error(f"OSRM routing failed: {e}")
        return None

    if data.get("code") != "Ok" or not data.get("routes"):
        logger.warning(f"OSRM returned no valid route: {data.get('code')}")
        return None

    route = data["routes"][0]
    geometry = route.get("geometry", {})
    coordinates = geometry.get("coordinates", [])

    # Convert from [lng, lat] to [lat, lng] for frontend consistency
    polyline = [[coord[1], coord[0]] for coord in coordinates]

    result = {
        "polyline": polyline,
        "distance_meters": route.get("distance", 0),
        "duration_seconds": route.get("duration", 0),
    }

    logger.info(f"Route found: {result['distance_meters']:.0f}m, {result['duration_seconds']:.0f}s, {len(polyline)} points")
    return result


# --- LLM Intent Extraction ---

INTENT_EXTRACTION_PROMPT = """You are an intent extraction assistant for "Just Now", a location-based services app.

Your task is to analyze user input and extract structured intent information.

## CRITICAL OUTPUT REQUIREMENT
Return ONLY raw JSON. NO markdown, NO explanation, ONLY the JSON object.

## Output Schema
{
  "category": "SERVICE" | "CHAT",
  "intent_type": "navigation" | "search_poi" | "ride_hailing" | "general_chat",
  "destination_query": "search query for the destination (if applicable)",
  "service_type": "taxi" | "walk" | "bike" | null,
  "slots": {
    // Key-value pairs extracted from intent
  },
  "response_language": "zh" | "en"
}

## Guidelines
1. For navigation/ride requests, extract the destination as a search query
2. Do NOT invent coordinates - only extract the place NAME or DESCRIPTION
3. For ambiguous places, include context (e.g., "南京 鸭血粉丝汤 夫子庙附近")
4. Match response language to user's input language

## Examples

User: "我要打车去南京南站"
{"category":"SERVICE","intent_type":"ride_hailing","destination_query":"南京南站","service_type":"taxi","slots":{"destination":"南京南站","service":"打车"},"response_language":"zh"}

User: "附近有什么好吃的鸭血粉丝汤"
{"category":"SERVICE","intent_type":"search_poi","destination_query":"鸭血粉丝汤","service_type":null,"slots":{"food_type":"鸭血粉丝汤","query_type":"nearby"},"response_language":"zh"}

User: "How do I get to the Confucius Temple?"
{"category":"SERVICE","intent_type":"navigation","destination_query":"Confucius Temple Nanjing","service_type":"walk","slots":{"destination":"Confucius Temple"},"response_language":"en"}

User: "What's the weather like today?"
{"category":"CHAT","intent_type":"general_chat","destination_query":null,"service_type":null,"slots":{"topic":"weather"},"response_language":"en"}

REMEMBER: Output ONLY raw JSON."""


async def extract_intent(user_text: str) -> dict:
    """
    Use LLM to extract structured intent from user's natural language input.

    Returns intent info WITHOUT coordinates (those come from real APIs).
    """
    client = get_client()

    if os.getenv("DEEPSEEK_API_KEY"):
        model = "deepseek-chat"
    else:
        model = os.getenv("LLM_MODEL", "deepseek-chat")

    logger.info(f"Extracting intent from: {user_text[:100]}...")

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": INTENT_EXTRACTION_PROMPT},
                {"role": "user", "content": user_text}
            ],
            temperature=0.3,  # Lower temperature for more consistent extraction
            max_tokens=500,
        )

        raw_content = response.choices[0].message.content
        cleaned = clean_llm_response(raw_content)
        result = json.loads(cleaned)

        logger.info(f"Extracted intent: {result}")
        return result

    except Exception as e:
        logger.error(f"Intent extraction failed: {e}")
        # Return a default intent for graceful degradation
        return {
            "category": "CHAT",
            "intent_type": "general_chat",
            "destination_query": None,
            "service_type": None,
            "slots": {"original_query": user_text},
            "response_language": "zh" if any('\u4e00' <= c <= '\u9fff' for c in user_text) else "en"
        }


# --- Response Builders ---

def build_disambiguation_response(
    locations: List[dict],
    original_query: str,
    language: str = "zh"
) -> dict:
    """Build a DisambiguationList response when multiple locations match."""

    title = "请选择目的地" if language == "zh" else "Select Destination"
    message = f"找到多个'{original_query}'相关的地点，请选择：" if language == "zh" else \
              f"Multiple locations found for '{original_query}'. Please select:"

    items = []
    for loc in locations[:MAX_DISAMBIGUATION_RESULTS]:
        distance_str = ""
        if loc.get("distance_meters"):
            dist = loc["distance_meters"]
            if dist < 1000:
                distance_str = f" ({dist:.0f}m)" if language == "en" else f" ({dist:.0f}米)"
            else:
                distance_str = f" ({dist/1000:.1f}km)" if language == "en" else f" ({dist/1000:.1f}公里)"

        items.append({
            "id": loc["id"],
            "name": loc["name"] + distance_str,
            "address": loc.get("address", ""),
            "lat": loc["lat"],
            "lng": loc["lng"],
            "distance_meters": loc.get("distance_meters"),
        })

    return {
        "intent_id": str(uuid.uuid4()),
        "category": "SERVICE",
        "ui_schema_version": "1.0",
        "slots": {"query": original_query, "status": "disambiguation_required"},
        "ui_payload": {
            "components": [
                {
                    "type": "DisambiguationList",
                    "widget_id": f"disambig_{uuid.uuid4().hex[:8]}",
                    "title": title,
                    "message": message,
                    "items": items,
                }
            ]
        }
    }


def build_navigation_response(
    user_lat: Optional[float],
    user_lng: Optional[float],
    dest_location: dict,
    route_data: Optional[dict],
    service_type: Optional[str],
    language: str = "zh"
) -> dict:
    """Build MapView + ActionList response for navigation/ride requests."""

    dest_lat = dest_location["lat"]
    dest_lng = dest_location["lng"]
    dest_name = dest_location["name"]

    components = []

    # Build markers
    markers = [{"lat": dest_lat, "lng": dest_lng, "title": dest_name}]
    if user_lat and user_lng:
        markers.insert(0, {"lat": user_lat, "lng": user_lng, "title": "我的位置" if language == "zh" else "My Location"})

    # Calculate appropriate zoom level
    if route_data and user_lat and user_lng:
        # Calculate bounds for route
        all_lats = [user_lat, dest_lat]
        all_lngs = [user_lng, dest_lng]
        lat_diff = max(all_lats) - min(all_lats)
        lng_diff = max(all_lngs) - min(all_lngs)
        max_diff = max(lat_diff, lng_diff)

        # Approximate zoom level
        if max_diff > 0.5:
            zoom = 10
        elif max_diff > 0.2:
            zoom = 11
        elif max_diff > 0.1:
            zoom = 12
        elif max_diff > 0.05:
            zoom = 13
        else:
            zoom = 14

        # Center between user and destination
        center_lat = (user_lat + dest_lat) / 2
        center_lng = (user_lng + dest_lng) / 2
    else:
        zoom = 14
        center_lat = dest_lat
        center_lng = dest_lng

    # MapView component
    map_component = {
        "type": "MapView",
        "widget_id": f"map_{uuid.uuid4().hex[:8]}",
        "center": {"lat": center_lat, "lng": center_lng},
        "zoom": zoom,
        "markers": markers,
    }

    # Add route polyline if available
    if route_data and route_data.get("polyline"):
        map_component["route_polyline"] = route_data["polyline"]

    components.append(map_component)

    # Build ActionList for ride-hailing
    if service_type == "taxi":
        # Format distance and duration
        if route_data:
            dist_km = route_data.get("distance_meters", 0) / 1000
            dur_min = route_data.get("duration_seconds", 0) / 60
            dist_str = f"{dist_km:.1f}公里" if language == "zh" else f"{dist_km:.1f}km"
            dur_str = f"{dur_min:.0f}分钟" if language == "zh" else f"{dur_min:.0f}min"
            subtitle_base = f"{dist_str} · 约{dur_str}" if language == "zh" else f"{dist_str} · ~{dur_str}"
        else:
            subtitle_base = ""

        list_title = "为您找到以下车辆" if language == "zh" else "Available Rides"

        action_items = [
            {
                "id": "ride_economy",
                "title": "快车 - 预计 ¥35" if language == "zh" else "Economy - Est. ¥35",
                "subtitle": f"距您 2 分钟 · {subtitle_base}" if language == "zh" else f"2 min away · {subtitle_base}",
                "action": {
                    "type": "deep_link",
                    "url": f"api:order_ride?type=economy&dest={dest_name}&dest_lat={dest_lat}&dest_lng={dest_lng}"
                }
            },
            {
                "id": "ride_premium",
                "title": "专车 - 预计 ¥58" if language == "zh" else "Premium - Est. ¥58",
                "subtitle": f"距您 1 分钟 · {subtitle_base}" if language == "zh" else f"1 min away · {subtitle_base}",
                "action": {
                    "type": "deep_link",
                    "url": f"api:order_ride?type=premium&dest={dest_name}&dest_lat={dest_lat}&dest_lng={dest_lng}"
                }
            },
            {
                "id": "ride_pool",
                "title": "拼车 - 预计 ¥22" if language == "zh" else "Pool - Est. ¥22",
                "subtitle": f"距您 4 分钟 · {subtitle_base}" if language == "zh" else f"4 min away · {subtitle_base}",
                "action": {
                    "type": "deep_link",
                    "url": f"api:order_ride?type=pool&dest={dest_name}&dest_lat={dest_lat}&dest_lng={dest_lng}"
                }
            },
        ]

        components.append({
            "type": "ActionList",
            "widget_id": f"rides_{uuid.uuid4().hex[:8]}",
            "title": list_title,
            "items": action_items,
        })

    # Build slots
    slots = {
        "destination": dest_name,
        "destination_lat": dest_lat,
        "destination_lng": dest_lng,
    }
    if route_data:
        slots["distance_meters"] = route_data.get("distance_meters")
        slots["duration_seconds"] = route_data.get("duration_seconds")
    if service_type:
        slots["service_type"] = service_type

    return {
        "intent_id": str(uuid.uuid4()),
        "category": "SERVICE",
        "ui_schema_version": "1.0",
        "slots": slots,
        "ui_payload": {"components": components}
    }


def build_poi_search_response(
    locations: List[dict],
    query: str,
    user_lat: Optional[float],
    user_lng: Optional[float],
    language: str = "zh"
) -> dict:
    """Build response for POI search (nearby food, shops, etc.)."""

    if not locations:
        # No results found
        title = "未找到结果" if language == "zh" else "No Results Found"
        content = f"抱歉，未能找到'{query}'相关的地点。请尝试其他搜索词。" if language == "zh" else \
                  f"Sorry, no locations found for '{query}'. Please try a different search."

        return {
            "intent_id": str(uuid.uuid4()),
            "category": "SERVICE",
            "ui_schema_version": "1.0",
            "slots": {"query": query, "results_count": 0},
            "ui_payload": {
                "components": [
                    {
                        "type": "InfoCard",
                        "widget_id": f"info_{uuid.uuid4().hex[:8]}",
                        "title": title,
                        "content_md": content,
                        "style": "warning"
                    }
                ]
            }
        }

    # Build map with all POIs
    markers = []
    for loc in locations[:10]:  # Limit markers
        markers.append({
            "lat": loc["lat"],
            "lng": loc["lng"],
            "title": loc["name"]
        })

    # Add user location marker
    if user_lat and user_lng:
        markers.insert(0, {
            "lat": user_lat,
            "lng": user_lng,
            "title": "我的位置" if language == "zh" else "My Location"
        })

    # Calculate center (first result or user location)
    if user_lat and user_lng:
        center_lat, center_lng = user_lat, user_lng
    else:
        center_lat = locations[0]["lat"]
        center_lng = locations[0]["lng"]

    components = []

    # MapView
    components.append({
        "type": "MapView",
        "widget_id": f"map_{uuid.uuid4().hex[:8]}",
        "center": {"lat": center_lat, "lng": center_lng},
        "zoom": 14,
        "markers": markers,
    })

    # ActionList with POI options
    list_title = f"'{query}'搜索结果" if language == "zh" else f"Results for '{query}'"
    action_items = []

    for loc in locations[:5]:
        distance_str = ""
        if loc.get("distance_meters"):
            dist = loc["distance_meters"]
            if dist < 1000:
                distance_str = f"{dist:.0f}米" if language == "zh" else f"{dist:.0f}m"
            else:
                distance_str = f"{dist/1000:.1f}公里" if language == "zh" else f"{dist/1000:.1f}km"

        action_items.append({
            "id": loc["id"],
            "title": loc["name"],
            "subtitle": f"{distance_str} · {loc.get('address', '')[:30]}..." if distance_str else loc.get("address", "")[:40],
            "action": {
                "type": "deep_link",
                "url": f"api:navigate?dest={loc['name']}&lat={loc['lat']}&lng={loc['lng']}"
            }
        })

    components.append({
        "type": "ActionList",
        "widget_id": f"pois_{uuid.uuid4().hex[:8]}",
        "title": list_title,
        "items": action_items,
    })

    return {
        "intent_id": str(uuid.uuid4()),
        "category": "SERVICE",
        "ui_schema_version": "1.0",
        "slots": {"query": query, "results_count": len(locations)},
        "ui_payload": {"components": components}
    }


def build_chat_response(user_text: str, language: str = "zh") -> dict:
    """Build a simple chat/informational response using LLM."""
    # For non-location intents, we still use LLM to generate a helpful response
    # This is a simplified version - you could enhance this with more LLM calls

    title = "回复" if language == "zh" else "Response"
    content = f"您说：'{user_text}'\n\n这个功能正在开发中。Just Now 目前专注于出行和位置服务。" if language == "zh" else \
              f"You said: '{user_text}'\n\nThis feature is under development. Just Now currently focuses on transportation and location services."

    return {
        "intent_id": str(uuid.uuid4()),
        "category": "CHAT",
        "ui_schema_version": "1.0",
        "slots": {"original_query": user_text},
        "ui_payload": {
            "components": [
                {
                    "type": "InfoCard",
                    "widget_id": f"chat_{uuid.uuid4().hex[:8]}",
                    "title": title,
                    "content_md": content,
                    "style": "standard"
                }
            ]
        }
    }


def create_fallback_response(error_message: str, user_text: str) -> dict:
    """Create a fallback UI response when processing fails."""
    return {
        "intent_id": str(uuid.uuid4()),
        "category": "CHAT",
        "ui_schema_version": "1.0",
        "slots": {
            "error": "processing_failed",
            "original_query": user_text[:100]
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


# --- Main Processing Logic ---

async def process_intent_with_lbs(
    text_input: str,
    user_lat: Optional[float] = None,
    user_lng: Optional[float] = None
) -> dict:
    """
    Main processing pipeline:
    1. Extract intent from user text using LLM
    2. Search for locations using Nominatim (if applicable)
    3. Get route using OSRM (if applicable)
    4. Build appropriate response
    """

    # Step 1: Extract intent using LLM
    intent = await extract_intent(text_input)

    intent_type = intent.get("intent_type", "general_chat")
    destination_query = intent.get("destination_query")
    service_type = intent.get("service_type")
    language = intent.get("response_language", "zh")

    logger.info(f"Intent type: {intent_type}, destination: {destination_query}, service: {service_type}")

    # Step 2: Handle based on intent type

    if intent_type == "general_chat" or not destination_query:
        # Non-location intent - return chat response
        return build_chat_response(text_input, language)

    # Step 3: Search for the destination
    locations = await search_location(
        query=destination_query,
        user_lat=user_lat,
        user_lng=user_lng
    )

    if not locations:
        # No locations found
        return build_poi_search_response([], destination_query, user_lat, user_lng, language)

    # Step 4: Check if disambiguation is needed
    # If multiple results are close in relevance/distance, ask user to choose
    if len(locations) > 1:
        first_dist = locations[0].get("distance_meters")
        second_dist = locations[1].get("distance_meters")

        # Check if top results are ambiguous (similar distance or importance)
        needs_disambiguation = False

        if first_dist is not None and second_dist is not None:
            # If second result is within threshold of first, disambiguate
            if second_dist - first_dist < DISAMBIGUATION_DISTANCE_THRESHOLD_METERS:
                needs_disambiguation = True
        else:
            # Without distance info, check if names are distinctly different
            first_imp = locations[0].get("importance", 0)
            second_imp = locations[1].get("importance", 0)
            if abs(first_imp - second_imp) < 0.1:
                needs_disambiguation = True

        if needs_disambiguation:
            return build_disambiguation_response(locations, destination_query, language)

    # Step 5: Use the best location
    best_location = locations[0]

    # Step 6: Get route if user location is available and it's a navigation/ride intent
    route_data = None
    if user_lat is not None and user_lng is not None:
        if intent_type in ("navigation", "ride_hailing"):
            route_data = await get_route(
                start_lat=user_lat,
                start_lng=user_lng,
                end_lat=best_location["lat"],
                end_lng=best_location["lng"],
                profile="driving" if service_type == "taxi" else "walking"
            )

    # Step 7: Build response based on intent type
    if intent_type == "search_poi":
        return build_poi_search_response(locations, destination_query, user_lat, user_lng, language)
    else:
        # Navigation or ride-hailing
        return build_navigation_response(
            user_lat=user_lat,
            user_lng=user_lng,
            dest_location=best_location,
            route_data=route_data,
            service_type=service_type,
            language=language
        )


# --- API Endpoints ---

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

    Now with Real-World LBS Integration:
    - Uses Nominatim for location search (no more hallucinated coordinates)
    - Uses OSRM for route calculation (real driving/walking routes)
    - Handles disambiguation when multiple locations match
    """
    trace_id = str(uuid.uuid4())
    logger.info(f"[{trace_id}] Received request: {request.text_input[:100]}...")
    logger.info(f"[{trace_id}] User location: ({request.current_lat}, {request.current_lng})")

    try:
        # Process with LBS integration
        ui_data = await process_intent_with_lbs(
            text_input=request.text_input,
            user_lat=request.current_lat,
            user_lng=request.current_lng
        )

        # Validate and return response
        response = GenUIResponse.model_validate(ui_data)
        logger.info(f"[{trace_id}] Successfully generated response")
        return response

    except Exception as e:
        logger.error(f"[{trace_id}] Processing error: {e}", exc_info=True)
        fallback = create_fallback_response(str(e), request.text_input)
        return GenUIResponse.model_validate(fallback)


@app.post(
    "/api/v1/voice",
    response_model=GenUIResponse,
    responses={
        422: {"model": ErrorResponse, "description": "Semantic Mismatch"},
        500: {"model": ErrorResponse, "description": "Server Error"},
    },
)
async def process_voice(
    audio: UploadFile = File(...),
    x_device_id: Optional[str] = Header(None, alias="X-Device-Id"),
    current_lat: Optional[float] = Header(None, alias="X-Current-Lat"),
    current_lng: Optional[float] = Header(None, alias="X-Current-Lng"),
):
    """
    Process voice input: transcribe audio using Whisper, then process intent.

    Route B: Record & Upload Architecture
    1. Receive audio file from frontend
    2. Transcribe using local Whisper model
    3. Pass transcribed text to existing intent processing pipeline
    4. Return GenUI response
    """
    trace_id = str(uuid.uuid4())
    logger.info(f"[{trace_id}] Received voice input: {audio.filename}")

    temp_path = None
    try:
        # Step 1: Save uploaded audio to temporary file
        suffix = os.path.splitext(audio.filename or ".wav")[1] or ".wav"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            temp_path = temp_file.name
            content = await audio.read()
            temp_file.write(content)
            logger.info(f"[{trace_id}] Saved audio to {temp_path} ({len(content)} bytes)")

        # Step 2: Transcribe audio using Whisper
        logger.info(f"[{trace_id}] Transcribing audio with Whisper...")
        model = get_whisper_model()
        result = model.transcribe(temp_path, language="zh")
        transcribed_text = result.get("text", "").strip()

        if not transcribed_text:
            logger.warning(f"[{trace_id}] Whisper returned empty transcription")
            fallback = create_fallback_response(
                "无法识别语音内容，请重试。",
                "[语音输入]"
            )
            return GenUIResponse.model_validate(fallback)

        logger.info(f"[{trace_id}] Transcribed text: {transcribed_text}")

        # Step 3: Process intent using existing pipeline
        ui_data = await process_intent_with_lbs(
            text_input=transcribed_text,
            user_lat=current_lat,
            user_lng=current_lng
        )

        response = GenUIResponse.model_validate(ui_data)
        logger.info(f"[{trace_id}] Successfully processed voice input")
        return response

    except Exception as e:
        logger.error(f"[{trace_id}] Voice processing error: {e}", exc_info=True)
        fallback = create_fallback_response(str(e), "[语音输入]")
        return GenUIResponse.model_validate(fallback)

    finally:
        # Clean up temporary file
        if temp_path and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
                logger.info(f"[{trace_id}] Cleaned up temp file: {temp_path}")
            except Exception as e:
                logger.warning(f"[{trace_id}] Failed to delete temp file: {e}")


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    has_api_key = bool(os.getenv("DEEPSEEK_API_KEY") or os.getenv("OPENAI_API_KEY"))

    if os.getenv("DEEPSEEK_API_KEY"):
        model = "deepseek-chat"
        provider = "DeepSeek"
    else:
        model = os.getenv("LLM_MODEL", "deepseek-chat")
        provider = "OpenAI"

    return {
        "status": "healthy",
        "version": "3.1.0",
        "features": {
            "lbs_integration": True,
            "nominatim_search": True,
            "osrm_routing": True,
            "disambiguation": True,
            "whisper_transcription": True,
        },
        "llm_configured": has_api_key,
        "provider": provider if has_api_key else "not configured",
        "model": model if has_api_key else "not configured",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
