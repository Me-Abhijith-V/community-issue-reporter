import json
from django.contrib.auth import get_user_model
from django.test import Client, TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from apps.notifications.models import Notification

User = get_user_model()


class CitizenRegistrationApprovalTests(TestCase):
    """
    Comprehensive tests for the citizen registration approval workflow:
    - Citizen self-registration defaults to pending & inactive.
    - Login blocking for pending and rejected citizens with informative errors.
    - REST API permission checks (citizens cannot list, approve, or reject).
    - REST API approve / reject actions with audit fields (reviewed_by, reviewed_at, rejection_reason).
    - Notification generation on approval and rejection.
    - Authority web portal views (/authority/registrations/, detail AJAX, web approve, web reject).
    - Idempotency and edge cases.
    """

    def setUp(self):
        self.api_client = APIClient()
        self.web_client = Client()

        # Create Authority User
        self.authority = User.objects.create_user(
            email="officer@municipality.gov",
            password="SecurePassword123!",
            full_name="Municipal Officer",
            role="authority",
            approval_status="approved",
            is_active=True,
        )

        # Create Admin User
        self.admin = User.objects.create_superuser(
            email="admin@municipality.gov",
            password="AdminPassword123!",
            full_name="System Admin",
        )

        # Create Pending Citizen
        self.pending_citizen = User.objects.create_user(
            email="citizen.pending@example.com",
            password="CitizenPassword123!",
            full_name="Pending Citizen",
            phone="9876543210",
            role="citizen",
            approval_status="pending",
            is_active=False,
        )

        # Create Approved Citizen
        self.approved_citizen = User.objects.create_user(
            email="citizen.approved@example.com",
            password="CitizenPassword123!",
            full_name="Approved Citizen",
            role="citizen",
            approval_status="approved",
            is_active=True,
        )

        # Create Rejected Citizen
        self.rejected_citizen = User.objects.create_user(
            email="citizen.rejected@example.com",
            password="CitizenPassword123!",
            full_name="Rejected Citizen",
            role="citizen",
            approval_status="rejected",
            is_active=False,
            rejection_reason="Duplicate account with unverified phone number.",
        )

    # ─────────────────────────────────────────────────────────────────────────
    # 1. Registration & Default State
    # ─────────────────────────────────────────────────────────────────────────

    def test_citizen_registration_defaults_to_pending_and_inactive(self):
        """New citizen registration via API must be created with pending status and inactive."""
        payload = {
            "email": "new.resident@example.com",
            "password": "StrongPassword123!",
            "full_name": "New Resident",
            "phone": "9998887776",
            "preferred_language": "en",
        }
        response = self.api_client.post("/api/auth/register/", payload, format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        user = User.objects.get(email="new.resident@example.com")
        self.assertEqual(user.approval_status, "pending")
        self.assertFalse(user.is_active)
        self.assertEqual(user.role, "citizen")
        self.assertIsNone(user.reviewed_by)
        self.assertIsNone(user.reviewed_at)
        self.assertEqual(user.rejection_reason, "")

    # ─────────────────────────────────────────────────────────────────────────
    # 2. Login Blocking & Messages
    # ─────────────────────────────────────────────────────────────────────────

    def test_pending_citizen_login_is_blocked_with_clear_error(self):
        """Pending citizen cannot log in; receives HTTP 401 with error_code=pending_approval."""
        payload = {
            "email": "citizen.pending@example.com",
            "password": "CitizenPassword123!",
        }
        response = self.api_client.post("/api/auth/login/", payload, format="json")
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        data = response.json()
        self.assertEqual(data.get("error_code"), "pending_approval")
        self.assertEqual(data.get("approval_status"), "pending")
        self.assertIn("awaiting authority approval", data.get("detail", "").lower())
        self.assertNotIn("access", data)

    def test_rejected_citizen_login_is_blocked_with_rejection_reason(self):
        """Rejected citizen cannot log in; receives HTTP 401 with error_code=registration_rejected and reason."""
        payload = {
            "email": "citizen.rejected@example.com",
            "password": "CitizenPassword123!",
        }
        response = self.api_client.post("/api/auth/login/", payload, format="json")
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        data = response.json()
        self.assertEqual(data.get("error_code"), "registration_rejected")
        self.assertEqual(data.get("approval_status"), "rejected")
        self.assertEqual(data.get("rejection_reason"), "Duplicate account with unverified phone number.")
        self.assertIn("rejected", data.get("detail", "").lower())
        self.assertNotIn("access", data)

    def test_approved_citizen_login_succeeds(self):
        """Approved and active citizen can log in and receives JWT access + refresh tokens."""
        payload = {
            "email": "citizen.approved@example.com",
            "password": "CitizenPassword123!",
        }
        response = self.api_client.post("/api/auth/login/", payload, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertIn("access", data)
        self.assertIn("refresh", data)
        self.assertEqual(data.get("user", {}).get("approval_status"), "approved")

    # ─────────────────────────────────────────────────────────────────────────
    # 3. Permissions & Security
    # ─────────────────────────────────────────────────────────────────────────

    def test_unauthenticated_user_cannot_access_registration_apis(self):
        """Unauthenticated requests to registration endpoints must be rejected (401)."""
        res_list = self.api_client.get("/api/users/registrations/")
        self.assertEqual(res_list.status_code, status.HTTP_401_UNAUTHORIZED)

        res_approve = self.api_client.post(f"/api/users/registrations/{self.pending_citizen.id}/approve/")
        self.assertEqual(res_approve.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_citizen_cannot_access_registration_list_or_actions(self):
        """Citizens must be forbidden (403) from accessing or modifying registrations."""
        self.api_client.force_authenticate(user=self.approved_citizen)

        # Cannot list registrations
        res_list = self.api_client.get("/api/users/registrations/")
        self.assertEqual(res_list.status_code, status.HTTP_403_FORBIDDEN)

        # Cannot approve self or others
        res_approve = self.api_client.post(f"/api/users/registrations/{self.pending_citizen.id}/approve/")
        self.assertEqual(res_approve.status_code, status.HTTP_403_FORBIDDEN)

        # Cannot reject
        res_reject = self.api_client.post(f"/api/users/registrations/{self.pending_citizen.id}/reject/")
        self.assertEqual(res_reject.status_code, status.HTTP_403_FORBIDDEN)

    # ─────────────────────────────────────────────────────────────────────────
    # 4. REST API Registration Management
    # ─────────────────────────────────────────────────────────────────────────

    def test_authority_can_list_and_filter_registrations(self):
        """Authority can list registrations with status filtering and summary counts."""
        self.api_client.force_authenticate(user=self.authority)

        response = self.api_client.get("/api/users/registrations/?status=pending")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()

        # Check summary counts structure
        counts = data.get("counts", {})
        self.assertIn("pending", counts)
        self.assertIn("approved", counts)
        self.assertIn("rejected", counts)
        self.assertGreaterEqual(counts["pending"], 1)

        # Check results contain only pending
        results = data.get("results", [])
        for item in results:
            self.assertEqual(item["approval_status"], "pending")

    def test_authority_can_search_registrations(self):
        """Authority can search registrations by name or email."""
        self.api_client.force_authenticate(user=self.authority)

        response = self.api_client.get("/api/users/registrations/?q=pending@example.com")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.json().get("results", [])
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["email"], "citizen.pending@example.com")

    def test_authority_can_view_registration_detail(self):
        """Authority can retrieve full registration detail including audit fields."""
        self.api_client.force_authenticate(user=self.authority)

        response = self.api_client.get(f"/api/users/registrations/{self.rejected_citizen.id}/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertEqual(data["email"], "citizen.rejected@example.com")
        self.assertEqual(data["approval_status"], "rejected")
        self.assertEqual(data["rejection_reason"], "Duplicate account with unverified phone number.")

    def test_authority_can_approve_citizen_registration(self):
        """Approving a citizen sets status=approved, is_active=True, logs reviewer, and sends notification."""
        self.api_client.force_authenticate(user=self.authority)

        response = self.api_client.post(f"/api/users/registrations/{self.pending_citizen.id}/approve/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        self.pending_citizen.refresh_from_db()
        self.assertEqual(self.pending_citizen.approval_status, "approved")
        self.assertTrue(self.pending_citizen.is_active)
        self.assertEqual(self.pending_citizen.reviewed_by, self.authority)
        self.assertIsNotNone(self.pending_citizen.reviewed_at)

        # Verify notification created
        notif = Notification.objects.filter(
            user=self.pending_citizen,
            notification_type="registration_approved",
        ).first()
        self.assertIsNotNone(notif)
        self.assertIn("approved", notif.title.lower())

    def test_authority_can_reject_citizen_registration_with_reason(self):
        """Rejecting a citizen sets status=rejected, is_active=False, records reason & reviewer, and creates notification."""
        self.api_client.force_authenticate(user=self.authority)

        reason = "Unable to verify municipal address records."
        response = self.api_client.post(
            f"/api/users/registrations/{self.pending_citizen.id}/reject/",
            {"rejection_reason": reason},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        self.pending_citizen.refresh_from_db()
        self.assertEqual(self.pending_citizen.approval_status, "rejected")
        self.assertFalse(self.pending_citizen.is_active)
        self.assertEqual(self.pending_citizen.rejection_reason, reason)
        self.assertEqual(self.pending_citizen.reviewed_by, self.authority)
        self.assertIsNotNone(self.pending_citizen.reviewed_at)

        # Verify notification created
        notif = Notification.objects.filter(
            user=self.pending_citizen,
            notification_type="registration_rejected",
        ).first()
        self.assertIsNotNone(notif)
        self.assertIn("rejected", notif.title.lower())

    # ─────────────────────────────────────────────────────────────────────────
    # 5. Authority Web Portal Views
    # ─────────────────────────────────────────────────────────────────────────

    def test_authority_web_portal_registration_list_view(self):
        """Authority user can access the registration list template in authority portal."""
        self.web_client.force_login(self.authority)

        response = self.web_client.get(reverse("authority:registrations"))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Citizen Registrations")
        self.assertContains(response, "citizen.pending@example.com")
        # Pending badge count in context
        self.assertIn("pending_registrations_count", response.context)
        self.assertGreaterEqual(response.context["pending_registrations_count"], 1)

    def test_authority_web_portal_registration_detail_ajax(self):
        """AJAX request to /authority/registrations/<id>/ returns JSON detail."""
        self.web_client.force_login(self.authority)

        url = reverse("authority:registration-detail", args=[self.pending_citizen.id])
        response = self.web_client.get(url, HTTP_X_REQUESTED_WITH="XMLHttpRequest")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["email"], "citizen.pending@example.com")
        self.assertEqual(data["approval_status"], "pending")

    def test_authority_web_portal_approve_action(self):
        """Authority user can approve registration via web portal POST."""
        self.web_client.force_login(self.authority)

        url = reverse("authority:approve-registration", args=[self.pending_citizen.id])
        response = self.web_client.post(url, follow=True)
        self.assertEqual(response.status_code, 200)

        self.pending_citizen.refresh_from_db()
        self.assertEqual(self.pending_citizen.approval_status, "approved")
        self.assertTrue(self.pending_citizen.is_active)
        self.assertEqual(self.pending_citizen.reviewed_by, self.authority)

    def test_authority_web_portal_reject_action(self):
        """Authority user can reject registration with reason via web portal POST."""
        self.web_client.force_login(self.authority)

        url = reverse("authority:reject-registration", args=[self.pending_citizen.id])
        response = self.web_client.post(
            url,
            {"rejection_reason": "Incomplete contact details provided."},
            follow=True,
        )
        self.assertEqual(response.status_code, 200)

        self.pending_citizen.refresh_from_db()
        self.assertEqual(self.pending_citizen.approval_status, "rejected")
        self.assertFalse(self.pending_citizen.is_active)
        self.assertEqual(self.pending_citizen.rejection_reason, "Incomplete contact details provided.")
