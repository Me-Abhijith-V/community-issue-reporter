from decimal import Decimal

from django.db.models import Q

from rest_framework import generics, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Issue, IssueUpvote, StatusUpdate
from .serializers import IssueSerializer, StatusUpdateSerializer
from .permissions import IsAuthority
from .ai_classifier import classify_issue, detect_duplicate_issue

from apps.notifications.services import (
    create_status_notification,
    notify_upvoters_of_status_change,
)
from apps.users.models import ReputationLog


class IssueListCreateView(generics.ListCreateAPIView):
    """
    GET:
        Return all issues. Supports filtering by category,
        status, severity, search, mine, and location radius.

    POST:
        Create a new issue for the currently authenticated user.

        AI automatically:
        - detects language
        - translates the description
        - suggests category
        - determines severity
        - checks for nearby duplicate issues
    """

    queryset = Issue.objects.all().select_related("reported_by")
    serializer_class = IssueSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        queryset = Issue.objects.all().select_related(
            "reported_by",
            "ai_duplicate_of",
        )

        # -------------------------------------------------
        # Filter by category
        # -------------------------------------------------
        category = self.request.query_params.get("category")

        if category:
            queryset = queryset.filter(category=category)

        # -------------------------------------------------
        # Filter by status
        # -------------------------------------------------
        issue_status = self.request.query_params.get("status")

        if issue_status:
            queryset = queryset.filter(status=issue_status)

        # -------------------------------------------------
        # Filter by AI severity
        # -------------------------------------------------
        severity = self.request.query_params.get("severity")

        if severity:
            queryset = queryset.filter(ai_severity=severity)

        # -------------------------------------------------
        # Search descriptions
        # -------------------------------------------------
        search = self.request.query_params.get("search")

        if search:
            queryset = queryset.filter(
                Q(original_description__icontains=search)
                | Q(translated_description__icontains=search)
            )

        # -------------------------------------------------
        # Show only issues reported by logged-in user
        # -------------------------------------------------
        mine = self.request.query_params.get("mine")

        if mine and mine.lower() == "true":
            queryset = queryset.filter(
                reported_by=self.request.user
            )

        # -------------------------------------------------
        # Show only issues upvoted by logged-in user
        # -------------------------------------------------
        upvoted = self.request.query_params.get("upvoted")

        if upvoted and upvoted.lower() == "true":
            queryset = queryset.filter(
                upvotes__user=self.request.user
            )

        # -------------------------------------------------
        # Filter issues near a location
        # -------------------------------------------------
        latitude = self.request.query_params.get("latitude")
        longitude = self.request.query_params.get("longitude")
        radius = self.request.query_params.get("radius")

        if latitude and longitude:
            try:
                latitude = Decimal(latitude)
                longitude = Decimal(longitude)

                # Default radius = 5 km
                radius = (
                    Decimal(radius)
                    if radius
                    else Decimal("5")
                )

                # Approximate conversion:
                # 1 degree latitude ≈ 111 km
                latitude_range = radius / Decimal("111")
                longitude_range = radius / Decimal("111")

                queryset = queryset.filter(
                    latitude__gte=latitude - latitude_range,
                    latitude__lte=latitude + latitude_range,
                    longitude__gte=longitude - longitude_range,
                    longitude__lte=longitude + longitude_range,
                )

            except (
                ValueError,
                TypeError,
                ArithmeticError,
            ):
                pass

        # -------------------------------------------------
        # Ordering
        # -------------------------------------------------
        ordering = self.request.query_params.get("ordering")

        allowed_ordering = {
            "created_at",
            "-created_at",
            "updated_at",
            "-updated_at",
            "upvote_count",
            "-upvote_count",
            "category",
            "-category",
            "status",
            "-status",
            "ai_severity",
            "-ai_severity",
        }

        if ordering in allowed_ordering:
            queryset = queryset.order_by(ordering)
        else:
            queryset = queryset.order_by("-created_at")

        return queryset

    def perform_create(self, serializer):
        # -------------------------------------------------
        # 1. SAVE THE ISSUE
        # -------------------------------------------------
        issue = serializer.save(
            reported_by=self.request.user
        )

        description = issue.original_description

        # -------------------------------------------------
        # 2. FIND NEARBY ISSUE IDs FOR DUPLICATE CHECK
        # -------------------------------------------------
        nearby_issues = Issue.objects.none()

        if (
            issue.latitude is not None
            and issue.longitude is not None
        ):
            latitude_range = Decimal("0.005")   # ~500 m
            longitude_range = Decimal("0.005")

            nearby_issues = (
                Issue.objects.filter(
                    latitude__gte=(
                        issue.latitude - latitude_range
                    ),
                    latitude__lte=(
                        issue.latitude + latitude_range
                    ),
                    longitude__gte=(
                        issue.longitude - longitude_range
                    ),
                    longitude__lte=(
                        issue.longitude + longitude_range
                    ),
                )
                .exclude(id=issue.id)
                .order_by("-created_at")
            )

        nearby_issue_ids = list(
            nearby_issues.values_list("id", flat=True)[:10]
        )

        # -------------------------------------------------
        # 3. FULL AI CLASSIFICATION (language, translate,
        #    category, severity, duplicate detection)
        # -------------------------------------------------
        if description:
            try:
                ai_result = classify_issue(
                    description,
                    nearby_issue_ids=nearby_issue_ids,
                )
            except Exception:
                ai_result = None

            if ai_result:
                # AI category
                category = ai_result.get("category")
                if category:
                    issue.ai_suggested_category = category
                    issue.category = category

                # AI severity
                severity = ai_result.get("severity")
                if severity:
                    issue.ai_severity = severity

                # Detected language
                detected_language = ai_result.get("detected_language")
                if detected_language:
                    issue.detected_language = detected_language

                # English translation
                translated_description = ai_result.get(
                    "translated_description"
                )
                if translated_description:
                    issue.translated_description = translated_description

                # Duplicate detection
                is_duplicate = ai_result.get("is_duplicate", False)
                issue.ai_is_duplicate = is_duplicate

                duplicate_id = ai_result.get("duplicate_of")
                if is_duplicate and duplicate_id:
                    try:
                        issue.ai_duplicate_of = Issue.objects.get(
                            id=duplicate_id
                        )
                    except Issue.DoesNotExist:
                        issue.ai_duplicate_of = None
                else:
                    issue.ai_duplicate_of = None

                # Duplicate reason (text explanation)
                duplicate_reason = ai_result.get("duplicate_reason")
                issue.ai_duplicate_reason = duplicate_reason or ""

        # -------------------------------------------------
        # 4. SAVE ALL AI RESULTS
        # -------------------------------------------------
        issue.save()

        # -------------------------------------------------
        # 5. GIVE +10 REPUTATION FOR SUBMISSION
        # -------------------------------------------------
        user = self.request.user

        already_awarded = ReputationLog.objects.filter(
            user=user,
            related_issue=issue,
            reason="submitted",
        ).exists()

        if not already_awarded:
            user.reputation_score = min(
                100,
                user.reputation_score + 10,
            )

            if user.reputation_score <= 30:
                user.reputation_level = "low"
            elif user.reputation_score <= 60:
                user.reputation_level = "normal"
            elif user.reputation_score <= 80:
                user.reputation_level = "trusted"
            else:
                user.reputation_level = "highly_trusted"

            user.save(
                update_fields=[
                    "reputation_score",
                    "reputation_level",
                ]
            )

            ReputationLog.objects.create(
                user=user,
                change=10,
                reason="submitted",
                related_issue=issue,
            )


class IssueDetailView(generics.RetrieveAPIView):
    """
    GET:
        Return details of a single issue.
    """

    queryset = Issue.objects.all().select_related(
        "reported_by",
        "ai_duplicate_of",
    )

    serializer_class = IssueSerializer
    permission_classes = [IsAuthenticated]


class IssueUpvoteView(APIView):
    """
    POST:
        Add an upvote to an issue.

    DELETE:
        Remove the user's upvote.
    """

    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        try:
            issue = Issue.objects.get(pk=pk)

        except Issue.DoesNotExist:
            return Response(
                {"error": "Issue not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # -------------------------------------------------
        # Check whether user already upvoted
        # -------------------------------------------------
        existing_upvote = IssueUpvote.objects.filter(
            issue=issue,
            user=request.user,
        ).exists()

        if existing_upvote:
            return Response(
                {
                    "error": (
                        "You have already upvoted "
                        "this issue."
                    ),
                    "upvoted": True,
                    "upvote_count": issue.upvote_count,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # -------------------------------------------------
        # Create upvote
        # -------------------------------------------------
        IssueUpvote.objects.create(
            issue=issue,
            user=request.user,
        )

        issue.upvote_count += 1

        issue.save(
            update_fields=["upvote_count"]
        )

        reputation_awarded = False

        # -------------------------------------------------
        # Award +5 reputation at 5 upvotes
        # -------------------------------------------------
        if issue.upvote_count == 5:
            already_awarded = ReputationLog.objects.filter(
                user=issue.reported_by,
                related_issue=issue,
                reason="upvoted_5",
            ).exists()

            if not already_awarded:
                user = issue.reported_by

                user.reputation_score = min(
                    100,
                    user.reputation_score + 5,
                )

                if user.reputation_score <= 30:
                    user.reputation_level = "low"
                elif user.reputation_score <= 60:
                    user.reputation_level = "normal"
                elif user.reputation_score <= 80:
                    user.reputation_level = "trusted"
                else:
                    user.reputation_level = "highly_trusted"

                user.save(
                    update_fields=[
                        "reputation_score",
                        "reputation_level",
                    ]
                )

                ReputationLog.objects.create(
                    user=user,
                    change=5,
                    reason="upvoted_5",
                    related_issue=issue,
                )

                reputation_awarded = True

        return Response(
            {
                "message": "Issue upvoted successfully.",
                "issue_id": issue.id,
                "upvote_count": issue.upvote_count,
                "upvoted": True,
                "reputation_awarded": reputation_awarded,
            },
            status=status.HTTP_201_CREATED,
        )

    def delete(self, request, pk):
        try:
            issue = Issue.objects.get(pk=pk)

        except Issue.DoesNotExist:
            return Response(
                {"error": "Issue not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        try:
            upvote = IssueUpvote.objects.get(
                issue=issue,
                user=request.user,
            )

        except IssueUpvote.DoesNotExist:
            return Response(
                {
                    "error": (
                        "You have not upvoted "
                        "this issue."
                    ),
                    "upvoted": False,
                    "upvote_count": issue.upvote_count,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # -------------------------------------------------
        # Remove upvote
        # -------------------------------------------------
        upvote.delete()

        issue.upvote_count = max(
            0,
            issue.upvote_count - 1,
        )

        issue.save(
            update_fields=["upvote_count"]
        )

        return Response(
            {
                "message": "Upvote removed successfully.",
                "issue_id": issue.id,
                "upvote_count": issue.upvote_count,
                "upvoted": False,
            },
            status=status.HTTP_200_OK,
        )


class IssueStatusUpdateView(APIView):
    """
    POST:
        Update the status of an issue.

    Only authority users can update issue status.
    """

    permission_classes = [IsAuthority]

    def post(self, request, pk):
        try:
            issue = Issue.objects.get(pk=pk)

        except Issue.DoesNotExist:
            return Response(
                {"error": "Issue not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        new_status = request.data.get("new_status")
        note = request.data.get("note", "")

        valid_statuses = dict(
            Issue.STATUS_CHOICES
        )

        # -------------------------------------------------
        # Validate status
        # -------------------------------------------------
        if new_status not in valid_statuses:
            return Response(
                {
                    "error": "Invalid status.",
                    "valid_statuses": list(
                        valid_statuses.keys()
                    ),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        old_status = issue.status

        # -------------------------------------------------
        # Prevent same status
        # -------------------------------------------------
        if old_status == new_status:
            return Response(
                {
                    "error": (
                        "Issue is already in "
                        "this status."
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # -------------------------------------------------
        # Forward-only status transition
        #
        # reported -> in_progress
        # in_progress -> resolved
        # resolved -> closed
        # -------------------------------------------------
        status_order = {
            "reported": 0,
            "in_progress": 1,
            "resolved": 2,
            "closed": 3,
        }

        if (
            old_status in status_order
            and new_status in status_order
        ):
            if (
                status_order[new_status]
                <= status_order[old_status]
            ):
                return Response(
                    {
                        "error": (
                            "Issue status can only "
                            "move forward."
                        ),
                        "current_status": old_status,
                        "requested_status": new_status,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        # -------------------------------------------------
        # Update issue status
        # -------------------------------------------------
        issue.status = new_status

        issue.save(
            update_fields=[
                "status",
                "updated_at",
            ]
        )

        # -------------------------------------------------
        # Award/deduct reputation based on status
        # -------------------------------------------------
        reporter = issue.reported_by

        if new_status == "resolved":
            already_resolved = ReputationLog.objects.filter(
                user=reporter,
                related_issue=issue,
                reason="resolved",
            ).exists()

            if not already_resolved:
                reporter.reputation_score = min(
                    100,
                    reporter.reputation_score + 20,
                )

                if reporter.reputation_score <= 30:
                    reporter.reputation_level = "low"
                elif reporter.reputation_score <= 60:
                    reporter.reputation_level = "normal"
                elif reporter.reputation_score <= 80:
                    reporter.reputation_level = "trusted"
                else:
                    reporter.reputation_level = "highly_trusted"

                reporter.save(
                    update_fields=[
                        "reputation_score",
                        "reputation_level",
                    ]
                )

                ReputationLog.objects.create(
                    user=reporter,
                    change=20,
                    reason="resolved",
                    related_issue=issue,
                )

        # -------------------------------------------------
        # Create status history
        # -------------------------------------------------
        status_update = StatusUpdate.objects.create(
            issue=issue,
            updated_by=request.user,
            old_status=old_status,
            new_status=new_status,
            note=note,
        )

        # -------------------------------------------------
        # Send notification to reporter
        # -------------------------------------------------
        create_status_notification(
            issue=issue,
            old_status=old_status,
            new_status=new_status,
        )

        # -------------------------------------------------
        # Send notification to upvoters (excluding reporter)
        # -------------------------------------------------
        try:
            notify_upvoters_of_status_change(
                issue=issue,
                old_status=old_status,
                new_status=new_status,
            )
        except Exception as e:
            print(f"[Notifications] Upvoter notify failed: {e}")

        return Response(
            {
                "message": (
                    "Issue status updated successfully."
                ),
                "issue": issue.id,
                "old_status": old_status,
                "new_status": new_status,
                "note": status_update.note,
                "updated_by": request.user.full_name,
                "timestamp": status_update.timestamp,
            },
            status=status.HTTP_200_OK,
        )


class StatusHistoryView(generics.ListAPIView):
    """
    GET:
        Return the complete status history
        of an issue.
    """

    serializer_class = StatusUpdateSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        issue_id = self.kwargs["issue_id"]

        return (
            StatusUpdate.objects.filter(
                issue_id=issue_id
            )
            .select_related("updated_by")
            .order_by("timestamp")
        )


class IssueMapView(generics.ListAPIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        issues = Issue.objects.all().select_related("reported_by")

        data = []

        for issue in issues:
            if issue.latitude is None or issue.longitude is None:
                continue

            reporter = issue.reported_by

            data.append({
                "id": issue.id,
                "category": issue.category,
                "status": issue.status,
                "ai_severity": issue.ai_severity,
                "upvote_count": issue.upvote_count,
                "latitude": float(issue.latitude),
                "longitude": float(issue.longitude),
                "created_at": issue.created_at,
                "reporter_reputation_score": reporter.reputation_score,
                "reporter_reputation_level": reporter.reputation_level,
            })

        return Response(data)


class ClassifyIssueView(APIView):
    """
    POST:
        Run AI analysis on a description before submission.
        Returns: category, severity, detected_language,
                 translated_description, is_duplicate,
                 duplicate_of, duplicate_reason.

    Request body:
        {
            "description": "...",
            "nearby_issue_ids": [1, 2, 3]   (optional)
        }
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        description = request.data.get("description", "").strip()

        if not description:
            return Response(
                {"error": "Description is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        nearby_ids = request.data.get("nearby_issue_ids", [])

        if not isinstance(nearby_ids, list):
            nearby_ids = []

        # Validate IDs are integers
        try:
            nearby_ids = [int(i) for i in nearby_ids]
        except (TypeError, ValueError):
            nearby_ids = []

        try:
            result = classify_issue(
                description,
                nearby_issue_ids=nearby_ids if nearby_ids else None,
            )
        except Exception as e:
            return Response(
                {"error": f"AI classification failed: {str(e)}"},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        if result is None:
            return Response(
                {"error": "AI service is temporarily unavailable."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        # If duplicate found, get the duplicate issue details
        duplicate_issue_data = None
        if result.get("is_duplicate") and result.get("duplicate_of"):
            try:
                dup_issue = Issue.objects.get(
                    id=result["duplicate_of"]
                )
                duplicate_issue_data = {
                    "id": dup_issue.id,
                    "category": dup_issue.category,
                    "status": dup_issue.status,
                    "original_description": dup_issue.original_description,
                    "translated_description": dup_issue.translated_description,
                    "upvote_count": dup_issue.upvote_count,
                    "created_at": dup_issue.created_at,
                    "latitude": float(dup_issue.latitude),
                    "longitude": float(dup_issue.longitude),
                }
            except Issue.DoesNotExist:
                pass

        return Response(
            {
                "category": result["category"],
                "severity": result["severity"],
                "detected_language": result["detected_language"],
                "translated_description": result["translated_description"],
                "is_duplicate": result["is_duplicate"],
                "duplicate_of": result["duplicate_of"],
                "duplicate_reason": result["duplicate_reason"],
                "duplicate_issue": duplicate_issue_data,
            },
            status=status.HTTP_200_OK,
        )