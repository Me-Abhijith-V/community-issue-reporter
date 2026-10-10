from apps.users.models import CustomUser


def authority_context(request):
    """
    Context processor providing authority panel context like pending registration count
    and shared map tile configuration.
    Available across all authority templates.
    """
    from django.conf import settings

    pending_count = 0
    if request.user.is_authenticated and (
        request.user.is_superuser or getattr(request.user, "role", None) == "authority"
    ):
        pending_count = CustomUser.objects.filter(
            role="citizen", approval_status="pending"
        ).count()

    return {
        "pending_registrations_count": pending_count,
        "map_tile_url": getattr(
            settings,
            "MAP_TILE_URL",
            "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}",
        ),
        "map_tile_attribution": getattr(
            settings,
            "MAP_TILE_ATTRIBUTION",
            "Tiles &copy; Esri &mdash; Source: Esri, DeLorme, NAVTEQ, USGS",
        ),
        "map_tile_topo_url": getattr(
            settings,
            "MAP_TILE_TOPO_URL",
            "https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}",
        ),
        "map_tile_dark_url": getattr(
            settings,
            "MAP_TILE_DARK_URL",
            "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}",
        ),
        "carto_api_key": getattr(settings, "CARTO_API_KEY", ""),
    }

