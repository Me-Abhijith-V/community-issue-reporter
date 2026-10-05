from django.urls import path

from .views import (
    NotificationListView,
    NotificationMarkReadView,
    FCMTokenUpdateView,
)

urlpatterns = [
    path(
        'notifications/',
        NotificationListView.as_view(),
        name='notification-list'
    ),
    path(
        'notifications/<int:pk>/read/',
        NotificationMarkReadView.as_view(),
        name='notification-mark-read'
    ),
    path(
        'notifications/device-token/',
        FCMTokenUpdateView.as_view(),
        name='notification-device-token'
    ),
]