from rest_framework import serializers

from .models import Issue, IssueUpvote, StatusUpdate


class IssueSerializer(serializers.ModelSerializer):

    original_description = serializers.CharField(
        required=False,
        allow_blank=True,
        default=""
    )

    # Writable AI fields so Flutter can send them at create time
    ai_suggested_category = serializers.CharField(
        required=False,
        allow_blank=True,
        default=""
    )

    ai_severity = serializers.CharField(
        required=False,
        allow_blank=True,
        default=""
    )

    ai_is_duplicate = serializers.BooleanField(
        required=False,
        allow_null=True,
        default=None
    )

    ai_duplicate_of = serializers.PrimaryKeyRelatedField(
        queryset=Issue.objects.all(),
        required=False,
        allow_null=True,
        default=None
    )

    reporter_name = serializers.CharField(
        source='reported_by.full_name',
        read_only=True
    )

    reporter_email = serializers.EmailField(
        source='reported_by.email',
        read_only=True
    )

    reporter_reputation_score = serializers.IntegerField(
        source='reported_by.reputation_score',
        read_only=True
    )

    reporter_reputation_level = serializers.CharField(
        source='reported_by.reputation_level',
        read_only=True
    )

    # Count of duplicate issues grouped under this canonical issue
    duplicate_reports_count = serializers.SerializerMethodField()

    ai_status = serializers.SerializerMethodField()

    address = serializers.CharField(
        required=False,
        allow_blank=True,
        default=""
    )

    class Meta:
        model = Issue

        fields = [
            'id',
            'reported_by',
            'reporter_name',
            'reporter_email',
            'reporter_reputation_score',
            'reporter_reputation_level',
            'original_description',
            'translated_description',
            'detected_language',
            'category',
            'latitude',
            'longitude',
            'address',
            'photo',
            'status',
            'ai_suggested_category',
            'ai_severity',
            'ai_severity_reason',
            'ai_severity_basis',
            'ai_is_duplicate',
            'ai_duplicate_of',
            'ai_duplicate_reason',
            'ai_validation_status',
            'ai_is_image_match',
            'ai_image_match_reason',
            'ai_status',
            'duplicate_reports_count',
            'upvote_count',
            'was_voice_input',
            'authority_decision',
            'authority_note',
            'created_at',
            'updated_at',
        ]

        read_only_fields = [
            'id',
            'reported_by',
            'reporter_name',
            'reporter_email',
            'reporter_reputation_score',
            'reporter_reputation_level',
            'ai_status',
            'upvote_count',
            'created_at',
            'updated_at',
        ]

    def get_ai_status(self, obj):
        if obj.ai_suggested_category and obj.ai_severity:
            return "success"
        return "failed"

    def get_duplicate_reports_count(self, obj):
        return obj.duplicate_issues.count()


class IssueUpvoteSerializer(serializers.ModelSerializer):
    """
    Serializer for an issue upvote.
    """

    user_name = serializers.CharField(
        source='user.full_name',
        read_only=True
    )

    class Meta:
        model = IssueUpvote

        fields = [
            'id',
            'issue',
            'user',
            'user_name',
            'created_at',
        ]

        read_only_fields = [
            'id',
            'user',
            'user_name',
            'created_at',
        ]


class StatusUpdateSerializer(serializers.ModelSerializer):
    """
    Serializer for issue status history.
    """

    updated_by_name = serializers.CharField(
        source='updated_by.full_name',
        read_only=True
    )

    class Meta:
        model = StatusUpdate

        fields = [
            'id',
            'issue',
            'updated_by',
            'updated_by_name',
            'old_status',
            'new_status',
            'note',
            'timestamp',
        ]

        read_only_fields = [
            'id',
            'updated_by',
            'updated_by_name',
            'timestamp',
        ]