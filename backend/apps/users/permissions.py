from rest_framework.permissions import BasePermission


class IsAuthorityOrAdmin(BasePermission):
    """
    Allows access only to authenticated users who are authority or superuser/staff.
    Ordinary citizens are strictly denied access.
    """

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and (
                getattr(request.user, "role", None) == "authority"
                or request.user.is_superuser
                or request.user.is_staff
            )
        )
