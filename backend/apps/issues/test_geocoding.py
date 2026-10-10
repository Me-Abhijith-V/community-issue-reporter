import json
from unittest.mock import patch, MagicMock
from django.test import TestCase
from django.urls import reverse
from django.contrib.auth import get_user_model
from django.core.management import call_command
from rest_framework.test import APIClient
from rest_framework import status

from apps.issues.models import Issue
from apps.issues.geocode import (
    validate_coordinates,
    reverse_geocode,
    reverse_geocode_nominatim,
    resolve_and_save_issue_address,
    clear_cache,
)

User = get_user_model()


class CoordinateValidationTests(TestCase):
    def test_valid_coordinates(self):
        coords = validate_coordinates(8.524138, 76.936638)
        self.assertIsNotNone(coords)
        lat, lng = coords
        self.assertAlmostEqual(lat, 8.524138)
        self.assertAlmostEqual(lng, 76.936638)

    def test_valid_string_coordinates(self):
        coords = validate_coordinates("8.5241", "76.9366")
        self.assertIsNotNone(coords)
        lat, lng = coords
        self.assertAlmostEqual(lat, 8.5241)
        self.assertAlmostEqual(lng, 76.9366)

    def test_invalid_latitude_out_of_range(self):
        self.assertIsNone(validate_coordinates(95.0, 76.0))
        self.assertIsNone(validate_coordinates(-95.0, 76.0))

    def test_invalid_longitude_out_of_range(self):
        self.assertIsNone(validate_coordinates(8.0, 185.0))
        self.assertIsNone(validate_coordinates(8.0, -185.0))

    def test_non_numeric_coordinates(self):
        self.assertIsNone(validate_coordinates("not_a_number", 76.0))
        self.assertIsNone(validate_coordinates(None, 76.0))
        self.assertIsNone(validate_coordinates(8.0, None))


class GeocodingServiceTests(TestCase):
    def setUp(self):
        clear_cache()

    @patch("apps.issues.geocode.requests.get")
    def test_reverse_geocode_success_and_cache(self, mock_get):
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "address": {
                "road": "MG Road",
                "suburb": "Palayam",
                "city": "Thiruvananthapuram",
                "state": "Kerala",
                "postcode": "695001",
            }
        }
        mock_get.return_value = mock_response

        # First call hits mock
        address = reverse_geocode(8.5241, 76.9366)
        self.assertEqual(address, "MG Road, Palayam, Thiruvananthapuram")
        self.assertEqual(mock_get.call_count, 1)

        # Second call for identical (or rounded nearby) coords uses cache
        cached_address = reverse_geocode(8.52412, 76.93661)
        self.assertEqual(cached_address, address)
        self.assertEqual(mock_get.call_count, 1)  # No extra HTTP request

    @patch("apps.issues.geocode.requests.get")
    def test_reverse_geocode_failure_returns_empty_never_coordinates(self, mock_get):
        mock_get.side_effect = Exception("Nominatim timeout")

        result = reverse_geocode(8.5241, 76.9366)
        # MUST return empty string, never coordinates!
        self.assertEqual(result, "")
        self.assertNotIn("8.5241", result)

    @patch("apps.issues.geocode.reverse_geocode")
    def test_resolve_and_save_issue_address(self, mock_geocode):
        mock_geocode.return_value = "Secretariat, Thiruvananthapuram, Kerala"

        user = User.objects.create_user(
            email="citizen_geo@example.com",
            phone="9876543210",
            full_name="Citizen Geo",
            role="citizen",
            is_active=True,
            approval_status="approved",
        )
        issue = Issue.objects.create(
            reported_by=user,
            original_description="Pothole near gate",
            category="pothole",
            latitude=8.5000,
            longitude=76.9500,
            address="",
        )

        resolved = resolve_and_save_issue_address(issue)
        self.assertEqual(resolved, "Secretariat, Thiruvananthapuram, Kerala")
        issue.refresh_from_db()
        self.assertEqual(issue.address, "Secretariat, Thiruvananthapuram, Kerala")

        # Second call with force=False should not call geocode again
        mock_geocode.reset_mock()
        resolved2 = resolve_and_save_issue_address(issue, force=False)
        self.assertEqual(resolved2, "Secretariat, Thiruvananthapuram, Kerala")
        mock_geocode.assert_not_called()


class ReverseGeocodeAPITests(TestCase):
    def setUp(self):
        clear_cache()
        self.client = APIClient()
        self.user = User.objects.create_user(
            email="api_user@example.com",
            phone="9876543211",
            full_name="API User",
            role="citizen",
            is_active=True,
            approval_status="approved",
        )
        self.url = reverse("reverse-geocode")

    def test_unauthenticated_request_rejected(self):
        response = self.client.get(self.url, {"latitude": 8.5241, "longitude": 76.9366})
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_missing_coordinates_returns_400(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("error", response.data)

    def test_invalid_coordinates_returns_400(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.get(self.url, {"latitude": 95.0, "longitude": 76.0})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("error", response.data)

    @patch("apps.issues.geocode.reverse_geocode")
    def test_valid_request_returns_address(self, mock_geocode):
        mock_geocode.return_value = "Central Station, Thiruvananthapuram, Kerala"
        self.client.force_authenticate(user=self.user)

        response = self.client.get(self.url, {"latitude": 8.4875, "longitude": 76.9525})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["address"], "Central Station, Thiruvananthapuram, Kerala")
        self.assertAlmostEqual(response.data["latitude"], 8.4875)
        self.assertAlmostEqual(response.data["longitude"], 76.9525)


class IssueAddressPersistenceTests(TestCase):
    def setUp(self):
        clear_cache()
        self.client = APIClient()
        self.user = User.objects.create_user(
            email="reporter@example.com",
            phone="9876543212",
            full_name="Reporter",
            role="citizen",
            is_active=True,
            approval_status="approved",
        )
        self.client.force_authenticate(user=self.user)

    @patch("apps.issues.geocode.reverse_geocode")
    def test_create_issue_auto_resolves_address_when_missing(self, mock_geocode):
        mock_geocode.return_value = "Auto Resolved Street, Thiruvananthapuram"

        import io
        from PIL import Image
        from django.core.files.uploadedfile import SimpleUploadedFile

        img_io = io.BytesIO()
        Image.new("RGB", (10, 10), color="blue").save(img_io, format="JPEG")
        photo = SimpleUploadedFile("test.jpg", img_io.getvalue(), content_type="image/jpeg")

        response = self.client.post(
            reverse("issue-list-create"),
            {
                "original_description": "Water pipe leak on road",
                "category": "water",
                "latitude": 8.5241,
                "longitude": 76.9366,
                "ai_suggested_category": "water",
                "ai_severity": "medium",
                "ai_validation_status": "valid",
                "photo": photo,
            },
            format="multipart",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["address"], "Auto Resolved Street, Thiruvananthapuram")

        # Verify DB
        issue = Issue.objects.get(id=response.data["id"])
        self.assertEqual(issue.address, "Auto Resolved Street, Thiruvananthapuram")

    def test_create_issue_preserves_client_supplied_address(self):
        import io
        from PIL import Image
        from django.core.files.uploadedfile import SimpleUploadedFile

        img_io = io.BytesIO()
        Image.new("RGB", (10, 10), color="red").save(img_io, format="JPEG")
        photo = SimpleUploadedFile("test.jpg", img_io.getvalue(), content_type="image/jpeg")

        response = self.client.post(
            reverse("issue-list-create"),
            {
                "original_description": "Streetlight broken",
                "category": "streetlight",
                "latitude": 8.5241,
                "longitude": 76.9366,
                "address": "Client Provided Address, Sector 4",
                "ai_suggested_category": "streetlight",
                "ai_severity": "low",
                "ai_validation_status": "valid",
                "photo": photo,
            },
            format="multipart",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["address"], "Client Provided Address, Sector 4")

        issue = Issue.objects.get(id=response.data["id"])
        self.assertEqual(issue.address, "Client Provided Address, Sector 4")


class BackfillAddressesCommandTests(TestCase):
    @patch("apps.issues.management.commands.backfill_addresses.reverse_geocode")
    def test_backfill_command_resolves_blank_addresses(self, mock_geocode):
        mock_geocode.return_value = "Backfilled Location, Kerala"

        user = User.objects.create_user(
            email="backfill_user@example.com",
            phone="9876543213",
            full_name="Backfill User",
            role="citizen",
            is_active=True,
            approval_status="approved",
        )

        issue_unresolved = Issue.objects.create(
            reported_by=user,
            original_description="Old issue without address",
            category="pothole",
            latitude=8.5100,
            longitude=76.9200,
            address="",
        )
        issue_resolved = Issue.objects.create(
            reported_by=user,
            original_description="Issue already with address",
            category="pothole",
            latitude=8.5200,
            longitude=76.9300,
            address="Existing Valid Address",
        )

        call_command("backfill_addresses")

        issue_unresolved.refresh_from_db()
        issue_resolved.refresh_from_db()

        self.assertEqual(issue_unresolved.address, "Backfilled Location, Kerala")
        self.assertEqual(issue_resolved.address, "Existing Valid Address")


class AuthorityGeocodingViewsTests(TestCase):
    def setUp(self):
        self.authority = User.objects.create_user(
            email="auth_officer@example.com",
            phone="9876543299",
            full_name="Authority Officer",
            role="authority",
            is_active=True,
            approval_status="approved",
        )
        self.authority.set_password("pass1234")
        self.authority.save()

        self.citizen = User.objects.create_user(
            email="cit_1@example.com",
            phone="9876543298",
            full_name="Citizen One",
            role="citizen",
            is_active=True,
            approval_status="approved",
        )

        self.issue_with_addr = Issue.objects.create(
            reported_by=self.citizen,
            original_description="Street light flickering",
            category="streetlight",
            latitude=8.5241,
            longitude=76.9366,
            address="Vellayambalam Junction, Trivandrum",
        )

        self.issue_without_addr = Issue.objects.create(
            reported_by=self.citizen,
            original_description="Garbage pile up",
            category="garbage",
            latitude=8.5000,
            longitude=76.9500,
            address="",
        )

    @patch("apps.issues.geocode.reverse_geocode")
    def test_authority_issue_list_renders_address(self, mock_geocode):
        mock_geocode.return_value = ""
        self.client.force_login(self.authority)
        response = self.client.get(reverse("authority:issues"))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Vellayambalam Junction, Trivandrum")
        # Should NOT contain raw coordinates in the primary address container
        self.assertNotContains(response, "8.52410, 76.93660")

    def test_authority_issue_detail_renders_address(self):
        self.client.force_login(self.authority)
        response = self.client.get(reverse("authority:issue-detail", args=[self.issue_with_addr.id]))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Vellayambalam Junction, Trivandrum")

    def test_authority_map_includes_address_in_json(self):
        self.client.force_login(self.authority)
        response = self.client.get(reverse("authority:map"))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Vellayambalam Junction, Trivandrum")

