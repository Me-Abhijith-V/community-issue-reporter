import io
import json
import logging
import os
import re
import time
from typing import Any, Dict, List, Optional, Set, Tuple

from google import genai
from google.genai import types
from google.genai.errors import APIError, ClientError, ServerError
from PIL import Image

logger = logging.getLogger("issues.ai_classifier")

# ---------------------------------------------------------------------------
# Model and Validation Configuration
# ---------------------------------------------------------------------------
DEFAULT_GEMINI_MODEL = "gemini-1.5-flash"

ALLOWED_CATEGORIES: Set[str] = {
    "pothole",
    "streetlight",
    "garbage",
    "water",
    "other",
}

ALLOWED_SEVERITIES: Set[str] = {
    "low",
    "medium",
    "high",
    "critical",
}

VALIDATION_STATUSES: Set[str] = {
    "valid",
    "mismatch",
    "uncertain",
}

DEFAULT_MAX_RETRIES = 3
DEFAULT_INITIAL_DELAY = 1.0  # seconds
DEFAULT_MAX_DELAY = 8.0  # seconds
MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB


class GeminiExecutionError(Exception):
    """Structured exception carrying diagnostic metadata about Gemini API failure."""

    def __init__(self, error_type: str, message: str, status_code: Optional[int] = None):
        super().__init__(message)
        self.error_type = error_type
        self.message = message
        self.status_code = status_code


def get_model_name() -> str:
    """Return configured Gemini primary model name from environment or fallback."""
    model = os.getenv("GEMINI_MODEL", DEFAULT_GEMINI_MODEL).strip()
    return model or DEFAULT_GEMINI_MODEL


def get_fallback_model_name() -> Optional[str]:
    """Return configured fallback model name if set and distinct."""
    fallback = os.getenv("GEMINI_FALLBACK_MODEL", "").strip()
    primary = get_model_name()
    if fallback and fallback != primary:
        return fallback
    return None


def get_genai_client() -> genai.Client:
    """
    Lazily initialize Google GenAI Client with GEMINI_API_KEY.
    Raises ValueError if API key is not configured.
    """
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise ValueError("GEMINI_API_KEY environment variable is not configured.")
    return genai.Client(api_key=api_key)


def classify_gemini_error(exc: Exception) -> Tuple[str, str, Optional[int], bool, Optional[float]]:
    """
    Diagnose actual error type and return:
    (error_type, user_friendly_message, status_code, is_transient, retry_after)
    """
    status_code: Optional[int] = getattr(exc, "code", None)
    retry_after: Optional[float] = None

    if isinstance(exc, APIError):
        # Extract Retry-After header if returned
        if hasattr(exc, "response") and exc.response and hasattr(exc.response, "headers"):
            raw_retry = exc.response.headers.get("retry-after")
            if raw_retry:
                try:
                    retry_after = float(raw_retry)
                except (ValueError, TypeError):
                    pass

        if status_code == 401:
            return (
                "invalid_key",
                "Gemini API key is invalid or unauthenticated. Please configure a valid GEMINI_API_KEY.",
                401,
                False,
                None,
            )
        if status_code == 403:
            return (
                "forbidden",
                "Access to the Gemini API model is forbidden with current credentials.",
                403,
                False,
                None,
            )
        if status_code == 404:
            return (
                "model_not_found",
                f"Configured Gemini model was not found.",
                404,
                False,
                None,
            )
        if status_code == 429:
            return (
                "quota_exhausted",
                "Gemini API rate limit or quota exceeded. Please try again shortly.",
                429,
                True,
                retry_after,
            )
        if status_code == 400:
            return (
                "bad_request",
                "Gemini API rejected the request payload as invalid.",
                400,
                False,
                None,
            )
        if isinstance(exc, ServerError) or (status_code and 500 <= status_code < 600):
            return (
                "server_error",
                f"Gemini server encountered a temporary error ({status_code}).",
                status_code,
                True,
                retry_after,
            )

    err_str = str(exc).lower()
    if "401" in err_str or "unauthenticated" in err_str or "invalid api key" in err_str:
        return (
            "invalid_key",
            "Gemini API key is invalid or unauthenticated.",
            401,
            False,
            None,
        )
    if "429" in err_str or "resource exhausted" in err_str or "too many requests" in err_str or "quota" in err_str:
        return (
            "quota_exhausted",
            "Gemini API rate limit or quota exceeded.",
            429,
            True,
            None,
        )
    if "timeout" in err_str or "timed out" in err_str:
        return (
            "timeout",
            "Request to Gemini API timed out.",
            None,
            True,
            None,
        )
    if "connection" in err_str or "network" in err_str or "reset" in err_str:
        return (
            "network_error",
            "Network connection error contacting Gemini service.",
            None,
            True,
            None,
        )

    return (
        "unknown",
        f"Gemini API call failed: {str(exc)}",
        status_code,
        False,
        None,
    )


def validate_and_prepare_image(image_input: Any) -> Tuple[Optional[types.Part], str, Optional[str]]:
    """
    Validate file size and image integrity using PIL.
    Returns:
        (image_part, severity_basis, error_message)
        - image_part: types.Part if valid, None otherwise
        - severity_basis: "text_and_image" or "text_only"
        - error_message: None if successful, descriptive string if invalid
    """
    if image_input is None:
        return None, "text_only", None

    if hasattr(image_input, "size") and getattr(image_input, "size", 0) > MAX_IMAGE_SIZE_BYTES:
        return None, "text_only", f"Image size exceeds maximum 10MB limit ({image_input.size} bytes)."

    raw_bytes: Optional[bytes] = None

    try:
        if hasattr(image_input, "read"):
            if hasattr(image_input, "seek"):
                image_input.seek(0)
            raw_bytes = image_input.read()
            if hasattr(image_input, "seek"):
                image_input.seek(0)
        elif isinstance(image_input, bytes):
            raw_bytes = image_input
        elif isinstance(image_input, str) and os.path.exists(image_input):
            with open(image_input, "rb") as f:
                raw_bytes = f.read()
    except Exception as exc:
        return None, "text_only", f"Unable to read image input: {str(exc)}"

    if not raw_bytes or len(raw_bytes) == 0:
        return None, "text_only", "Image file is empty."

    if len(raw_bytes) > MAX_IMAGE_SIZE_BYTES:
        return None, "text_only", f"Image size exceeds maximum 10MB limit ({len(raw_bytes)} bytes)."

    try:
        img = Image.open(io.BytesIO(raw_bytes))
        img.verify()
        fmt = (img.format or "JPEG").upper()
        mime_map = {
            "JPEG": "image/jpeg",
            "JPG": "image/jpeg",
            "PNG": "image/png",
            "WEBP": "image/webp",
            "GIF": "image/gif",
        }
        if fmt not in mime_map:
            return None, "text_only", f"Unsupported image format: {fmt}."

        mime_type = mime_map[fmt]
        part = types.Part.from_bytes(data=raw_bytes, mime_type=mime_type)
        return part, "text_and_image", None
    except Exception as exc:
        return None, "text_only", f"Invalid or corrupted image file: {str(exc)}"


def _clean_json_text(text: str) -> str:
    """Extract and isolate JSON text from markdown code fences or conversational text."""
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text)
        text = text.strip()

    match = re.search(r"(\{.*\})", text, re.DOTALL)
    if match:
        text = match.group(1).strip()

    return text


def _format_nearby_issues(nearby_issues: Optional[List[Any]]) -> str:
    """Format nearby issues into clear text with ID, category, and description."""
    if not nearby_issues:
        return "None reported nearby."

    lines = []
    for item in nearby_issues:
        if isinstance(item, dict):
            issue_id = item.get("id")
            cat = item.get("category", "issue")
            desc = (
                item.get("translated_description")
                or item.get("original_description")
                or item.get("description", "")
            )
        else:
            issue_id = getattr(item, "id", None)
            cat = getattr(item, "category", "issue")
            desc = getattr(item, "translated_description", None) or getattr(
                item, "original_description", ""
            )

        if issue_id is not None:
            clean_desc = str(desc).strip().replace("\n", " ")[:200]
            lines.append(f"- Issue ID {issue_id} [{cat}]: \"{clean_desc}\"")

    return "\n".join(lines) if lines else "None reported nearby."


def _execute_with_retry_and_fallback(
    contents: Any,
    config: Optional[types.GenerateContentConfig] = None,
) -> str:
    """
    Execute Gemini API call with bounded retries, Retry-After header respect,
    exponential backoff, and optional configured fallback model.
    """
    client = get_genai_client()

    primary_model = get_model_name()
    fallback_model = get_fallback_model_name()
    models_to_try = [primary_model]
    if fallback_model:
        models_to_try.append(fallback_model)

    try:
        max_retries = int(os.getenv("GEMINI_MAX_RETRIES", DEFAULT_MAX_RETRIES))
    except (ValueError, TypeError):
        max_retries = DEFAULT_MAX_RETRIES

    try:
        initial_delay = float(os.getenv("GEMINI_INITIAL_RETRY_DELAY", DEFAULT_INITIAL_DELAY))
    except (ValueError, TypeError):
        initial_delay = DEFAULT_INITIAL_DELAY

    try:
        max_delay = float(os.getenv("GEMINI_MAX_RETRY_DELAY", DEFAULT_MAX_DELAY))
    except (ValueError, TypeError):
        max_delay = DEFAULT_MAX_DELAY

    last_error_diag: Optional[Tuple[str, str, Optional[int], bool, Optional[float]]] = None

    for model_name in models_to_try:
        logger.info("Attempting Gemini request with model: %s", model_name)
        for attempt in range(1, max_retries + 1):
            start_time = time.time()
            try:
                logger.info(
                    "Gemini request start (model=%s, attempt=%d/%d)",
                    model_name,
                    attempt,
                    max_retries,
                )
                response = client.models.generate_content(
                    model=model_name,
                    contents=contents,
                    config=config,
                )
                latency_ms = int((time.time() - start_time) * 1000)
                logger.info(
                    "Gemini request success (model=%s, attempt=%d, latency=%dms)",
                    model_name,
                    attempt,
                    latency_ms,
                )
                if not response or not response.text:
                    raise ValueError("Gemini returned empty response text.")
                return response.text

            except Exception as exc:
                latency_ms = int((time.time() - start_time) * 1000)
                err_type, friendly_msg, status_code, is_transient, retry_after = classify_gemini_error(exc)
                last_error_diag = (err_type, friendly_msg, status_code, is_transient, retry_after)

                # Scrub API key from logs
                error_msg = str(exc)
                api_key = os.getenv("GEMINI_API_KEY", "")
                if api_key and api_key in error_msg:
                    error_msg = error_msg.replace(api_key, "[REDACTED_API_KEY]")

                logger.warning(
                    "Gemini request failed (model=%s, attempt=%d/%d, type=%s, status=%s, latency=%dms): %s",
                    model_name,
                    attempt,
                    max_retries,
                    err_type,
                    status_code,
                    latency_ms,
                    error_msg,
                )

                if not is_transient:
                    logger.error(
                        "Permanent error encountered from Gemini (type=%s, status=%s). Aborting retries.",
                        err_type,
                        status_code,
                    )
                    raise GeminiExecutionError(err_type, friendly_msg, status_code)

                if attempt >= max_retries:
                    logger.warning(
                        "Exhausted %d attempts for model %s.",
                        max_retries,
                        model_name,
                    )
                    break

                # Backoff calculation: respect Retry-After if provided
                if retry_after is not None and retry_after > 0:
                    backoff = min(max_delay, retry_after)
                else:
                    backoff = min(max_delay, initial_delay * (2 ** (attempt - 1)))
                    backoff += (attempt * 0.1)

                logger.info("Retrying Gemini request after %.2f seconds backoff...", backoff)
                time.sleep(backoff)

    # If we reached here, all attempts (and models) failed
    if last_error_diag:
        err_type, friendly_msg, status_code, _, _ = last_error_diag
        raise GeminiExecutionError(err_type, friendly_msg, status_code)

    raise GeminiExecutionError("unknown", "Gemini request failed after all retries.")


def _validate_and_normalize_result(
    raw_dict: Dict[str, Any],
    original_description: str,
    valid_nearby_ids: Set[int],
    severity_basis: str,
    image_err_note: Optional[str] = None,
) -> Dict[str, Any]:
    """Validate and normalize fields from raw AI JSON response."""
    # 1. Validation status & Image match
    val_status = str(raw_dict.get("validation_status", "valid")).strip().lower()
    if val_status not in VALIDATION_STATUSES:
        val_status = "uncertain"

    is_img_match = raw_dict.get("is_image_match")
    if is_img_match is not None and not isinstance(is_img_match, bool):
        is_img_match = str(is_img_match).lower() in ("true", "1", "yes")

    # Align is_image_match and validation_status
    if val_status == "mismatch":
        is_img_match = False
    elif val_status == "valid":
        is_img_match = True
    elif val_status == "uncertain":
        is_img_match = None

    match_reason = str(raw_dict.get("image_match_reason") or "").strip()
    if not match_reason:
        if val_status == "valid":
            match_reason = "Uploaded photo visually confirms the reported community problem."
        elif val_status == "mismatch":
            match_reason = "Uploaded photo depicts an unrelated subject or a different issue."
        else:
            match_reason = "Photo evidence is partially visible, dark, or uncertain."

    if image_err_note:
        match_reason = f"{match_reason} ({image_err_note})".strip()

    # 2. Category
    category = str(raw_dict.get("category", "")).strip().lower()
    if category not in ALLOWED_CATEGORIES:
        category = "other"

    # 3. Severity & Reason
    severity = str(raw_dict.get("severity", "")).strip().lower()
    if severity not in ALLOWED_SEVERITIES:
        severity = "medium"

    severity_reason = str(raw_dict.get("severity_reason") or "").strip()
    if not severity_reason:
        severity_reason = f"Severity assessed as {severity} based on visible hazard scale."

    # 4. Detected language
    detected_lang = str(raw_dict.get("detected_language", "en")).strip().lower()
    if not detected_lang or len(detected_lang) > 10:
        detected_lang = "en"

    # 5. Translated description
    translated = raw_dict.get("translated_description")
    if translated and isinstance(translated, str):
        translated = translated.strip()
    else:
        translated = original_description

    if detected_lang == "en" and not translated:
        translated = original_description

    # 6. Duplicate detection
    is_duplicate = raw_dict.get("is_duplicate", False)
    if not isinstance(is_duplicate, bool):
        is_duplicate = str(is_duplicate).lower() in ("true", "1", "yes")

    dup_id_raw = raw_dict.get("duplicate_of") or raw_dict.get("duplicate_issue_id")
    duplicate_of: Optional[int] = None
    duplicate_reason: Optional[str] = None

    if is_duplicate and dup_id_raw is not None:
        try:
            parsed_id = int(dup_id_raw)
            if parsed_id in valid_nearby_ids:
                duplicate_of = parsed_id
                raw_reason = raw_dict.get("duplicate_reason")
                duplicate_reason = str(raw_reason).strip() if raw_reason else "Matched existing nearby issue."
            else:
                is_duplicate = False
        except (TypeError, ValueError):
            is_duplicate = False

    if not is_duplicate:
        duplicate_of = None
        duplicate_reason = None

    return {
        "validation_status": val_status,
        "is_image_match": is_img_match,
        "image_match_reason": match_reason,
        "category": category,
        "severity": severity,
        "severity_basis": severity_basis,
        "severity_reason": severity_reason,
        "detected_language": detected_lang,
        "translated_description": translated or original_description,
        "is_duplicate": is_duplicate,
        "duplicate_of": duplicate_of,
        "duplicate_reason": duplicate_reason,
        "ai_success": True,
    }


def classify_issue(
    description: str,
    image_file: Optional[Any] = None,
    nearby_issue_ids: Optional[List[int]] = None,
    nearby_issues: Optional[List[Any]] = None,
) -> Optional[Dict[str, Any]]:
    """
    Perform multimodal AI analysis on an issue description and optional image:
    - Description-image mismatch validation
    - Text and image-based severity scoring
    - Category classification
    - Language detection & English translation
    - Duplicate detection against nearby issues

    Returns structured, validated dict if successful:
        {
            "validation_status": "valid" | "mismatch" | "uncertain",
            "is_image_match": True | False | None,
            "image_match_reason": "...",
            "category": "...",
            "severity": "...",
            "severity_basis": "text_and_image" | "text_only",
            "severity_reason": "...",
            "detected_language": "...",
            "translated_description": "...",
            "is_duplicate": True/False,
            "duplicate_of": issue_id or None,
            "duplicate_reason": "..." or None,
            "ai_success": True,
        }

    Returns a failure dict (with ai_success=False and error_type) or None if input empty.
    """
    if not description or not description.strip():
        return None

    # Collect valid nearby issue IDs
    valid_ids: Set[int] = set()
    if nearby_issue_ids:
        for nid in nearby_issue_ids:
            try:
                valid_ids.add(int(nid))
            except (TypeError, ValueError):
                pass

    resolved_nearby_issues = nearby_issues
    if resolved_nearby_issues is None and valid_ids:
        try:
            from .models import Issue
            resolved_nearby_issues = list(Issue.objects.filter(id__in=valid_ids)[:10])
        except Exception:
            resolved_nearby_issues = None
    elif resolved_nearby_issues:
        for item in resolved_nearby_issues:
            item_id = item.get("id") if isinstance(item, dict) else getattr(item, "id", None)
            if item_id is not None:
                try:
                    valid_ids.add(int(item_id))
                except (TypeError, ValueError):
                    pass

    nearby_text = _format_nearby_issues(resolved_nearby_issues)

    # Validate image
    image_part, severity_basis, image_err = validate_and_prepare_image(image_file)
    if image_err:
        logger.warning("Image preparation warning: %s", image_err)

    prompt = f"""You are an expert AI civic analyst for a community issue reporting system.

Analyze this community issue report submitted by a citizen:
CITIZEN DESCRIPTION:
"{description.strip()}"

NEARBY RECENTLY REPORTED ISSUES:
{nearby_text}

Perform ALL of the following tasks:

1. DESCRIPTION-IMAGE MATCH VALIDATION:
   - If an image is provided, carefully compare the description with the photo.
   - Set validation_status:
     * "valid": The photo clearly depicts the reported community issue (e.g. description says pothole, photo shows a pothole or damaged street).
     * "mismatch": The photo depicts a completely DIFFERENT civic issue (e.g. description says "streetlight" but photo shows "garbage dump"), or depicts an unrelated subject (e.g. selfie, pet, food, indoor room, meme, cartoon, random object).
     * "uncertain": The photo is blurry, dark, low quality, taken from a strange angle, or damage is partially obscured, such that you cannot confirm nor rule out a match.
   - Set is_image_match: true if "valid", false if "mismatch", null if "uncertain" or if no image was provided.
   - Set image_match_reason: A concise 1-2 sentence explanation of the match or mismatch.

2. CATEGORY CLASSIFICATION:
   - Based on combined text and visible image evidence (or text if no image):
   - Choose exactly one: pothole, streetlight, garbage, water, other.

3. SEVERITY SCORING:
   - Determine severity: low, medium, high, critical.
     * critical: Immediate bodily danger or catastrophic obstacle (crater on highway, exposed live wires, massive sewage burst).
     * high: Major hazard or major disruption (large pothole, completely overflowing dumpster, unlit dark intersection).
     * medium: Moderate inconvenience or defect without immediate physical peril.
     * low: Minor cosmetic flaw with minimal disruption.
   - If text and image conflict on severity, flag uncertainty instead of inventing details.
   - Set severity_basis: "{severity_basis}".
   - Set severity_reason: Concise 1-sentence explanation of damage scale and public safety hazard.

4. LANGUAGE DETECTION & TRANSLATION:
   - detected_language: ISO 639-1 code (e.g. "en", "ml", "ta", "hi").
   - translated_description: English translation (same as input if already English).

5. DUPLICATE DETECTION:
   - Check if this report is a duplicate of one of the nearby issues listed above.
   - is_duplicate: true or false.
   - duplicate_of: integer Issue ID from nearby issues list, or null.
   - duplicate_reason: short explanation or null.

Return ONLY a valid JSON object matching this schema:
{{
    "validation_status": "valid",
    "is_image_match": true,
    "image_match_reason": "Explanation of visual match or mismatch",
    "category": "pothole",
    "severity": "medium",
    "severity_basis": "{severity_basis}",
    "severity_reason": "Explanation of severity score based on visible damage",
    "detected_language": "en",
    "translated_description": "English translation here",
    "is_duplicate": false,
    "duplicate_of": null,
    "duplicate_reason": null
}}
"""

    contents: Any = prompt
    if image_part is not None:
        contents = [prompt, image_part]

    config = types.GenerateContentConfig(
        response_mime_type="application/json",
        automatic_function_calling=types.AutomaticFunctionCallingConfig(
            disable=True
        ),
    )

    try:
        raw_text = _execute_with_retry_and_fallback(contents, config=config)
        cleaned_text = _clean_json_text(raw_text)
        parsed_dict = json.loads(cleaned_text)

        if not isinstance(parsed_dict, dict):
            logger.error("Parsed Gemini response is not a dict: %s", type(parsed_dict))
            return {
                "ai_success": False,
                "error_type": "malformed_response",
                "error": "Gemini returned a non-dictionary response.",
                "validation_status": "uncertain",
                "is_image_match": None,
                "severity_basis": severity_basis,
            }

        return _validate_and_normalize_result(
            parsed_dict,
            original_description=description.strip(),
            valid_nearby_ids=valid_ids,
            severity_basis=severity_basis,
            image_err_note=image_err,
        )

    except GeminiExecutionError as exc:
        logger.error("classify_issue execution error (%s): %s", exc.error_type, exc.message)
        return {
            "ai_success": False,
            "error_type": exc.error_type,
            "error": exc.message,
            "status_code": exc.status_code,
            "validation_status": "uncertain",
            "is_image_match": None,
            "image_match_reason": f"AI analysis failed: {exc.message}",
            "severity_basis": severity_basis,
        }
    except Exception as exc:
        err_type, friendly_msg, status_code, _, _ = classify_gemini_error(exc)
        logger.error("classify_issue unexpected failure (%s): %s", err_type, friendly_msg)
        return {
            "ai_success": False,
            "error_type": err_type,
            "error": friendly_msg,
            "status_code": status_code,
            "validation_status": "uncertain",
            "is_image_match": None,
            "image_match_reason": f"AI analysis failed: {friendly_msg}",
            "severity_basis": severity_basis,
        }


def detect_duplicate_issue(
    new_description: str,
    existing_issues: List[Any],
) -> Optional[Dict[str, Any]]:
    """
    Compare a new issue against nearby existing issues to detect duplicates.

    Returns:
        {
            "is_duplicate": True/False,
            "duplicate_of": issue_id or None,
            "duplicate_reason": "..." or None,
            "ai_success": True,
        }
    """
    if not new_description or not new_description.strip():
        return None

    if not existing_issues:
        return {
            "is_duplicate": False,
            "duplicate_of": None,
            "duplicate_reason": None,
            "ai_success": True,
        }

    valid_ids: Set[int] = set()
    for item in existing_issues:
        item_id = item.get("id") if isinstance(item, dict) else getattr(item, "id", None)
        if item_id is not None:
            try:
                valid_ids.add(int(item_id))
            except (TypeError, ValueError):
                pass

    nearby_text = _format_nearby_issues(existing_issues)

    prompt = f"""You are an AI assistant for a civic issue reporting system.

Determine whether the NEW issue describes the SAME real-world problem as one of the EXISTING nearby issues.

NEW ISSUE:
"{new_description.strip()}"

EXISTING NEARBY ISSUES:
{nearby_text}

Rules:
- Mark as duplicate ONLY if it refers to the SAME real-world incident/hazard.
- Do NOT mark as duplicate just because it has the same category.
- If duplicate, duplicate_of MUST be one of the existing Issue IDs listed above.

Return ONLY valid JSON:
{{
    "is_duplicate": true,
    "duplicate_of": 123,
    "duplicate_reason": "Short explanation of why it matches"
}}
or if not duplicate:
{{
    "is_duplicate": false,
    "duplicate_of": null,
    "duplicate_reason": null
}}
"""

    config = types.GenerateContentConfig(
        response_mime_type="application/json",
        automatic_function_calling=types.AutomaticFunctionCallingConfig(
            disable=True
        ),
    )

    try:
        raw_text = _execute_with_retry_and_fallback(prompt, config=config)
        cleaned_text = _clean_json_text(raw_text)
        parsed_dict = json.loads(cleaned_text)

        if not isinstance(parsed_dict, dict):
            return {"is_duplicate": False, "duplicate_of": None, "duplicate_reason": None, "ai_success": False}

        is_dup = parsed_dict.get("is_duplicate", False)
        if not isinstance(is_dup, bool):
            is_dup = str(is_dup).lower() in ("true", "1", "yes")

        dup_of = parsed_dict.get("duplicate_of")
        dup_reason = parsed_dict.get("duplicate_reason")

        if is_dup and dup_of is not None:
            try:
                dup_of = int(dup_of)
                if dup_of not in valid_ids:
                    is_dup = False
                    dup_of = None
                    dup_reason = None
            except (TypeError, ValueError):
                is_dup = False
                dup_of = None
                dup_reason = None
        else:
            is_dup = False
            dup_of = None
            dup_reason = None

        return {
            "is_duplicate": is_dup,
            "duplicate_of": dup_of,
            "duplicate_reason": dup_reason,
            "ai_success": True,
        }

    except Exception as exc:
        err_type, friendly_msg, _, _, _ = classify_gemini_error(exc)
        logger.error("detect_duplicate_issue failed (%s): %s", err_type, friendly_msg)
        return {"is_duplicate": False, "duplicate_of": None, "duplicate_reason": None, "ai_success": False, "error": friendly_msg}