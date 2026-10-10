"""
Reverse geocoding adapter for the authority panel.
Delegates to the shared apps.issues.geocode implementation.
"""

from apps.issues.geocode import (
    clear_cache,
    format_address_from_osm_data,
    reverse_geocode,
    resolve_and_save_issue_address,
    validate_coordinates,
)


def reverse_geocode_cached(lat: float, lng: float) -> str:
    """
    Return a short human-readable address for (lat, lng).
    Delegates to shared reverse_geocode. Returns empty string if resolution fails (never raw coordinates).
    """
    return reverse_geocode(lat, lng)
