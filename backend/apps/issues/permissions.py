from rest_framework.permissions import BasePermission


class IsAuthority(BasePermission):
    """
    Allows access only to authenticated users
    whose role is 'authority'.
    """

    def has_permission(self, request, view):
        return (
            request.user
            and request.user.is_authenticated
            and request.user.role == 'authority'
        )