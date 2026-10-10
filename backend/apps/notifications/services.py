import os

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

from .models import Notification


FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


def get_fcm_access_token():
    credentials_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

    if not credentials_path:
        raise RuntimeError(
            "GOOGLE_APPLICATION_CREDENTIALS is not configured."
        )

    credentials = service_account.Credentials.from_service_account_file(
        credentials_path,
        scopes=[FCM_SCOPE],
    )

    credentials.refresh(Request())

    return credentials.token


def send_fcm_notification(
    fcm_token,
    title,
    body,
    data=None,
):
    credentials_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

    if not credentials_path:
        raise RuntimeError(
            "GOOGLE_APPLICATION_CREDENTIALS is not configured."
        )

    credentials = service_account.Credentials.from_service_account_file(
        credentials_path,
        scopes=[FCM_SCOPE],
    )

    credentials.refresh(Request())

    project_id = credentials.project_id

    url = (
        f"https://fcm.googleapis.com/v1/projects/"
        f"{project_id}/messages:send"
    )

    message = {
        "message": {
            "token": fcm_token,
            "notification": {
                "title": title,
                "body": body,
            },
        }
    }

    if data:
        message["message"]["data"] = {
            str(key): str(value)
            for key, value in data.items()
        }

    response = requests.post(
        url,
        headers={
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json",
        },
        json=message,
        timeout=15,
    )

    if not response.ok:
        raise RuntimeError(
            f"FCM request failed ({response.status_code}): "
            f"{response.text}"
        )

    return response.json()


def _send_push(user, title, body, data=None):
    """
    Send an FCM push notification to a single user if they have an FCM
    token. Silently ignores errors (e.g. credentials not configured).
    """
    if not user.fcm_token:
        return
    try:
        send_fcm_notification(
            fcm_token=user.fcm_token,
            title=title,
            body=body,
            data=data or {},
        )
    except Exception as e:
        print(f"[FCM] Push to user {user.id} failed: {e}")


def create_status_notification(issue, old_status, new_status):
    """
    Notify the issue reporter about a status change.

    RECIPIENT: always issue.reported_by — never the current logged-in user.
    """
    reporter = issue.reported_by  # always the reporter, never request.user

    title = "Issue Status Updated"
    message = (
        f"Your reported issue #{issue.id} "
        f"has been updated from '{old_status}' to '{new_status}'."
    )

    notification = Notification.objects.create(
        user=reporter,
        notification_type="status_update",
        title=title,
        message=message,
        issue=issue,
    )

    _send_push(
        reporter,
        title,
        message,
        data={
            "notification_type": "status_update",
            "issue_id": str(issue.id),
        },
    )

    return notification


def notify_upvoters_of_status_change(issue, old_status, new_status):
    """
    Notify every citizen who upvoted this issue about the status change.

    Rules:
    - Excludes the reporter (they already receive create_status_notification).
    - Excludes anyone who is not a citizen (authority users don't need app notifs).
    - One in-app Notification record per upvoter.
    - Avoids duplicate notifications: checks that no notification with this
      exact (user, issue, new_status message) already exists in the DB.
    """
    from apps.issues.models import IssueUpvote  # avoid circular import

    reporter_id = issue.reported_by_id  # DB field, no extra query

    title = "Issue Update"
    message = (
        f"An issue you upvoted (#{issue.id}) "
        f"has been updated from '{old_status}' to '{new_status}'."
    )

    upvote_users = (
        IssueUpvote.objects
        .filter(issue=issue)
        .exclude(user_id=reporter_id)          # reporter gets separate notif
        .select_related("user")
        .values_list("user", flat=False)
    )

    # Fetch user objects once
    upvoters = (
        IssueUpvote.objects
        .filter(issue=issue)
        .exclude(user_id=reporter_id)
        .select_related("user")
    )

    # Deduplicate: find upvoters who already have this exact notification
    already_notified_ids = set(
        Notification.objects
        .filter(
            issue=issue,
            notification_type="status_update",
            message=message,
        )
        .values_list("user_id", flat=True)
    )

    for upvote in upvoters:
        user = upvote.user
        if user.id in already_notified_ids:
            continue  # skip duplicate

        Notification.objects.create(
            user=user,
            notification_type="status_update",
            title=title,
            message=message,
            issue=issue,
        )

        _send_push(
            user,
            title,
            message,
            data={
                "notification_type": "status_update",
                "issue_id": str(issue.id),
            },
        )


def create_authority_decision_notification(issue, decision, reason):
    """
    Notify the issue reporter when an authority marks the issue
    as 'invalid' or 'fake'.

    RECIPIENT: always issue.reported_by.
    """
    reporter = issue.reported_by

    rep_impact = {
        "invalid": "−15 reputation",
        "fake": "−30 reputation",
    }.get(decision, "reputation adjusted")

    title = f"Issue Marked {decision.title()}"
    message = (
        f"Your report #{issue.id} has been reviewed by the authority "
        f"and marked as '{decision}'. Reason: {reason}. "
        f"Your reputation has been adjusted ({rep_impact})."
    )

    notification = Notification.objects.create(
        user=reporter,
        notification_type="status_update",
        title=title,
        message=message,
        issue=issue,
    )

    _send_push(
        reporter,
        title,
        message,
        data={
            "notification_type": "status_update",
            "issue_id": str(issue.id),
            "decision": decision,
        },
    )

    return notification


def create_duplicate_notification(issue, canonical_issue):
    """
    Notify the issue reporter when their report is grouped as a duplicate.

    RECIPIENT: always issue.reported_by.
    """
    reporter = issue.reported_by

    title = "Report Grouped as Duplicate"
    message = (
        f"Your report #{issue.id} has been reviewed and grouped "
        f"as a duplicate of Issue #{canonical_issue.id} by the authority."
    )

    notification = Notification.objects.create(
        user=reporter,
        notification_type="duplicate",
        title=title,
        message=message,
        issue=issue,
    )

    _send_push(
        reporter,
        title,
        message,
        data={
            "notification_type": "duplicate",
            "issue_id": str(issue.id),
            "canonical_id": str(canonical_issue.id),
        },
    )

    return notification


def create_registration_approval_notification(user):
    """
    Notify the citizen that their registration has been approved.
    """
    title = "Registration Approved"
    message = (
        f"Welcome, {user.full_name}! Your registration has been approved by the authority. "
        "You can now log in and report community issues."
    )

    try:
        notification = Notification.objects.create(
            user=user,
            notification_type="registration_approved",
            title=title,
            message=message,
            issue=None,
        )

        _send_push(
            user,
            title,
            message,
            data={
                "notification_type": "registration_approved",
            },
        )
        return notification
    except Exception as exc:
        print(f"[Notifications] Registration approval notification failed: {exc}")
        return None


def create_registration_rejection_notification(user, reason=""):
    """
    Notify the citizen that their registration could not be approved.
    """
    title = "Registration Rejected"
    reason_text = f" Reason: {reason}." if reason else ""
    message = (
        f"Hello {user.full_name}, your citizen registration could not be approved by the authority.{reason_text} "
        "Please contact the authority if you believe this was in error."
    )

    try:
        notification = Notification.objects.create(
            user=user,
            notification_type="registration_rejected",
            title=title,
            message=message,
            issue=None,
        )

        _send_push(
            user,
            title,
            message,
            data={
                "notification_type": "registration_rejected",
                "reason": reason,
            },
        )
        return notification
    except Exception as exc:
        print(f"[Notifications] Registration rejection notification failed: {exc}")
        return None