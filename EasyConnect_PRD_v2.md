# EasyConnect — Product Requirements Document
**Version:** 1.1  
**Status:** Draft  
**Platform:** Android  
**Last Updated:** May 2026

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [User Personas](#3-user-personas)
4. [Product Principles](#4-product-principles)
5. [MVP Feature Specifications](#5-mvp-feature-specifications)
6. [Non-Functional Requirements](#6-non-functional-requirements)
7. [Tech Stack](#7-tech-stack)
8. [Data Models](#8-data-models)
9. [Project Structure](#9-project-structure)
10. [MVP Development Phases](#10-mvp-development-phases)
11. [Permissions](#11-permissions)
12. [Open Questions & Risks](#12-open-questions--risks)
13. [Success Metrics](#13-success-metrics)
14. [Out of Scope (Post-MVP)](#14-out-of-scope-post-mvp)

---

## 1. Executive Summary

EasyConnect is an Android app that allows elderly, non-literate, or low-digital-literacy users to make calls, send voice messages, and video call family members — without reading a single word. Contacts are represented by large face photos. Every action is confirmed by a spoken voice prompt in the user's language.

The app is configured once by a family member (admin) and then handed to the primary user to operate independently.

---

## 2. Problem Statement

### Who is affected

Millions of elderly people in India cannot read text, struggle with standard smartphone UIs, and rely on family members to make basic calls for them. This creates:

- Loss of independence and dignity for the elderly person
- Constant interruptions for family members
- Missed communication during emergencies

### What currently fails

| Problem | Root Cause |
|---|---|
| Can't find the right contact | Contacts listed as text names, not faces |
| Accidentally presses wrong buttons | Touch targets too small |
| Doesn't know if call connected | No spoken feedback |
| Gets lost in menus | Too many screens and steps |
| Can't record a voice note | Requires reading and typing |

### What EasyConnect solves

A single-screen, face-first, voice-guided communication app where every action requires only one tap.

---

## 3. User Personas

### 3.1 Primary User — "Amma"

| Attribute | Detail |
|---|---|
| Age | 65–80 |
| Literacy | Non-literate or low-literate in English |
| Language | Telugu, Hindi, or regional language |
| Phone experience | Can answer calls; struggles to initiate them |
| Vision | May need large text and high contrast |
| Motor skills | Slower; benefits from large touch targets |
| Goal | Call family independently without asking for help |

**Key insight:** Amma recognises faces instantly but cannot read "Santhosh" or "Priya" in a contact list.

---

### 3.2 Secondary User — Family Admin

| Attribute | Detail |
|---|---|
| Age | 25–45 |
| Literacy | Fluent in English |
| Phone experience | Comfortable with smartphones |
| Relationship | Son, daughter, or caregiver |
| Goal | Set up the app once; update it remotely or in person |
| Pain point | Tired of being called just to make a call for a parent |

**Key insight:** The admin sets up EasyConnect once. After that, they should almost never need to touch it.

---

## 4. Product Principles

These principles are non-negotiable. Any feature that violates them must be redesigned.

| # | Principle | What it means in practice |
|---|---|---|
| P1 | **No typing** | The primary user never sees a keyboard |
| P2 | **Face-first navigation** | Photos are the primary UI element, not names |
| P3 | **One-screen experience** | All contacts visible on a single screen; no navigation required |
| P4 | **Fixed layout** | Contacts never reorder automatically; positions are set by the admin |
| P5 | **Voice-guided UX** | Every action triggers spoken confirmation in the user's language |
| P6 | **Forgiveness** | No action is irreversible without a spoken warning and confirmation |

---

## 5. MVP Feature Specifications

---

### 5.1 Home Screen

#### Layout
- Single scrollable grid (2 columns on phones, 3 on tablets)
- No hamburger menus, tabs, or bottom navigation bars
- SOS button pinned to the bottom of the screen at all times
- Admin access icon in top-right corner (small, non-intrusive)

#### Contact Card
Each card contains:

| Element | Specification |
|---|---|
| Photo | Full-width circular crop, minimum 120×120dp |
| Name label | Large font (18sp+), below photo, single line |
| Audio call button | Green, phone icon, minimum 64×64dp |
| Video call button | Blue, video icon, minimum 64×64dp |
| Voice message button | Orange, microphone icon, minimum 64×64dp |

#### Empty State
If no contacts exist, show a full-screen prompt saying: *"Ask your family member to add contacts."* No other UI elements.

---

### 5.2 Audio Call

#### User Flow
1. User taps the green call button on a contact card
2. Device vibrates (haptic feedback)
3. App speaks: *"Calling [Name]"* in the configured language
4. Native Android phone dialer opens and begins the call

#### Acceptance Criteria
- Call is initiated within 500ms of button tap
- Voice prompt plays before the dialer opens
- Works without internet
- Falls back gracefully if CALL_PHONE permission is denied (see Section 11)

#### Error States
| Scenario | Behaviour |
|---|---|
| No SIM card | Spoken: *"No SIM card found. Cannot make call."* |
| Permission denied | Spoken: *"Call permission not allowed. Ask your family to fix this."* |
| Invalid phone number | Spoken: *"This contact has no phone number saved."* |

#### Technical Notes
- Use `url_launcher` with `tel:` intent
- No custom VoIP required for MVP

---

### 5.3 WhatsApp Video Call

#### User Flow
1. User taps the blue video icon on a contact card
2. Device vibrates
3. App speaks: *"Starting video call with [Name]"*
4. WhatsApp opens directly on the video call screen for that contact

#### Acceptance Criteria
- Launches directly to WhatsApp video call (not WhatsApp home screen)
- Works if WhatsApp is installed

#### Error States
| Scenario | Behaviour |
|---|---|
| WhatsApp not installed | Spoken: *"WhatsApp is not installed."* → Show button to open Play Store |
| Contact has no WhatsApp number | Spoken: *"No WhatsApp number saved for [Name]."* |
| WhatsApp intent fails | Spoken: *"Could not open WhatsApp. Please try again."* |

#### Technical Notes
- Use WhatsApp deep link: `https://wa.me/[number]`
- Fall back to `intent://` if deep link fails
- WhatsApp number may differ from regular phone number; store separately

---

### 5.4 Voice Message

#### User Flow
1. User taps the orange microphone button on a contact card
2. App speaks: *"Recording message for [Name]. Tap stop when done."*
3. Recording begins immediately (no intermediate screen)
4. A large, pulsing red STOP button appears, covering the lower half of the screen
5. User taps stop
6. App plays back the recording and speaks: *"Message recorded. Tap send or delete."*
7. Two large buttons appear: Send (green) and Delete (red)
8. Tapping Send opens WhatsApp sharing flow with the audio file pre-loaded

#### Acceptance Criteria
- Recording starts within 200ms of button tap
- Playback available before sending
- User can delete and re-record
- Audio file shared as `.m4a` or `.ogg` (WhatsApp compatible)
- Recording is auto-deleted after successful send or explicit delete

#### Error States
| Scenario | Behaviour |
|---|---|
| Microphone permission denied | Spoken: *"Microphone not allowed. Ask your family to fix this."* |
| No WhatsApp installed | Spoken: *"WhatsApp is not installed. Cannot send message."* |
| Recording too short (<1s) | Spoken: *"Message too short. Please try again."* |
| Storage full | Spoken: *"Not enough space on the phone. Please free up space."* |

#### Technical Notes
- Use `record` package
- Target format: `m4a` (compatible with WhatsApp)
- Temp files stored in app cache directory; cleared on send/delete

---

### 5.5 Voice Guidance System

#### Supported Languages
- Telugu (`te-IN`)
- Hindi (`hi-IN`)
- English (`en-IN`)

Language is set by the admin and applies to all voice prompts globally.

#### Voice Prompt Catalogue

| Event | Telugu | Hindi | English |
|---|---|---|---|
| Calling started | *"[Name] కి కాల్ చేస్తున్నారు"* | *"[Name] को कॉल किया जा रहा है"* | *"Calling [Name]"* |
| Video call starting | *"[Name] తో వీడియో కాల్"* | *"[Name] को वीडियो कॉल"* | *"Starting video call with [Name]"* |
| Recording started | *"రికార్డ్ అవుతోంది"* | *"रिकॉर्डिंग शुरू"* | *"Recording started"* |
| Message sent | *"మెసేజ్ పంపబడింది"* | *"संदेश भेजा गया"* | *"Message sent"* |
| No internet | *"ఇంటర్నెట్ లేదు"* | *"इंटरनेट नहीं है"* | *"No internet connection"* |
| WhatsApp missing | *"WhatsApp లేదు"* | *"WhatsApp नहीं है"* | *"WhatsApp is not installed"* |
| Battery low | *"బ్యాటరీ తక్కువగా ఉంది"* | *"बैटरी कम है"* | *"Battery is low"* |
| SOS triggered | *"అత్యవసర కాల్ చేస్తున్నారు"* | *"आपातकालीन कॉल की जा रही है"* | *"Calling emergency contact"* |

#### Technical Notes
- Use `flutter_tts` package (wraps Android TTS)
- Ensure TTS language pack is downloaded on first launch
- If TTS fails silently (no language pack), fall back to English
- All prompts are pre-defined strings; no dynamic TTS generation from user input

---

### 5.6 Contact Management (Admin Mode)

#### Access Control
Admin mode is protected by either:
- A 4-digit PIN, or
- Device fingerprint (if available)

PIN is set on first app launch. If the admin forgets the PIN, recovery requires uninstalling and reinstalling the app. This is intentional — the primary user must not be able to accidentally enter admin mode.

#### Admin Actions

| Action | Description |
|---|---|
| Add contact | Name, phone number, optional WhatsApp number, photo |
| Edit contact | Modify any field of an existing contact |
| Delete contact | Remove a contact (with spoken confirmation prompt) |
| Reorder contacts | Drag-and-drop to set grid position |
| Update photo | Replace photo via camera or gallery |
| Set preferred action | Choose default action (call/video/message) for long-press |
| Set contact colour | Optional colour label for card border |

#### Validation Rules
- Name: required, max 30 characters
- Phone number: required, valid Indian or international format
- WhatsApp number: optional; if absent, video and message buttons are disabled for that contact
- Photo: required; a placeholder silhouette is shown until one is added

---

### 5.7 Photo Management

#### Capture Methods
- Camera (live capture)
- Gallery (import from photos)

#### Processing
1. Image is cropped to a square
2. Face is auto-detected and centred (using ML Kit Face Detection if available; manual crop fallback)
3. Image is resized to 300×300px and stored locally as JPEG (quality 85)

#### Acceptance Criteria
- All contact photos must look visually consistent (same size and shape)
- Photos persist across app updates
- Photos are included in CSV/JSON export (as base64 or relative path)

---

### 5.8 CSV Import

#### Purpose
Allow the admin to bulk-add contacts from a spreadsheet — useful when setting up the app for the first time with many family members.

#### CSV Schema

```
name,phone,whatsapp,photo_path
Santhosh,+919876543210,+919876543210,/storage/photos/santosh.jpg
Amma,+919123456789,,
```

| Column | Required | Notes |
|---|---|---|
| `name` | Yes | Display name, max 30 characters |
| `phone` | Yes | Used for audio calls |
| `whatsapp` | No | Used for video calls and voice messages |
| `photo_path` | No | Absolute path on device or relative to CSV location |

#### Import Flow
1. Admin selects a CSV file
2. App parses and previews all rows in a table
3. Validation errors are highlighted per row (not blocking — admin can skip invalid rows)
4. Admin taps "Import" to confirm
5. App imports valid rows; reports a summary (e.g., "8 contacts imported, 2 skipped")

#### Validation Rules
- Duplicate phone numbers: warn, ask whether to skip or overwrite
- Missing name: row is skipped
- Invalid phone format: row is flagged; admin can edit inline before importing
- Missing photo: contact is imported with placeholder photo

---

### 5.9 CSV / JSON Export

#### Export Scope
All contact data including:
- Name, phone, WhatsApp number
- Grid position index
- Photo (as base64 string in JSON; as file path in CSV)
- Preferred action setting
- App settings (language, voice enabled, SOS contact)

#### Formats
- **CSV** — for editing in Excel or Sheets
- **JSON** — for full backup and restore (includes settings and photo data)

#### Use Cases
- Backup before phone reset
- Transfer contacts to a new phone
- Edit bulk contacts on a computer

---

### 5.10 SOS Button

#### Appearance
- Always visible, pinned to the bottom of the home screen
- Red background, large emergency icon
- Label: *"Emergency"* (or equivalent in the selected language)

#### Behaviour
1. User taps SOS button
2. App shows a 3-second countdown with spoken warning: *"Calling emergency contact in 3… 2… 1…"*
3. User can cancel during countdown by tapping anywhere outside the button
4. After countdown, app calls the designated emergency contact using the native dialer
5. Optionally, if location permission is granted, app sends a pre-formatted WhatsApp message with the user's last known GPS location

#### Admin Configuration
- SOS contact is set in admin settings
- Location sharing is opt-in
- If no SOS contact is set, button shows a message: *"Emergency contact not set. Ask your family to set this up."*

---

## 6. Non-Functional Requirements

### 6.1 Accessibility

| Requirement | Specification |
|---|---|
| Minimum touch target | 64×64dp for all interactive elements |
| Font size | Minimum 16sp; contact names at 18sp+ |
| Colour contrast | WCAG AA compliant (4.5:1 ratio minimum) |
| Animations | None by default; respect system reduce-motion setting |
| Layout | Fixed and predictable; no dynamic reordering |
| Screen reader | Core actions must be accessible via TalkBack |

### 6.2 Performance

| Metric | Target |
|---|---|
| Cold app launch | < 2 seconds |
| Button response (haptic + audio) | < 100ms |
| Contact grid render (20 contacts) | < 500ms |
| Photo load per card | < 200ms (from local storage) |

### 6.3 Offline Support

| Feature | Requires Internet? |
|---|---|
| Audio calls | No |
| Contact grid | No |
| Voice prompts (TTS) | No (after first launch) |
| WhatsApp video call | Yes |
| Voice message send | Yes (WhatsApp) |
| SOS call | No |
| SOS location share | Yes |

### 6.4 Device Support

- Minimum Android version: Android 8.0 (API 26)
- Target Android version: Android 14 (API 34)
- Screen sizes: 5" to 7" phones; basic tablet support (3-column grid)
- RAM: Works on 2GB RAM devices

### 6.5 Storage

- App size: < 30MB installed
- Contact data: < 5MB for 50 contacts with photos
- Temporary audio files: auto-deleted after send; max 10MB retained at any time

---

## 7. Tech Stack

All packages are free and open source.

### Frontend

| Technology | Package / Tool | Reason |
|---|---|---|
| Framework | Flutter (stable channel) | Cross-platform Android support, fast development, accessibility APIs |
| State management | Riverpod | Scalable, testable, compile-safe |
| Routing | GoRouter | Declarative; minimal for this app (2 routes: home + admin) |

### Local Storage

| Technology | Package | Reason |
|---|---|---|
| Database | Hive | Lightweight, offline-first, no SQL setup |
| Fallback | SQLite (via `sqflite`) | If Hive causes issues on older devices |

### Device Features

| Feature | Package |
|---|---|
| Image picker | `image_picker` |
| Image cropping | `image_cropper` |
| Text-to-speech | `flutter_tts` |
| Audio recording | `record` |
| Permissions | `permission_handler` |
| URL / intent launch | `url_launcher` |
| CSV parsing | `csv` |
| JSON serialisation | `dart:convert` (built-in) |

### Integrations

| Integration | Method |
|---|---|
| Native phone call | `url_launcher` with `tel:` URI |
| WhatsApp video call | WhatsApp deep link (`https://wa.me/`) + intent fallback |
| WhatsApp voice message | `share_plus` with audio file |
| Face detection (photo crop) | `google_mlkit_face_detection` (optional; degrade gracefully) |

### Localisation

| Technology | Package |
|---|---|
| i18n | `flutter_intl` |
| Languages | Telugu (`te`), Hindi (`hi`), English (`en`) |

---

## 8. Data Models

### Contact

```dart
class Contact {
  final String id;               // UUID
  final String name;             // Display name
  final String phoneNumber;      // For audio calls
  final String? whatsappNumber;  // For WhatsApp calls/messages (may differ)
  final String? photoPath;       // Absolute path to local image file
  final String colorTheme;       // Hex color for card border (optional)
  final String preferredAction;  // 'call' | 'video' | 'message'
  final int positionIndex;       // Grid position (admin-set; never auto-sorted)
  final String? voiceLabelPath;  // Optional custom voice label audio
}
```

### Settings

```dart
class AppSettings {
  final String language;       // 'te' | 'hi' | 'en'
  final bool voiceEnabled;     // Master toggle for TTS
  final String? sosContactId;  // Reference to Contact.id
  final bool sosLocationShare; // Whether to send location on SOS
  final String adminPin;       // 4-digit hashed PIN
  final bool fingerprintEnabled;
}
```

---

## 9. Project Structure

```
lib/
├── core/
│   ├── constants/          # colours, dimensions, strings
│   ├── theme/              # app theme, text styles
│   └── utils/              # validators, phone formatters
├── features/
│   ├── contacts/
│   │   ├── models/
│   │   ├── repositories/
│   │   ├── providers/
│   │   └── widgets/        # ContactCard, ContactGrid
│   ├── calling/
│   │   ├── services/       # AudioCallService, VideoCallService
│   │   └── providers/
│   ├── voice_message/
│   │   ├── services/       # RecordingService, ShareService
│   │   └── providers/
│   ├── settings/
│   │   ├── models/
│   │   ├── repositories/
│   │   └── screens/        # AdminScreen, PinEntryScreen
│   └── sos/
│       └── services/       # SosService, LocationService
├── services/
│   ├── tts_service.dart    # Voice guidance system
│   ├── storage_service.dart
│   └── csv_service.dart
├── screens/
│   ├── home_screen.dart
│   └── admin_screen.dart
└── main.dart
```

---

## 10. MVP Development Phases

| Phase | Deliverable | Done When |
|---|---|---|
| 1 | Static UI | Home screen renders with hardcoded contacts; all buttons visible |
| 2 | Audio calling | Tapping call button initiates native call with voice prompt |
| 3 | WhatsApp video calling | Tapping video button opens WhatsApp call; error states handled |
| 4 | Voice recording & send | Record, playback, send via WhatsApp; delete and re-record |
| 5 | CSV import / export | Bulk import works; full backup export works |
| 6 | Voice guidance system | All prompts working in all 3 languages |
| 7 | Admin mode | PIN-protected contact management with all CRUD operations |
| 8 | SOS button | Emergency call + optional location message |
| 9 | User testing | Tested with 3+ elderly users; failure rate < 1 unassisted error per session |

---

## 11. Permissions

| Permission | When Requested | Why |
|---|---|---|
| `CALL_PHONE` | First call attempt | Make phone calls |
| `RECORD_AUDIO` | First voice message | Record audio messages |
| `READ_EXTERNAL_STORAGE` | First photo import | Import contact photos from gallery |
| `CAMERA` | First photo capture | Take contact photos |
| `ACCESS_FINE_LOCATION` | SOS setup (optional) | Send location in SOS message |
| `READ_CONTACTS` | Never | Not required; contacts are stored in-app |

### Permission Denial Handling
- If a critical permission is denied, a spoken prompt explains the issue in the user's language
- A helper screen (admin-visible) explains how to re-enable permissions in Android settings
- The app never crashes on permission denial

---

## 12. Open Questions & Risks

### Open Questions

| # | Question | Owner | Priority |
|---|---|---|---|
| OQ-1 | Should admins be able to manage contacts remotely (e.g., via a web interface)? | Product | Post-MVP |
| OQ-2 | Should the app support non-Indian phone number formats? | Engineering | Pre-launch |
| OQ-3 | What happens if WhatsApp changes its deep link API? | Engineering | Pre-launch |
| OQ-4 | Should voice prompts be pre-recorded audio files (higher quality) or TTS (more flexible)? | Design | Phase 6 |
| OQ-5 | Is there a need for a "simple mode" lock that prevents the primary user from accidentally opening admin mode? | UX | Phase 7 |

### Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| WhatsApp deep links are deprecated | Medium | High | Monitor WhatsApp API; build fallback to standard WhatsApp number share |
| Android TTS language packs not installed | Medium | High | Prompt download on first launch; fall back to English |
| Face detection fails on older devices | High | Low | Manual crop is the default; ML Kit is optional enhancement |
| Elderly users find 64dp targets still too small | Medium | High | Pilot test in Phase 7; increase to 80dp if needed |
| Admin forgets PIN | Medium | Medium | Document clearly that reinstall is the recovery path; consider optional security question |

---

## 13. Success Metrics

### Primary Success Criteria (MVP)

The MVP is successful if an elderly user with no prior training can:
1. Identify and call a family member independently
2. Record and send a voice message independently
3. Trigger the SOS button in under 5 seconds

### Quantitative Targets (Phase 7 Testing)

| Metric | Target |
|---|---|
| Task completion rate (unaided call) | > 90% |
| Average time to place a call | < 10 seconds from app open |
| "What do I press?" incidents per session | 0 |
| App crashes per 100 sessions | < 1 |
| User confidence rating (1–5) | ≥ 4.0 |

### Failure Condition

If a user asks *"What do I press now?"* more than once per session during usability testing, the UX has failed and must be redesigned before launch.

---

## 14. Out of Scope (Post-MVP)

The following features are explicitly excluded from v1.0. Do not build, stub, or scaffold these.

| Feature | Reason deferred |
|---|---|
| Launcher / kiosk mode | Requires Android admin permissions; complex setup |
| Spam call protection | Requires telephony integration |
| Medicine reminders | Separate product domain |
| Remote admin dashboard | Requires backend infrastructure |
| AI voice assistant | Scope and cost risk |
| Simplified Android shell | Requires device-level access |
| Group calls | Complexity; unclear user need for this persona |
| Dark mode | Low-vision users benefit from high-contrast light mode; revisit post-testing |

---

## Appendix A — UX Anti-Patterns (Never Do)

| Anti-Pattern | Why It Fails for This User |
|---|---|
| Swipe gestures | Unlearnable without reading instructions |
| Hidden menus / hamburgers | Invisible to users who don't know to look |
| Floating action buttons | Position is non-obvious; easily missed |
| Confirm dialogs with text | Requires reading |
| Auto-sorted contact lists | Destroys the user's mental map |
| Small icons (< 48dp) | Motor difficulty; visual difficulty |
| Animations > 200ms | Confusing; can look like a freeze |
| Multiple navigation levels | User cannot navigate back reliably |

---

## Appendix B — UX Best Practices (Always Do)

| Practice | Implementation |
|---|---|
| Spoken feedback | Every tap triggers TTS confirmation |
| Haptic feedback | Every tap triggers device vibration |
| Giant buttons | Minimum 64×64dp; prefer 80×80dp |
| Fixed positions | Admin sets grid positions; they never change |
| Large photos | Minimum 120×120dp display size |
| High contrast | Dark text on light background; avoid grey-on-grey |
| Clear colours | Green = call, Blue = video, Orange = message, Red = stop/SOS |
| Consistent iconography | Same icon always means the same action across all cards |

---

*End of Document*
