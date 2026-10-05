from django.db import transaction

from rest_framework import serializers, status
from rest_framework.permissions import IsAuthenticated, IsAdminUser
from rest_framework.response import Response
from rest_framework.views import APIView

from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework_simplejwt.views import TokenObtainPairView

from .models import CustomUser, ReputationLog
from .serializers import (
    UserRegistrationSerializer,
    UserSerializer,
    FCMTokenSerializer,
    ReputationLogSerializer,
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
                            "Your registration is waiting for authority approval. "
                            "You will be able to log in once approved."
                        ),
                        "error_code": "pending_approval",
                    }
                )
            if user.approval_status == "rejected":
                raise serializers.ValidationError(
                    {
                        "detail": (
                            "Your registration has been rejected by the authority. "
                            "Please contact support if you believe this is a mistake."
                        ),
                        "error_code": "registration_rejected",
                    }
                )

        # Normal path — let the parent handle active/inactive checks.
        return super().validate(attrs)


class CustomTokenObtainPairView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer


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
# Approval / Rejection API (called by authority panel AJAX)
# ─────────────────────────────────────────────────────────────

class ApproveUserView(APIView):
    """
    POST /api/users/<pk>/approve/
    Authority/superuser only.  Activates the user's account.
    """

    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        if not (request.user.is_superuser or request.user.role == 'authority'):
            return Response(
                {'error': 'Permission denied.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        try:
            user = CustomUser.objects.get(pk=pk, role='citizen')
        except CustomUser.DoesNotExist:
            return Response(
                {'error': 'Citizen not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        if user.approval_status == 'approved':
            return Response(
                {'error': 'Already approved.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user.approval_status = 'approved'
        user.is_active = True
        user.save(update_fields=['approval_status', 'is_active'])

        return Response(
            {'message': f'{user.full_name} has been approved and can now log in.'},
            status=status.HTTP_200_OK,
        )


class RejectUserView(APIView):
    """
    POST /api/users/<pk>/reject/
    Authority/superuser only.  Keeps the account inactive.
    """

    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        if not (request.user.is_superuser or request.user.role == 'authority'):
            return Response(
                {'error': 'Permission denied.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        try:
            user = CustomUser.objects.get(pk=pk, role='citizen')
        except CustomUser.DoesNotExist:
            return Response(
                {'error': 'Citizen not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        if user.approval_status == 'rejected':
            return Response(
                {'error': 'Already rejected.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user.approval_status = 'rejected'
        user.is_active = False
        user.save(update_fields=['approval_status', 'is_active'])

        return Response(
            {'message': f'{user.full_name}\'s registration has been rejected.'},
            status=status.HTTP_200_OK,
        )