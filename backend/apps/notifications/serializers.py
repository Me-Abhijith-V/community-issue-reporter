from rest_framework import serializers

from .models import Notification
from apps.users.models import CustomUser


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = [
            'id',
            'notification_type',
            'title',
            'message',
            'issue',
            'is_read',
            'created_at',
        ]
        read_only_fields = [
            'id',
            'notification_type',
            'title',
            'message',
            'issue',
            'created_at',
        ]


class FCMTokenSerializer(serializers.Serializer):
    fcm_token = serializers.CharField(
        max_length=255,
        allow_blank=False,
    )

    def update(self, instance, validated_data):
        instance.fcm_token = validated_data['fcm_token']
        instance.save(
            update_fields=['fcm_token']
        )
        return instance

    def create(self, validated_data):
        return validated_data