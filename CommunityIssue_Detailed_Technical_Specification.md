# AI-Powered Community Issue Reporter & Tracker
## Complete Project Reference Document
### MCA 3rd Semester Mini Project | Academic Year 2025–2026

> **How to use this document:**
> This file is the single source of truth for the entire project. Upload it to any AI tool (ChatGPT, Claude, Gemini, Copilot, etc.) and say *"Read this document. Help me build [specific thing]."* The AI will have complete context about every part of the project without you explaining anything.

---

## TABLE OF CONTENTS

1. [What This App Does — Plain English](#1-what-this-app-does--plain-english)
2. [Who Uses This App](#2-who-uses-this-app)
3. [The Problem Being Solved](#3-the-problem-being-solved)
4. [How the App Works — Step by Step](#4-how-the-app-works--step-by-step)
5. [Complete Tech Stack](#5-complete-tech-stack)
6. [Project Folder & File Structure](#6-project-folder--file-structure)
7. [Database Design](#7-database-design)
8. [All API Endpoints](#8-all-api-endpoints)
9. [Module 1 — User Authentication](#9-module-1--user-authentication)
10. [Module 2 — Issue Reporting](#10-module-2--issue-reporting)
11. [Module 3 — Issue Listing & Search](#11-module-3--issue-listing--search)
12. [Module 4 — Map View with Heatmap & Clustering](#12-module-4--map-view-with-heatmap--clustering)
13. [Module 5 — Status Tracking](#13-module-5--status-tracking)
14. [Module 6 — Authority Panel](#14-module-6--authority-panel)
15. [Module 7 — User Dashboard & Reputation Score](#15-module-7--user-dashboard--reputation-score)
16. [Module 8 — Community Upvote](#16-module-8--community-upvote)
17. [Module 9 — AI-Powered Issue Analysis](#17-module-9--ai-powered-issue-analysis)
18. [Module 10 — Multilingual Support](#18-module-10--multilingual-support)
19. [Module 11 — Voice-to-Text Reporting](#19-module-11--voice-to-text-reporting)
20. [Module 12 — Push Notifications (Optional)](#20-module-12--push-notifications-optional)
21. [Flutter App — All Screens](#21-flutter-app--all-screens)
22. [Flutter App — State Management](#22-flutter-app--state-management)
23. [Flutter App — Navigation Structure](#23-flutter-app--navigation-structure)
24. [Flutter App — All Packages](#24-flutter-app--all-packages)
25. [Django Backend — Project Settings](#25-django-backend--project-settings)
26. [Django Backend — All Models](#26-django-backend--all-models)
27. [Django Backend — Serializers](#27-django-backend--serializers)
28. [Django Backend — Views & Logic](#28-django-backend--views--logic)
29. [Django Backend — URL Routing](#29-django-backend--url-routing)
30. [Django Backend — Admin Panel](#30-django-backend--admin-panel)
31. [AI Integration — Gemini API](#31-ai-integration--gemini-api)
32. [Authentication Flow — JWT](#32-authentication-flow--jwt)
33. [Image Upload Flow](#33-image-upload-flow)
34. [GPS & Maps Flow](#34-gps--maps-flow)
35. [Status Update Flow](#35-status-update-flow)
36. [Voice-to-Text Flow](#36-voice-to-text-flow)
37. [Multilingual Flow](#37-multilingual-flow)
38. [Reputation Score Flow](#38-reputation-score-flow)
39. [Map Clustering & Heatmap Flow](#39-map-clustering--heatmap-flow)
40. [Testing Plan](#40-testing-plan)
41. [Sprint Plan & Timeline](#41-sprint-plan--timeline)
42. [Scrum Book Guide](#42-scrum-book-guide)
43. [Git Workflow](#43-git-workflow)
44. [Environment Variables & Secrets](#44-environment-variables--secrets)
45. [Common Errors & Fixes](#45-common-errors--fixes)
46. [Free Tools Reference](#46-free-tools-reference)

---

## 1. What This App Does — Plain English

This is a **mobile app for Android** that lets ordinary citizens report broken or damaged things in their city — like potholes, broken streetlights, overflowing garbage bins, or water pipe leaks.

Think of it like this:

> You are walking on the road. You see a huge pothole. You open this app, tap a microphone and **speak** your complaint in **Malayalam or any language** — the app converts it to text automatically. Or you type it. Either way, the AI reads your description and tells you the category, urgency, and whether someone else already reported the same thing. You take a photo, and press Submit. The app automatically records where you are using GPS. Your report goes to the local government authority. You can then check from your phone whether they are working on it.

**Four advanced features make this app stand out from all existing systems:**

- **Multilingual Support** — Citizens speak or type in Malayalam, Tamil, Hindi, or any language. AI translates automatically. The authority always sees English.
- **Voice-to-Text Reporting** — Tap a microphone, speak the complaint, speech becomes text. No typing needed.
- **Heatmap + Clustering on Map** — Instead of individual pins, heavily-reported areas glow red on a heatmap. Nearby pins of the same type cluster together automatically.
- **Citizen Reputation Score** — Citizens build a trust score over time. Good, genuine reports increase the score. Invalid reports decrease it. High-reputation citizens' reports are shown first.

**The app has two sides:**
- **Citizens** use the Android mobile app (built with Flutter)
- **Authorities** use a web-based admin panel (built with Django Admin) on their computer or phone browser

**Everything in this project is 100% free.** No paid tools, no credit cards, no paid APIs.

---

## 2. Who Uses This App

| User Type | What They Do | How They Access |
|-----------|-------------|-----------------|
| **Citizen** | Register, login, report issues by voice or text in any language, track status, upvote, view heatmap | Flutter Android app |
| **Authority / Admin** | View reports, update status, manage issues, view heatmap, see reputation scores | Django Admin web panel (browser) |
| **Developer (You)** | Build, test, run, maintain everything | VS Code + Android Studio + Postman |

---

## 3. The Problem Being Solved

**Current situation (the problem):**
- Citizens have no digital way to report civic problems with photo + location proof
- Authorities get verbal complaints with no verifiable location data
- Same problem gets reported multiple times with no deduplication system
- Citizens never know if their complaint was seen or acted upon
- No accountability — authorities face no pressure to respond
- Language barrier — citizens not comfortable typing in English cannot easily use apps
- No way to assess citizen credibility — spam and fake reports are indistinguishable from genuine ones
- Maps with individual pins become unusable when many issues are reported in one area

**What this app solves:**
- One-tap photo + GPS reporting — takes under 60 seconds
- Voice input — speak in any language, no typing needed
- Automatic translation — citizen speaks Malayalam, authority sees English
- Duplicate detection using AI — reduces noise for authorities
- Real-time status tracking — citizens see exactly what is happening
- Community upvoting — most-affected areas get prioritised
- AI severity scoring — critical issues surface to the top automatically
- Heatmap view — authorities see problem zones visually at a glance
- Marker clustering — map stays usable even with hundreds of issues
- Reputation scoring — genuine citizens are trusted more over time

---

## 4. How the App Works — Step by Step

### Citizen Journey (Reporting an Issue)

```
Step 1  — Citizen opens app on Android phone
Step 2  — Citizen registers with name, email, phone, password
Step 3  — Citizen logs in → JWT token stored on device
Step 4  — Citizen taps "Report Issue" button on home screen
Step 5  — Citizen EITHER:
            (a) Taps microphone icon → speaks complaint in any language
                → speech_to_text converts speech to text automatically
            OR
            (b) Types the description manually
Step 6  — If citizen typed/spoke in Malayalam or any regional language:
            → Gemini AI detects language, translates to English internally
            → English version used for analysis, original stored too
Step 7  — Citizen taps "AI Analyse" button (sparkle icon ✨)
            → App sends description to Django backend
            → Django calls Gemini AI API (one call)
            → Gemini returns: category + severity + duplicate check
            → App shows: category pre-filled, severity badge, duplicate warning (if any)
Step 8  — Citizen takes photo using device camera (via app)
Step 9  — App reads GPS coordinates from device automatically
Step 10 — Citizen confirms and taps Submit
Step 11 — App sends HTTP POST to /api/issues/ with:
            photo + GPS + description + translated_description + AI results + language_detected
Step 12 — Django saves everything to PostgreSQL database
Step 13 — Django updates citizen's reputation score (+points for valid submission)
Step 14 — App shows success screen with issue ID
```

### Authority Journey (Managing Issues)

```
Step 1 — Authority opens Django Admin panel in browser
Step 2 — Authority logs in with superuser credentials
Step 3 — Authority sees list of all reported issues
           → Sorted by AI severity (Critical first)
           → All descriptions shown in English (regardless of original language)
           → Reputation score of reporting citizen shown
           → Filter by category, status, date
Step 4 — Authority taps an issue → sees photo, GPS location, description, upvote count, citizen reputation
Step 5 — Authority changes status to "In Progress"
           → StatusUpdate record saved with note and timestamp
Step 6 — Citizen's app shows updated status in Issue Detail screen
Step 7 — Authority resolves issue → status becomes "Resolved"
Step 8 — Django automatically updates citizen's reputation score (+points for resolved issue)
Step 9 — If push notifications enabled → citizen gets FCM alert
```

### Duplicate Detection Journey

```
Citizen types or speaks description
    ↓
AI checks against nearby issues (within ~500m radius)
    ↓
If similar issue found:
    App shows warning: "A similar issue was reported 200m away"
    App shows: [View Existing Issue] [Submit Anyway] buttons
    ↓
Citizen can tap "View Existing Issue" → opens it → upvotes it
    ↓
No duplicate created. Upvote count increases.
Citizen reputation unchanged (not penalised for duplicate — they were warned)
```

### Voice Reporting Journey

```
Step 1 — Citizen taps microphone button on Report Issue screen
Step 2 — Device shows "Listening..." indicator
Step 3 — Citizen speaks: "Valiya kuzhiyaanu MG Road-il bus stop-nte അടുത്ത്"
          (Malayalam: "There is a big pothole near the bus stop on MG Road")
Step 4 — speech_to_text package converts spoken words to text in real time
Step 5 — Text appears in the description field automatically
Step 6 — Citizen taps "AI Analyse" — Gemini detects Malayalam, translates to English
Step 7 — English translation: "There is a big pothole near the bus stop on MG Road"
Step 8 — AI returns: category=pothole, severity=high, is_duplicate=false
Step 9 — Citizen submits — both original Malayalam + English translation saved in DB
```

### Multilingual Journey

```
Citizen types in Malayalam → Gemini detects "ml" (Malayalam ISO code)
                           → Translates to English
                           → Saves both versions in DB
                              original_description = "MG Road-il kuzhiyaanu"
                              description = "There is a pothole on MG Road"
                           → Authority dashboard shows English version
                           → Citizen's app shows their original language version
```

### Reputation Score Journey

```
NEW citizen starts with score: 50 (neutral)

+10 points  → Submit a report (any report)
+20 points  → Report marked "Resolved" by authority
+5 points   → Report upvoted by 5+ other citizens
-15 points  → Report marked "Invalid" by authority
-30 points  → Report marked "Fake" by authority

Score ranges:
  0–30   → Low trust  → report shown lower in feed
  31–60  → Normal     → standard display
  61–80  → Trusted    → small "✓ Trusted Citizen" badge
  81–100 → Highly Trusted → report shown at top of feed, authority notified
```

---

## 5. Complete Tech Stack

| Layer | Technology | Version | Why This One | Free? |
|-------|-----------|---------|-------------|-------|
| **Mobile Frontend** | Flutter (Dart) | 3.x | Cross-platform, single codebase for Android | ✅ Free |
| **Backend Framework** | Django | 4.2 LTS | Stable, batteries-included, great admin panel | ✅ Free |
| **REST API** | Django REST Framework (DRF) | 3.15 | Best REST API library for Django | ✅ Free |
| **Database (Dev)** | SQLite | Built-in | Zero setup for development | ✅ Free |
| **Database (Prod)** | PostgreSQL | 15 | Production-grade, free forever | ✅ Free |
| **Authentication** | JWT via djangorestframework-simplejwt | 5.3 | Stateless, secure, industry standard | ✅ Free |
| **AI Engine** | Google Gemini 1.5 Flash | Latest | Free tier: 1,500 calls/day, no credit card | ✅ Free |
| **AI Tasks** | Category + Severity + Duplicate + Translation | — | All from one Gemini call | ✅ Free |
| **Maps** | Google Maps Flutter Plugin | 2.x | Best map plugin for Flutter | ✅ Free (28k loads/month) |
| **Heatmap** | Google Maps Flutter Plugin (heatmap layer) | 2.x | Native heatmap support in same plugin | ✅ Free |
| **Marker Clustering** | google_maps_cluster_manager | 3.x | Clusters nearby markers automatically | ✅ Free |
| **GPS** | geolocator Flutter package | 11.x | Simple GPS coordinates from device | ✅ Free |
| **Camera** | image_picker Flutter package | 1.x | Access device camera or gallery | ✅ Free |
| **Voice Input** | speech_to_text Flutter package | 6.x | Uses device's built-in speech engine — no API | ✅ Free |
| **HTTP Client (Flutter)** | Dio | 5.x | Supports multipart upload for photos | ✅ Free |
| **State Management** | Provider | 6.x | Simple, beginner-friendly | ✅ Free |
| **Local Storage (Flutter)** | shared_preferences | 2.x | Store JWT token on device | ✅ Free |
| **Push Notifications** | Firebase Cloud Messaging (FCM) | Latest | Free forever, no limits | ✅ Free |
| **Image Storage** | Django media files (/media/) | — | Local folder during development | ✅ Free |
| **Version Control** | Git + GitHub | — | Mandatory for evaluation | ✅ Free |
| **Bug Tracking** | GitHub Issues | — | Built into GitHub, free | ✅ Free |
| **API Testing** | Postman | Free tier | Test every endpoint before writing Flutter code | ✅ Free |
| **IDE (Backend)** | VS Code | Latest | Lightweight, free | ✅ Free |
| **IDE (Frontend)** | Android Studio | Latest | Required for Flutter + Android emulator | ✅ Free |
| **DB GUI** | pgAdmin 4 | Latest | View PostgreSQL data visually | ✅ Free |
| **ER Diagrams** | Draw.io (app.diagrams.net) | Browser | No login needed | ✅ Free |
| **UI Wireframes** | Figma | Free tier | Student-friendly, 3 free projects | ✅ Free |
| **Project Report** | LaTeX via Overleaf | Free tier | Required by curriculum | ✅ Free |

---

## 6. Project Folder & File Structure

```
community_issue_tracker/           ← Root project folder (this is your Git repo)
│
├── backend/                       ← Django project
│   ├── manage.py
│   ├── requirements.txt
│   ├── .env                       ← Secrets (NEVER commit)
│   ├── .env.example
│   │
│   ├── config/
│   │   ├── settings.py
│   │   ├── urls.py
│   │   └── wsgi.py
│   │
│   ├── apps/
│   │   ├── users/                 ← Module 1: Auth + Reputation
│   │   │   ├── models.py          ← CustomUser model (includes reputation_score field)
│   │   │   ├── serializers.py
│   │   │   ├── views.py
│   │   │   ├── urls.py
│   │   │   ├── reputation.py      ← NEW: Reputation score calculation logic
│   │   │   ├── admin.py
│   │   │   └── tests.py
│   │   │
│   │   ├── issues/                ← Modules 2–9: Core + AI
│   │   │   ├── models.py          ← Issue model (multilingual fields added)
│   │   │   ├── serializers.py
│   │   │   ├── views.py
│   │   │   ├── urls.py
│   │   │   ├── admin.py
│   │   │   ├── ai_classifier.py   ← Gemini AI: category+severity+duplicate+translation
│   │   │   ├── permissions.py
│   │   │   ├── filters.py
│   │   │   └── tests.py
│   │   │
│   │   └── notifications/         ← Module 12: Push notifications
│   │       ├── services.py
│   │       └── signals.py
│   │
│   └── media/
│       └── issues/
│
├── mobile/                        ← Flutter project
│   ├── pubspec.yaml
│   ├── android/
│   │   └── app/src/main/
│   │       ├── AndroidManifest.xml  ← Maps key + microphone permission
│   │       └── google-services.json ← Firebase config
│   │
│   └── lib/
│       ├── main.dart
│       ├── constants/
│       │   ├── api_constants.dart
│       │   └── app_colors.dart
│       │
│       ├── models/
│       │   ├── user_model.dart         ← includes reputationScore field
│       │   ├── issue_model.dart        ← includes originalDescription, detectedLanguage
│       │   └── status_update_model.dart
│       │
│       ├── services/
│       │   ├── auth_service.dart
│       │   ├── issue_service.dart
│       │   ├── speech_service.dart     ← NEW: Voice-to-text wrapper
│       │   └── notification_service.dart
│       │
│       ├── providers/
│       │   ├── auth_provider.dart
│       │   └── issue_provider.dart
│       │
│       ├── screens/
│       │   ├── splash_screen.dart
│       │   ├── onboarding_screen.dart
│       │   ├── auth/
│       │   │   ├── login_screen.dart
│       │   │   └── register_screen.dart
│       │   ├── home/
│       │   │   └── home_screen.dart
│       │   ├── issue/
│       │   │   ├── report_issue_screen.dart  ← includes voice mic + language badge
│       │   │   ├── issue_detail_screen.dart
│       │   │   └── map_screen.dart           ← includes heatmap toggle + clustering
│       │   ├── dashboard/
│       │   │   ├── my_reports_screen.dart
│       │   │   └── profile_screen.dart       ← shows reputation score + badge
│       │   └── notifications/
│       │       └── notifications_screen.dart
│       │
│       └── widgets/
│           ├── issue_card.dart
│           ├── status_badge.dart
│           ├── severity_badge.dart
│           ├── category_icon.dart
│           ├── status_timeline.dart
│           ├── reputation_badge.dart   ← NEW: Shows citizen trust level
│           └── voice_input_button.dart ← NEW: Mic button with listening animation
│
├── docs/
│   ├── main.tex
│   └── images/
│
├── README.md
└── .gitignore
```

---

## 7. Database Design

### Entity Relationships

```
CustomUser  ──(1:many)──> Issue               (one user reports many issues)
CustomUser  ──(1:many)──> IssueUpvote         (one user upvotes many issues)
CustomUser  ──(1:many)──> StatusUpdate        (one authority updates many issues)
CustomUser  ──(1:1)────>  ReputationLog       (one score record per user)
Issue       ──(1:many)──> IssueUpvote
Issue       ──(1:many)──> StatusUpdate
Issue       ──(self)────> Issue               (ai_duplicate_of self-reference)
```

### Model: CustomUser

Extends Django's built-in `AbstractUser`. Adds phone, role, FCM token, and reputation score.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | AutoField (PK) | auto | Primary key |
| `email` | EmailField | Yes | Used as login username |
| `full_name` | CharField(100) | Yes | Display name |
| `phone` | CharField(15) | No | Optional |
| `role` | CharField choices | Yes | `citizen` or `authority` — default: `citizen` |
| `fcm_token` | CharField(255) | No | Firebase push token |
| `reputation_score` | PositiveIntegerField | auto | Starts at 50, range 0–100 |
| `reputation_level` | CharField choices | auto | `low`, `normal`, `trusted`, `highly_trusted` |
| `date_joined` | DateTimeField | auto | Set automatically |
| `preferred_language` | CharField(10) | No | ISO code e.g. `ml`, `ta`, `hi`, `en` — default: `en` |

**Login field:** `email`

### Model: Issue

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | AutoField (PK) | auto | Primary key |
| `title` | CharField(200) | Yes | Short title |
| `description` | TextField | Yes | English version (translated if needed) |
| `original_description` | TextField | No | Original language text if citizen used non-English |
| `detected_language` | CharField(10) | No | ISO language code detected by AI e.g. `ml`, `ta`, `en` |
| `category` | CharField choices | Yes | `pothole`, `streetlight`, `garbage`, `water`, `other` |
| `latitude` | DecimalField(9,6) | Yes | GPS latitude |
| `longitude` | DecimalField(9,6) | Yes | GPS longitude |
| `photo` | ImageField | Yes | Uploaded to `media/issues/` |
| `status` | CharField choices | Yes | `reported`, `in_progress`, `resolved`, `closed` — default: `reported` |
| `reported_by` | ForeignKey(CustomUser) | Yes | Citizen who submitted |
| `ai_suggested_category` | CharField(50) | No | AI category suggestion |
| `ai_severity` | CharField choices | No | `low`, `medium`, `high`, `critical` |
| `ai_is_duplicate` | BooleanField | No | True if AI detected duplicate |
| `ai_duplicate_of` | ForeignKey(Issue, null=True) | No | Points to similar existing issue |
| `upvote_count` | PositiveIntegerField | auto | Cached upvote count |
| `was_voice_input` | BooleanField | auto | True if citizen used voice-to-text |
| `created_at` | DateTimeField | auto | Creation timestamp |
| `updated_at` | DateTimeField | auto | Last update timestamp |

### Model: IssueUpvote

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | AutoField (PK) | auto | Primary key |
| `issue` | ForeignKey(Issue) | Yes | Which issue was upvoted |
| `user` | ForeignKey(CustomUser) | Yes | Who upvoted it |
| `created_at` | DateTimeField | auto | When the upvote happened |

**Constraint:** `unique_together = ('issue', 'user')`

### Model: StatusUpdate

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | AutoField (PK) | auto | Primary key |
| `issue` | ForeignKey(Issue) | Yes | Which issue was updated |
| `updated_by` | ForeignKey(CustomUser) | Yes | Which authority |
| `old_status` | CharField choices | Yes | Status before |
| `new_status` | CharField choices | Yes | Status after |
| `note` | TextField | No | Authority's comment |
| `timestamp` | DateTimeField | auto | When changed |

### Model: ReputationLog

Audit trail for reputation changes — explains why a citizen's score changed.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | AutoField (PK) | auto | Primary key |
| `user` | ForeignKey(CustomUser) | Yes | Whose score changed |
| `change` | IntegerField | Yes | Positive or negative points e.g. +10, -15 |
| `reason` | CharField choices | Yes | `submitted`, `resolved`, `upvoted`, `invalid`, `fake` |
| `related_issue` | ForeignKey(Issue, null=True) | No | Which issue caused the change |
| `timestamp` | DateTimeField | auto | When the change happened |

---

## 8. All API Endpoints

**Base URL (development):** `http://127.0.0.1:8000/api/`
**Base URL (on emulator):** `http://10.0.2.2:8000/api/`
**Authentication header:** `Authorization: Bearer <access_token>`

### Auth Endpoints

| Method | Endpoint | Auth | Purpose |
|--------|----------|------|---------|
| POST | `/auth/register/` | No | Create account |
| POST | `/auth/login/` | No | Returns JWT access + refresh tokens |
| POST | `/auth/token/refresh/` | No | Get new access token |
| GET | `/auth/me/` | Yes | Get own profile including reputation_score |
| PATCH | `/auth/me/fcm-token/` | Yes | Update push token |

### Issue Endpoints

| Method | Endpoint | Auth | Notes |
|--------|----------|------|-------|
| GET | `/issues/` | Yes | List all issues. Params: `?category=&status=&page=&ordering=` |
| POST | `/issues/` | Yes | Create issue. Multipart: photo + fields including `original_description`, `detected_language`, `was_voice_input` |
| GET | `/issues/{id}/` | Yes | Full issue detail |
| PATCH | `/issues/{id}/status/` | Authority | Update status. Triggers reputation update for citizen. |
| DELETE | `/issues/{id}/` | Own issue | Only if status is `reported` |
| GET | `/issues/map/` | Yes | Lightweight: `{id, lat, lng, status, category, upvote_count}` for map |
| POST | `/issues/{id}/upvote/` | Yes | Toggle upvote |
| GET | `/issues/{id}/history/` | Yes | StatusUpdate records |
| POST | `/issues/classify/` | Yes | AI analysis. Returns: category, severity, is_duplicate, duplicate_issue_id, duplicate_reason, detected_language, translated_description |

### User Endpoints

| Method | Endpoint | Auth | Notes |
|--------|----------|------|-------|
| GET | `/users/me/issues/` | Yes | My submitted issues |
| GET | `/users/me/stats/` | Yes | `{total, resolved, pending, in_progress}` |
| GET | `/users/me/reputation/` | Yes | `{score, level, log[]}` — full reputation history |

---

## 9. Module 1 — User Authentication

### What This Module Does (Plain English)
This is the front door of the app. Every citizen must register and log in before using any feature. The app uses JWT — a digital ID card stored on the phone. The user's reputation score starts at 50 (neutral) the moment they register.

### User Registration Flow
```
1. Citizen fills: Full Name, Email, Phone (optional), Password
2. Flutter sends POST /api/auth/register/
3. Django creates CustomUser with reputation_score=50, reputation_level='normal'
4. Also creates initial ReputationLog entry: reason='account_created', change=0
5. Flutter navigates to Login screen
```

### User Login Flow
```
1. Citizen enters email + password
2. Flutter sends POST /api/auth/login/
3. Django returns: { access, refresh, user: { id, full_name, reputation_score, reputation_level } }
4. Flutter stores tokens + user data in SharedPreferences
5. Flutter navigates to Home screen
```

### Token Refresh Flow (Automatic)
```
1. Access token expires (60 minutes)
2. Flutter catches 401 → sends POST /auth/token/refresh/ with refresh token
3. Gets new access token → retries original request
4. Invisible to the user
```

### Django Backend — What to Build

**`apps/users/models.py`**
```python
REPUTATION_LEVELS = [
    ('low', 'Low Trust'),
    ('normal', 'Normal'),
    ('trusted', 'Trusted'),
    ('highly_trusted', 'Highly Trusted'),
]

class CustomUser(AbstractUser):
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['full_name']
    email = models.EmailField(unique=True)
    full_name = models.CharField(max_length=100)
    phone = models.CharField(max_length=15, blank=True)
    role = models.CharField(max_length=20,
        choices=[('citizen','Citizen'),('authority','Authority')],
        default='citizen')
    fcm_token = models.CharField(max_length=255, blank=True)
    reputation_score = models.PositiveIntegerField(default=50)
    reputation_level = models.CharField(max_length=20,
        choices=REPUTATION_LEVELS, default='normal')
    preferred_language = models.CharField(max_length=10, default='en')
```

**`apps/users/reputation.py`** — NEW FILE
```python
# update_reputation(user, change, reason, related_issue=None)
# - Clamps score to 0–100
# - Updates reputation_level based on new score:
#     0–30 → 'low', 31–60 → 'normal', 61–80 → 'trusted', 81–100 → 'highly_trusted'
# - Creates ReputationLog record
# - Saves user

REPUTATION_CHANGES = {
    'submitted': +10,
    'resolved': +20,
    'upvoted_5': +5,
    'invalid': -15,
    'fake': -30,
}
```

### Flutter — What to Build

**`lib/screens/auth/register_screen.dart`**
- Fields: Full Name, Email, Phone, Password, Confirm Password
- Show "Language Preference" dropdown (English, Malayalam, Tamil, Hindi)
- Saves preferred_language to SharedPreferences after registration

**`lib/screens/auth/login_screen.dart`**
- Fields: Email, Password
- After login, save reputation_score and reputation_level to provider

### Packages Required
- Backend: `djangorestframework-simplejwt==5.3.1`
- Flutter: `shared_preferences: ^2.2.2`, `dio: ^5.4.0`

---

## 10. Module 2 — Issue Reporting

### What This Module Does (Plain English)
This is the core feature. Citizens report a problem by speaking or typing, take a photo, and submit. The app handles GPS, AI analysis, voice-to-text, and language detection automatically. The citizen does almost nothing — the app does everything.

### Report Submission Flow
```
1.  Citizen taps "+" or "Report Issue" on Home screen
2.  Report Issue screen opens
3.  Citizen EITHER:
      (a) Taps 🎤 microphone button → speaks in any language
          → speech_to_text converts to text in real time
          → text appears in description field
      OR
      (b) Types description manually
4.  Citizen taps "AI Analyse ✨" button
      → App detects if GPS ready, fetches nearby issue IDs
      → Sends description to /api/issues/classify/
      → Gemini detects language, translates if needed, analyses
      → Returns: category, severity, is_duplicate, duplicate_reason,
                 detected_language, translated_description
      → App shows:
          - Category dropdown pre-filled
          - Severity badge (🔴 High)
          - Language badge (🇮🇳 Malayalam → translated to English)
          - ⚠️ Duplicate warning if found (with [View Existing] button)
5.  Citizen taps camera button → takes photo
6.  GPS coordinates auto-captured in background
7.  Citizen confirms title and taps Submit
8.  Flutter sends multipart POST to /api/issues/ with:
      photo, title, description (English), original_description,
      detected_language, was_voice_input, category, latitude, longitude,
      ai_severity, ai_is_duplicate, ai_duplicate_of
9.  Django saves to DB
10. Django calls update_reputation(user, +10, 'submitted', issue)
11. Django returns 201 with issue ID
12. Flutter navigates to Issue Detail screen
```

### Voice Input Detail

```
Package: speech_to_text (flutter)
- Citizen taps mic → SpeechToText.listen() starts
- Real-time: words appear in field as citizen speaks
- Auto-stops after 3 seconds of silence
- Works with: English, Malayalam, Tamil, Hindi, and all device-supported languages
- No API key needed — uses device's built-in speech recognition engine
- Completely offline-capable (no internet needed for voice-to-text step)
```

### Photo Upload Detail
- Must be multipart/form-data (not JSON — JSON cannot carry binary)
- Use Dio package with FormData
- `was_voice_input` field: boolean — True if mic was used, False if typed

### GPS Detail
- `geolocator` package reads device GPS chip
- Must request `ACCESS_FINE_LOCATION` permission
- On emulator: set fake location in Extended Controls

### Django Backend — What to Build

**`apps/issues/models.py`** additions to Issue:
```python
original_description = models.TextField(blank=True)   # citizen's original language text
detected_language = models.CharField(max_length=10, blank=True)  # 'ml', 'ta', 'hi', 'en'
was_voice_input = models.BooleanField(default=False)  # True if mic was used
```

**`apps/issues/views.py`** — perform_create:
```python
def perform_create(self, serializer):
    issue = serializer.save(reported_by=self.request.user)
    # Call AI classifier — already done at classify/ endpoint
    # Update reputation
    from apps.users.reputation import update_reputation
    update_reputation(self.request.user, +10, 'submitted', issue)
```

### Flutter — What to Build

**`lib/screens/issue/report_issue_screen.dart`**
- Title field
- Description field (multiline, 3 lines minimum)
- 🎤 Voice input button (beside description field) — see Module 11
- "AI Analyse ✨" button
- AI result card: category chip + severity badge + language detected badge + duplicate warning
- Camera/Gallery picker button with thumbnail
- GPS status: "📍 Location captured" or "Getting location..."
- Category dropdown (may be pre-filled by AI)
- Submit button (disabled until photo + location + title filled)
- Loading overlay during submission

**`lib/services/issue_service.dart`**
```dart
Future<Issue> createIssue(FormData formData) async
// POST /issues/ with multipart FormData

Future<Map> classifyIssue(String description, List<int> nearbyIds) async
// POST /issues/classify/
// Returns: category, severity, is_duplicate, duplicate_id, duplicate_reason,
//          detected_language, translated_description
```

### Packages Required
- Flutter: `image_picker: ^1.0.7`, `geolocator: ^11.0.0`, `dio: ^5.4.0`, `permission_handler: ^11.3.0`, `speech_to_text: ^6.6.0`
- Backend: `Pillow==10.3.0`, `google-generativeai==0.7.2`

### AndroidManifest.xml additions
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

---

## 11. Module 3 — Issue Listing & Search

### What This Module Does (Plain English)
The main feed screen. All reported issues shown as a scrollable list. Citizens can filter by type or status. Issues from citizens with higher reputation scores appear first when sorting by relevance.

### API Query Parameters
```
GET /api/issues/?category=pothole&status=reported&page=2&ordering=-upvote_count
```
- `category` — filter by category
- `status` — filter by status
- `ordering` — `-created_at`, `-upvote_count`, `-ai_severity`, `-reporter__reputation_score`
- `page` — pagination (20 per page)

### IssueCard shows:
- Category icon + title + status badge + severity badge
- Distance from user (calculated from GPS)
- Upvote count
- Time ago
- Small reputation badge of the reporting citizen (👑 Trusted / ✓ Normal)

### Packages Required
- Backend: `django-filter==23.5`
- Flutter: `timeago: ^3.6.1`

---

## 12. Module 4 — Map View with Heatmap & Clustering

### What This Module Does (Plain English)
The map screen shows ALL reported issues in three ways — individual pins, a heatmap overlay showing problem density, and automatic clustering of nearby pins. These are three toggleable views on the same map screen.

**Pin View** — Default. Red pin = Reported, Orange = In Progress, Green = Resolved.

**Heatmap View** — Areas with many unresolved complaints glow red/orange/yellow. Areas with few complaints are green or transparent. This shows problem zones at a glance without reading any complaints. Extremely useful for authorities planning maintenance routes.

**Cluster View** — Nearby pins of the same category merge into a numbered cluster badge (e.g. "Pothole ×12"). Tapping expands the cluster. Prevents map from becoming unusable in densely-reported areas.

### Map Screen Layout
```
┌──────────────────────────────────────┐
│  [Map View]        [📍 Pin | 🔥 Heat | 📦 Cluster]  ← Toggle tabs
├──────────────────────────────────────┤
│                                      │
│    [Google Map fills full screen]    │
│                                      │
│  In Pin mode:   🔴 🔴 🟢 🟠         │
│  In Heat mode:  🔴 glowing zone      │
│  In Cluster:    [Pothole ×8] badge   │
│                                      │
├──────────────────────────────────────┤ ← Bottom sheet on tap
│ 🕳️ Pothole — MG Road                 │
│ Status: Reported  👍 12  Reputation ✓│
│    [View Full Details →]             │
└──────────────────────────────────────┘
```

### Heatmap Technical Detail
```dart
// Google Maps Flutter Plugin supports WeightedLatLng for heatmap
// Each issue is a WeightedLatLng point:
//   weight = 1.0 (reported) → 2.0 (high severity) → 3.0 (critical + many upvotes)

List<WeightedLatLng> heatmapPoints = issues.map((issue) {
  double weight = 1.0;
  if (issue.aiSeverity == 'critical') weight = 3.0;
  else if (issue.aiSeverity == 'high') weight = 2.0;
  if (issue.upvoteCount > 10) weight += 0.5;
  return WeightedLatLng(LatLng(issue.lat, issue.lng), weight: weight);
}).toList();

// Heatmap layer is toggled by tapping the Heat tab
```

### Clustering Technical Detail
```dart
// Package: google_maps_cluster_manager
// ClusterManager groups nearby markers automatically
// Each cluster shows: category name + count badge
// Tapping cluster → map zooms in → pins expand

ClusterManager _manager = ClusterManager<Issue>(
  issues,
  _updateMarkers,
  markerBuilder: _markerBuilder,
);

// Custom cluster icon shows: "Pothole ×8" in a pill badge
// Tapping zooms in until individual pins are visible
```

### Django Backend — What to Build

**`/api/issues/map/` (GET)** — returns all issues lightweight:
```json
[
  {
    "id": 1,
    "title": "Pothole on MG Road",
    "latitude": "8.524100",
    "longitude": "76.936600",
    "status": "reported",
    "category": "pothole",
    "ai_severity": "high",
    "upvote_count": 12,
    "reporter_reputation_level": "trusted"
  }
]
```
- No photo, no description (saves bandwidth)
- No pagination (map needs all pins at once)
- Include `reporter_reputation_level` to show trust badge on pin popup

### Flutter — What to Build

**`lib/screens/issue/map_screen.dart`**
- Full-screen `GoogleMap` widget
- Three tab toggle: Pin / Heatmap / Cluster (ToggleButtons widget)
- `_mode` state: `'pin'`, `'heat'`, `'cluster'`
- When mode == 'pin': standard BitmapDescriptor coloured markers
- When mode == 'heat': `HeatmapLayer` with weighted points
- When mode == 'cluster': `ClusterManager` managing all markers
- Bottom sheet on marker/cluster tap
- My location blue dot
- Loading indicator on fetch

**`lib/providers/issue_provider.dart`**
- `mapIssues` — full list for map
- `fetchMapData()` — calls `/issues/map/`

### Packages Required
- Flutter: `google_maps_flutter: ^2.5.3`, `google_maps_cluster_manager: ^3.0.0`

### Google Maps Setup
```
1. console.cloud.google.com → Create project
2. Enable: Maps SDK for Android
3. Create API Key → restrict to Android app
4. Add to AndroidManifest.xml inside <application>:
   <meta-data android:name="com.google.android.geo.API_KEY"
              android:value="YOUR_KEY_HERE"/>
5. Store key in .env file (for reference)
```

---

## 13. Module 5 — Status Tracking

### What This Module Does (Plain English)
Citizens follow their complaint through four stages — Reported, In Progress, Resolved, Closed. Every change is recorded permanently with who changed it, when, and why. Full audit trail = full transparency.

### Status Flow
```
[Reported] → [In Progress] → [Resolved] → [Closed]
    ↑              ↑               ↑            ↑
 Citizen         Authority      Authority    Authority
 submits         starts          fixes        closes
```

**Rules:**
- Only `role = authority` can change status
- Status moves forward only
- Every change creates a StatusUpdate record
- When status → `resolved`: Django calls `update_reputation(citizen, +20, 'resolved', issue)`
- When status → `closed` with note "invalid": Django calls `update_reputation(citizen, -15, 'invalid', issue)`
- When status → `closed` with note "fake": Django calls `update_reputation(citizen, -30, 'fake', issue)`

### Issue Detail Screen shows:
- Photo (full width, tappable)
- Category, severity, detected language
- "Was voice input" indicator (🎤 icon if True)
- GPS coordinates + small map preview
- Reporting citizen's reputation badge
- Upvote button + count
- STATUS TIMELINE widget (vertical, all changes with notes)

### Django Backend — What to Build

**`apps/issues/views.py` — IssueStatusUpdateView**
```python
# PATCH /api/issues/{id}/status/
# - Validates: request.user.role == 'authority'
# - Validates: status transition is forward
# - Creates StatusUpdate record
# - Updates issue.status
# - If new_status == 'resolved': update_reputation(issue.reported_by, +20, 'resolved', issue)
# - If new_status == 'closed' and 'fake' in note.lower(): update_reputation(..., -30, 'fake', issue)
# - If new_status == 'closed' and 'invalid' in note.lower(): update_reputation(..., -15, 'invalid', issue)
# - Triggers FCM push notification via Django signal
```

---

## 14. Module 6 — Authority Panel

### What This Module Does (Plain English)
The web dashboard for government officers. They log in at /admin/, see all complaints in English regardless of original language, sorted by AI severity. Citizen reputation scores are visible to help assess complaint credibility.

### Django Admin Setup

**`apps/issues/admin.py`**
```python
@admin.register(Issue)
class IssueAdmin(admin.ModelAdmin):
    list_display = [
        'id', 'title', 'category', 'status', 'ai_severity',
        'upvote_count', 'detected_language', 'was_voice_input',
        'reporter_reputation',   # custom method showing citizen score
        'created_at'
    ]
    list_filter = ['category', 'status', 'ai_severity', 'detected_language', 'was_voice_input']
    search_fields = ['title', 'description']
    ordering = ['-ai_severity', '-upvote_count', '-created_at']
    readonly_fields = [
        'reported_by', 'ai_suggested_category', 'ai_severity',
        'ai_is_duplicate', 'detected_language', 'original_description',
        'was_voice_input', 'created_at', 'updated_at'
    ]
    actions = ['mark_in_progress', 'mark_resolved']

    def reporter_reputation(self, obj):
        return f"{obj.reported_by.reputation_score} ({obj.reported_by.reputation_level})"
    reporter_reputation.short_description = 'Citizen Trust'
```

Note: Authority always sees `description` field (English). The `original_description` field is shown as a readonly extra field for reference.

---

## 15. Module 7 — User Dashboard & Reputation Score

### What This Module Does (Plain English)
Every citizen has a personal dashboard showing their submitted issues, statistics, and their reputation score. The reputation score is a trust indicator — the more genuine reports you make, the higher your score. High-score citizens get a badge and their reports are prioritised.

### Reputation Score System

**Starting score:** 50 (neutral, `normal` level)

| Event | Points | Reason |
|-------|--------|--------|
| Submit any report | +10 | `submitted` |
| Report marked Resolved by authority | +20 | `resolved` |
| Report gets 5+ upvotes | +5 | `upvoted_5` |
| Report marked Invalid by authority | -15 | `invalid` |
| Report marked Fake by authority | -30 | `fake` |

**Score → Level mapping:**
| Score | Level | Display |
|-------|-------|---------|
| 0–30 | `low` | ⚠️ Low Trust |
| 31–60 | `normal` | — (no badge) |
| 61–80 | `trusted` | ✓ Trusted Citizen |
| 81–100 | `highly_trusted` | 👑 Highly Trusted |

**How reputation affects the app:**
- Issues from `highly_trusted` citizens shown first when sorting by relevance
- Issues from `low` trust citizens shown at bottom, flagged to authority for manual review
- Authority admin panel shows citizen's reputation level next to each issue

### My Reports Screen
- Summary stats row: Total Submitted | Resolved | Pending
- Reputation card: Score (e.g. "72 — Trusted ✓"), progress bar 0–100
- "My Reputation History" — tap to see full ReputationLog
- List of own issues (same card design as Home screen)

### Profile Screen
- User name, email, preferred language, account date
- Reputation score prominently displayed with badge
- "Total Reports: 8 | Resolved: 5"
- Logout button

### Django Backend — What to Build

**`/api/users/me/reputation/` (GET)**
```json
{
  "score": 72,
  "level": "trusted",
  "log": [
    {"change": +10, "reason": "submitted", "issue_id": 3, "timestamp": "2025-08-15T10:30:00Z"},
    {"change": +20, "reason": "resolved", "issue_id": 3, "timestamp": "2025-08-17T14:00:00Z"},
    {"change": -15, "reason": "invalid", "issue_id": 5, "timestamp": "2025-08-18T09:00:00Z"}
  ]
}
```

### Flutter — What to Build

**`lib/widgets/reputation_badge.dart`**
```dart
// Shows:
// level == 'highly_trusted' → 👑 gold badge
// level == 'trusted'        → ✓ blue badge
// level == 'normal'         → nothing (no badge)
// level == 'low'            → ⚠️ grey badge
```

**`lib/screens/dashboard/profile_screen.dart`**
- Reputation card with score number (large), level text, progress bar
- Tap "History" → modal with full ReputationLog list

---

## 16. Module 8 — Community Upvote

### What This Module Does (Plain English)
Multiple affected citizens upvote existing issues instead of filing duplicates. Upvote count visible to authorities — most-upvoted issues get prioritised. When an issue reaches 5 upvotes, the reporting citizen gets a small reputation boost.

### Upvote Rules
- One upvote per user per issue (`unique_together` in DB)
- Tap again to remove upvote (toggle)
- `upvote_count` cached on Issue record
- When `upvote_count` crosses 5 for the first time: Django calls `update_reputation(reporter, +5, 'upvoted_5', issue)`

### Django Backend
```python
# POST /api/issues/{id}/upvote/
# - Check if IssueUpvote exists for (issue, user)
# - If exists: delete → decrement upvote_count
# - If not exists: create → increment upvote_count
# - If upvote_count == 5: update_reputation(issue.reported_by, +5, 'upvoted_5', issue)
# - Return: { "upvoted": true/false, "upvote_count": N }
```

---

## 17. Module 9 — AI-Powered Issue Analysis

### What This Module Does (Plain English)
The AI brain of the app. One Gemini API call handles FOUR tasks simultaneously:
1. Detect the language of the description
2. Translate to English if needed
3. Suggest the correct category
4. Score severity
5. Check for duplicate issues nearby

All five outputs come from one JSON response. Fast, free, and fails gracefully.

### What Gets Sent to Gemini

```python
prompt = f"""You are an AI assistant for a multilingual civic issue reporting app.

Citizen reported this issue (may be in any language):
"{description}"

Recently reported issues nearby (already in English):
{nearby_text}

Return ONLY valid JSON, no markdown, no explanation:
{{
  "detected_language": "ml",
  "translated_description": "There is a large pothole near the bus stop on MG Road",
  "category": "pothole",
  "severity": "high",
  "is_duplicate": false,
  "duplicate_issue_id": null,
  "duplicate_reason": ""
}}

Rules:
- detected_language: ISO 639-1 code (e.g. "en", "ml", "ta", "hi"). "en" if already English.
- translated_description: English translation. Same as input if already English.
- category: one of pothole, streetlight, garbage, water, other
- severity: one of low, medium, high, critical
- is_duplicate: true only if a nearby issue is clearly the same problem
- duplicate_issue_id: integer ID or null
- duplicate_reason: plain English explanation or empty string
"""
```

### What Gemini Returns
```json
{
  "detected_language": "ml",
  "translated_description": "There is a large pothole near the bus stop on MG Road",
  "category": "pothole",
  "severity": "high",
  "is_duplicate": false,
  "duplicate_issue_id": null,
  "duplicate_reason": ""
}
```

### Complete ai_classifier.py

```python
import google.generativeai as genai
import json
from django.conf import settings

genai.configure(api_key=settings.GEMINI_API_KEY)
model = genai.GenerativeModel("gemini-1.5-flash")

VALID_CATEGORIES = ["pothole", "streetlight", "garbage", "water", "other"]
VALID_SEVERITIES = ["low", "medium", "high", "critical"]

DEFAULT_RESULT = {
    "detected_language": "en",
    "translated_description": "",
    "category": "other",
    "severity": "low",
    "is_duplicate": False,
    "duplicate_issue_id": None,
    "duplicate_reason": ""
}

def analyse_issue(description: str, nearby_issues: list) -> dict:
    try:
        nearby_text = "None reported nearby."
        if nearby_issues:
            nearby_text = "\n".join([
                f"- ID {i['id']}: {i['category'].title()} — \"{i['description'][:120]}\""
                for i in nearby_issues[:5]
            ])

        prompt = f"""You are an AI assistant for a multilingual civic issue reporting app.

Citizen reported this issue (may be in any language):
"{description}"

Recently reported issues nearby:
{nearby_text}

Return ONLY valid JSON, no markdown, no explanation:
{{"detected_language":"en","translated_description":"","category":"pothole","severity":"high","is_duplicate":false,"duplicate_issue_id":null,"duplicate_reason":""}}

Rules:
- detected_language: ISO 639-1 code. "en" if already English.
- translated_description: English translation. Same as input if already English.
- category: one of pothole,streetlight,garbage,water,other
- severity: one of low,medium,high,critical
- is_duplicate: true only if nearby issue is clearly same problem
- duplicate_issue_id: integer ID or null
- duplicate_reason: plain English or empty string"""

        response = model.generate_content(prompt)
        raw = response.text.strip().replace("```json","").replace("```","").strip()
        result = json.loads(raw)

        return {
            "detected_language": str(result.get("detected_language", "en"))[:10],
            "translated_description": str(result.get("translated_description", description))[:2000],
            "category": result.get("category","other") if result.get("category") in VALID_CATEGORIES else "other",
            "severity": result.get("severity","low") if result.get("severity") in VALID_SEVERITIES else "low",
            "is_duplicate": bool(result.get("is_duplicate", False)),
            "duplicate_issue_id": result.get("duplicate_issue_id", None),
            "duplicate_reason": str(result.get("duplicate_reason", ""))[:300],
        }
    except Exception:
        return {**DEFAULT_RESULT, "translated_description": description}
```

### classify_issue_view (Django)
```python
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def classify_issue_view(request):
    description = request.data.get('description', '').strip()
    if not description or len(description) < 3:
        return Response(DEFAULT_RESULT)

    nearby_ids = request.data.get('nearby_issue_ids', [])
    nearby_issues = []
    if nearby_ids:
        nearby_issues = list(
            Issue.objects.filter(id__in=nearby_ids[:5])
            .values('id', 'category', 'description')
        )

    result = analyse_issue(description, nearby_issues)
    return Response(result)
```

### Flutter — AI button in report_issue_screen.dart
```
1. Citizen types OR speaks description
2. Taps [✨ AI Analyse] button
3. Loading spinner on button
4. Fetch nearby issue IDs (bounding box query)
5. POST /api/issues/classify/ with description + nearby_ids
6. Response shows:
   ┌────────────────────────────────┐
   │ 🌐 Detected: Malayalam         │
   │    → Translated to English     │
   │ Category: [Pothole ✓]         │
   │ Severity: [🔴 High]           │
   │ ⚠️ Similar issue found nearby! │
   │   "Road damage on MG Road"     │
   │ [View Existing] [Submit Anyway]│
   └────────────────────────────────┘
```

### Gemini Setup
```
1. Go to: aistudio.google.com
2. Sign in with Google → Get API Key → Create
3. Copy key → add to .env: GEMINI_API_KEY=your_key
4. pip install google-generativeai==0.7.2
Free tier: 1,500 calls/day, 15/minute, ₹0, no card
```

---

## 18. Module 10 — Multilingual Support

### What This Module Does (Plain English)
Citizens can type or speak in Malayalam, Tamil, Hindi, or any language. Gemini AI detects the language and translates to English automatically. The English version is stored as the main `description` field. The original text is stored in `original_description`. Authorities always see English. Citizens see their own language.

### Language Detection & Translation Flow
```
Citizen writes/speaks: "MG Road-il valiya kuzhiyaanu" (Malayalam)
         ↓
Gemini detects: detected_language = "ml"
Gemini translates: "There is a large pothole on MG Road"
         ↓
Django saves:
  description          = "There is a large pothole on MG Road"  (English)
  original_description = "MG Road-il valiya kuzhiyaanu"         (Malayalam)
  detected_language    = "ml"
         ↓
Authority dashboard → sees: "There is a large pothole on MG Road"
Citizen app → shows: "MG Road-il valiya kuzhiyaanu" (their original)
```

### Supported Languages (via Gemini)
Gemini 1.5 Flash supports all major Indian languages and global languages natively:
- Malayalam (ml), Tamil (ta), Telugu (te), Kannada (kn)
- Hindi (hi), Bengali (bn), Marathi (mr), Gujarati (gu)
- English (en), Arabic (ar), French (fr), and many more
- No extra setup — Gemini handles it automatically

### Language Badge on Issue Card
```dart
// If detected_language != 'en':
// Show small flag + language name
// e.g. "🇮🇳 Malayalam" chip on the issue card
// Tapping it shows: "Original: MG Road-il valiya kuzhiyaanu"
```

### Django Backend Changes
- `Issue.description` → always English (translated if needed)
- `Issue.original_description` → citizen's original text (blank if English)
- `Issue.detected_language` → ISO code
- Filter in admin: `list_filter = [..., 'detected_language']`
- No third-party translation library needed — Gemini handles everything

---

## 19. Module 11 — Voice-to-Text Reporting

### What This Module Does (Plain English)
Citizens tap a microphone button and describe the problem by speaking. The spoken words are converted to text in real time using the device's built-in speech recognition engine. No internet connection needed for this step. No API key required. Works in any language the device supports.

### Technical Detail

**Package:** `speech_to_text: ^6.6.0`

**How it works:**
- Uses Android's built-in SpeechRecognizer (Google's speech engine)
- Completely free — no API calls, no quota, no cost
- Works offline for many languages
- Supports Malayalam, Tamil, Hindi, and all languages Android supports

```dart
// lib/services/speech_service.dart

import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();

  Future<bool> initialize() async {
    return await _speech.initialize(
      onError: (error) => print('Speech error: $error'),
    );
  }

  void startListening({required Function(String) onResult}) {
    _speech.listen(
      onResult: (result) => onResult(result.recognizedWords),
      localeId: 'ml_IN',  // or use detected preferred_language from user profile
      pauseFor: Duration(seconds: 3),
    );
  }

  void stopListening() => _speech.stop();
  bool get isListening => _speech.isListening;
}
```

### Voice Input Button Widget

**`lib/widgets/voice_input_button.dart`**
```dart
// Shows: microphone icon
// State 1 (idle):    🎤 grey icon
// State 2 (listening): 🎤 red pulsing icon + "Listening..."
// State 3 (done):    🎤 green icon + words appear in description field

// Tap to start → tap again to stop early (or auto-stops after 3s silence)
```

### AndroidManifest.xml addition for microphone
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

### Report Issue Screen with Voice Button
```
┌──────────────────────────────────┐
│ Describe the problem:            │
│ ┌────────────────────────────┐  │
│ │ Type here...               │  │
│ │                            │  │
│ └───────────────────┐        │  │
│                     │ [🎤]   │  ← Mic button beside field
│                                 │
│ [✨ AI Analyse]                 │
└──────────────────────────────────┘

When mic is active:
│ ● LISTENING... (red pulse)      │
│ "Valiya kuzhiyaanu MG Road..."  │ ← Real-time text appears
```

### was_voice_input field in DB
- Set to `True` when citizen used the mic button
- Shown as 🎤 icon in authority panel and issue detail
- Useful for analytics: track what % of citizens prefer voice vs text

---

## 20. Module 12 — Push Notifications (Optional)

### What This Module Does (Plain English)
When an authority updates an issue's status, the reporting citizen gets an instant push notification on their phone — even when the app is closed.

### Technical Flow
```
1. Citizen opens app → firebase_messaging gets FCM device token
2. Flutter PATCH /api/auth/me/fcm-token/ to save token in DB
3. Authority updates status in admin panel
4. Django signal fires: post_save on StatusUpdate
5. Signal calls FCM API:
   - To: issue.reported_by.fcm_token
   - Title: "Issue Status Updated"
   - Body: "Your 'Pothole on MG Road' is now In Progress"
   - Data: { "issue_id": 42 }
6. Citizen receives notification → taps → app opens issue detail
```

### Setup
```
1. console.firebase.google.com → Create project
2. Add Android app → enter Flutter package name
3. Download google-services.json → place in mobile/android/app/
4. Follow Flutter Firebase setup docs
```

### Packages Required
- Flutter: `firebase_core: ^2.27.0`, `firebase_messaging: ^14.7.0`
- Backend: `requests==2.31.0` (for calling FCM HTTP API)

---

## 21. Flutter App — All Screens

| Screen File | Route | What It Shows |
|------------|-------|---------------|
| `splash_screen.dart` | `/` | Logo + auto-navigate |
| `onboarding_screen.dart` | `/onboarding` | 3-slide intro |
| `login_screen.dart` | `/login` | Login form |
| `register_screen.dart` | `/register` | Registration + language preference |
| `home_screen.dart` | `/home` | Issue feed with reputation badges |
| `report_issue_screen.dart` | `/report` | Form with 🎤 mic + AI + camera |
| `issue_detail_screen.dart` | `/issue/:id` | Full detail + timeline + language badge |
| `map_screen.dart` | `/map` | Map with Pin/Heatmap/Cluster toggle |
| `my_reports_screen.dart` | `/my-reports` | Own issues + stats |
| `profile_screen.dart` | `/profile` | Info + reputation score + history |
| `notifications_screen.dart` | `/notifications` | Push notification history |

### Bottom Navigation Bar
```
[🏠 Home]  [🗺️ Map]  [➕ Report]  [📋 My Reports]  [👤 Profile]
```

---

## 22. Flutter App — State Management

Using **Provider** package.

### AuthProvider
- Holds: `currentUser` (includes `reputationScore`, `reputationLevel`, `preferredLanguage`)
- Methods: `login()`, `logout()`, `register()`, `updateReputation()`

### IssueProvider
- Holds: `issues`, `mapIssues`, `myIssues`, `mapMode` ('pin'/'heat'/'cluster')
- Methods: `fetchIssues()`, `fetchMapData()`, `createIssue()`, `upvoteIssue()`, `classifyIssue()`, `setMapMode(mode)`

### Provider Setup in main.dart
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    ChangeNotifierProvider(create: (_) => IssueProvider()),
  ],
  child: MaterialApp(...)
)
```

---

## 23. Flutter App — Navigation Structure

```dart
routes: {
  '/':              (ctx) => SplashScreen(),
  '/onboarding':    (ctx) => OnboardingScreen(),
  '/login':         (ctx) => LoginScreen(),
  '/register':      (ctx) => RegisterScreen(),
  '/home':          (ctx) => MainShell(),
  '/report':        (ctx) => ReportIssueScreen(),
  '/notifications': (ctx) => NotificationsScreen(),
}

// Issue detail with argument:
Navigator.pushNamed(context, '/issue', arguments: issueId);

// MainShell: IndexedStack with 4 tabs:
// 0: HomeScreen, 1: MapScreen, 2: MyReportsScreen, 3: ProfileScreen
// FAB in centre of bottom nav → opens ReportIssueScreen
```

---

## 24. Flutter App — All Packages

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Networking
  dio: ^5.4.0

  # Auth & Storage
  shared_preferences: ^2.2.2

  # Maps & Location
  google_maps_flutter: ^2.5.3
  google_maps_cluster_manager: ^3.0.0   # NEW: marker clustering
  geolocator: ^11.0.0
  geocoding: ^3.0.0

  # Camera & Media
  image_picker: ^1.0.7

  # Voice Input                          # NEW
  speech_to_text: ^6.6.0

  # State Management
  provider: ^6.1.2

  # Firebase (Module 12 — optional)
  firebase_core: ^2.27.0
  firebase_messaging: ^14.7.0

  # UI & UX
  cached_network_image: ^3.3.1
  timeago: ^3.6.1
  flutter_spinkit: ^5.2.0

  # Permissions
  permission_handler: ^11.3.0

  # Utilities
  intl: ^0.19.0
```

---

## 25. Django Backend — Project Settings

### `requirements.txt`
```
Django==4.2.13
djangorestframework==3.15.1
djangorestframework-simplejwt==5.3.1
django-filter==23.5
Pillow==10.3.0
psycopg2-binary==2.9.9
python-dotenv==1.0.1
google-generativeai==0.7.2
django-cors-headers==4.3.1
requests==2.31.0
```

### `config/settings.py` — Key Sections

```python
import os
from pathlib import Path
from datetime import timedelta
from dotenv import load_dotenv

load_dotenv()
BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = os.getenv('DJANGO_SECRET_KEY')
DEBUG = os.getenv('DEBUG', 'True') == 'True'
ALLOWED_HOSTS = ['*']

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'rest_framework_simplejwt',
    'django_filters',
    'corsheaders',
    'apps.users',
    'apps.issues',
    'apps.notifications',
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',  # must be first
    # ... rest of defaults
]

AUTH_USER_MODEL = 'users.CustomUser'

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_FILTER_BACKENDS': [
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.OrderingFilter',
        'rest_framework.filters.SearchFilter',
    ],
    'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination',
    'PAGE_SIZE': 20,
}

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=60),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=30),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
}

MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'
STATIC_URL = '/static/'
CORS_ALLOW_ALL_ORIGINS = True   # Development only
GEMINI_API_KEY = os.getenv('GEMINI_API_KEY')
```

---

## 26. Django Backend — All Models

See Section 7 for complete field listings.

### Model Relationships Summary
```python
# apps/users/models.py
class CustomUser(AbstractUser):
    USERNAME_FIELD = 'email'
    reputation_score = models.PositiveIntegerField(default=50)
    reputation_level = models.CharField(max_length=20, default='normal')
    preferred_language = models.CharField(max_length=10, default='en')

class ReputationLog(models.Model):
    user = ForeignKey(CustomUser, on_delete=CASCADE)
    change = models.IntegerField()
    reason = models.CharField(max_length=30)
    related_issue = ForeignKey('issues.Issue', null=True, on_delete=SET_NULL)
    timestamp = models.DateTimeField(auto_now_add=True)

# apps/issues/models.py
class Issue(models.Model):
    reported_by = ForeignKey(CustomUser, on_delete=CASCADE)
    original_description = models.TextField(blank=True)
    detected_language = models.CharField(max_length=10, blank=True, default='en')
    was_voice_input = models.BooleanField(default=False)
    ai_duplicate_of = ForeignKey('self', null=True, blank=True, on_delete=SET_NULL)

class IssueUpvote(models.Model):
    issue = ForeignKey(Issue, on_delete=CASCADE)
    user = ForeignKey(CustomUser, on_delete=CASCADE)
    class Meta:
        unique_together = ('issue', 'user')

class StatusUpdate(models.Model):
    issue = ForeignKey(Issue, on_delete=CASCADE, related_name='status_history')
    updated_by = ForeignKey(CustomUser, on_delete=CASCADE)
    old_status = models.CharField(max_length=20)
    new_status = models.CharField(max_length=20)
    note = models.TextField(blank=True)
    timestamp = models.DateTimeField(auto_now_add=True)
```

---

## 27. Django Backend — Serializers

### Users App
- `RegisterSerializer` — validates + creates user, sets reputation_score=50
- `UserSerializer` — read-only (id, full_name, email, role, reputation_score, reputation_level, preferred_language)
- `ReputationLogSerializer` — read-only (change, reason, related_issue id, timestamp)

### Issues App
- `IssueCreateSerializer` — POST; includes original_description, detected_language, was_voice_input
- `IssueListSerializer` — GET list; lightweight; includes reporter reputation_level
- `IssueDetailSerializer` — GET single; all fields + status_history + language info
- `StatusUpdateSerializer` — read-only history

---

## 28. Django Backend — Views & Logic

| View | Method | URL | Auth | Purpose |
|------|--------|-----|------|---------|
| `RegisterView` | POST | `/auth/register/` | No | Create account |
| `LoginView` | POST | `/auth/login/` | No | JWT tokens |
| `TokenRefreshView` | POST | `/auth/token/refresh/` | No | Refresh |
| `UserProfileView` | GET, PATCH | `/auth/me/` | Yes | Profile |
| `FCMTokenView` | PATCH | `/auth/me/fcm-token/` | Yes | Save push token |
| `ReputationView` | GET | `/users/me/reputation/` | Yes | Score + log |
| `IssueListCreateView` | GET, POST | `/issues/` | Yes | List + create |
| `IssueDetailView` | GET | `/issues/{id}/` | Yes | Single issue |
| `IssueStatusUpdateView` | PATCH | `/issues/{id}/status/` | Authority | Update + reputation |
| `IssueMapView` | GET | `/issues/map/` | Yes | Map data |
| `IssueUpvoteView` | POST | `/issues/{id}/upvote/` | Yes | Toggle upvote |
| `IssueHistoryView` | GET | `/issues/{id}/history/` | Yes | Status timeline |
| `ClassifyIssueView` | POST | `/issues/classify/` | Yes | AI: category + severity + duplicate + language + translation |
| `UserIssuesView` | GET | `/users/me/issues/` | Yes | My issues |
| `UserStatsView` | GET | `/users/me/stats/` | Yes | My stats |

---

## 29. Django Backend — URL Routing

### `config/urls.py`
```python
urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/', include('apps.users.urls')),
    path('api/', include('apps.issues.urls')),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
```

### `apps/users/urls.py`
```python
urlpatterns = [
    path('auth/register/', RegisterView.as_view()),
    path('auth/login/', TokenObtainPairView.as_view()),
    path('auth/token/refresh/', TokenRefreshView.as_view()),
    path('auth/me/', UserProfileView.as_view()),
    path('auth/me/fcm-token/', FCMTokenView.as_view()),
    path('users/me/issues/', UserIssuesView.as_view()),
    path('users/me/stats/', UserStatsView.as_view()),
    path('users/me/reputation/', ReputationView.as_view()),  # NEW
]
```

### `apps/issues/urls.py`
```python
urlpatterns = [
    path('issues/', IssueListCreateView.as_view()),
    path('issues/map/', IssueMapView.as_view()),
    path('issues/classify/', classify_issue_view),
    path('issues/<int:pk>/', IssueDetailView.as_view()),
    path('issues/<int:pk>/status/', IssueStatusUpdateView.as_view()),
    path('issues/<int:pk>/upvote/', IssueUpvoteView.as_view()),
    path('issues/<int:pk>/history/', IssueHistoryView.as_view()),
]
```

---

## 30. Django Backend — Admin Panel

```python
@admin.register(Issue)
class IssueAdmin(admin.ModelAdmin):
    list_display = [
        'id', 'title', 'category', 'status', 'ai_severity',
        'upvote_count', 'detected_language', 'was_voice_input',
        'reporter_trust', 'created_at'
    ]
    list_filter = [
        'category', 'status', 'ai_severity',
        'detected_language', 'was_voice_input', 'created_at'
    ]
    search_fields = ['title', 'description', 'original_description']
    ordering = ['-ai_severity', '-upvote_count', '-created_at']
    readonly_fields = [
        'reported_by', 'ai_suggested_category', 'ai_severity',
        'ai_is_duplicate', 'detected_language', 'original_description',
        'was_voice_input', 'created_at', 'updated_at'
    ]
    actions = ['mark_in_progress', 'mark_resolved', 'mark_invalid', 'mark_fake']

    def reporter_trust(self, obj):
        return f"{obj.reported_by.reputation_score} — {obj.reported_by.reputation_level}"
    reporter_trust.short_description = 'Citizen Trust'

    def mark_invalid(self, request, queryset):
        for issue in queryset:
            issue.status = 'closed'
            issue.save()
            update_reputation(issue.reported_by, -15, 'invalid', issue)

    def mark_fake(self, request, queryset):
        for issue in queryset:
            issue.status = 'closed'
            issue.save()
            update_reputation(issue.reported_by, -30, 'fake', issue)


@admin.register(CustomUser)
class UserAdmin(admin.ModelAdmin):
    list_display = ['email', 'full_name', 'role', 'reputation_score', 'reputation_level', 'preferred_language']
    list_filter = ['role', 'reputation_level', 'preferred_language']
    search_fields = ['email', 'full_name']
```

---

## 31. AI Integration — Gemini API

See Section 17 for complete implementation.

| Item | Value |
|------|-------|
| Model | `gemini-1.5-flash` |
| Free calls/day | 1,500 |
| Free calls/minute | 15 |
| Cost | ₹0 — no credit card |
| Python package | `google-generativeai==0.7.2` |
| API key portal | aistudio.google.com |
| Tasks per call | 5: language detect + translate + category + severity + duplicate |
| Failure | Returns safe defaults — app never crashes |
| Languages | All major languages including all Indian languages |

---

## 32. Authentication Flow — JWT

```
SharedPreferences keys:
  'access_token'       → JWT access token
  'refresh_token'      → JWT refresh token
  'user_id'            → logged-in user ID
  'user_role'          → 'citizen' or 'authority'
  'reputation_score'   → cached reputation score
  'reputation_level'   → cached level
  'preferred_language' → 'en', 'ml', 'ta', etc.
```

**Dio Interceptor:**
- Before every request: add `Authorization: Bearer <access_token>`
- On 401: try POST `/auth/token/refresh/` → retry original request
- If refresh fails: clear tokens → navigate to Login screen

---

## 33. Image Upload Flow

```
Flutter (phone)                      Django (server)
─────────────────                   ─────────────────
1. image_picker returns file path
2. Dio FormData.fromMap({
     'photo': MultipartFile.fromFile(path),
     'title': '...',
     'description': 'English text',
     'original_description': 'Malayalam text',
     'detected_language': 'ml',
     'was_voice_input': 'true',
     'latitude': '8.5241',
     'longitude': '76.9366',
     'ai_severity': 'high',
     'ai_is_duplicate': 'false',
   })
3. Dio POST to /api/issues/ ──────→ 4. ImageField saves to /media/issues/
                                    5. DB stores path + all fields
                                    6. update_reputation(user, +10, 'submitted')
                                    7. Returns 201 + issue data
```

---

## 34. GPS & Maps Flow

```dart
// Check and request permission
LocationPermission permission = await Geolocator.checkPermission();
if (permission == LocationPermission.denied) {
  permission = await Geolocator.requestPermission();
}

// Get coordinates
Position position = await Geolocator.getCurrentPosition(
  desiredAccuracy: LocationAccuracy.high,
  timeLimit: Duration(seconds: 10),
);
```

**Emulator fix:** Android Studio → Extended Controls → Location → set fake lat/lng

**Nearby issues bounding box:**
```dart
double latDelta = 0.0045;  // ~500m
double lngDelta = 0.0055;
// GET /issues/?lat_min=&lat_max=&lng_min=&lng_max=
```

---

## 35. Status Update Flow

```
Authority marks "Resolved" in admin:
  → StatusUpdate record created
  → update_reputation(citizen, +20, 'resolved', issue)
  → Django signal fires → FCM push to citizen

Authority marks "Closed" with note "fake":
  → StatusUpdate record created
  → update_reputation(citizen, -30, 'fake', issue)
  → Citizen's reputation_level may drop to 'low'

Citizen app:
  → If open: provider refreshes → status timeline updates
  → If closed: push notification shows → tap opens issue detail
```

---

## 36. Voice-to-Text Flow

```
Citizen taps 🎤 mic button
    ↓
permission_handler requests RECORD_AUDIO permission
    ↓
SpeechToText.listen() starts
    ↓
Android SpeechRecognizer processes audio (device-local)
    ↓
Words stream into description field in real time
    ↓
3 seconds silence → auto-stops (or citizen taps mic again)
    ↓
was_voice_input = true (stored in DB)
    ↓
Citizen taps ✨ AI Analyse → text sent to Gemini for language detection + translation
```

**Important:** Voice-to-text is completely local — no internet needed for this step alone. The AI Analyse step (Gemini) does need internet.

---

## 37. Multilingual Flow

```
Citizen writes "MG Road-il kuzhiyaanu" (Malayalam)
    ↓
Taps AI Analyse
    ↓
POST /api/issues/classify/ with { "description": "MG Road-il kuzhiyaanu", ... }
    ↓
Django → Gemini:
  Returns {
    "detected_language": "ml",
    "translated_description": "There is a pothole on MG Road",
    "category": "pothole",
    "severity": "high",
    ...
  }
    ↓
Flutter shows: 🌐 Malayalam → English translation shown to citizen
    ↓
Citizen submits:
  POST /api/issues/ with:
    description = "There is a pothole on MG Road"   (English)
    original_description = "MG Road-il kuzhiyaanu"  (Malayalam)
    detected_language = "ml"
    ↓
DB saves both versions
    ↓
Authority sees English description in admin panel
Citizen sees their original Malayalam in the app
```

---

## 38. Reputation Score Flow

```
NEW CITIZEN REGISTERS:
  reputation_score = 50
  reputation_level = 'normal'
  ReputationLog: { change: 0, reason: 'account_created' }

CITIZEN SUBMITS REPORT:
  update_reputation(user, +10, 'submitted', issue)
  score: 50 → 60
  level: 'normal' (31–60)

REPORT GETS 5 UPVOTES:
  update_reputation(user, +5, 'upvoted_5', issue)
  score: 60 → 65
  level: 'trusted' (61–80) → badge appears: ✓ Trusted Citizen

AUTHORITY RESOLVES ISSUE:
  update_reputation(user, +20, 'resolved', issue)
  score: 65 → 85
  level: 'highly_trusted' (81–100) → badge: 👑 Highly Trusted

AUTHORITY MARKS ISSUE FAKE:
  update_reputation(user, -30, 'fake', issue)
  score: 85 → 55
  level: 'normal' (31–60) → badge removed

SCORE CLAMP: never below 0, never above 100
```

---

## 39. Map Clustering & Heatmap Flow

### Clustering Flow
```
1. Fetch all map data from /api/issues/map/
2. ClusterManager receives List<Issue> with lat/lng
3. At current zoom level: nearby markers merge into clusters
4. Cluster badge shows: category + count (e.g. "Pothole ×8")
5. User zooms in → clusters split into individual pins
6. Tap individual pin → bottom sheet with issue summary
```

### Heatmap Flow
```
1. Fetch all map data (same endpoint as pin view)
2. Filter to show only status='reported' (unresolved)
3. Create WeightedLatLng for each issue:
   weight = base 1.0
   + 1.0 if severity == 'critical'
   + 0.5 if severity == 'high'
   + 0.3 if upvote_count > 10
4. Add HeatmapLayer to GoogleMap
5. Result: densely-reported areas glow red, sparse areas green/transparent
6. User toggles back to Pin/Cluster view using tab buttons
```

### Mode Toggle in Flutter
```dart
// map_screen.dart state:
String _mapMode = 'pin'; // 'pin', 'heat', 'cluster'

// ToggleButtons at top of screen:
// [📍 Pin] [🔥 Heatmap] [📦 Cluster]

// Switching mode:
setState(() { _mapMode = 'heat'; });
// Re-renders GoogleMap with appropriate layer
```

---

## 40. Testing Plan

### Backend Unit Tests (`apps/issues/tests.py`)
Run: `python manage.py test`

| ID | Test | Expected |
|----|------|---------|
| TC-01 | Register valid user | 201, score=50 |
| TC-02 | Register duplicate email | 400 |
| TC-03 | Login valid credentials | 200 + tokens |
| TC-04 | Login wrong password | 401 |
| TC-05 | Submit issue with photo + GPS | 201, reputation+10 |
| TC-06 | Submit issue without photo | 400 |
| TC-07 | Submit issue with Malayalam description | 201, detected_language='ml' |
| TC-08 | Upvote an issue | 200, count+1 |
| TC-09 | Upvote same issue twice | 400 |
| TC-10 | Upvote triggers reputation at count=5 | reputation+5 |
| TC-11 | Update status as authority → resolved | 200, reputation+20 |
| TC-12 | Update status as citizen | 403 |
| TC-13 | Update status backward | 400 |
| TC-14 | Mark issue invalid → reputation-15 | score decreases |
| TC-15 | Mark issue fake → reputation-30 | score decreases |
| TC-16 | AI classify valid description | 200 + valid JSON |
| TC-17 | AI classify Malayalam text | detected_language='ml', has translation |
| TC-18 | AI classify endpoint — AI failure (mocked) | 200 + safe defaults |
| TC-19 | Map endpoint returns lat/lng only | 200, no photo field |
| TC-20 | Filter issues by category | Only matching category |
| TC-21 | Reputation log endpoint | Returns score + log array |
| TC-22 | Reputation clamped at 100 | Never exceeds 100 |
| TC-23 | Reputation clamped at 0 | Never goes below 0 |

### Flutter Widget Tests (`mobile/test/`)
Run: `flutter test`

| ID | Screen | What to Test |
|----|--------|-------------|
| WT-01 | LoginScreen | Form renders |
| WT-02 | RegisterScreen | Language preference dropdown present |
| WT-03 | HomeScreen | Reputation badge renders on IssueCard |
| WT-04 | ReportIssueScreen | Mic button present |
| WT-05 | ReportIssueScreen | Language badge shows after AI analyse |
| WT-06 | ReportIssueScreen | Submit disabled until required fields filled |
| WT-07 | MapScreen | Mode toggle buttons present (Pin/Heat/Cluster) |
| WT-08 | ProfileScreen | Reputation score and badge visible |
| WT-09 | StatusBadge | Correct colour per status |

### Manual Testing Checklist
```
[ ] Register + check reputation starts at 50
[ ] Login + check auto-login on restart
[ ] Submit issue by typing → check reputation becomes 60
[ ] Submit issue by voice in Malayalam → check language detected
[ ] Check AI analyse shows language badge + translation
[ ] Submit issue → check English stored as description
[ ] Check issue in admin → authority sees English
[ ] Update status to Resolved → check reputation becomes 80
[ ] Upvote an issue 5 times from different accounts → check reputation+5
[ ] Mark issue as fake → check reputation decreases
[ ] Check map in Pin mode → pins coloured correctly
[ ] Switch to Heatmap mode → density overlay visible
[ ] Switch to Cluster mode → nearby pins merge into badges
[ ] Zoom in on cluster → expands to individual pins
[ ] Check profile screen → reputation score + badge matches score
[ ] Check reputation history → all changes listed
```

### Coverage Report
```bash
pip install coverage
coverage run manage.py test
coverage report -m
coverage html   # visual report at htmlcov/index.html
```

---

## 41. Sprint Plan & Timeline

| Sprint | Weeks | Modules | Goals | Deliverables |
|--------|-------|---------|-------|-------------|
| S0 | 1–2 | Setup | Synopsis, Git repo, project skeleton, product backlog | `main.dart` runs, `manage.py runserver` works |
| S1 | 3–4 | M1 | Auth + reputation score foundation | Login returns JWT + score. Reputation model created. |
| S2 | 5–6 | M2 + M11 | Issue reporting + voice input + AI (with translation) | Voice → text → AI → submit with language stored |
| S3 | 7–8 | M3 + M4 | Issue list + Map (Pin + Heatmap + Cluster) — **Demo 1** | Feed loads. Map shows all 3 modes. |
| S4 | 9–10 | M5 + M6 | Status tracking + authority panel with reputation display | Status update → reputation change. Admin shows trust. |
| S5 | 11–12 | M7 + M8 | Dashboard + upvote + reputation UI — **Demo 2** | Profile shows score. Upvote triggers reputation. |
| S6 | 13–14 | M10 + Testing | Multilingual polish + unit tests + bug fixes | All languages tested. GitHub Issues closed. |
| S7 | 15–16 | Git + Docs | v1.0 tag, README, Scrum Book complete | `git tag v1.0` pushed. |
| S8 | 17–18 | Report | LaTeX report + final presentation | PDF submitted. |

---

## 42. Scrum Book Guide

### Part I — Product Backlog (all user stories)

| ID | User Story | Priority | Sprint | Status |
|----|-----------|----------|--------|--------|
| US-01 | As a citizen I can register | High | S1 | |
| US-02 | As a citizen I can log in securely | High | S1 | |
| US-03 | My reputation score starts at 50 on registration | High | S1 | |
| US-04 | As a citizen I can report an issue with photo | High | S2 | |
| US-05 | As a citizen I can use my voice to describe the issue | High | S2 | |
| US-06 | The app detects my language and translates automatically | High | S2 | |
| US-07 | AI suggests the category and severity | High | S2 | |
| US-08 | AI warns me if a similar issue exists nearby | Medium | S2 | |
| US-09 | I can browse all issues in a feed | Medium | S3 | |
| US-10 | I can see all issues on a map with pins | Medium | S3 | |
| US-11 | I can switch map to heatmap view | Medium | S3 | |
| US-12 | I can switch map to cluster view | Medium | S3 | |
| US-13 | I can track my issue through 4 stages | High | S4 | |
| US-14 | As authority I can update issue status | High | S4 | |
| US-15 | Authority can see citizen reputation in admin | Medium | S4 | |
| US-16 | I can see My Reports in dashboard | Medium | S5 | |
| US-17 | I can upvote issues | Medium | S5 | |
| US-18 | My reputation increases when issue is resolved | High | S5 | |
| US-19 | My reputation badge is visible on profile | Medium | S5 | |
| US-20 | Authority can mark reports fake to reduce reputation | Medium | S6 | |
| US-21 | I receive push notifications on status change | Low | Optional | |

### Part II — Database & UI Design
- ER diagram (Draw.io) — include all 5 models
- API endpoint table (from Section 8)
- Flutter wireframes (Figma) for all screens including new map modes
- Language flow diagram (Section 37)
- Reputation flow diagram (Section 38)

### Part III — Testing & Validation
- All 23 backend test cases
- All 9 Flutter widget tests
- Bug log with GitHub issue numbers
- Coverage screenshot

### Part IV — Version Details

| Version | Date | Tag | What Changed |
|---------|------|-----|-------------|
| v0.1 | Week 4 end | v0.1 | Auth + reputation model |
| v0.2 | Week 6 end | v0.2 | Issue reporting + voice + AI with translation |
| v0.3 | Week 8 end | v0.3 | Map with heatmap + cluster |
| v0.4 | Week 10 end | v0.4 | Status tracking + reputation updates |
| v0.5 | Week 12 end | v0.5 | Dashboard + upvote + reputation UI |
| v0.9 | Week 14 end | v0.9 | Tests + bug fixes |
| v1.0 | Week 16 end | v1.0 | Final release |

---

## 43. Git Workflow

```bash
# Setup
git init
git remote add origin https://github.com/yourusername/community-issue-tracker.git
git branch -M main
git push -u origin main

# Daily
git add .
git commit -m "feat: add voice input mic button to report screen"
git push origin sprint-2

# Sprint end
git checkout main
git merge sprint-2
git tag v0.2
git push origin main --tags
```

**Commit message format:**
```
feat: add new feature
fix: fix a bug
test: add test cases
docs: update README
refactor: restructure without changing behaviour
chore: update packages
```

---

## 44. Environment Variables & Secrets

### `.env` (NEVER commit)
```
DJANGO_SECRET_KEY=your-long-random-secret-key
DEBUG=True
GEMINI_API_KEY=your-key-from-aistudio.google.com
GOOGLE_MAPS_API_KEY=your-key-from-console.cloud.google.com

# PostgreSQL (production only)
DB_NAME=community_issues_db
DB_USER=postgres
DB_PASSWORD=your-db-password
DB_HOST=localhost
DB_PORT=5432
```

### `.env.example` (commit this)
```
DJANGO_SECRET_KEY=
DEBUG=True
GEMINI_API_KEY=
GOOGLE_MAPS_API_KEY=
DB_NAME=
DB_USER=
DB_PASSWORD=
DB_HOST=localhost
DB_PORT=5432
```

### `.gitignore`
```
__pycache__/
*.pyc
.env
venv/
backend/media/
backend/db.sqlite3
mobile/.dart_tool/
mobile/build/
mobile/android/local.properties
mobile/android/key.properties
mobile/google-services.json
.vscode/
.idea/
.DS_Store
```

---

## 45. Common Errors & Fixes

| Error | Where | Cause | Fix |
|-------|-------|-------|-----|
| `CORS error` | Flutter → Django | CORS not set | Install `django-cors-headers`, add to MIDDLEWARE first |
| `401 Unauthorized` | API calls | Token missing/expired | Add `Authorization: Bearer <token>` header |
| `GPS returns 0,0` | Emulator | No real GPS | Extended Controls → Location → set fake coordinates |
| `Image not loading` | Flutter | Wrong media URL | Use `http://10.0.2.2:8000/media/` in emulator |
| `Pillow not installed` | Django | ImageField needs it | `pip install Pillow` |
| `Gemini returns non-JSON` | AI module | Model added markdown | Strip ``` fences before `json.loads()` |
| `speech_to_text not working` | Flutter | No RECORD_AUDIO permission | Add permission to AndroidManifest.xml + request at runtime |
| `speech_to_text returns empty` | Flutter | Emulator has no mic | Test on real device for voice input |
| `Cluster markers not grouping` | Flutter | Manager not updated | Call `_manager.setItems(issues)` after data loads |
| `Heatmap not showing` | Flutter | No WeightedLatLng | Check issues list is not empty before creating heatmap |
| `Reputation not updating` | Django | Signal not firing | Check `update_reputation()` is called in the view, not just the signal |
| `upvote_count not refreshing` | Django | Stale object | Call `issue.refresh_from_db()` after upvote save |
| `detected_language is null` | Django | AI failed | Default fallback returns `"en"` — always safe |
| `Flutter rebuild loop` | Flutter | Provider setState in build | Move API calls to `initState()` |
| `Cannot connect to Django` | Flutter | Wrong base URL | Emulator: `10.0.2.2:8000`, Real device: PC's LAN IP |
| `Migration error` | Django | Model changed | `python manage.py makemigrations && migrate` |

---

## 46. Free Tools Reference

| Tool | Purpose | URL | Notes |
|------|---------|-----|-------|
| Flutter SDK | Mobile frontend | flutter.dev | Install first |
| Android Studio | IDE + emulator | developer.android.com | Required for emulator |
| VS Code | Backend IDE | code.visualstudio.com | Lighter |
| Python 3.11+ | Backend language | python.org | Use venv |
| pgAdmin 4 | PostgreSQL GUI | pgadmin.org | Visual DB viewer |
| Postman | API testing | postman.com | Test all endpoints |
| Draw.io | ER diagrams | app.diagrams.net | No login needed |
| Figma | UI wireframes | figma.com | Free 3 projects |
| Overleaf | LaTeX report | overleaf.com | Required for report |
| GitHub | Code + bugs | github.com | Free public repos |
| aistudio.google.com | Gemini API key | aistudio.google.com | Free, no card |
| console.cloud.google.com | Maps API key | cloud.google.com | Free $200/month |
| console.firebase.google.com | Push notifications | firebase.google.com | Free tier |

---

## HOW TO USE THIS DOCUMENT WITH AI TOOLS

Upload this file to ChatGPT, Claude, Gemini, or GitHub Copilot and use prompts like:

```
"I am building the project described in this document.
Help me write the Django Issue model from Section 26."

"Build the Flutter ReportIssueScreen from Section 10
including the voice input mic button and AI analyse button."

"Write the complete ai_classifier.py from Section 17
with multilingual support."

"Write the MapScreen from Section 12 with all three
modes: Pin, Heatmap, and Cluster."

"Write the reputation.py file from Section 9 with all
the update_reputation logic."

"I am getting a CORS error. Based on this project, what is the fix?"
```

---

*End of Document — AI-Powered Community Issue Reporter & Tracker*
*MCA 3rd Semester Mini Project | Academic Year 2025–2026*
*Features: Voice-to-Text | Multilingual AI | Heatmap + Clustering | Reputation Score*