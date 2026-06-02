# EasyConnect

EasyConnect is a specialized Android application designed to bridge the digital divide for elderly, non-literate, or low-literacy users. By replacing complex mobile interfaces with a simplified, face-first layout and comprehensive Text-to-Speech (TTS) voice guidance, the application empowers users to independently make phone calls, launch WhatsApp video calls, and record and send voice messages.

The application is designed to be configured once by a family member or caregiver (acting as the administrator) and subsequently handed over to the primary user for independent, routine use.

## Product Principles

The user experience is guided by the following design principles:
- No Typing Required: The primary user interface contains no keyboards or text inputs.
- Face-First Layout: Contacts are represented visually by prominent photos rather than text labels.
- Single-Screen Navigation: All primary contact entries are accessible directly from a single main screen.
- Permanent Grid Order: The order and grid position of contacts are fixed by the administrator to preserve the user's spatial memory.
- Multilingual Voice Guidance: All touch inputs and system actions trigger spoken confirmation in the user's chosen language.
- Action Confirmation: Important actions require clear, step-by-step confirmation prompts to prevent accidental calls or deletions.

## Key Features

### Primary Home Grid
- A simple, single scrollable grid displaying contacts as large, high-contrast face cards.
- Clean color-coded circular action borders to visually separate contacts.
- Quick action triggers for calling, WhatsApp video calls, and voice messages.
- Clean visual design with high-contrast text and layout elements.

### Guided Audio and Video Calling
- Standard phone call initiation using native system intents.
- Direct-to-video-call deep links targeting WhatsApp, bypassing search menus.
- Immediate haptic vibration and spoken audio cues (e.g., "Calling Santhosh") prior to launching the call.

### Guided Voice Messaging
- Simple audio recording triggered by the contact's microphone button.
- Clean overlay with a large, high-visibility "Stop" button.
- Voice playback options allowing the user to listen to the recorded message before sending.
- One-tap "Send" or "Delete" actions to dispatch the recording via WhatsApp or discard it locally.

### SOS Emergency Operations
- A prominent red emergency button pinned to the bottom of the home screen.
- A 3-second spoken countdown allowing the user to cancel accidental triggers.
- Automatic calling of the designated emergency contact.
- Optional integration with GPS location services to send the user's current location via a structured SMS/WhatsApp message.

### Protected Administrator Dashboard
- Secured by a 4-digit PIN or local device biometric authentication.
- Full CRUD operations for contact entry management (Name, Phone Number, WhatsApp Number, and Photo).
- Drag-and-drop reordering interface to adjust layout placement.
- Local configuration settings (default TTS language selection, emergency contact binding, and location sharing preferences).
- Data backup and recovery via CSV or JSON file import/export.

## Tech Stack

The application is built on a modern, robust, and open-source mobile stack:
- Framework: Flutter (Stable Channel)
- State Management: Riverpod
- Routing: GoRouter
- Local Database: Hive (with SQLite fallback)
- Image Capture: Image Picker and Image Cropper
- Voice Engine: Android Text-to-Speech via Flutter TTS
- Audio Capture: Record package
- System Intents: URL Launcher and Share Plus

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

## Getting Started

### Prerequisites

- Flutter SDK (latest stable channel version)
- Android SDK (API level 26 minimum, API level 34 targeted)
- A physical Android device or emulator with Google Play Services (required for Text-to-Speech engines)

### Installation

1. Clone the repository to your local system:
   ```bash
   git clone https://github.com/santjsx/easyConnect.git
   cd EasyConnect
   ```

2. Retrieve project dependencies:
   ```bash
   flutter pub get
   ```

3. Run the code generation tool to build model serializers:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. Launch the application in development mode:
   ```bash
   flutter run
   ```

5. Assemble the release build APK:
   ```bash
   flutter build apk --release
   ```

## Configuration and Permissions

The application requests the following Android permissions to function properly:
- `CALL_PHONE`: Initiating standard telephone calls.
- `RECORD_AUDIO`: Capturing voice recordings for messages.
- `CAMERA` and `READ_EXTERNAL_STORAGE` (up to API 32) / `READ_MEDIA_IMAGES` (API 33+): Selecting and cropping contact photos.
- `ACCESS_FINE_LOCATION`: Retrieving GPS coordinates for emergency SOS notifications.

All permission requests are accompanied by local spoken explanations in the selected language if denied, ensuring the user is never stranded on a blank or broken state.

## CSV Import Format

For quick administration setup, contacts can be imported in bulk using a CSV file. The file must use the following schema:

```csv
name,phone,whatsapp,photo_path
Santhosh,+919876543210,+919876543210,/storage/emulated/0/Pictures/santhosh.jpg
Amma,+919123456789,,
```

### Schema Details
- `name`: Text string representing the contact name (maximum 30 characters). Required.
- `phone`: Standard phone number format used for voice calls. Required.
- `whatsapp`: Designated WhatsApp phone number. Optional. (If blank, video calling and voice messaging buttons are automatically hidden).
- `photo_path`: The absolute file path to the contact's photograph stored on the local device. Optional.

## Accessibility Specifications

- Spacing and Touch Targets: Interactive components conform to a minimum target size of 64x64 dp, with standard button layouts optimized for 80x80 dp.
- Color Contrast: Typography and background colors conform to WCAG AA guidelines with a minimum contrast ratio of 4.5:1.
- Offline Capability: The application functions without internet access for audio dialing, local contact editing, SOS calling, and local Text-to-Speech prompts.
