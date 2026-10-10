from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from rest_framework import serializers, status
from rest_framework.pagination import PageNumberPagination
from rest_framework.permissions import IsAuthenticated, IsAdminUser
from rest_framework.response import Response
from rest_framework.views import APIView

from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework_simplejwt.views import TokenObtainPairView

from .models import CustomUser, ReputationLog
from .permissions import IsAuthorityOrAdmin
from .serializers import (
    UserRegistrationSerializer,
    UserSerializer,
    CitizenRegistrationSerializer,
    FCMTokenSerializer,
    ReputationLogSerializer,
)
from apps.notifications.services import (
    create_registration_approval_notification,
    create_registration_rejection_notification,
)


# ─────────────────────────────────────────────────────────────
# Custom JWT login — blocks pending / rejected citizens
# ─────────────────────────────────────────────────────────────

class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    """
    Extends the default JWT serializer so that a pending or
    rejected citizen gets a specific error_code instead of the
    generic 'No active account' message.
    """

    def validate(self, attrs):
        email = attrs.get(self.username_field, "").lower().strip()
        password = attrs.get("password", "")

        # Look up the user by email regardless of is_active so we
        # can distinguish pending/rejected from wrong credentials.
        try:
            user = CustomUser.objects.get(email=email)
        except CustomUser.DoesNotExist:
            # Fall through — parent will raise the standard error.
            return super().validate(attrs)

        # Correct password but account is not approved?
        if user.check_password(password):
            if user.approval_status == "pending":
                raise serializers.ValidationError(
                    {
                        "detail": (
                            "Your registration is awaiting authority approval. "
                            "You will be able to log in once approved."
                        ),
                        "error_code": "pending_approval",
                        "approval_status": "pending",
                    }
                )
            if user.approval_status == "rejected":
                reason_note = (
                    f" Reason: {user.rejection_reason}."
                    if user.rejection_reason
                    else ""
                )
                raise serializers.ValidationError(
                    {
                        "detail": (
                            f"Your registration has been rejected by the authority.{reason_note} "
                            "Please contact the authority if you believe this is a mistake or wish to reapply."
                        ),
                        "error_code": "registration_rejected",
                        "approval_status": "rejected",
                        "rejection_reason": user.rejection_reason or "",
                    }
                )

        data = super().validate(attrs)
        data["user"] = {
            "id": self.user.id,
            "email": self.user.email,
            "full_name": self.user.full_name,
            "role": self.user.role,
            "approval_status": self.user.approval_status,
        }
        return data


class CustomTokenObtainPairView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer

    def post(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        try:
            serializer.is_valid(raise_exception=True)
        except serializers.ValidationError as e:
            detail = e.detail
            if isinstance(detail, dict) and "error_code" in detail:
                flattened = {}
                for k, v in detail.items():
                    if isinstance(v, (list, tuple)) and len(v) == 1:
                        flattened[k] = str(v[0])
                    else:
                        flattened[k] = v
                return Response(flattened, status=status.HTTP_401_UNAUTHORIZED)
            raise e
        return Response(serializer.validated_data, status=status.HTTP_200_OK)


# ─────────────────────────────────────────────────────────────
# Registration
# ─────────────────────────────────────────────────────────────

class RegisterView(APIView):
    """
    Register a new citizen account.
    The account starts as PENDING and cannot log in until
    the authority approves it.
    """

    permission_classes = []

    @transaction.atomic
    def post(self, request):
        serializer = UserRegistrationSerializer(
            data=request.data
        )

        if serializer.is_valid():
            user = serializer.save()

            return Response(
                {
                    'message': (
                        'Registration submitted successfully. '
                        'Your account is pending approval by the authority. '
                        'You will be able to log in once approved.'
                    ),
                    'approval_status': user.approval_status,
                    'user_id': user.id,
                },
                status=status.HTTP_201_CREATED
            )

        return Response(
            serializer.errors,
            status=status.HTTP_400_BAD_REQUEST
        )


# ─────────────────────────────────────────────────────────────
# Profile
# ─────────────────────────────────────────────────────────────

class UserProfileView(APIView):
    """
    Get or update the currently authenticated user's profile.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = UserSerializer(request.user)

        return Response(
            serializer.data,
            status=status.HTTP_200_OK
        )

    def patch(self, request):
        serializer = UserSerializer(
            request.user,
            data=request.data,
            partial=True
        )

        if serializer.is_valid():
            serializer.save()

            return Response(
                serializer.data,
                status=status.HTTP_200_OK
            )

        return Response(
            serializer.errors,
            status=status.HTTP_400_BAD_REQUEST
        )


# ─────────────────────────────────────────────────────────────
# FCM token
# ─────────────────────────────────────────────────────────────

class FCMTokenView(APIView):
    """
    Update the Firebase Cloud Messaging token
    for the authenticated user.
    """

    permission_classes = [IsAuthenticated]

    def patch(self, request):
        serializer = FCMTokenSerializer(
            request.user,
            data=request.data,
            partial=True
        )

        if serializer.is_valid():
            serializer.save()

            return Response(
                {
                    'message': 'FCM token updated successfully.',
                    'fcm_token': request.user.fcm_token,
                },
                status=status.HTTP_200_OK
            )

        return Response(
            serializer.errors,
            status=status.HTTP_400_BAD_REQUEST
        )


# ─────────────────────────────────────────────────────────────
# Reputation
# ─────────────────────────────────────────────────────────────

class ReputationView(APIView):
    """
    Return the authenticated user's reputation
    and complete reputation history.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        logs = ReputationLog.objects.filter(
            user=request.user
        ).select_related(
            'related_issue'
        )

        return Response(
            {
                'score': request.user.reputation_score,
                'level': request.user.reputation_level,
                'log': ReputationLogSerializer(
                    logs,
                    many=True
                ).data,
            },
            status=status.HTTP_200_OK
        )


# ─────────────────────────────────────────────────────────────
# Authority Citizen Registration Management APIs
# ─────────────────────────────────────────────────────────────

class RegistrationPagination(PageNumberPagination):
    page_size = 20
    page_size_query_param = "page_size"
    max_page_size = 100


class RegistrationListView(APIView):
    """
    GET /api/users/registrations/
    Lists citizen registrations for authority review.
    Query params:
        - status: 'pending' | 'approved' | 'rejected' | 'all' (default: 'all')
        - search: text search by name, email, or phone
    """

    permission_classes = [IsAuthorityOrAdmin]

    def get(self, request):
        status_filter = request.query_params.get("status", "all").strip().lower()
        search_query = (
            request.query_params.get("search")
            or request.query_params.get("q")
            or ""
        ).strip()

        queryset = CustomUser.objects.filter(role="citizen").select_related("reviewed_by")

        if status_filter in ["pending", "approved", "rejected"]:
            queryset = queryset.filter(approval_status=status_filter)

        if search_query:
            queryset = queryset.filter(
                Q(full_name__icontains=search_query)
                | Q(email__icontains=search_query)
                | Q(phone__icontains=search_query)
            )

        # Ordering: pending first, then newest
        queryset = queryset.order_by(
            "-date_joined"
        )

        # Compute summary counts for the tabs/badges
        base_citizens = CustomUser.objects.filter(role="citizen")
        counts = {
            "all": base_citizens.count(),
            "pending": base_citizens.filter(approval_status="pending").count(),
            "approved": base_citizens.filter(approval_status="approved").count(),
            "rejected": base_citizens.filter(approval_status="rejected").count(),
        }

        paginator = RegistrationPagination()
        page = paginator.paginate_queryset(queryset, request)
        serializer = CitizenRegistrationSerializer(page, many=True)

        return Response({
            "count": paginator.page.paginator.count if paginator.page else len(serializer.data),
            "next": paginator.get_next_link(),
            "previous": paginator.get_previous_link(),
            "counts": counts,
            "results": serializer.data,
        })


class RegistrationDetailView(APIView):
    """
    GET /api/users/registrations/<pk>/
    Retrieve full registration details for a citizen.
    """

    permission_classes = [IsAuthorityOrAdmin]

    def get(self, request, pk):
        try:
            user = CustomUser.objects.select_related("reviewed_by").get(pk=pk, role="citizen")
        except CustomUser.DoesNotExist:
            return Response(
                {"error": "Citizen registration not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        serializer = CitizenRegistrationSerializer(user)
        return Response(serializer.data, status=status.HTTP_200_OK)


class ApproveUserView(APIView):
    """
    POST /api/users/<pk>/approve/ or /api/users/registrations/<pk>/approve/
    Authority/superuser only. Activates the citizen account and notifies them.
    Idempotent: repeating approval is safely handled.
    """

    permission_classes = [IsAuthorityOrAdmin]

    def post(self, request, pk):
        try:
            user = CustomUser.objects.get(pk=pk, role="citizen")
        except CustomUser.DoesNotExist:
            return Response(
                {"error": "Citizen not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if user.pk == request.user.pk:
            return Response(
                {"error": "Cannot approve your own account."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Idempotent check
        if user.approval_status == "approved" and user.is_active:
            return Response(
                {
                    "message": f"{user.full_name} is already approved and active.",
                    "approval_status": "approved",
                    "already_approved": True,
                },
                status=status.HTTP_200_OK,
            )

        user.approval_status = "approved"
        user.is_active = True
        user.reviewed_by = request.user
        user.reviewed_at = timezone.now()
        user.save(update_fields=["approval_status", "is_active", "reviewed_by", "reviewed_at"])

        # Notify citizen (failure to notify does not undo approval)
        create_registration_approval_notification(user)

        return Response(
            {
                "message": f"{user.full_name} has been approved and can now log in.",
                "approval_status": "approved",
                "user_id": user.id,
            },
            status=status.HTTP_200_OK,
        )


class RejectUserView(APIView):
    """
    POST /api/users/<pk>/reject/ or /api/users/registrations/<pk>/reject/
    Authority/superuser only. Deactivates citizen account and records rejection reason.
    Idempotent: repeating rejection updates reason and safely handles state.
    """

    permission_classes = [IsAuthorityOrAdmin]

    def post(self, request, pk):
        try:
            user = CustomUser.objects.get(pk=pk, role="citizen")
        except CustomUser.DoesNotExist:
            return Response(
                {"error": "Citizen not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if user.pk == request.user.pk:
            return Response(
                {"error": "Cannot reject your own account."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        rejection_reason = request.data.get("rejection_reason", "").strip()

        # Idempotent check
        if user.approval_status == "rejected" and not user.is_active and not rejection_reason:
            return Response(
                {
                    "message": f"{user.full_name}'s registration is already rejected.",
                    "approval_status": "rejected",
                    "already_rejected": True,
                },
                status=status.HTTP_200_OK,
            )

        user.approval_status = "rejected"
        user.is_active = False
        if rejection_reason:
            user.rejection_reason = rejection_reason
        user.reviewed_by = request.user
        user.reviewed_at = timezone.now()
        user.save(update_fields=["approval_status", "is_active", "rejection_reason", "reviewed_by", "reviewed_at"])

        # Notify citizen (failure to notify does not undo rejection)
        create_registration_rejection_notification(user, reason=user.rejection_reason)

        return Response(
            {
                "message": f"{user.full_name}'s registration has been rejected.",
                "approval_status": "rejected",
                "rejection_reason": user.rejection_reason,
                "user_id": user.id,
            },
            status=status.HTTP_200_OK,
        )