from functools import wraps
import json

from django.contrib import messages
from django.db.models import Count, Case, When, IntegerField
from django.contrib.auth import authenticate, login, logout
from django.contrib.auth.decorators import login_required
from django.core.paginator import Paginator
from django.db.models import Q
from django.http import JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_POST

from apps.issues.models import Issue, StatusUpdate
from apps.users.models import CustomUser, ReputationLog


def authority_required(view_func):

    @wraps(view_func)
    @login_required(login_url="/authority/login/")
    def wrapped(request, *args, **kwargs):

        if (
            not request.user.is_superuser
            and request.user.role != "authority"
        ):
            messages.error(
                request,
                "Authority access is required."
            )
            return redirect("authority:login")

        return view_func(request, *args, **kwargs)

    return wrapped


def reputation_level(score):

    if score <= 30:
        return "low"

    if score <= 60:
        return "normal"

    if score <= 80:
        return "trusted"

    return "highly_trusted"


def _apply_reputation(user, delta, reason, issue):
    """
    Award or deduct reputation idempotently.
    Returns True if the change was applied, False if already recorded.
    """
    already = ReputationLog.objects.filter(
        user=user,
        related_issue=issue,
        reason=reason,
    ).exists()

    if already:
        return False

    user.reputation_score = max(0, min(100, user.reputation_score + delta))
    user.reputation_level = reputation_level(user.reputation_score)
    user.save(update_fields=["reputation_score", "reputation_level"])

    ReputationLog.objects.create(
        user=user,
        change=delta,
        reason=reason,
        related_issue=issue,
    )
    return True


def _notify_reporter_and_upvoters(issue, old_status, new_status):
    """Send status-change notifications to the reporter AND every upvoter."""
    from apps.notifications.services import (
        create_status_notification,
        notify_upvoters_of_status_change,
    )
    try:
        create_status_notification(issue, old_status, new_status)
    except Exception as exc:
        print(f"[Authority] Reporter notification failed: {exc}")
    try:
        notify_upvoters_of_status_change(issue, old_status, new_status)
    except Exception as exc:
        print(f"[Authority] Upvoter notification failed: {exc}")


def authority_login(request):

    if request.user.is_authenticated:

        if (
            request.user.is_superuser
            or request.user.role == "authority"
        ):
            return redirect("authority:dashboard")

        logout(request)

    if request.method == "POST":

        email = request.POST.get(
            "email",
            ""
        ).strip()

        password = request.POST.get(
            "password",
            ""
        )

        user = authenticate(
            request,
            username=email,
            password=password,
        )

        if (
            user is not None
            and (
                user.is_superuser
                or user.role == "authority"
            )
        ):
            login(request, user)

            return redirect(
                "authority:dashboard"
            )

        messages.error(
            request,
            "Invalid authority credentials."
        )

    return render(
        request,
        "authority/login.html"
    )


def authority_logout(request):

    logout(request)

    return redirect(
        "authority:login"
    )


@authority_required
def dashboard(request):

    # ── Scalar counts ──────────────────────────────────────────
    total = Issue.objects.count()
    reported = Issue.objects.filter(status="reported").count()
    in_progress = Issue.objects.filter(status="in_progress").count()
    resolved = Issue.objects.filter(status="resolved").count()
    closed = Issue.objects.filter(status="closed").count()
    high_priority = (
        Issue.objects.filter(ai_severity__in=["high", "critical"])
        .exclude(status="closed")
        .count()
    )

    # ── Chart: by category ─────────────────────────────────────
    cat_qs = (
        Issue.objects.values("category")
        .annotate(cnt=Count("id"))
        .order_by("category")
    )
    category_labels = [r["category"] or "unknown" for r in cat_qs]
    category_data   = [r["cnt"]      for r in cat_qs]

    # ── Chart: by status ───────────────────────────────────────
    status_order = ["reported", "in_progress", "resolved", "closed"]
    status_counts = {
        r["status"]: r["cnt"]
        for r in Issue.objects.values("status").annotate(cnt=Count("id"))
    }
    status_labels = [s.replace("_", " ").title() for s in status_order]
    status_data   = [status_counts.get(s, 0) for s in status_order]

    # ── Chart: by severity ─────────────────────────────────────
    sev_order = ["critical", "high", "medium", "low", ""]
    sev_counts = {
        r["ai_severity"]: r["cnt"]
        for r in Issue.objects.values("ai_severity").annotate(cnt=Count("id"))
    }
    severity_labels = ["Critical", "High", "Medium", "Low", "Unknown"]
    severity_data   = [sev_counts.get(s, 0) for s in sev_order]

    context = {
        "total":        total,
        "reported":     reported,
        "in_progress":  in_progress,
        "resolved":     resolved,
        "closed":       closed,
        "high_priority": high_priority,

        "recent_issues": Issue.objects.select_related("reported_by").order_by("-created_at")[:10],

        # Chart data (safe JSON for embedding in <script>)
        "category_labels_json": json.dumps(category_labels),
        "category_data_json":   json.dumps(category_data),
        "status_labels_json":   json.dumps(status_labels),
        "status_data_json":     json.dumps(status_data),
        "severity_labels_json": json.dumps(severity_labels),
        "severity_data_json":   json.dumps(severity_data),
    }

    return render(request, "authority/dashboard.html", context)


@authority_required
def issue_list(request):

    queryset = Issue.objects.select_related(
        "reported_by"
    )

    search = request.GET.get(
        "search",
        ""
    ).strip()

    category = request.GET.get(
        "category",
        ""
    )

    status = request.GET.get(
        "status",
        ""
    )

    severity = request.GET.get(
        "severity",
        ""
    )

    sort = request.GET.get(
        "sort",
        "sev_high" # Default: Severity Highest -> Lowest
    )

    if search:

        queryset = queryset.filter(
            Q(
                original_description__icontains=search
            )
            |
            Q(
                translated_description__icontains=search
            )
            |
            Q(
                reported_by__full_name__icontains=search
            )
            |
            Q(
                reported_by__email__icontains=search
            )
        )

    if category:
        queryset = queryset.filter(
            category=category
        )

    if status:
        queryset = queryset.filter(
            status=status
        )

    if severity:
        queryset = queryset.filter(
            ai_severity=severity
        )

    # Base annotation for severity
    queryset = queryset.annotate(
        sev_order=Case(
            When(ai_severity="critical", then=0),
            When(ai_severity="high",     then=1),
            When(ai_severity="medium",   then=2),
            When(ai_severity="low",      then=3),
            default=4,
            output_field=IntegerField(),
        )
    )

    # Apply sorting
    if sort == "sev_high":
        queryset = queryset.order_by("sev_order", "-created_at")
    elif sort == "sev_low":
        queryset = queryset.order_by("-sev_order", "-created_at")
    elif sort == "date_new":
        queryset = queryset.order_by("-created_at")
    elif sort == "date_old":
        queryset = queryset.order_by("created_at")
    elif sort == "updated_new":
        queryset = queryset.order_by("-updated_at")
    elif sort == "updated_old":
        queryset = queryset.order_by("updated_at")
    elif sort == "status_a":
        queryset = queryset.order_by("status", "-created_at")
    elif sort == "status_z":
        queryset = queryset.order_by("-status", "-created_at")
    elif sort == "category_a":
        queryset = queryset.order_by("category", "-created_at")
    elif sort == "category_z":
        queryset = queryset.order_by("-category", "-created_at")
    elif sort == "upvotes_high":
        queryset = queryset.order_by("-upvote_count", "-created_at")
    elif sort == "upvotes_low":
        queryset = queryset.order_by("upvote_count", "-created_at")
    elif sort == "id_high":
        queryset = queryset.order_by("-id")
    elif sort == "id_low":
        queryset = queryset.order_by("id")
    elif sort == "location_a":
        # Can't easily order by reverse geocoded readable text without expensive DB functions 
        # since it's computed per page. So we order by latitude/longitude as a proxy, 
        # or we could skip it if not viable. Let's just order by ID to avoid crashing, 
        # but location_readable isn't a DB field.
        # Let's order by longitude, latitude
        queryset = queryset.order_by("longitude", "latitude")
    elif sort == "reporter_a":
        queryset = queryset.order_by("reported_by__full_name", "-created_at")
    else:
        # Fallback default
        queryset = queryset.order_by("sev_order", "-created_at")


    paginator = Paginator(queryset, 15)
    page_obj = paginator.get_page(request.GET.get("page"))

    # ── Per-page reverse geocoding ─────────────────────────────
    # Build addresses for the current page only (avoids hitting
    # the geocoder for the entire queryset on every request).
    from .geocode import reverse_geocode_cached
    geo_map = {}  # issue.id -> address string
    for issue in page_obj.object_list:
        if issue.latitude and issue.longitude:
            geo_map[issue.id] = reverse_geocode_cached(
                float(issue.latitude), float(issue.longitude)
            )

    return render(
        request,
        "authority/issues.html",
        {
            "page_obj":        page_obj,
            "search":          search,
            "category":        category,
            "status":          status,
            "severity":        severity,
            "sort":            sort,
            "category_choices": Issue.CATEGORY_CHOICES,
            "status_choices":   Issue.STATUS_CHOICES,
            "severity_choices": Issue.SEVERITY_CHOICES,
            "geo_map":          geo_map,
        }
    )


@authority_required
def issue_detail(request, pk):

    issue = get_object_or_404(
        Issue.objects.select_related(
            "reported_by"
        ),
        pk=pk
    )

    if request.method == "POST":

        action = request.POST.get(
            "action"
        )

        note = request.POST.get(
            "note",
            ""
        ).strip()

        old_status = issue.status

        # --------------------------------
        # IN PROGRESS
        # --------------------------------

        if action == "in_progress":

            if issue.status != "reported":
                messages.error(
                    request,
                    "Only reported issues can be moved to In Progress."
                )
                return redirect("authority:issue-detail", pk=pk)

            issue.status = "in_progress"
            issue.save(update_fields=["status", "updated_at"])

            StatusUpdate.objects.create(
                issue=issue,
                updated_by=request.user,
                old_status=old_status,
                new_status="in_progress",
                note=note,
            )

            # Notify reporter + every upvoter
            _notify_reporter_and_upvoters(issue, old_status, "in_progress")

            messages.success(
                request,
                f"Issue #{issue.id} moved to In Progress."
            )

        # --------------------------------
        # RESOLVED
        # --------------------------------

        elif action == "resolved":

            if issue.status != "in_progress":
                messages.error(
                    request,
                    "Only In Progress issues can be resolved."
                )
                return redirect("authority:issue-detail", pk=pk)

            issue.status = "resolved"
            issue.save(update_fields=["status", "updated_at"])

            StatusUpdate.objects.create(
                issue=issue,
                updated_by=request.user,
                old_status=old_status,
                new_status="resolved",
                note=note,
            )

            # Idempotent +20 reputation for the reporter
            _apply_reputation(issue.reported_by, 20, "resolved", issue)

            # Notify reporter + every upvoter
            _notify_reporter_and_upvoters(issue, old_status, "resolved")

            messages.success(
                request,
                f"Issue #{issue.id} resolved. Reporter received +20 reputation."
            )

        # --------------------------------
        # CLOSED
        # --------------------------------

        elif action == "closed":

            if issue.status != "resolved":
                messages.error(
                    request,
                    "Only resolved issues can be closed."
                )
                return redirect("authority:issue-detail", pk=pk)

            issue.status = "closed"
            issue.save(update_fields=["status", "updated_at"])

            StatusUpdate.objects.create(
                issue=issue,
                updated_by=request.user,
                old_status=old_status,
                new_status="closed",
                note=note,
            )

            # Notify reporter + every upvoter
            _notify_reporter_and_upvoters(issue, old_status, "closed")

            messages.success(
                request,
                f"Issue #{issue.id} closed."
            )

        # --------------------------------
        # INVALID / FAKE
        # --------------------------------

        elif action in ["invalid", "fake"]:

            if issue.authority_decision:
                messages.error(
                    request,
                    "This issue already has an authority decision."
                )

            elif not note:
                messages.error(
                    request,
                    "A reason is required."
                )

            else:
                issue.authority_decision = action
                issue.authority_note = note
                issue.status = "closed"
                issue.save(
                    update_fields=[
                        "authority_decision",
                        "authority_note",
                        "status",
                        "updated_at",
                    ]
                )

                StatusUpdate.objects.create(
                    issue=issue,
                    updated_by=request.user,
                    old_status=old_status,
                    new_status="closed",
                    note=f"{action.title()}: {note}",
                )

                # Idempotent reputation penalty on the REPORTER only
                delta = -15 if action == "invalid" else -30
                _apply_reputation(
                    issue.reported_by, delta, action, issue
                )

                # Targeted authority-decision notification to reporter only
                try:
                    from apps.notifications.services import (
                        create_authority_decision_notification,
                    )
                    create_authority_decision_notification(
                        issue, action, note
                    )
                except Exception as exc:
                    print(f"[Authority] Decision notification failed: {exc}")

                messages.success(
                    request,
                    f"Issue #{issue.id} marked {action}. "
                    f"Reporter reputation adjusted."
                )

        return redirect(
            "authority:issue-detail",
            pk=pk
        )

    history = issue.status_history.select_related(
        "updated_by"
    ).order_by("-timestamp")

    # Geocoded address for the detail view
    from .geocode import reverse_geocode_cached
    geocoded_address = None
    if issue.latitude and issue.longitude:
        geocoded_address = reverse_geocode_cached(
            float(issue.latitude), float(issue.longitude)
        )

    return render(
        request,
        "authority/issue_detail.html",
        {
            "issue": issue,
            "history": history,
            "geocoded_address": geocoded_address,
        }
    )


@authority_required
def authority_map(request):

    issues = Issue.objects.exclude(
        latitude__isnull=True
    ).exclude(
        longitude__isnull=True
    ).select_related("reported_by")

    data = []

    for issue in issues:

        data.append({
            "id": issue.id,
            "latitude": float(issue.latitude),
            "longitude": float(issue.longitude),
            "category": issue.category,
            "status": issue.status,
            "severity": issue.ai_severity or "",
            "upvotes": issue.upvote_count,
            "is_duplicate": bool(issue.ai_is_duplicate),
            "duplicate_count": issue.duplicate_issues.count(),
        })

    return render(
        request,
        "authority/map.html",
        {
            "map_data": json.dumps(data)
        }
    )


@authority_required
def user_list(request):

    search = request.GET.get(
        "search",
        ""
    ).strip()

    # Pending registrations — always shown regardless of search
    pending_users = CustomUser.objects.filter(
        role="citizen",
        approval_status="pending",
    ).order_by("date_joined")

    queryset = CustomUser.objects.prefetch_related(
        "reported_issues"
    ).exclude(approval_status="pending")

    if search:

        queryset = queryset.filter(
            Q(
                full_name__icontains=search
            )
            |
            Q(
                email__icontains=search
            )
        )

    queryset = queryset.order_by(
        "-reputation_score"
    )

    paginator = Paginator(
        queryset,
        20
    )

    page_obj = paginator.get_page(
        request.GET.get("page")
    )

    return render(
        request,
        "authority/users.html",
        {
            "page_obj": page_obj,
            "search": search,
            "pending_users": pending_users,
        }
    )


@authority_required
@require_POST
def approve_user(request, pk):
    """Approve a pending citizen registration."""
    user = get_object_or_404(
        CustomUser, pk=pk, role="citizen"
    )
    if user.approval_status != "pending":
        messages.warning(request, "User is not pending approval.")
    else:
        user.approval_status = "approved"
        user.is_active = True
        user.save(update_fields=["approval_status", "is_active"])
        messages.success(
            request,
            f"{user.full_name} has been approved and can now log in."
        )
    return redirect("authority:users")


@authority_required
@require_POST
def reject_user(request, pk):
    """Reject a pending citizen registration."""
    user = get_object_or_404(
        CustomUser, pk=pk, role="citizen"
    )
    if user.approval_status == "rejected":
        messages.warning(request, "Already rejected.")
    else:
        user.approval_status = "rejected"
        user.is_active = False
        user.save(update_fields=["approval_status", "is_active"])
        messages.success(
            request,
            f"{user.full_name}'s registration has been rejected."
        )
    return redirect("authority:users")


@authority_required
@require_POST
def associate_duplicate(request, pk):
    """
    Manually associate an issue as a duplicate of another.
    POST: { canonical_id: <int> }
    """

    issue = get_object_or_404(Issue, pk=pk)

    canonical_id = request.POST.get("canonical_id", "").strip()

    if not canonical_id:
        messages.error(request, "Canonical issue ID is required.")
        return redirect("authority:issue-detail", pk=pk)

    try:
        canonical_id = int(canonical_id)
    except (TypeError, ValueError):
        messages.error(request, "Invalid canonical issue ID.")
        return redirect("authority:issue-detail", pk=pk)


    if canonical_id == issue.id:
        messages.error(request, "An issue cannot be a duplicate of itself.")
        return redirect("authority:issue-detail", pk=pk)

    try:
        canonical = Issue.objects.get(id=canonical_id)
    except Issue.DoesNotExist:
        messages.error(request, f"Issue #{canonical_id} does not exist.")
        return redirect("authority:issue-detail", pk=pk)

    issue.ai_is_duplicate = True
    issue.ai_duplicate_of = canonical
    issue.save(update_fields=["ai_is_duplicate", "ai_duplicate_of", "updated_at"])

    # Notify the reporter (issue.reported_by, not request.user)
    try:
        from apps.notifications.services import create_duplicate_notification
        create_duplicate_notification(issue, canonical)
    except Exception as exc:
        print(f"[Authority] Duplicate notification failed: {exc}")

    messages.success(
        request,
        f"Issue #{issue.id} has been associated as a duplicate of Issue #{canonical.id}."
    )

    return redirect("authority:issue-detail", pk=pk)
