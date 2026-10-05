from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import CustomUser, ReputationLog


@admin.register(CustomUser)
class CustomUserAdmin(UserAdmin):
    """
    Shows CustomUser in the Django admin panel.
    """
    model = CustomUser

    list_display = [
        'email', 'full_name', 'role',
        'reputation_score', 'reputation_level',
        'preferred_language', 'is_active'
    ]
    list_filter  = ['role', 'reputation_level', 'preferred_language', 'is_active']
    search_fields = ['email', 'full_name']
    ordering     = ['email']

    # Fields shown when editing a user
    fieldsets = (
        (None, {'fields': ('email', 'password')}),
        ('Personal Info', {'fields': ('full_name', 'phone')}),
        ('Role & Reputation', {
            'fields': ('role', 'reputation_score', 'reputation_level', 'preferred_language')
        }),
        ('Push Notifications', {'fields': ('fcm_token',)}),
        ('Permissions', {'fields': ('is_active', 'is_staff', 'is_superuser')}),
        ('Important Dates', {'fields': ('last_login', 'date_joined')}),
    )

    # Fields shown when CREATING a new user in admin
    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('email', 'full_name', 'password1', 'password2', 'role'),
        }),
    )


@admin.register(ReputationLog)
class ReputationLogAdmin(admin.ModelAdmin):
    list_display  = ['user', 'change', 'reason', 'related_issue', 'timestamp']
    list_filter   = ['reason']
    search_fields = ['user__email', 'user__full_name']
    ordering      = ['-timestamp']
    readonly_fields = ['user', 'change', 'reason', 'related_issue', 'timestamp']