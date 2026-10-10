from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models


# Reputation level choices
REPUTATION_LEVELS = [
    ('low', 'Low Trust'),
    ('normal', 'Normal'),
    ('trusted', 'Trusted'),
    ('highly_trusted', 'Highly Trusted'),
]


class CustomUserManager(BaseUserManager):
    """
    Custom manager for CustomUser.

    Users log in using their email instead of username.
    """

    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError("Email is required")

        email = self.normalize_email(email)

        # Citizens require authority approval before they can log in.
        # is_active=False prevents JWT auth until approved.
        if extra_fields.get('role', 'citizen') == 'citizen' and not extra_fields.get('is_superuser'):
            extra_fields.setdefault('is_active', False)
            extra_fields.setdefault('approval_status', 'pending')
        else:
            extra_fields.setdefault('is_active', True)
            extra_fields.setdefault('approval_status', 'approved')

        user = self.model(
            email=email,
            **extra_fields
        )

        if password:
            user.set_password(password)

        user.save(using=self._db)

        return user

    def create_superuser(self, email, password=None, **extra_fields):
        """
        Creates a Django admin superuser.
        """

        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)
        extra_fields.setdefault('approval_status', 'approved')

        if extra_fields.get('is_staff') is not True:
            raise ValueError(
                "Superuser must have is_staff=True"
            )

        if extra_fields.get('is_superuser') is not True:
            raise ValueError(
                "Superuser must have is_superuser=True"
            )

        return self.create_user(
            email=email,
            password=password,
            **extra_fields
        )


class CustomUser(AbstractUser):
    """
    Custom user model.

    Users log in using their email instead of username.
    """

    # Remove Django's username field.
    username = None

    # Required fields
    email = models.EmailField(
        unique=True
    )

    full_name = models.CharField(
        max_length=100
    )

    # Optional phone number
    phone = models.CharField(
        max_length=15,
        blank=True
    )

    # User role
    role = models.CharField(
        max_length=20,
        choices=[
            ('citizen', 'Citizen'),
            ('authority', 'Authority'),
        ],
        default='citizen'
    )

    # Approval status — citizens must be approved before they can log in.
    APPROVAL_CHOICES = [
        ('pending', 'Pending Approval'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ]
    approval_status = models.CharField(
        max_length=10,
        choices=APPROVAL_CHOICES,
        default='pending',
    )

    # Authority review audit fields
    reviewed_by = models.ForeignKey(
        'self',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reviewed_registrations',
    )
    reviewed_at = models.DateTimeField(
        null=True,
        blank=True,
    )
    rejection_reason = models.TextField(
        blank=True,
        default='',
    )

    # Firebase Cloud Messaging token
    fcm_token = models.CharField(
        max_length=255,
        blank=True
    )

    # Reputation system
    reputation_score = models.PositiveIntegerField(
        default=50
    )

    reputation_level = models.CharField(
        max_length=20,
        choices=REPUTATION_LEVELS,
        default='normal'
    )

    # Preferred language
    preferred_language = models.CharField(
        max_length=10,
        default='en'
    )

    # Use email instead of username for authentication
    USERNAME_FIELD = 'email'

    # Required when creating a superuser
    REQUIRED_FIELDS = ['full_name']

    # IMPORTANT:
    # Use our custom manager instead of Django's default UserManager.
    objects = CustomUserManager()

    def __str__(self):
        return f"{self.full_name} ({self.email})"


class ReputationLog(models.Model):
    """
    Tracks every change to a user's reputation score.
    """

    REASON_CHOICES = [
        ('account_created', 'Account Created'),
        ('submitted', 'Report Submitted'),
        ('resolved', 'Report Resolved'),
        ('upvoted_5', 'Report Got 5 Upvotes'),
        ('invalid', 'Report Marked Invalid'),
        ('fake', 'Report Marked Fake'),
    ]

    user = models.ForeignKey(
        CustomUser,
        on_delete=models.CASCADE,
        related_name='reputation_logs'
    )

    # Positive or negative reputation change
    change = models.IntegerField()

    reason = models.CharField(
        max_length=30,
        choices=REASON_CHOICES
    )

    # Issue responsible for the reputation change
    related_issue = models.ForeignKey(
        'issues.Issue',
        null=True,
        blank=True,
        on_delete=models.SET_NULL
    )

    timestamp = models.DateTimeField(
        auto_now_add=True
    )

    def __str__(self):
        sign = '+' if self.change >= 0 else ''

        return (
            f"{self.user.full_name}: "
            f"{sign}{self.change} "
            f"({self.reason})"
        )

    class Meta:
        ordering = ['-timestamp']