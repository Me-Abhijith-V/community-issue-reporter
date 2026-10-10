import json
from decimal import Decimal

from django.db.models import Q

from rest_framework import generics, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
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

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        description = serializer.validated_data.get("original_description", "").strip()
        photo = request.FILES.get("photo")

        # -------------------------------------------------
        # 1. ENFORCE DESCRIPTION-IMAGE MISMATCH VALIDATION
        # -------------------------------------------------
        # Check if caller already supplied pre-classified validation status
        pre_val = serializer.validated_data.get("ai_validation_status")
        if pre_val == "mismatch":
            reason = (
                serializer.validated_data.get("ai_image_match_reason")
                or "The uploaded photo depicts an unrelated subject or a different issue."
            )
            return Response(
                {
                    "error": "Invalid report: Description and image do not match.",
                    "validation_status": "mismatch",
                    "is_image_match": False,
                    "image_match_reason": reason,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        pre_cat = serializer.validated_data.get("ai_suggested_category")
        pre_sev = serializer.validated_data.get("ai_severity")

        ai_result = None
        # If pre-classified AI results were NOT supplied, run classification with image
        if not (pre_cat and pre_sev) and description:
            lat = serializer.validated_data.get("latitude")
            lng = serializer.validated_data.get("longitude")
            nearby_issues = Issue.objects.none()
            if lat is not None and lng is not None:
                lat_range = Decimal("0.005")
                lng_range = Decimal("0.005")
                nearby_issues = Issue.objects.filter(
                    latitude__gte=lat - lat_range,
                    latitude__lte=lat + lat_range,
                    longitude__gte=lng - lng_range,
                    longitude__lte=lng + lng_range,
                ).order_by("-created_at")[:10]

            nearby_ids = list(nearby_issues.values_list("id", flat=True))

            try:
                ai_result = classify_issue(
                    description,
                    image_file=photo,
                    nearby_issues=list(nearby_issues[:5]),
                    nearby_issue_ids=nearby_ids,
                )
            except Exception:
                ai_result = None

            # Backend enforcement: Reject if mismatch detected
            if ai_result and ai_result.get("ai_success") and ai_result.get("validation_status") == "mismatch":
                reason = (
                    ai_result.get("image_match_reason")
                    or "The uploaded photo depicts an unrelated subject or a different issue."
                )
                return Response(
                    {
                        "error": "Invalid report: Description and image do not match.",
                        "validation_status": "mismatch",
                        "is_image_match": False,
                        "image_match_reason": reason,
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        # -------------------------------------------------
        # 2. SAVE THE ISSUE
        # -------------------------------------------------
        issue = serializer.save(reported_by=request.user)

        # -------------------------------------------------
        # 2b. AUTO-RESOLVE ADDRESS IF MISSING
        # -------------------------------------------------
        if not issue.address and issue.latitude and issue.longitude:
            from .geocode import reverse_geocode
            resolved_addr = reverse_geocode(issue.latitude, issue.longitude)
            if resolved_addr:
                issue.address = resolved_addr

        # -------------------------------------------------
        # 3. APPLY MULTIMODAL AI RESULTS
        # -------------------------------------------------
        if pre_cat and pre_sev:
            issue.category = pre_cat
            issue.ai_suggested_category = pre_cat
            issue.ai_severity = pre_sev
            if serializer.validated_data.get("ai_severity_reason"):
                issue.ai_severity_reason = serializer.validated_data["ai_severity_reason"]
            if serializer.validated_data.get("ai_severity_basis"):
                issue.ai_severity_basis = serializer.validated_data["ai_severity_basis"]
            if serializer.validated_data.get("ai_validation_status"):
                issue.ai_validation_status = serializer.validated_data["ai_validation_status"]
            if serializer.validated_data.get("ai_is_image_match") is not None:
                issue.ai_is_image_match = serializer.validated_data["ai_is_image_match"]
            if serializer.validated_data.get("ai_image_match_reason"):
                issue.ai_image_match_reason = serializer.validated_data["ai_image_match_reason"]
            if serializer.validated_data.get("detected_language"):
                issue.detected_language = serializer.validated_data["detected_language"]
            if serializer.validated_data.get("translated_description"):
                issue.translated_description = serializer.validated_data["translated_description"]
            if serializer.validated_data.get("ai_is_duplicate") is not None:
                issue.ai_is_duplicate = serializer.validated_data["ai_is_duplicate"]
            if serializer.validated_data.get("ai_duplicate_of"):
                issue.ai_duplicate_of = serializer.validated_data["ai_duplicate_of"]
            if serializer.validated_data.get("ai_duplicate_reason"):
                issue.ai_duplicate_reason = serializer.validated_data["ai_duplicate_reason"]
            issue.save()
        elif ai_result and ai_result.get("ai_success"):
            issue.category = ai_result["category"]
            issue.ai_suggested_category = ai_result["category"]
            issue.ai_severity = ai_result["severity"]
            issue.ai_severity_reason = ai_result.get("severity_reason") or ""
            issue.ai_severity_basis = ai_result.get("severity_basis") or "text_only"
            issue.ai_validation_status = ai_result.get("validation_status") or "valid"
            issue.ai_is_image_match = ai_result.get("is_image_match")
            issue.ai_image_match_reason = ai_result.get("image_match_reason") or ""
            issue.detected_language = ai_result.get("detected_language") or "en"
            issue.translated_description = ai_result.get("translated_description") or description
            issue.ai_is_duplicate = ai_result.get("is_duplicate", False)
            dup_id = ai_result.get("duplicate_of")
            if issue.ai_is_duplicate and dup_id:
                try:
                    issue.ai_duplicate_of = Issue.objects.get(id=dup_id)
                except Issue.DoesNotExist:
                    issue.ai_duplicate_of = None
            else:
                issue.ai_duplicate_of = None
            issue.ai_duplicate_reason = ai_result.get("duplicate_reason") or ""
            issue.save()
        else:
            issue.ai_suggested_category = ""
            issue.ai_severity = ""
            issue.ai_severity_reason = ""
            issue.ai_severity_basis = "text_only"
            issue.ai_validation_status = "uncertain"
            issue.ai_is_image_match = None
            issue.ai_image_match_reason = ""
            issue.ai_is_duplicate = None
            issue.ai_duplicate_of = None
            issue.ai_duplicate_reason = ""
            issue.save()

        # -------------------------------------------------
        # 4. GIVE +10 REPUTATION FOR SUBMISSION
        # -------------------------------------------------
        user = request.user
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

        headers = self.get_success_headers(serializer.data)
        out_serializer = self.get_serializer(issue)
        return Response(out_serializer.data, status=status.HTTP_201_CREATED, headers=headers)


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
        Run AI analysis on a description and optional photo before submission.
        Returns: category, severity, severity_basis, severity_reason,
                 validation_status, is_image_match, image_match_reason,
                 detected_language, translated_description,
                 is_duplicate, duplicate_of, duplicate_reason.

    Request body (JSON or multipart/form-data):
        - description: "..."
        - photo: file (optional)
        - nearby_issue_ids: [1, 2, 3] or "1,2,3" (optional)
    """

    parser_classes = [MultiPartParser, FormParser, JSONParser]
    permission_classes = [IsAuthenticated]

    def post(self, request):
        description = request.data.get("description", "").strip()

        if not description:
            return Response(
                {"error": "Description is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        photo = request.FILES.get("photo")

        raw_nearby = request.data.get("nearby_issue_ids", [])
        if isinstance(raw_nearby, str):
            try:
                parsed_json = json.loads(raw_nearby)
                if isinstance(parsed_json, list):
                    raw_nearby = parsed_json
                else:
                    raw_nearby = [raw_nearby]
            except Exception:
                raw_nearby = [x.strip() for x in raw_nearby.split(",") if x.strip()]
        elif not isinstance(raw_nearby, list):
            raw_nearby = []

        try:
            nearby_ids = [int(i) for i in raw_nearby if str(i).strip()]
        except (TypeError, ValueError):
            nearby_ids = []

        try:
            result = classify_issue(
                description,
                nearby_issue_ids=nearby_ids if nearby_ids else None,
                image_file=photo,
            )
        except Exception as e:
            return Response(
                {
                    "error": f"AI classification failed: {str(e)}",
                    "error_type": "unexpected_error",
                    "ai_success": False,
                    "validation_status": "uncertain",
                    "is_image_match": None,
                    "severity_basis": "text_only",
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        if result is None or not result.get("ai_success"):
            error_type = (result or {}).get("error_type", "ai_error")
            error_msg = (result or {}).get("error", "AI service is temporarily unavailable.")
            status_code = (result or {}).get("status_code") or status.HTTP_503_SERVICE_UNAVAILABLE
            return Response(
                {
                    "error": error_msg,
                    "error_type": error_type,
                    "ai_success": False,
                    "validation_status": (result or {}).get("validation_status", "uncertain"),
                    "is_image_match": None,
                    "severity_basis": (result or {}).get("severity_basis", "text_only"),
                },
                status=status_code,
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
                "ai_success": True,
                "category": result["category"],
                "severity": result["severity"],
                "severity_basis": result.get("severity_basis", "text_only"),
                "severity_reason": result.get("severity_reason", ""),
                "validation_status": result.get("validation_status", "valid"),
                "is_image_match": result.get("is_image_match"),
                "image_match_reason": result.get("image_match_reason", ""),
                "detected_language": result["detected_language"],
                "translated_description": result["translated_description"],
                "is_duplicate": result["is_duplicate"],
                "duplicate_of": result["duplicate_of"],
                "duplicate_reason": result["duplicate_reason"],
                "duplicate_issue": duplicate_issue_data,
            },
            status=status.HTTP_200_OK,
        )


class ReverseGeocodeView(APIView):
    """
    GET /api/issues/reverse-geocode/
    Resolves (latitude, longitude) coordinates into a clean human-readable address.
    Query parameters:
        - latitude: float/Decimal
        - longitude: float/Decimal
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        lat = request.query_params.get("latitude")
        lng = request.query_params.get("longitude")

        from .geocode import validate_coordinates, reverse_geocode

        valid = validate_coordinates(lat, lng)
        if not valid:
            return Response(
                {
                    "error": "Invalid or missing coordinates. Latitude must be in [-90, 90], Longitude in [-180, 180].",
                    "address": "",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        f_lat, f_lng = valid
        address = reverse_geocode(f_lat, f_lng)

        return Response(
            {
                "latitude": f_lat,
                "longitude": f_lng,
                "address": address,
                "status": "success" if address else "unavailable",
            },
            status=status.HTTP_200_OK,
        )