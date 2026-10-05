"""
Lightweight reverse geocoding helper for the authority panel.

Uses Nominatim (OpenStreetMap) — free, no API key required.
Results are cached in a module-level dict so each unique
lat/lng is only fetched once per server process.
"""

import requests

_cache: dict[tuple[float, float], str] = {}

_NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse"
_HEADERS = {
    "User-Agent": "CommunityIssueTracker-AuthorityPanel/1.0",
}


def _round_coords(lat: float, lng: float) -> tuple[float, float]:
    """Round to 4 decimal places (~11 m) to maximise cache hits."""
    return (round(lat, 4), round(lng, 4))


def reverse_geocode_cached(lat: float, lng: float) -> str:
    """
    Return a short human-readable address for (lat, lng).

    Falls back to "lat, lng" string if the lookup fails.
    """
    key = _round_coords(lat, lng)

    if key in _cache:
        return _cache[key]

    try:
        resp = requests.get(
            _NOMINATIM_URL,
            params={
                "lat": key[0],
                "lon": key[1],
                "format": "json",
                "zoom": 16,           # street-level detail
                "addressdetails": 1,
            },
            headers=_HEADERS,
            timeout=4,
        )

        if resp.ok:
            data = resp.json()
            addr = data.get("address", {})

            # Build a concise address: road, suburb/quarter, city
            parts = []
            road = addr.get("road") or addr.get("pedestrian") or addr.get("path")
            if road:
                parts.append(road)
            suburb = (
                addr.get("suburb")
                or addr.get("quarter")
                or addr.get("neighbourhood")
            )
            if suburb:
                parts.append(suburb)
            city = (
                addr.get("city")
                or addr.get("town")
                or addr.get("village")
                or addr.get("county")
            )
            if city:
                parts.append(city)

            result = ", ".join(parts) if parts else data.get("display_name", "")[:80]
        else:
            result = ""

    except Exception:
        result = ""

    if not result:
        result = f"{key[0]:.5f}, {key[1]:.5f}"

    _cache[key] = result
    return result
