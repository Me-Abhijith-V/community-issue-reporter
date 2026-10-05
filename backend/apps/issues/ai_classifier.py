import json
import os
import time

from google import genai
from google.genai import types


client = genai.Client(
    api_key=os.getenv("GEMINI_API_KEY")
)


def classify_issue(description, nearby_issue_ids=None):
    """
    Full AI analysis: language detection, translation,
    category, severity, duplicate detection — in one call.

    Returns:
        {
            "category": "...",
            "severity": "...",
            "detected_language": "...",
            "translated_description": "...",
            "is_duplicate": True/False,
            "duplicate_of": issue_id or None,
            "duplicate_reason": "..." or None,
        }

    Returns None if Gemini is unavailable.
    """

    nearby_ids_str = (
        json.dumps(nearby_issue_ids)
        if nearby_issue_ids
        else "[]"
    )

    prompt = f"""
You are an AI assistant for a community issue reporting system.

Analyze this community issue description submitted by a citizen:

"{description}"

Perform ALL of the following tasks:

1. Detect the language of the description (return ISO 639-1 code, e.g. "en", "ml", "ta", "hi")
2. Translate the description to English if it is not already in English.
3. Classify the issue into exactly one category:
   - pothole
   - streetlight
   - garbage
   - water
   - other
4. Determine the severity:
   - low
   - medium
   - high
   - critical
5. Check if this appears to be a duplicate of a nearby issue with one of these IDs: {nearby_ids_str}
   Only mark as duplicate if the description clearly refers to the SAME specific problem, not just the same category.

Return ONLY valid JSON in exactly this format (no markdown, no extra text):

{{
    "detected_language": "en",
    "translated_description": "English text here",
    "category": "pothole",
    "severity": "medium",
    "is_duplicate": false,
    "duplicate_of": null,
    "duplicate_reason": null
}}

If it is a duplicate, set is_duplicate to true, duplicate_of to the matching issue ID (integer), and duplicate_reason to a short explanation.
If it is not a duplicate, set is_duplicate to false, duplicate_of to null, duplicate_reason to null.
"""

    for attempt in range(3):
        try:
            response = client.models.generate_content(
                model="gemini-3.8-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    automatic_function_calling=types.AutomaticFunctionCallingConfig(
                        disable=True
                    )
                ),
            )

            text = response.text.strip()
            text = text.replace("```json", "")
            text = text.replace("```", "")
            text = text.strip()

            result = json.loads(text)

            allowed_categories = {
                "pothole",
                "streetlight",
                "garbage",
                "water",
                "other",
            }

            allowed_severity = {
                "low",
                "medium",
                "high",
                "critical",
            }

            category = result.get("category", "other")
            severity = result.get("severity", "medium")
            detected_language = result.get("detected_language", "en")
            translated_description = result.get(
                "translated_description", description
            )
            is_duplicate = result.get("is_duplicate", False)
            duplicate_of = result.get("duplicate_of", None)
            duplicate_reason = result.get("duplicate_reason", None)

            if category not in allowed_categories:
                category = "other"

            if severity not in allowed_severity:
                severity = "medium"

            if not isinstance(is_duplicate, bool):
                is_duplicate = False

            if is_duplicate and duplicate_of is not None:
                try:
                    duplicate_of = int(duplicate_of)
                    if nearby_issue_ids and duplicate_of not in nearby_issue_ids:
                        is_duplicate = False
                        duplicate_of = None
                        duplicate_reason = None
                except (TypeError, ValueError):
                    is_duplicate = False
                    duplicate_of = None
                    duplicate_reason = None
            else:
                duplicate_of = None
                duplicate_reason = None

            # If language is English, translated_description == original
            if detected_language == "en":
                translated_description = description

            return {
                "category": category,
                "severity": severity,
                "detected_language": detected_language,
                "translated_description": translated_description,
                "is_duplicate": is_duplicate,
                "duplicate_of": duplicate_of,
                "duplicate_reason": duplicate_reason,
            }

        except Exception as e:
            print(
                f"GEMINI ERROR (attempt {attempt + 1}/3):",
                e
            )

            if attempt < 2:
                time.sleep(2)

    return None


def detect_duplicate_issue(new_description, existing_issues):
    """
    Compare a new issue against nearby existing issues.

    Returns:
        {
            "is_duplicate": True/False,
            "duplicate_of": issue_id or None
        }

    Returns None if Gemini is unavailable.
    """

    if not existing_issues:
        return {
            "is_duplicate": False,
            "duplicate_of": None,
        }

    issues_text = ""

    for issue in existing_issues:
        desc = issue.translated_description or issue.original_description
        issues_text += f"""
Issue ID: {issue.id}
Description: "{desc}"
Category: "{issue.category}"
Location: latitude {issue.latitude}, longitude {issue.longitude}

"""

    prompt = f"""
You are an AI assistant for a community issue reporting system.

Determine whether the NEW issue is a duplicate of one of the EXISTING issues.

NEW ISSUE:
Description: "{new_description}"

EXISTING ISSUES:
{issues_text}

Two issues should be considered duplicates only when they appear to describe
the same real-world problem at approximately the same location.

Do NOT consider them duplicates just because they have the same category.

Return ONLY valid JSON.

If the new issue is a duplicate, return:

{{
    "is_duplicate": true,
    "duplicate_of": 123
}}

where 123 is the ID of the matching existing issue.

If it is not a duplicate, return:

{{
    "is_duplicate": false,
    "duplicate_of": null
}}
"""

    for attempt in range(3):
        try:
            response = client.models.generate_content(
                model="gemini-3.8-flash",
                contents=prompt,
                config=types.GenerateContentConfig(
                    automatic_function_calling=types.AutomaticFunctionCallingConfig(
                        disable=True
                    )
                ),
            )

            text = response.text.strip()
            text = text.replace("```json", "")
            text = text.replace("```", "")
            text = text.strip()

            result = json.loads(text)

            is_duplicate = result.get(
                "is_duplicate",
                False
            )

            duplicate_of = result.get(
                "duplicate_of",
                None
            )

            if not isinstance(is_duplicate, bool):
                is_duplicate = False

            if is_duplicate:
                try:
                    duplicate_of = int(duplicate_of)
                except (TypeError, ValueError):
                    is_duplicate = False
                    duplicate_of = None

                valid_ids = {
                    issue.id for issue in existing_issues
                }

                if duplicate_of not in valid_ids:
                    is_duplicate = False
                    duplicate_of = None

            else:
                duplicate_of = None

            return {
                "is_duplicate": is_duplicate,
                "duplicate_of": duplicate_of,
            }

        except Exception as e:
            print(
                f"GEMINI DUPLICATE ERROR "
                f"(attempt {attempt + 1}/3):",
                e
            )

            if attempt < 2:
                time.sleep(2)

    return None