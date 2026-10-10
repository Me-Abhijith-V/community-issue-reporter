"""
Shared, robust reverse-geocoding service for Community Issue Tracker.

Features:
- Validates latitude (-90 to +90) and longitude (-180 to +180).
- In-memory cache by rounded coordinates (~11m precision).
- Complies with Nominatim usage policy (configurable User-Agent, bounded rate limits).
- Bounded retries (up to 2 attempts) with timeout & backoff.
- Produces clean, concise human-readable addresses.
- Returns empty string on failure (NEVER raw coordinates!).
"""

import logging
import os
import time
from decimal import Decimal
from typing import Optional, Tuple

import requests
from django.conf import settings

logger = logging.getLogger(__name__)

# Cache of (rounded_lat, rounded_lng) -> address string
_cache: dict[tuple[float, float], str] = {}

# Time of last external HTTP request to respect provider rate limits (>= 1.0s gap)
_last_request_time: float = 0.0

DEFAULT_USER_AGENT = "CommunityIssueTracker/1.0 (civic-issue-reporter; contact: civic-support@local.gov)"
DEFAULT_NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse"


def get_nominatim_url() -> str:
    return getattr(
        settings,
        "NOMINATIM_URL",
        os.environ.get("NOMINATIM_URL", DEFAULT_NOMINATIM_URL),
    )


def get_user_agent() -> str:
    return getattr(
        settings,
        "GEOCODING_USER_AGENT",
        os.environ.get("GEOCODING_USER_AGENT", DEFAULT_USER_AGENT),
    )


def validate_coordinates(lat: any, lng: any) -> Optional[Tuple[float, float]]:
    """
    Validate and convert latitude and longitude to floats within valid bounds.
    Latitude: [-90.0, 90.0], Longitude: [-180.0, 180.0]
    """
    if lat is None or lng is None:
        return None

    try:
        if isinstance(lat, Decimal):
            f_lat = float(lat)
        else:
            f_lat = float(str(lat).strip())

        if isinstance(lng, Decimal):
            f_lng = float(lng)
        else:
            f_lng = float(str(lng).strip())

        if (
            -90.0 <= f_lat <= 90.0
            and -180.0 <= f_lng <= 180.0
            and not (abs(f_lat) < 0.00001 and abs(f_lng) < 0.00001)
        ):
            return (f_lat, f_lng)
        logger.warning(f"Coordinates out of bounds or uninitialized: lat={f_lat}, lng={f_lng}")
        return None
    except (ValueError, TypeError):
        return None


def round_coords(lat: float, lng: float, decimals: int = 4) -> Tuple[float, float]:
    """Round to 4 decimal places (~11 meters) to maximise cache hits."""
    return (round(lat, decimals), round(lng, decimals))


def clear_cache():
    """Clear in-memory geocoding cache (useful for testing)."""
    global _cache
    _cache.clear()


def format_address_from_osm_data(data: dict) -> str:
    """Format Nominatim OSM response into a concise human-readable address."""
    addr = data.get("address", {})
    parts = []

    # 1. Road / Street
    road = (
        addr.get("road")
        or addr.get("pedestrian")
        or addr.get("path")
        or addr.get("footway")
        or addr.get("cycleway")
        or addr.get("street")
    )
    if road:
        parts.append(str(road).strip())

    # 2. Suburb / Quarter / Locality
    suburb = (
        addr.get("suburb")
        or addr.get("quarter")
        or addr.get("neighbourhood")
        or addr.get("residential")
        or addr.get("commercial")
    )
    if suburb and suburb not in parts:
        parts.append(str(suburb).strip())

    # 3. City / Town / Village / Municipality
    city = (
        addr.get("city")
        or addr.get("town")
        or addr.get("village")
        or addr.get("municipality")
        or addr.get("county")
    )
    if city and city not in parts:
        parts.append(str(city).strip())

    # 4. State / District (if no city or for regional context)
    state = addr.get("state") or addr.get("district")
    if state and len(parts) < 2 and state not in parts:
        parts.append(str(state).strip())

    if parts:
        return ", ".join(parts[:3])

    # Fallback to display_name snippet if specific components absent
    display_name = data.get("display_name", "")
    if display_name:
        components = [c.strip() for c in display_name.split(",") if c.strip()]
        return ", ".join(components[:3]) if components else display_name[:80]

    return ""


def reverse_geocode(lat: any, lng: any, max_retries: int = 2, timeout: float = 4.0) -> str:
    """
    Reverse geocode coordinates into a short human-readable address.

    Returns:
        A human-readable address string on success, or "" on failure.
        NEVER returns raw coordinates.
    """
    global _last_request_time

    valid = validate_coordinates(lat, lng)
    if not valid:
        return ""

    f_lat, f_lng = valid
    key = round_coords(f_lat, f_lng)

    # Return cached address if available
    if key in _cache:
        return _cache[key]

    url = get_nominatim_url()
    headers = {"User-Agent": get_user_agent()}
    params = {
        "lat": key[0],
        "lon": key[1],
        "format": "jsonv2",
        "zoom": 17,
        "addressdetails": 1,
    }

    address_result = ""
    for attempt in range(1, max_retries + 1):
        try:
            # Respect rate limit (minimum 1.0 second between consecutive calls to Nominatim)
            elapsed = time.time() - _last_request_time
            if elapsed < 1.0:
                time.sleep(1.0 - elapsed)

            _last_request_time = time.time()

            resp = requests.get(url, params=params, headers=headers, timeout=timeout)

            if resp.status_code == 200:
                data = resp.json()
                formatted = format_address_from_osm_data(data)
                if formatted:
                    address_result = formatted
                    _cache[key] = address_result
                    return address_result
                break
            elif resp.status_code == 429:
                logger.warning(f"Nominatim rate limit hit on attempt {attempt}/{max_retries}")
                time.sleep(1.0 * attempt)
            else:
                logger.warning(f"Nominatim HTTP {resp.status_code} on attempt {attempt}")
        except (requests.RequestException, Exception) as exc:
            logger.warning(f"Nominatim request error on attempt {attempt}/{max_retries}: {exc}")
            if attempt < max_retries:
                time.sleep(0.5 * attempt)

    return address_result


def resolve_and_save_issue_address(issue, force: bool = False) -> str:
    """
    Safely resolve the address for an Issue instance and persist it if found.
    Does not make an HTTP request if issue.address is already set and force is False.
    """
    if issue.address and not force:
        return issue.address

    if not (issue.latitude and issue.longitude):
        return ""

    resolved = reverse_geocode(issue.latitude, issue.longitude)
    if resolved:
        issue.address = resolved
        issue.save(update_fields=["address"])
        return resolved

    return issue.address or ""


# Backward-compatible alias
reverse_geocode_nominatim = reverse_geocode
