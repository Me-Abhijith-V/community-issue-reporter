import django_filters

from .models import Issue


class IssueFilter(django_filters.FilterSet):

    class Meta:
        model = Issue
        fields = [
            'category',
            'status',
            'reported_by',
            'was_voice_input',
        ]