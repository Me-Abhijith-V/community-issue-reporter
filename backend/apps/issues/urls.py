from django.urls import path

from .views import (
    IssueListCreateView,
    IssueDetailView,
    IssueUpvoteView,
    IssueStatusUpdateView,
    StatusHistoryView,
    IssueMapView,
    ClassifyIssueView,
    ReverseGeocodeView,
)

urlpatterns = [
    path(
        '',
        IssueListCreateView.as_view(),
        name='issue-list-create'
    ),

    path(
        'reverse-geocode/',
        ReverseGeocodeView.as_view(),
        name='reverse-geocode'
    ),

    path(
        'map/',
        IssueMapView.as_view(),
        name='issue-map'
    ),

    path(
        'classify/',
        ClassifyIssueView.as_view(),
        name='issue-classify'
    ),

    path(
        '<int:pk>/',
        IssueDetailView.as_view(),
        name='issue-detail'
    ),

    path(
        '<int:pk>/upvote/',
        IssueUpvoteView.as_view(),
        name='issue-upvote'
    ),

    path(
        '<int:pk>/status/',
        IssueStatusUpdateView.as_view(),
        name='issue-status-update'
    ),

    path(
        '<int:issue_id>/status-history/',
        StatusHistoryView.as_view(),
        name='status_history'
    ),
]