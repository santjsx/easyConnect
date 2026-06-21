# EasyConnect — Codebase Memory & Intelligence Map

EasyConnect is a specialized assistive telecommunications system engineered specifically for elderly, cognitively impaired, and illiterate individuals. It transforms a standard Android smartphone into a foolproof, voice-guided calling terminal, managed remotely by caregivers through a web dashboard.

---

## 1. Project Overview
EasyConnect consists of two primary components:
1. **Flutter Mobile Application**: Replaces the native Android dialer interface. It runs as a fullscreen launcher with simplified touch targets, offline-first operation, continuous local text-to-speech (TTS) voice guidance in regional Indian languages (Telugu, Hindi, English), and native telephony hooks (kiosk mode, direct calling, and call overlay interception).
2. **Web Caregiver Dashboard**: A lightweight single-page application (SPA) built with vanilla HTML, Tailwind CSS, and Firebase JS Web SDK v10. It allows caregivers to remotely manage contacts (photo, name, number, custom voice labeling) and configure medication/check-in alarms without needing physical access to the senior's phone.

---

## 2. Business Purpose
* **The Problem**: Standard smartphones are unusable for seniors suffering from vision deterioration, fine-motor decline, or cognitive disorders. Complex menu structures, small touch targets, system notifications, and sudden layout changes create friction and isolation.
* **The Solution**: EasyConnect eliminates navigation by displaying a high-contrast grid of large contact cards. An active voice guidance system (using regional accents) reads out names on hover or tap.
* **Caregiver Peace of Mind**: The system features bi-directional Firestore synchronization, continuous remote telemetry updates (battery, charging status, SIM card condition, signal strength, GPS coordinates), a wellness check-in system, and a remote "Find My Phone" alarm.

---

## 3. Tech Stack
### Mobile App
* **Core Framework**: Flutter (Dart)
* **Local Storage**: Hive (NoSQL database with TypeAdapters)
* **State Management**: Flutter Riverpod (ProviderContainer, state notifications)
* **Cloud Sync**: Firebase Core, Cloud Firestore (`cloud_firestore`)
* **Telephony & Dialer**: Android Native (`InCallService`, `TelecomManager`, `RoleManager`, custom MethodChannel bindings)
* **Text-to-Speech**: `flutter_tts` (system fallback) and Azure Speech Cognitive Services (for high-fidelity regional neural voice caching)
* **Audio Handling**: `record` (AAC voice messages recording), `audioplayers` (caching/playback)
* **Sensor Integration**: Accelerometer shake detection (via `SensorEventListener` in `MainActivity.kt`)

### Caregiver Dashboard
* **Structure**: HTML5, Vanilla JavaScript
* **Styling**: Tailwind CSS (CDN), Lucide Icons
* **Cloud Backend**: Google Firebase Firestore & Firebase Storage Web SDK (v10.8.0 modules)
* **Hosting**: Vercel

---

## 4. Repository Structure
```
EasyConnect/
├── android/                         # Android Native module (Dialer & telephony integrations)
│   └── app/src/main/
│       ├── AndroidManifest.xml      # Dialer, overlay, boot-receivers, SMS and location permissions
│       └── kotlin/com/easyconnect/app/
│           ├── MainActivity.kt      # MethodChannel handlers, shake detection, contact creator
│           ├── EasyConnectInCallService.kt   # System InCallService for telephonic hooks
│           └── EasyConnectKeepAliveService.kt # Wakes up Dart VM for call responsiveness
├── assets/                          # Static assets and regional translation dictionaries
├── firestore.rules                  # Strict security policies for Firestore CRUD
├── lib/                             # Flutter Mobile App Source Code
│   ├── core/                        # Design tokens, global themes, shared constants
│   │   ├── constants/               # Color definitions, layout configurations
│   │   └── theme/                   # Theme builders for accent colors
│   ├── features/                    # Modular feature directories
│   │   ├── alarm/                   # Medicine & wake-up reminder models
│   │   ├── calling/                 # Dialer screen, incoming overlay, WhatsApp/SIP services
│   │   ├── contacts/                # Contacts grid, local repository, reordering widgets
│   │   ├── settings/                # Passcode locked Admin Hub, settings screen
│   │   ├── sos/                     # Location dispatching, SMS intent routing, countdown dialogs
│   │   ├── voice_message/           # Audio message recording, native WhatsApp sending service
│   │   └── wellness/                # Inactivity monitoring timer and confirmation overlays
│   ├── screens/                     # Root screen layouts (HomeScreen, AlarmRingScreen)
│   ├── services/                    # Shared system services (Backup, TTS, Status, Firestore Sync)
│   └── main.dart                    # Startup initialization and global MethodChannel overlays
└── web_dashboard/                   # Caregiver web dashboard (Single Page Application)
    ├── index.html                   # Core dashboard layout and modular Firebase controllers
    ├── config.js                    # Firebase configuration variables
    └── privacy.html                 # Offline-first product privacy statement
```

---

## 5. System Architecture
```
┌────────────────────────────────────────────────────────────────────────┐
│                        CAREGIVER WEB DASHBOARD                         │
│                    (Vanilla JS, Tailwind, Firebase)                    │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │  Firebase Web SDK (v10)
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        GOOGLE FIRESTORE (CLOUD)                        │
│                   /families/{familyCode}/contacts                      │
│                   /families/{familyCode}/alarms                        │
│                   /families/{familyCode}/telemetry                     │
│                   /families/{familyCode}/commands                      │
└──────────────────────────────────▲─────────────────────────────────────┘
                                   │  Bi-directional snapshot sync
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        FLUTTER MOBILE SERVICE                          │
│        [FirebaseSyncService] ──(maps data)──> [Local Hive Database]     │
└──────────────────┬──────────────────────────────────────▲──────────────┘
                   │ MethodChannel                        │ MethodChannel
                   ▼ (telephony, audio, sensors)          │ (announcements, shake)
┌─────────────────────────────────────────────────────────┴──────────────┐
│                         ANDROID NATIVE LAYER                           │
│     [MainActivity.kt] [EasyConnectInCallService] [KeepAliveService]     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Routing Map
The app uses a custom layout wrapper and state machine rather than complex multi-page routing. Navigation details are cataloged in [routes.md](file:///c:/Users/heysa/Documents/Dev/EasyConnect/routes.md).

| Screen | File Path | Route Trigger | Auth Required |
| :--- | :--- | :--- | :--- |
| **Home (Contacts)** | [home_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/screens/home_screen.dart) | Initial App Root (`MaterialApp.home`) | None |
| **Incoming Call Overlay** | [incoming_call_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/calling/screens/incoming_call_screen.dart) | Stacked offstage wrapper in `SystemCallOverlayWrapper` | None |
| **Outgoing Dialer/Call Screen**| [calling_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/calling/screens/calling_screen.dart) | Pushed on top of stack via custom `PageRouteBuilder` | None |
| **Admin Pin Pad** | [admin_hub_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/settings/screens/admin_hub_screen.dart) | Admin Hub entry via Home Screen | Local Admin PIN |
| **Manage Contacts** | [manage_contacts_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/settings/screens/manage_contacts_screen.dart) | Pushed from Admin Hub | Local Admin PIN |
| **App Settings** | [app_settings_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/settings/screens/app_settings_screen.dart) | Pushed from Admin Hub | Local Admin PIN |
| **Alarm Ringing Overlay** | [alarm_ring_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/screens/alarm_ring_screen.dart) | Triggered by local alarms check loop | None |

---

## 7. Frontend Architecture (Mobile)
* **Root Overlay**: The `MaterialApp` builder wraps the active navigator child inside [SystemCallOverlayWrapper](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/main.dart#L201). This ensures that alarms, incoming call sheets, and shake actions trigger on top of any active screen (including during active dialogs or settings modifications).
* **Grid Layouts**: Supports `Classic` (dense grid with vertical lists) and `Modern` modes (large contact cards with custom status chips for telemetry, battery, and voice guide toggle).
* **Gesture Safeguards**: Contacts reordering is locked behind a toggle button. Cards must be long-pressed and dragged only when edit mode (`_isEditingGrid` = true) is active to prevent unintentional reordering by the user.

---

## 8. Backend Architecture
* **Cloud Layer**: Serviced entirely by **Google Firebase**.
* **Storage Optimization**: Because photos and custom voice labels are written directly into the Firestore contacts subcollection as Base64 strings, [firestore.rules](file:///c:/Users/heysa/Documents/Dev/EasyConnect/firestore.rules) enforces a strict payload size limit of `<350KB` on `photoUrl` and `voiceLabelUrl` to avoid hitting Firestore's maximum document capacity limit of 1MB.
* **Command Pipe**: A Firestore document listener `/families/{familyCode}/commands/find_phone` polls for trigger changes. A timestamp check ensures command intents are discarded if they are older than 5 minutes.

---

## 9. Database Architecture
Database details are mapped in [database-map.md](file:///c:/Users/heysa/Documents/Dev/EasyConnect/database-map.md).

### Local Storage (Hive NoSQL)
* **Contacts Box (`contacts`)**: Stores `Contact` model objects. Key fields: `id`, `name`, `phoneNumber`, `whatsappNumber`, `photoPath` (local storage path), `colorTheme` (Hex tag), `preferredAction`, `positionIndex`, `voiceLabelPath` (local audio path).
* **Settings Box (`settings`)**: Stores app configuration. Key fields: `language`, `voiceEnabled`, `sosContactId`, `adminPin`, `familySyncCode`, `isSyncEnabled`, `wellnessCheckEnabled`, `wellnessIntervalHours`, `azureSpeechSubscriptionKey` & Azure voices configuration.
* **Call Logs Box (`call_logs`)**: Stores `CallLog` history. Fields: `id`, `name`, `phoneNumber`, `type` (`missed`, `dialed`, `incoming`), `timestamp`.
* **Alarms Box (`alarms`)**: Stores daily or weekly reminder schedules. Fields: `id`, `time` (`HH:mm`), `label`, `days` (integer weekday index list), `isEnabled`, `lastUpdated`.

### Cloud Storage (Firestore Collections)
* `/families/{familyCode}/contacts/{contactId}` (bi-directional sync mapping to Hive)
* `/families/{familyCode}/alarms/{alarmId}` (bi-directional sync mapping to Hive)
* `/families/{familyCode}/telemetry/device` (unidirectional upload from phone)
* `/families/{familyCode}/commands/find_phone` (unidirectional download from web)

---

## 10. Authentication Flow
* **No Cloud Accounts**: To maximize accessibility and remove friction, the system does not require Google accounts or email verification.
* **Family Sync Code**: Caregivers bind their dashboard using a unique, URL-safe Family Sync Code (`^[a-z0-9_\-]+$`) generated in the app settings.
* **Admin PIN Guard**: Access to settings, contacts management, and dashboard syncing is locked behind a local PIN (stored in `settings.adminPin`). Biometric fingerprints are supported through local Android system APIs.

---

## 11. API Inventory
API mappings are fully detailed in [api-map.md](file:///c:/Users/heysa/Documents/Dev/EasyConnect/api-map.md).

### Platform Method Channels (`com.easyconnect.app/calling`)
* `makeDirectCall`: Places calls instantly via TelecomManager.
* `makeWhatsAppVideoCall`: Queries WhatsApp contacts database natively and initiates video calls.
* `createSystemContact`: Programmatically adds contacts to the system address book to force WhatsApp indexing.
* `shareAudioToWhatsApp`: Attaches recorded voice files directly to a WhatsApp recipient chat.
* `sendDirectSMS`: Sends background SMS messages during emergency wellness escalations.
* `startKioskMode` / `stopKioskMode`: Disables home and back keys to lock the app as the user's primary interface.
* `acceptSystemCall` / `hangUpSystemCall`: Handles ringing telecom calls.

### Third-Party Services
* **Azure Cognitive Speech Services API**: Generates neural TTS audio using region configurations, saving results as `.mp3` files inside `tts_cache/` for instant offline replay.

---

## 12. Telemetry Sync Flow
```
User Touches Device ─> Updates _lastInteractionTime (home_screen.dart)
                               │
                       Inactivity Check (Every 1 minute)
                               │
                       If Idle > Settings.wellnessIntervalHours & Time is 8 AM - 9 PM
                               │
                       Show Flashing WellnessCheckInDialog (5 mins countdown)
                               ├─────────────── answered ──────────────────> Dismiss & Reset Inactivity Timer
                               ▼ unanswered
                       Query GPS Coordinates via Geolocator
                               │
                       Generate SMS Message with Maps Link
                               │
                       Invoke Native Platform Method 'sendDirectSMS' to Caregivers
                               │
                       Speak Vocal Confirmation & Reset Inactivity Timer
```

---

## 13. Important Files
* [main.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/main.dart): App entry point containing `SystemCallOverlayWrapper` which coordinates incoming ringing overlay transitions, alarm loops, and background initializations.
* [firebase_sync_service.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/services/firebase_sync_service.dart): Manages real-time Firestore listeners, telemetry uploads, command listeners, and base64 decode isolates.
* [tts_service.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/services/tts_service.dart): Custom translation engine containing Telugu, Hindi, and English phonetics and Azure Cognitive cloud speech handlers.
* [MainActivity.kt](file:///c:/Users/heysa/Documents/Dev/EasyConnect/android/app/src/main/kotlin/com/easyconnect/app/MainActivity.kt): Native bridge implementing Direct Dialer, WhatsApp contacts queries, Direct SMS sending, Kiosk Mode execution, and accelerometer shake listeners.
* [EasyConnectInCallService.kt](file:///c:/Users/heysa/Documents/Dev/EasyConnect/android/app/src/main/kotlin/com/easyconnect/app/EasyConnectInCallService.kt): Custom `InCallService` capturing state machine events for incoming, dialing, and active calls.
* [index.html](file:///c:/Users/heysa/Documents/Dev/EasyConnect/web_dashboard/index.html): SPA dashboard managing caregiver UI rendering, audio recording/uploading, and real-time Firestore synchronization.

---

## 14. Performance Notes
* **Startup Speed**: Cold launches execute in under 200ms. Hive databases are opened with self-healing try/catch routines. TTS pre-warming is offloaded to a background microtask.
* **Frame Rate (60/120fps)**: Firestore sync parses Base64 strings. Because parsing heavy strings can freeze the UI thread, base64 encoding and decoding is processed using Flutter `compute` isolates.
* **Isolate Preservation**: A periodic 25-second keep-alive ping is sent to the Method Channel to prevent Android from freezing the Dart VM during idle states.

---

## 15. Known Risks & Technical Debt
* **Base64 Payload Size**: Base64 uploads to Firestore are bounded at <350KB. Large photos or longer audio recordings can lead to sync failures. Uploading directly to Firebase Storage using SAS tokens is a recommended upgrade.
* **WhatsApp Sync Latency**: When a contact is added via `createSystemContact`, WhatsApp takes 5-15 seconds to index it, causing initial call attempts to fail.
* **Direct SMS Cost**: Wellness check-in escalations send direct cellular SMS messages, which could incur carrier fees for the user.

---

## 16. Development Workflow
* Run locally: `flutter run`
* Build Release APK: `flutter build apk --release`
* Run Dashboard locally: Serve `web_dashboard` via standard local webserver (e.g. `npx http-server ./web_dashboard`).
* Deploy Dashboard: Handled automatically by Vercel Integration on repository commits.
