import json
from unittest.mock import MagicMock, patch

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient

from google.genai.errors import ClientError, ServerError

from .ai_classifier import (
    classify_issue,
    detect_duplicate_issue,
    get_model_name,
    validate_and_prepare_image,
)
from .models import Issue

User = get_user_model()


class MockGenAIResponse:
    def __init__(self, text: str):
        self.text = text


class AIClassifierUnitTests(TestCase):
    """Unit tests for ai_classifier.py covering all failure and success scenarios."""

    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_classify_success_with_all_fields(self, mock_get_client):
        """Test happy path: Gemini returns complete structured JSON."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client
        mock_client.models.generate_content.return_value = MockGenAIResponse(
            json.dumps({
                "detected_language": "ml",
                "translated_description": "Large pothole in the road near town hall",
                "category": "pothole",
                "severity": "high",
                "is_duplicate": False,
                "duplicate_of": None,
                "duplicate_reason": None,
            })
        )

        result = classify_issue("റോഡിൽ വലിയ കുഴിയുണ്ട്")

        self.assertIsNotNone(result)
        self.assertEqual(result["category"], "pothole")
        self.assertEqual(result["severity"], "high")
        self.assertEqual(result["detected_language"], "ml")
        self.assertEqual(result["translated_description"], "Large pothole in the road near town hall")
        self.assertFalse(result["is_duplicate"])
        self.assertIsNone(result["duplicate_of"])
        self.assertTrue(result["ai_success"])

    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_classify_genuine_other(self, mock_get_client):
        """Test genuine 'other' category prediction is distinguished and marked ai_success: True."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client
        mock_client.models.generate_content.return_value = MockGenAIResponse(
            json.dumps({
                "detected_language": "en",
                "translated_description": "Fallen tree blocking the sidewalk",
                "category": "other",
                "severity": "medium",
                "is_duplicate": False,
                "duplicate_of": None,
                "duplicate_reason": None,
            })
        )

        result = classify_issue("Fallen tree blocking the sidewalk")

        self.assertIsNotNone(result)
        self.assertEqual(result["category"], "other")
        self.assertEqual(result["severity"], "medium")
        self.assertTrue(result["ai_success"])

    @patch("time.sleep", return_value=None)
    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_classify_timeout_and_recovery(self, mock_get_client, mock_sleep):
        """Test transient timeout on attempt 1, followed by recovery on attempt 2."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        # Attempt 1 raises Timeout exception, Attempt 2 succeeds
        mock_client.models.generate_content.side_effect = [
            TimeoutError("Connection timed out"),
            MockGenAIResponse(
                json.dumps({
                    "detected_language": "en",
                    "translated_description": "Streetlight broken",
                    "category": "streetlight",
                    "severity": "low",
                    "is_duplicate": False,
                    "duplicate_of": None,
                    "duplicate_reason": None,
                })
            ),
        ]

        result = classify_issue("Streetlight broken")

        self.assertIsNotNone(result)
        self.assertEqual(result["category"], "streetlight")
        self.assertEqual(mock_client.models.generate_content.call_count, 2)
        mock_sleep.assert_called_once()

    @patch("time.sleep", return_value=None)
    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_classify_rate_limit_429_then_recovers(self, mock_get_client, mock_sleep):
        """Test 429 rate limit triggers exponential backoff and succeeds on retry."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        rate_limit_error = ClientError(429, {"error": {"message": "Resource exhausted", "code": 429}})
        mock_client.models.generate_content.side_effect = [
            rate_limit_error,
            MockGenAIResponse(
                json.dumps({
                    "detected_language": "en",
                    "translated_description": "Garbage dump overflowing",
                    "category": "garbage",
                    "severity": "high",
                    "is_duplicate": False,
                    "duplicate_of": None,
                    "duplicate_reason": None,
                })
            ),
        ]

        result = classify_issue("Garbage dump overflowing")

        self.assertIsNotNone(result)
        self.assertEqual(result["category"], "garbage")
        self.assertEqual(mock_client.models.generate_content.call_count, 2)
        mock_sleep.assert_called_once()

    @patch("time.sleep", return_value=None)
    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_classify_rate_limit_exhausted(self, mock_get_client, mock_sleep):
        """Test bounded retries when 429 persists across all attempts."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        rate_limit_error = ClientError(429, {"error": {"message": "Resource exhausted", "code": 429}})
        mock_client.models.generate_content.side_effect = rate_limit_error

        result = classify_issue("Garbage pile")

        self.assertIsNotNone(result)
        self.assertFalse(result["ai_success"])
        self.assertEqual(result["error_type"], "quota_exhausted")
        self.assertEqual(mock_client.models.generate_content.call_count, 3)

    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_classify_permanent_error_fails_fast(self, mock_get_client):
        """Permanent errors (e.g. 401 unauthenticated or 400 bad request) fail immediately without retrying."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client

        auth_error = ClientError(401, {"error": {"message": "Invalid API Key", "code": 401}})
        mock_client.models.generate_content.side_effect = auth_error

        result = classify_issue("Water pipe burst")

        self.assertIsNotNone(result)
        self.assertFalse(result["ai_success"])
        self.assertEqual(result["error_type"], "invalid_key")
        # Must fail fast on attempt 1
        self.assertEqual(mock_client.models.generate_content.call_count, 1)

    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_classify_malformed_json_handled_safely(self, mock_get_client):
        """Test malformed / garbled response is caught safely and returns structured error without crashing."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client
        mock_client.models.generate_content.return_value = MockGenAIResponse(
            "I am an AI and here is the result: {not valid json at all}"
        )

        result = classify_issue("Something is broken")
        self.assertIsNotNone(result)
        self.assertFalse(result["ai_success"])
        self.assertIn("error", result)

    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_classify_missing_fields_defaults_safely(self, mock_get_client):
        """Test missing fields in response use safe defaults instead of failing."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client
        # Missing severity and invalid category
        mock_client.models.generate_content.return_value = MockGenAIResponse(
            json.dumps({
                "category": "unknown_category_xyz",
            })
        )

        result = classify_issue("Road problem")

        self.assertIsNotNone(result)
        self.assertEqual(result["category"], "other")
        self.assertEqual(result["severity"], "medium")
        self.assertEqual(result["detected_language"], "en")
        self.assertFalse(result["is_duplicate"])

    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_duplicate_detection_found(self, mock_get_client):
        """Test duplicate issue detection correctly links to provided nearby ID."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client
        mock_client.models.generate_content.return_value = MockGenAIResponse(
            json.dumps({
                "detected_language": "en",
                "translated_description": "Huge pothole at bus stop",
                "category": "pothole",
                "severity": "high",
                "is_duplicate": True,
                "duplicate_of": 42,
                "duplicate_reason": "Same pothole at bus stop reported earlier.",
            })
        )

        result = classify_issue(
            "Big pothole at the bus stop",
            nearby_issue_ids=[42, 99],
        )

        self.assertIsNotNone(result)
        self.assertTrue(result["is_duplicate"])
        self.assertEqual(result["duplicate_of"], 42)
        self.assertIn("Same pothole", result["duplicate_reason"])

    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_duplicate_fabricated_id_rejected(self, mock_get_client):
        """Test that if AI hallucinates an ID not in the nearby issues, duplicate status is rejected."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client
        mock_client.models.generate_content.return_value = MockGenAIResponse(
            json.dumps({
                "detected_language": "en",
                "translated_description": "Water leak",
                "category": "water",
                "severity": "medium",
                "is_duplicate": True,
                "duplicate_of": 9999,  # Not in nearby_issue_ids!
                "duplicate_reason": "Fabricated match",
            })
        )

        result = classify_issue(
            "Water pipe leak",
            nearby_issue_ids=[10, 20],
        )

        self.assertIsNotNone(result)
        # Because 9999 was not in [10, 20], must be normalized to False
        self.assertFalse(result["is_duplicate"])
        self.assertIsNone(result["duplicate_of"])

    @patch("apps.issues.ai_classifier.get_genai_client")
    def test_classify_multimodal_valid_match(self, mock_get_client):
        """Test multimodal classification when image and description match."""
        mock_client = MagicMock()
        mock_get_client.return_value = mock_client
        mock_client.models.generate_content.return_value = MockGenAIResponse(
            json.dumps({
                "detected_language": "en",
                "translated_description": "Massive pothole on road",
                "category": "pothole",
                "severity": "critical",
                "severity_basis": "text_and_image",
                "severity_reason": "Deep crater exceeding 15cm depth in middle lane posing immediate tire hazard",
                "validation_status": "valid",
                "is_image_match": True,
                "image_match_reason": "Photo clearly shows a deep circular crater in asphalt",
                "is_duplicate": False,
                "duplicate_of": None,
                "duplicate_reason": None,
            })
        )

        from django.core.files.uploadedfile import SimpleUploadedFile
        gif_bytes = b'GIF89a\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;'
        test_img = SimpleUploadedFile("pothole.gif", gif_bytes, content_type="image/gif")

        result = classify_issue("Massive pothole on road", image_file=test_img)

        self.assertTrue(result["ai_success"])
        self.assertEqual(result["category"], "pothole")
        self.assertEqual(result["severity"], "critical")
        self.assertEqual(result["severity_basis"], "text_and_image")
        self.assertEqual(result["validation_status"], "valid")
        self.assertTrue(result["is_image_match"])

    def test_validate_and_prepare_image(self):
        """Test image validation and preparation for valid, corrupt, and oversized images."""
        from django.core.files.uploadedfile import SimpleUploadedFile

        # 1. Valid GIF
        gif_bytes = b'GIF89a\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;'
        valid_file = SimpleUploadedFile("test.gif", gif_bytes, content_type="image/gif")
        part, severity_basis, err = validate_and_prepare_image(valid_file)
        self.assertIsNotNone(part)
        self.assertEqual(severity_basis, "text_and_image")
        self.assertIsNone(err)

        # 2. Corrupted image
        corrupt_file = SimpleUploadedFile("bad.png", b"not an image", content_type="image/png")
        part, mime, err = validate_and_prepare_image(corrupt_file)
        self.assertIsNone(part)
        self.assertIn("corrupt", err.lower())

        # 3. Oversized file (> 10MB)
        large_mock = MagicMock()
        large_mock.size = 11 * 1024 * 1024
        part, mime, err = validate_and_prepare_image(large_mock)
        self.assertIsNone(part)
        self.assertIn("exceeds", err.lower())


class AIViewsIntegrationTests(TestCase):
    """Integration tests for ClassifyIssueView and IssueListCreateView."""

    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            email="citizen@example.com",
            password="testpassword123",
            role="citizen",
            full_name="Citizen Tester",
            approval_status="approved",
            is_active=True,
        )
        self.client.force_authenticate(user=self.user)

    @patch("apps.issues.views.classify_issue")
    def test_classify_view_success(self, mock_classify):
        """Test POST /api/issues/classify/ returns 200 with structured data."""
        mock_classify.return_value = {
            "category": "pothole",
            "severity": "high",
            "detected_language": "en",
            "translated_description": "Deep pothole on MG Road",
            "is_duplicate": False,
            "duplicate_of": None,
            "duplicate_reason": None,
            "ai_success": True,
        }

        url = reverse("issue-classify")
        response = self.client.post(
            url,
            {"description": "Deep pothole on MG Road"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertTrue(data["ai_success"])
        self.assertEqual(data["category"], "pothole")
        self.assertEqual(data["severity"], "high")

    @patch("apps.issues.views.classify_issue")
    def test_classify_view_failure_returns_503(self, mock_classify):
        """Test POST /api/issues/classify/ returns 503 when AI is unavailable."""
        mock_classify.return_value = None

        url = reverse("issue-classify")
        response = self.client.post(
            url,
            {"description": "Deep pothole on MG Road"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        data = response.json()
        self.assertFalse(data["ai_success"])
        self.assertIn("error", data)

    @patch("apps.issues.views.classify_issue")
    def test_issue_create_with_preclassified_ai_persists(self, mock_classify):
        """Test that pre-classified AI results from Flutter are stored directly without redundant Gemini call."""
        url = reverse("issue-list-create")
        payload = {
            "original_description": "Broken street lamp near sector 4",
            "latitude": "12.971600",
            "longitude": "77.594600",
            "ai_suggested_category": "streetlight",
            "ai_severity": "low",
            "detected_language": "en",
            "translated_description": "Broken street lamp near sector 4",
        }

        from django.core.files.uploadedfile import SimpleUploadedFile
        gif_bytes = b'GIF89a\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;'
        photo = SimpleUploadedFile("lamp.gif", gif_bytes, content_type="image/gif")
        payload["photo"] = photo

        response = self.client.post(url, payload, format="multipart")

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        # classify_issue should NOT have been called because AI fields were already supplied
        mock_classify.assert_not_called()

        issue = Issue.objects.get(id=response.data["id"])
        self.assertEqual(issue.category, "streetlight")
        self.assertEqual(issue.ai_suggested_category, "streetlight")
        self.assertEqual(issue.ai_severity, "low")
        self.assertEqual(response.data["ai_status"], "success")

    @patch("apps.issues.views.classify_issue")
    def test_issue_create_when_ai_fails_marks_status_failed(self, mock_classify):
        """When AI fails during issue creation, ai_status must be 'failed' and category not falsely claimed as AI."""
        mock_classify.return_value = None

        url = reverse("issue-list-create")
        payload = {
            "original_description": "Broken drain cover",
            "latitude": "12.971600",
            "longitude": "77.594600",
        }

        from django.core.files.uploadedfile import SimpleUploadedFile
        gif_bytes = b'GIF89a\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;'
        photo = SimpleUploadedFile("drain.gif", gif_bytes, content_type="image/gif")
        payload["photo"] = photo

        response = self.client.post(url, payload, format="multipart")

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        issue = Issue.objects.get(id=response.data["id"])
        self.assertEqual(issue.ai_suggested_category, "")
        self.assertEqual(issue.ai_severity, "")
        self.assertEqual(response.data["ai_status"], "failed")

    @patch("apps.issues.views.classify_issue")
    def test_issue_create_mismatch_rejected_http_400(self, mock_classify):
        """When pre-classified AI flags mismatch between description and photo, creation must be rejected with HTTP 400."""
        url = reverse("issue-list-create")
        payload = {
            "original_description": "Streetlight not working",
            "latitude": "12.971600",
            "longitude": "77.594600",
            "ai_validation_status": "mismatch",
            "ai_image_match_reason": "Photo shows a cat, unrelated to street lighting",
        }

        from django.core.files.uploadedfile import SimpleUploadedFile
        gif_bytes = b'GIF89a\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;'
        payload["photo"] = SimpleUploadedFile("cat.gif", gif_bytes, content_type="image/gif")

        response = self.client.post(url, payload, format="multipart")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("error", response.data)
        self.assertIn("do not match", response.data["error"])
        # Verify no issue was created
        self.assertFalse(Issue.objects.filter(original_description="Streetlight not working").exists())

    @patch("apps.issues.views.classify_issue")
    def test_issue_create_uncertain_allowed_and_persisted(self, mock_classify):
        """When AI validation status is uncertain and citizen confirms, report is accepted and persisted with uncertain status."""
        url = reverse("issue-list-create")
        payload = {
            "original_description": "Water leak in alley",
            "latitude": "12.971600",
            "longitude": "77.594600",
            "ai_suggested_category": "water",
            "ai_severity": "medium",
            "ai_severity_basis": "text_and_image",
            "ai_severity_reason": "Moderate water pool in side alley",
            "ai_validation_status": "uncertain",
            "ai_image_match_reason": "Image is slightly dark, could not fully confirm leak source",
        }

        from django.core.files.uploadedfile import SimpleUploadedFile
        gif_bytes = b'GIF89a\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;'
        payload["photo"] = SimpleUploadedFile("dark.gif", gif_bytes, content_type="image/gif")

        response = self.client.post(url, payload, format="multipart")

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        issue = Issue.objects.get(id=response.data["id"])
        self.assertEqual(issue.ai_validation_status, "uncertain")
        self.assertEqual(issue.ai_severity, "medium")
        self.assertEqual(issue.ai_severity_basis, "text_and_image")

    @patch("apps.issues.views.classify_issue")
    def test_classify_view_with_photo_multipart(self, mock_classify):
        """Test POST /api/issues/classify/ with multipart photo upload passes image to classifier and returns multimodal fields."""
        mock_classify.return_value = {
            "category": "pothole",
            "severity": "high",
            "severity_basis": "text_and_image",
            "severity_reason": "Visible deep damage on arterial road",
            "validation_status": "valid",
            "is_image_match": True,
            "image_match_reason": "Photo clearly shows deep pothole in asphalt",
            "detected_language": "en",
            "translated_description": "Dangerous pothole near metro station",
            "is_duplicate": False,
            "duplicate_of": None,
            "duplicate_reason": None,
            "ai_success": True,
        }

        from django.core.files.uploadedfile import SimpleUploadedFile
        gif_bytes = b'GIF89a\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;'
        photo = SimpleUploadedFile("metro_pothole.gif", gif_bytes, content_type="image/gif")

        url = reverse("issue-classify")
        response = self.client.post(
            url,
            {
                "description": "Dangerous pothole near metro station",
                "photo": photo,
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertTrue(data["ai_success"])
        self.assertEqual(data["severity_basis"], "text_and_image")
        self.assertEqual(data["validation_status"], "valid")
        self.assertTrue(data["is_image_match"])
        self.assertEqual(data["image_match_reason"], "Photo clearly shows deep pothole in asphalt")