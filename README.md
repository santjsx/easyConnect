# EasyConnect

EasyConnect is a specialized Android application and caregiver administration dashboard designed to bridge the digital divide for elderly, non-literate, or low-literacy users. By replacing complex mobile interfaces with a simplified, face-first layout and comprehensive Text-to-Speech (TTS) voice guidance, the application empowers users to independently make phone calls, launch WhatsApp video calls, and record/send voice messages without needing to read or write.

The application acts as the device's default dialer, intercepting native telephony events to present senior-friendly overlays. It syncs in real-time with a cloud Firestore database managed by caregivers via the Web Admin Dashboard.

---

## Product Principles

The user experience is guided by the following core design principles:
- **No Typing Required**: The primary user interface contains absolutely no keyboards or text inputs.
- **Face-First Layout**: Contacts are represented visually by prominent photos rather than text labels.
- **Single-Screen Navigation**: All primary contact entries are accessible directly from a single, main grid screen.
- **Permanent Grid Order**: The order and grid position of contacts are fixed by the administrator to preserve the user's spatial memory.
- **Multilingual Voice Guidance**: All touch inputs, alerts, and system actions trigger spoken confirmation in the user's regional language.
- **Action Confirmation**: Important actions (like calls or emergency triggers) require clear, step-by-step confirmation prompts or cancellation options to prevent accidental triggers.

---

## Key Features

### 1. Primary Home Grid & Custom Layouts
- **Premium Squircle Avatars**: Profile photos are displayed inside mathematically smooth continuous-corner squircle borders that resist shape distortion across different device screen widths.
- **Two Layout Options**:
  - **Classic Mode**: A high-density 4-column display tailored for low-literacy users, featuring a simple floating dialer toggle.
  - **Modern Mode**: A spacious 2-3 column display with an integrated caregiver action drawer and custom floating navigation bar.
- **Haptic Feedback**: High-intensity vibration cues paired with all touch gestures.

### 2. Missed Call Pulsing Notifications
- **Breathing Pulse Indicator**: Contact cards with unread missed calls feature an animated glowing red card border and shadow.
- **Visual Status Badges**: Displays a missed call icon on the corner of the avatar.
- **Double-Tap Guidance**: Displays a high-visibility "TAP AGAIN" label for photoless contact cards, indicating to the user to callback.

### 3. Integrated Keypad Dialer & Call Logs
- **Simplified Dialer Keypad**: A clean tab featuring extra-large digits, spoken number inputs, and an instant-call button.
- **Interactive Call Logs**: A dedicated log screen displaying caller details, call type status badges (Incoming, Outgoing, Missed), and quick call-back actions.

### 4. Guided Telemetry & SIM Status Checks
- **SIM Card Health Alerts**: Spoken voice alerts are triggered instantly if the SIM state changes (absent, locked by PIN/PUK, hardware error, or disconnected) with localized troubleshooting guidelines.
- **Smart Battery Level Alerts**: Audibly warns the user when their battery level hits critical thresholds (**20%**, **10%**, and **5%**). 
- **Interrupt Prevention**: Automatically queues telemetry voice warnings if a call is active, delivering the message only after the call ends.
- **Charger Prompts**: Confirms charging connection audibly (silenced during system boot to prevent noise).

### 5. Emergency SOS GPS Dispatcher
- **Audible 3-Second Countdown**: Prominent red SOS button triggers a full-screen `3... 2... 1...` spoken countdown that can be canceled by tapping anywhere outside.
- **Call Auto-Rejection**: Automatically hangs up any incoming calls during the countdown to prevent interruption.
- **Dual Location Dispatch**: Directly dials the primary caregiver and simultaneously dispatches GPS coordinates via SMS (containing a Google Maps link) to up to two distinct fallback contacts.

### 6. Caregiver Management & Import Tools
- **Address Book Integration**: Allows caregivers to import contacts directly from the device's native address book using an interactive search-and-select directory dialog.
- **CSV Bulk Import**: Upload spreadsheet contact entries (`name,phone,whatsapp,photo_path`) with automatic fields validation.
- **Simulation Suite**: Allows caregivers to simulate incoming and outgoing call states to train and onboard senior users offline.

### 7. Backup, Recovery & Self-Healing
- **Path-Independent ZIP Backup**: Packages app settings, contacts, photos, and custom audio recordings into a single archive, translating absolute filesystem paths to relative mappings to ensure reliable restoration on any destination phone.
- **Self-Healing Color Themes**: Scans contacts on startup and auto-resolves color theme collisions using a mathematically distinct HSL golden ratio distribution.
- **Biometric Lock**: Restricts configuration pages with a 4-digit PIN or local device biometric authentication.

---

## Tech Stack

The application is built on a modern, robust, and open-source mobile stack:
- **Framework**: Flutter (Stable Channel managed via `puro`)
- **State Management**: Riverpod
- **Local Database**: Hive (with SQLite fallback support)
- **Image Cropper**: Image Picker and Image Cropper
- **Voice Engine**: Android Text-to-Speech via Flutter TTS
- **Audio Capture**: Record package
- **System Intents**: URL Launcher and Share Plus

---

## Project Structure

```text
lib/
├── core/
│   ├── constants/          # Application colors, dimensions, and standard strings
│   ├── theme/              # Typography styles, visual design system
│   └── utils/              # Data validation and phone number formatters
├── features/
│   ├── contacts/           # Contact models, providers, database CRUD, and grid widgets
│   ├── calling/            # Native voice and WhatsApp video call managers
│   ├── voice_message/      # Audio recording state and WhatsApp document sharing services
│   ├── settings/           # App settings models, providers, and administration screens
│   └── sos/                # Emergency countdown, call, and location-sharing workflows
├── services/
│   ├── tts_service.dart    # TTS speech synthesis controller
│   ├── storage_service.dart# Abstract database wrapper for local storage
│   └── csv_service.dart    # CSV import and export compiler
├── screens/
│   ├── home_screen.dart    # Main face-grid page with SOS footer
│   └── admin_screen.dart   # Protected settings and contact editing page
└── main.dart               # App entrypoint, database initialization, and provider tree
```

---

## Getting Started

### Prerequisites
- Flutter SDK (stable channel, version 3.19+ recommended, managed via `puro`)
- Android SDK (API level 26 minimum, API level 34 targeted)
- A physical Android device or emulator with Google Play Services (required for Text-to-Speech engines)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/santjsx/easyConnect.git
   cd EasyConnect
   ```

2. Retrieve project dependencies:
   ```bash
   puro flutter pub get
   ```

3. Run the code generation tool:
   ```bash
   puro flutter pub run build_runner build --delete-conflicting-outputs
   ```

4. Launch the application:
   ```bash
   puro flutter run
   ```

5. Assemble the release build APK:
   ```bash
   puro flutter build apk --release
   ```

---

## Configuration and Permissions

The application requests the following Android permissions:
- `CALL_PHONE`: For initiating standard telephone calls.
- `RECORD_AUDIO`: For capturing voice recordings for messages.
- `CAMERA` and `READ_MEDIA_IMAGES` (or `READ_EXTERNAL_STORAGE`): For selecting and cropping contact photos.
- `ACCESS_FINE_LOCATION`: For retrieving GPS coordinates for emergency SOS notifications.
- `SEND_SMS`: For dispatching emergency GPS coordinates to backup contacts.

All permissions are accompanied by spoken instructions in the selected regional language if denied, ensuring the user is never stranded on a blank or broken page.
