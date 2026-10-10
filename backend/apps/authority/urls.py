from django.urls import path
from . import views

app_name = "authority"

urlpatterns = [
    path("", views.dashboard, name="dashboard"),
    path("login/", views.authority_login, name="login"),
    path("logout/", views.authority_logout, name="logout"),

    path("issues/", views.issue_list, name="issues"),
    path("issues/<int:pk>/", views.issue_detail, name="issue-detail"),
    path("issues/<int:pk>/associate-duplicate/", views.associate_duplicate, name="associate-duplicate"),

    path("map/", views.authority_map, name="map"),

    path("users/", views.user_list, name="users"),
    path("users/<int:pk>/approve/", views.approve_user, name="approve-user"),
    path("users/<int:pk>/reject/", views.reject_user, name="reject-user"),

    # Citizen registrations management
    path("registrations/", views.registration_list, name="registrations"),
    path("registrations/<int:pk>/", views.registration_detail, name="registration-detail"),
    path("registrations/<int:pk>/approve/", views.approve_registration, name="approve-registration"),
    path("registrations/<int:pk>/reject/", views.reject_registration, name="reject-registration"),
]