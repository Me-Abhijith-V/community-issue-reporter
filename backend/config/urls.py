from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('admin/', admin.site.urls),

    path('api/', include('apps.users.urls')),
    path('api/issues/', include('apps.issues.urls')),
    path('api/', include('apps.notifications.urls')),
    path("authority/", include("apps.authority.urls")),
]

urlpatterns += static(
    settings.MEDIA_URL,
    document_root=settings.MEDIA_ROOT
)