import json
from django.test import TestCase, override_settings
from django.urls import reverse
from django.contrib.auth import get_user_model

from apps.issues.models import Issue

User = get_user_model()


class AuthorityMapViewTests(TestCase):
    def setUp(self):
        self.authority = User.objects.create_user(
            email="auth_map_admin@example.com",
            phone="9876543201",
            full_name="Authority Admin",
            role="authority",
            is_active=True,
            approval_status="approved",
        )
        self.citizen = User.objects.create_user(
            email="cit_map_user@example.com",
            phone="9876543202",
            full_name="Citizen Tester",
            role="citizen",
            is_active=True,
            approval_status="approved",
        )

        # Issue 1: Valid coordinates
        self.issue_valid = Issue.objects.create(
            reported_by=self.citizen,
            original_description="Pothole on Main Road",
            category="pothole",
            status="reported",
            ai_severity="high",
            latitude=8.5241,
            longitude=76.9366,
            address="Main Road, Trivandrum",
        )

        # Issue 2: Another valid issue
        self.issue_water = Issue.objects.create(
            reported_by=self.citizen,
            original_description="Broken water pipeline",
            category="water",
            status="in_progress",
            ai_severity="medium",
            latitude=8.5000,
            longitude=76.9500,
            address="Water Works Road, Trivandrum",
        )

        # Issue 3: Invalid coordinates (e.g. 0, 0 or null)
        self.issue_invalid = Issue.objects.create(
            reported_by=self.citizen,
            original_description="Issue without proper GPS",
            category="garbage",
            status="reported",
            ai_severity="low",
            latitude=0.0,
            longitude=0.0,
            address="",
        )

    def test_anonymous_redirected_to_login(self):
        response = self.client.get(reverse("authority:map"))
        self.assertEqual(response.status_code, 302)
        self.assertIn("/authority/login/", response.url)

    def test_authority_map_renders_successfully(self):
        self.client.force_login(self.authority)
        response = self.client.get(reverse("authority:map"))
        self.assertEqual(response.status_code, 200)
        self.assertTemplateUsed(response, "authority/map.html")

        # Check context
        self.assertEqual(response.context["mapped_count"], 2)
        self.assertEqual(response.context["unmapped_count"], 1)
        self.assertEqual(response.context["total_count"], 3)

        # Check content
        content = response.content.decode("utf-8")
        self.assertIn("Main Road, Trivandrum", content)
        self.assertIn("Water Works Road, Trivandrum", content)
        self.assertIn("authority-map", content)
        self.assertIn("map-data", content)
        self.assertIn("invalidateSize", content)
        self.assertIn("arcgisonline.com", content)

    def test_authority_map_category_filter(self):
        self.client.force_login(self.authority)
        response = self.client.get(reverse("authority:map"), {"category": "pothole"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.context["mapped_count"], 1)
        self.assertEqual(response.context["total_count"], 1)

        map_data = json.loads(response.context["map_data"])
        self.assertEqual(len(map_data), 1)
        self.assertEqual(map_data[0]["id"], self.issue_valid.id)

    def test_authority_map_search_filter(self):
        self.client.force_login(self.authority)
        response = self.client.get(reverse("authority:map"), {"search": "pipeline"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.context["mapped_count"], 1)

        map_data = json.loads(response.context["map_data"])
        self.assertEqual(len(map_data), 1)
        self.assertEqual(map_data[0]["id"], self.issue_water.id)

    @override_settings(
        MAP_TILE_URL="https://custom.tiles.example.com/{z}/{x}/{y}.png",
        MAP_TILE_ATTRIBUTION="&copy; Custom Map Provider",
    )
    def test_authority_map_configurable_tile_settings(self):
        self.client.force_login(self.authority)
        response = self.client.get(reverse("authority:map"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.context["tile_url"],
            "https://custom.tiles.example.com/{z}/{x}/{y}.png",
        )
        self.assertIn("https://custom.tiles.example.com/{z}/{x}/{y}.png", response.content.decode("utf-8"))
        self.assertIn("Custom Map Provider", response.content.decode("utf-8"))

    def test_issue_detail_mini_map_renders_with_shared_tiles(self):
        self.client.force_login(self.authority)
        response = self.client.get(reverse("authority:issue-detail", args=[self.issue_valid.id]))
        self.assertEqual(response.status_code, 200)
        content = response.content.decode("utf-8")
        self.assertIn("detail-map", content)
        self.assertIn("arcgisonline.com", content)
        self.assertNotIn("cartocdn.com", content)  # No CARTO watermarked tiles!
        self.assertIn("invalidateSize", content)

