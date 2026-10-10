from django.urls import path

from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    RegisterView,
    UserProfileView,
    FCMTokenView,
    ReputationView,
    ApproveUserView,
    RejectUserView,
    RegistrationListView,
    RegistrationDetailView,
    CustomTokenObtainPairView,
)


urlpatterns = [
    # Registration
    path(
        'auth/register/',
        RegisterView.as_view(),
        name='register'
    ),

    # Login — custom view that returns pending/rejected error codes
    path(
        'auth/login/',
        CustomTokenObtainPairView.as_view(),
        name='login'
    ),

    # Refresh access token
    path(
        'auth/token/refresh/',
        TokenRefreshView.as_view(),
        name='token_refresh'
    ),

    # Current user's profile
    path(
        'auth/me/',
        UserProfileView.as_view(),
        name='user_profile'
    ),

    # FCM push notification token
    path(
        'auth/me/fcm-token/',
        FCMTokenView.as_view(),
        name='fcm_token'
    ),

    # Reputation
    path(
        'users/me/reputation/',
        ReputationView.as_view(),
        name='user_reputation'
    ),

    # Authority approval / rejection
    path(
        'users/<int:pk>/approve/',
        ApproveUserView.as_view(),
        name='user_approve'
    ),
    path(
        'users/<int:pk>/reject/',
        RejectUserView.as_view(),
        name='user_reject'
    ),

    # Dedicated registration management endpoints
    path(
        'users/registrations/',
        RegistrationListView.as_view(),
        name='registration_list'
    ),
    path(
        'users/registrations/<int:pk>/',
        RegistrationDetailView.as_view(),
        name='registration_detail'
    ),
    path(
        'users/registrations/<int:pk>/approve/',
        ApproveUserView.as_view(),
        name='registration_approve'
    ),
    path(
        'users/registrations/<int:pk>/reject/',
        RejectUserView.as_view(),
        name='registration_reject'
    ),
]