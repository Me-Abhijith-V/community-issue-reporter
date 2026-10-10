from django.contrib.auth import authenticate
from rest_framework import serializers

from .models import CustomUser, ReputationLog


class UserRegistrationSerializer(serializers.ModelSerializer):
    """
    Serializer used when creating a new citizen account.
    """

    password = serializers.CharField(
        write_only=True,
        min_length=8
    )

    class Meta:
        model = CustomUser

        fields = [
            'full_name',
            'email',
            'phone',
            'password',
            'preferred_language',
        ]

    def validate_email(self, value):
        if CustomUser.objects.filter(
            email__iexact=value
        ).exists():
            raise serializers.ValidationError(
                "An account with this email already exists."
            )

        return value.lower()

    def create(self, validated_data):
        password = validated_data.pop('password')

        user = CustomUser.objects.create_user(
            password=password,
            role='citizen',
            is_active=False,
            approval_status='pending',
            **validated_data
        )

        ReputationLog.objects.create(
            user=user,
            change=0,
            reason='account_created',
        )

        return user


class UserSerializer(serializers.ModelSerializer):
    """
    Serializer for returning user information.
    """

    class Meta:
        model = CustomUser

        fields = [
            'id',
            'full_name',
            'email',
            'phone',
            'role',
            'approval_status',
            'reviewed_at',
            'rejection_reason',
            'fcm_token',
            'reputation_score',
            'reputation_level',
            'preferred_language',
            'date_joined',
        ]

        read_only_fields = [
            'id',
            'email',
            'role',
            'approval_status',
            'reviewed_at',
            'rejection_reason',
            'reputation_score',
            'reputation_level',
            'date_joined',
        ]


class CitizenRegistrationSerializer(serializers.ModelSerializer):
    """
    Serializer used by authority panel to list and review citizen registrations.
    """
    reviewed_by_name = serializers.SerializerMethodField()
    reviewed_by_email = serializers.SerializerMethodField()
    reports_count = serializers.SerializerMethodField()

    class Meta:
        model = CustomUser
        fields = [
            'id',
            'full_name',
            'email',
            'phone',
            'role',
            'preferred_language',
            'approval_status',
            'is_active',
            'date_joined',
            'reviewed_by',
            'reviewed_by_name',
            'reviewed_by_email',
            'reviewed_at',
            'rejection_reason',
            'reputation_score',
            'reputation_level',
            'reports_count',
        ]
        read_only_fields = fields

    def get_reviewed_by_name(self, obj):
        return obj.reviewed_by.full_name if obj.reviewed_by else None

    def get_reviewed_by_email(self, obj):
        return obj.reviewed_by.email if obj.reviewed_by else None

    def get_reports_count(self, obj):
        if hasattr(obj, 'reported_issues_count'):
            return obj.reported_issues_count
        return obj.reported_issues.count()


class FCMTokenSerializer(serializers.ModelSerializer):
    """
    Serializer for updating the Firebase push notification token.
    """

    class Meta:
        model = CustomUser

        fields = [
            'fcm_token',
        ]


class ReputationLogSerializer(serializers.ModelSerializer):
    """
    Serializer for reputation history.
    """

    class Meta:
        model = ReputationLog

        fields = [
            'change',
            'reason',
            'related_issue',
            'timestamp',
        ]

        read_only_fields = [
            'change',
            'reason',
            'related_issue',
            'timestamp',
        ]