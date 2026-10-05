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
            'fcm_token',
            'reputation_score',
            'reputation_level',
            'preferred_language',
        ]

        read_only_fields = [
            'id',
            'email',
            'role',
            'approval_status',
            'reputation_score',
            'reputation_level',
        ]


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