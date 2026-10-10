from django.conf import settings
from django.db import models


class Issue(models.Model):

    CATEGORY_CHOICES = [
        ('pothole', 'Pothole'),
        ('streetlight', 'Streetlight'),
        ('garbage', 'Garbage'),
        ('water', 'Water'),
        ('other', 'Other'),
    ]

    STATUS_CHOICES = [
        ('reported', 'Reported'),
        ('in_progress', 'In Progress'),
        ('resolved', 'Resolved'),
        ('closed', 'Closed'),
    ]

    SEVERITY_CHOICES = [
        ('low', 'Low'),
        ('medium', 'Medium'),
        ('high', 'High'),
        ('critical', 'Critical'),
    ]

    reported_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='reported_issues'
    )

    original_description = models.TextField(blank=True)

    translated_description = models.TextField(blank=True)

    detected_language = models.CharField(
        max_length=10,
        blank=True,
        default='en'
    )

    category = models.CharField(
        max_length=20,
        choices=CATEGORY_CHOICES,
        default='other'
    )

    latitude = models.DecimalField(
        max_digits=9,
        decimal_places=6
    )

    longitude = models.DecimalField(
        max_digits=9,
        decimal_places=6
    )

    address = models.CharField(
        max_length=255,
        blank=True,
        default=''
    )

    photo = models.ImageField(
        upload_to='issues/'
    )

    status = models.CharField(
        max_length=20,
        choices=STATUS_CHOICES,
        default='reported'
    )

    ai_suggested_category = models.CharField(
        max_length=50,
        blank=True
    )

    ai_severity = models.CharField(
        max_length=20,
        choices=SEVERITY_CHOICES,
        blank=True
    )

    ai_is_duplicate = models.BooleanField(
        null=True,
        blank=True
    )

    ai_duplicate_of = models.ForeignKey(
        'self',
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='duplicate_issues'
    )

    ai_duplicate_reason = models.TextField(blank=True, default='')

    ai_severity_reason = models.TextField(blank=True, default='')

    ai_severity_basis = models.CharField(
        max_length=30,
        blank=True,
        default='text_only'
    )

    ai_validation_status = models.CharField(
        max_length=20,
        blank=True,
        default='valid'
    )

    ai_is_image_match = models.BooleanField(
        null=True,
        blank=True,
        default=True
    )

    ai_image_match_reason = models.TextField(blank=True, default='')

    upvote_count = models.PositiveIntegerField(default=0)

    was_voice_input = models.BooleanField(default=False)

    created_at = models.DateTimeField(auto_now_add=True)

    updated_at = models.DateTimeField(auto_now=True)

    authority_decision = models.CharField(
    max_length=20,
    choices=[
        ("invalid", "Invalid"),
        ("fake", "Fake"),
    ],
    blank=True,
    default="",
    )

    authority_note = models.TextField(
    blank=True,
    default="",
    )

    def __str__(self):
        return f"Issue #{self.id} - {self.category} - {self.status}"


class IssueUpvote(models.Model):

    issue = models.ForeignKey(
        Issue,
        on_delete=models.CASCADE,
        related_name='upvotes'
    )

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='issue_upvotes'
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('issue', 'user')

    def __str__(self):
        return f"{self.user} upvoted Issue #{self.issue.id}"


class StatusUpdate(models.Model):

    issue = models.ForeignKey(
        Issue,
        on_delete=models.CASCADE,
        related_name='status_history'
    )

    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='status_updates'
    )

    old_status = models.CharField(
        max_length=20,
        choices=Issue.STATUS_CHOICES
    )

    new_status = models.CharField(
        max_length=20,
        choices=Issue.STATUS_CHOICES
    )

    note = models.TextField(blank=True)

    timestamp = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return (
            f"Issue #{self.issue.id}: "
            f"{self.old_status} → {self.new_status}"
        )