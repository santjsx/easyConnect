# EasyConnect — AI Build Prompt Sequence
**Use with:** Claude Code, Cursor, or any AI coding assistant  
**Stack:** Flutter + Riverpod + Hive + GoRouter  
**Read the PRD first before running any prompt.**

---

## How to Use This Document

- Run prompts **in order**. Each one builds on the last.
- After each prompt, **verify the checklist** before moving to the next.
- If the AI makes a mistake, use the **correction prompt** at the end of each section.
- Copy each prompt block exactly — the specificity is intentional.

---

## PHASE 0 — Project Bootstrap

### Prompt 0.1 — Create the Flutter project

```
Create a new Flutter project called "easyconnect" targeting Android only.

Set minimum SDK to Android API 26 (Android 8.0).
Set target SDK to API 34.

Add these dependencies to pubspec.yaml:
- flutter_riverpod: ^2.5.1
- go_router: ^13.2.0
- hive_flutter: ^1.1.0
- hive: ^2.2.3
- build_runner: ^2.4.8
- hive_generator: ^2.0.1
- uuid: ^4.3.3
- flutter_tts: ^4.0.2
- record: ^5.1.2
- image_picker: ^1.0.7
- image_cropper: ^7.1.0
- permission_handler: ^11.3.0
- url_launcher: ^6.2.5
- share_plus: ^9.0.0
- csv: ^6.0.0
- path_provider: ^2.1.2
- flutter_intl (via intl: ^0.19.0)

Set up the folder structure exactly as follows:
lib/
  core/
    constants/
    theme/
    utils/
  features/
    contacts/
      models/
      repositories/
      providers/
      widgets/
    calling/
      services/
      providers/
    voice_message/
      services/
      providers/
    settings/
      models/
      repositories/
      screens/
    sos/
      services/
  services/
  screens/
  main.dart

Run flutter pub get and confirm there are no errors.
```

#### ✅ Checklist
- [x] `flutter pub get` runs without errors
- [x] Folder structure matches above exactly
- [x] `pubspec.yaml` has all dependencies listed

---

### Prompt 0.2 — Android permissions and configuration

```
Configure the Android project for EasyConnect.

In android/app/src/main/AndroidManifest.xml, add these permissions:
- android.permission.CALL_PHONE
- android.permission.RECORD_AUDIO
- android.permission.READ_EXTERNAL_STORAGE (maxSdkVersion 32)
- android.permission.READ_MEDIA_IMAGES (for API 33+)
- android.permission.CAMERA
- android.permission.ACCESS_FINE_LOCATION
- android.permission.VIBRATE

Also add the following intent query for WhatsApp deep links inside the <queries> block:
<package android:name="com.whatsapp" />

Set android:usesCleartextTraffic="false" in the application tag.
Set the app label to "EasyConnect".

In android/app/build.gradle, confirm minSdkVersion is 26 and targetSdkVersion is 34.
```

#### ✅ Checklist
- [x] All permissions in `AndroidManifest.xml`
- [x] WhatsApp package query added
- [x] `minSdkVersion` is `26`

---

### Prompt 0.3 — Data models with Hive

```
Create the two core data models for EasyConnect using Hive for local storage.

File: lib/features/contacts/models/contact_model.dart

Create a HiveObject called Contact with these fields:
- id: String (UUID, part 0)
- name: String (part 1)
- phoneNumber: String (part 2)
- whatsappNumber: String? nullable (part 3)
- photoPath: String? nullable (part 4)
- colorTheme: String default '#4CAF50' (part 5)
- preferredAction: String default 'call' — values: 'call', 'video', 'message' (part 6)
- positionIndex: int (part 7)
- voiceLabelPath: String? nullable (part 8)

File: lib/features/settings/models/app_settings_model.dart

Create a HiveObject called AppSettings with these fields:
- language: String default 'en' — values: 'en', 'hi', 'te' (part 0)
- voiceEnabled: bool default true (part 1)
- sosContactId: String? nullable (part 2)
- sosLocationShare: bool default false (part 3)
- adminPin: String (4-digit, stored as plain string for MVP) (part 4)
- fingerprintEnabled: bool default false (part 5)

Register both adapters in main.dart inside main() before runApp.
Open two Hive boxes: 'contacts' and 'settings'.

Run build_runner to generate the adapter files:
flutter pub run build_runner build --delete-conflicting-outputs
```

#### ✅ Checklist
- [ ] `contact_model.g.dart` and `app_settings_model.g.dart` generated
- [ ] Both boxes opened in `main.dart`
- [ ] App compiles without errors

---

### Prompt 0.4 — App theme

```
Create a global app theme for EasyConnect in lib/core/theme/app_theme.dart.

Requirements:
- Primary colour: #4CAF50 (green — for call buttons)
- Use MaterialApp ThemeData
- Default font size: 16sp
- Large font size constant: 20sp
- Extra large: 24sp

Create a constants file at lib/core/constants/app_colours.dart with:
- kCallGreen = Color(0xFF4CAF50)
- kVideoBlue = Color(0xFF2196F3)
- kMessageOrange = Color(0xFFFF9800)
- kStopRed = Color(0xFFF44336)
- kSosRed = Color(0xFFD32F2F)
- kCardBackground = Color(0xFFFFFFFF)
- kTextDark = Color(0xFF212121)

Create lib/core/constants/app_dimensions.dart with:
- kMinTouchTarget = 64.0
- kContactPhotoSize = 120.0
- kButtonIconSize = 32.0
- kCardBorderRadius = 16.0
- kGridSpacing = 12.0

Apply the theme in main.dart via MaterialApp.
```

#### ✅ Checklist
- [ ] Theme applied globally in `main.dart`
- [ ] Constants file exists and is importable
- [ ] App renders without errors

---

## PHASE 1 — Static UI

### Prompt 1.1 — Home screen layout

```
Build the home screen for EasyConnect at lib/screens/home_screen.dart.

Layout requirements:
- Scaffold with no AppBar
- Body: GridView.builder with 2 columns, crossAxisSpacing and mainAxisSpacing both 12.0
- Each grid item renders a ContactCard widget (create a placeholder for now)
- At the bottom of the screen, outside the grid, pin a SOS button that is always visible
- The SOS button should be full width, height 72dp, background color kSosRed, white text "Emergency", font size 20sp, bold
- In the top-right corner, show a small settings icon (admin access) — IconButton with Icons.admin_panel_settings, size 28

Use a hardcoded list of 4 fake contacts for now:
[
  { name: "Santhosh", phone: "+919876543210", positionIndex: 0 },
  { name: "Priya", phone: "+919123456789", positionIndex: 1 },
  { name: "Ravi", phone: "+918765432100", positionIndex: 2 },
  { name: "Amma", phone: "+917654321098", positionIndex: 3 }
]

The grid must be sorted by positionIndex and must NEVER auto-sort alphabetically or by any other field.
```

#### ✅ Checklist
- [ ] Grid renders 4 contact cards
- [ ] SOS button visible and pinned at bottom
- [ ] Admin icon in top-right
- [ ] No AppBar

---

### Prompt 1.2 — Contact card widget

```
Create the ContactCard widget at lib/features/contacts/widgets/contact_card.dart.

The card takes a Contact object (use the placeholder model for now).

Layout (vertical, inside a Card with rounded corners of 16dp):
1. Top section: Circular photo placeholder (120×120dp), grey background, person icon centered if no photo
2. Contact name: centered below photo, font size 18sp, bold, color kTextDark, max 1 line with ellipsis
3. Action buttons row: 3 equal-width IconButtons horizontally
   - Green phone icon (kCallGreen) — minimum touch target 64×64dp
   - Blue video icon (kVideoBlue) — minimum touch target 64×64dp
   - Orange mic icon (kMessageOrange) — minimum touch target 64×64dp

All three buttons must have:
- A background circle (CircleAvatar or Container with BoxDecoration)
- Icon size 32dp
- onPressed: print statement for now ("Call tapped: [name]", etc.)

Card elevation: 3
Card background: kCardBackground
Padding inside card: 12dp all sides
```

#### ✅ Checklist
- [ ] Three action buttons visible and tappable
- [ ] Photo placeholder renders correctly
- [ ] Touch targets are at least 64×64dp (verify with Flutter inspector)
- [ ] Name truncates with ellipsis if too long

---

### Prompt 1.3 — Empty state

```
In home_screen.dart, add an empty state.

If the contact list is empty, instead of the grid, show a centered Column with:
- Icon: Icons.people_outline, size 80, color grey
- Text: "Ask your family member to add contacts.", font size 18sp, centered, grey, padding 24dp horizontal

This empty state must replace the grid entirely — do not show both.
Wrap the grid/empty state toggle in a conditional based on whether the contact list is empty.
```

#### ✅ Checklist
- [ ] Empty state appears when list is empty
- [ ] Grid appears when contacts exist
- [ ] No layout overflow errors

---

## PHASE 2 — Audio Calling

### Prompt 2.1 — TTS Service

```
Create the TTS service before building calling, as it's needed for voice feedback.

File: lib/services/tts_service.dart

Create a class TTSService with:
- A FlutterTts instance
- An async init() method that sets:
  - language based on AppSettings.language ('en-IN', 'hi-IN', 'te-IN')
  - speech rate: 0.45 (slightly slower than default)
  - volume: 1.0
  - pitch: 1.0
- A speak(String text) method that calls flutterTts.speak(text)
- A stop() method
- A setLanguage(String langCode) method that re-initialises with the new language

Create a Riverpod provider for TTSService at lib/services/tts_service.dart:
final ttsServiceProvider = Provider<TTSService>((ref) => TTSService());

Make TTSService a singleton through Riverpod — do not instantiate it manually anywhere else.

Test by calling ttsService.speak("EasyConnect ready") on app startup in main.dart (remove after testing).
```

#### ✅ Checklist
- [ ] TTS speaks on app launch (remove test after verifying)
- [ ] No TTS errors in the console
- [ ] Provider is accessible from any widget using `ref.read`

---

### Prompt 2.2 — Audio call service

```
Create the audio call service at lib/features/calling/services/audio_call_service.dart.

Create a class AudioCallService that takes a TTSService as a dependency.

Method: Future<void> makeCall(Contact contact) that does the following in order:
1. Trigger haptic feedback: HapticFeedback.heavyImpact()
2. Speak the call prompt based on language:
   - 'en': "Calling [contact.name]"
   - 'hi': "[contact.name] को कॉल किया जा रहा है"
   - 'te': "[contact.name] కి కాల్ చేస్తున్నారు"
3. Wait 1500ms for the TTS to finish
4. Launch the native dialer using url_launcher: Uri(scheme: 'tel', path: contact.phoneNumber)
5. If url_launcher canLaunch returns false, speak the error: "Cannot make call. Please check phone settings."

Handle these error cases with spoken feedback:
- Phone number is empty or null: speak "This contact has no phone number saved."
- Launch fails: speak "Could not start the call. Please try again."

Create a Riverpod provider for AudioCallService.
```

#### ✅ Checklist
- [ ] Tapping call button speaks the contact's name then opens dialer
- [ ] Haptic fires before TTS
- [ ] Error state tested by passing an empty phone number

---

### Prompt 2.3 — Wire call button to service

```
In ContactCard, replace the print statement on the green call button's onPressed with:

ref.read(audioCallServiceProvider).makeCall(contact)

ContactCard must be a ConsumerWidget (Riverpod).

Also add a permission check before calling. In AudioCallService.makeCall(), before launching the dialer:
- Use permission_handler to check Permission.phone status
- If not granted, request it
- If permanently denied, speak: "Call permission is not allowed. Please ask your family to fix this in phone settings."
- Only proceed to launch if permission is granted

Test on a real device or emulator with a valid phone number.
```

#### ✅ Checklist
- [ ] Call button triggers TTS then opens dialer
- [ ] Permission is requested if not already granted
- [ ] Denied permission shows spoken error (not a crash)

---

## PHASE 3 — WhatsApp Video Call

### Prompt 3.1 — WhatsApp call service

```
Create lib/features/calling/services/whatsapp_call_service.dart.

Create a class WhatsAppCallService that takes a TTSService as a dependency.

Method: Future<void> makeVideoCall(Contact contact) that:
1. Checks if contact.whatsappNumber is null or empty
   - If so, speak: "No WhatsApp number saved for [contact.name]." and return
2. Trigger HapticFeedback.heavyImpact()
3. Speak: "Starting video call with [contact.name]" (in the configured language)
4. Wait 1500ms
5. Build the WhatsApp deep link: "https://wa.me/[cleaned number]"
   - Cleaned number: strip all spaces, dashes, parentheses; keep the + prefix
6. Attempt to launch the URL using url_launcher with mode: LaunchMode.externalApplication
7. If the launch fails (WhatsApp not installed):
   - Speak: "WhatsApp is not installed."
   - Show a SnackBar (via a callback or context) with a button: "Install WhatsApp" that opens the Play Store listing

Helper method: String _cleanNumber(String number) that removes all non-digit characters except leading +.

Create a Riverpod provider for WhatsAppCallService.
Wire the blue video button in ContactCard to call whatsAppCallService.makeVideoCall(contact).
```

#### ✅ Checklist
- [ ] Video button speaks prompt then opens WhatsApp call
- [ ] Button is visually disabled (grey) if `whatsappNumber` is null
- [ ] Not-installed error triggers spoken feedback + snackbar

---

## PHASE 4 — Voice Message

### Prompt 4.1 — Recording service

```
Create lib/features/voice_message/services/recording_service.dart.

Create a class RecordingService with:

State:
- bool isRecording
- String? currentRecordingPath

Methods:

Future<String?> startRecording() — does the following:
  1. Check and request Permission.microphone
  2. If denied, return null
  3. Generate a temp file path in the app's temp directory: 
     [tempDir]/easyconnect_msg_[timestamp].m4a
  4. Start recording using the record package with AudioEncoder.aacLc, 44100 Hz
  5. Set isRecording = true
  6. Return the file path

Future<String?> stopRecording() — does the following:
  1. Stop the recording
  2. Set isRecording = false
  3. Return the path to the saved file
  4. Validate the file exists and is > 0 bytes; if not, return null

Future<void> deleteRecording(String path) — deletes the file at path

Do not share or send from this service. Sharing is handled separately.

Create a Riverpod StateNotifierProvider that exposes:
- isRecording: bool
- recordingPath: String?
- Start, stop, delete methods
```

#### ✅ Checklist
- [ ] Recording creates an `.m4a` file in temp directory
- [ ] Stop returns a valid file path
- [ ] File exists after recording stops

---

### Prompt 4.2 — Voice message UI flow

```
Create a full-screen recording overlay widget at 
lib/features/voice_message/widgets/recording_overlay.dart.

This overlay appears on top of the home screen (not a new route) when the user taps the orange mic button.

States to handle:
1. RECORDING state:
   - Dark semi-transparent background (Colors.black87)
   - Large pulsing red circle in the center (animate scale between 0.9 and 1.1, repeat)
   - Text above circle: "Recording..." in white, 22sp
   - Contact name below: "[Name]", white, 18sp
   - Large STOP button at bottom: red, full width, 72dp tall, white text "STOP", 20sp bold
   - Tapping STOP calls stopRecording()

2. PREVIEW state (after stop):
   - Show waveform placeholder (just a flat coloured bar for MVP — no real waveform)
   - Text: "Message recorded" in white, 20sp
   - PLAY button (grey, large icon) to replay the recording using audioplayers or just url_launcher
   - Two equal-width buttons at bottom:
     - DELETE (red): deletes file, closes overlay
     - SEND (green): calls the share service

3. SENDING state:
   - Show a brief spinner with text "Opening WhatsApp..."

Close the overlay on successful send or delete.
Show this overlay using a Stack on the home screen, toggled by a boolean in a StateNotifier.
```

#### ✅ Checklist
- [ ] Overlay appears over home screen (not full navigation push)
- [ ] Pulsing animation plays during recording
- [ ] STOP transitions to preview state
- [ ] DELETE closes overlay and removes temp file
- [ ] SEND triggers WhatsApp share flow

---

### Prompt 4.3 — Send via WhatsApp

```
Create lib/features/voice_message/services/share_service.dart.

Create a class ShareService.

Method: Future<void> sendVoiceMessage(String filePath, Contact contact) that:
1. Checks WhatsApp is installed (same check as Phase 3)
2. If not installed, speak: "WhatsApp is not installed. Cannot send message."
3. Uses share_plus to share the file:
   ShareParams(
     files: [XFile(filePath, mimeType: 'audio/m4a')],
     text: '',
   )
   This opens the Android share sheet pre-filtered to WhatsApp if possible.
4. After share completes (await), speak: "Message sent"
5. Delete the temp file after successful share

Note: share_plus on Android will open the system share sheet. This is acceptable for MVP.
A direct WhatsApp share can be attempted first using the intent:
  content://... with package com.whatsapp
  Fall back to share_plus if the intent fails.

Wire the SEND button in the recording overlay to this service.
```

#### ✅ Checklist
- [ ] Tapping SEND opens WhatsApp (or share sheet)
- [ ] Temp file is deleted after send
- [ ] "Message sent" is spoken after the share sheet closes

---

## PHASE 5 — CSV Import / Export

### Prompt 5.1 — Contact repository

```
Before building CSV features, set up the contact repository using Hive.

Create lib/features/contacts/repositories/contact_repository.dart.

Class ContactRepository with methods:
- Future<List<Contact>> getAllContacts() — returns all contacts sorted by positionIndex
- Future<void> addContact(Contact contact)
- Future<void> updateContact(Contact contact) — find by id, update in place
- Future<void> deleteContact(String id)
- Future<void> reorderContacts(List<String> orderedIds) — updates positionIndex for each

Use the Hive 'contacts' box.
Generate UUIDs using the uuid package.

Create a Riverpod provider that exposes a Stream<List<Contact>> that auto-updates when the box changes (use Hive's watchBoxe() or listenable()).

Update the home screen to read from this provider instead of the hardcoded list.
```

#### ✅ Checklist
- [ ] Adding a contact via debug code persists after hot restart
- [ ] Home screen re-renders when contacts change
- [ ] Contacts are returned sorted by `positionIndex`

---

### Prompt 5.2 — CSV import

```
Create lib/services/csv_service.dart.

Create a class CsvService.

Method: Future<List<ContactImportRow>> parseCSV(String filePath) that:
1. Reads the file at filePath
2. Parses it using the csv package
3. Expects headers: name, phone, whatsapp, photo_path (case-insensitive)
4. Returns a list of ContactImportRow objects:
   class ContactImportRow {
     String? name;
     String? phone;
     String? whatsapp;
     String? photoPath;
     List<String> errors; // e.g. ["Missing name", "Invalid phone number"]
   }
5. Validates each row:
   - name is required; if blank, add error "Missing name"
   - phone is required; must match regex ^\+?[0-9\s\-\(\)]{7,15}$; if invalid, add error "Invalid phone number"
   - Duplicate phone numbers within the file: add error "Duplicate phone number"
6. Returns ALL rows (including invalid ones); the UI will show errors per row

Method: Future<void> importValidRows(List<ContactImportRow> rows, ContactRepository repo) that:
- Skips rows with errors
- Creates Contact objects with uuid, positionIndex = current max + 1
- Calls repo.addContact for each

Create an admin import screen at lib/features/settings/screens/import_screen.dart that:
- Has a button to pick a CSV file using file_picker (add this dependency: file_picker: ^8.0.6)
- Shows a preview table of parsed rows with error rows highlighted in red
- Has an "Import [N] valid contacts" button
- Shows a result snackbar: "8 contacts imported, 2 skipped"
```

#### ✅ Checklist
- [ ] Valid CSV imports all rows correctly
- [ ] Invalid rows are highlighted, not imported
- [ ] Duplicate numbers within the file are flagged
- [ ] Position index increments correctly for imported contacts

---

### Prompt 5.3 — CSV and JSON export

```
Add export methods to CsvService.

Method: Future<String> exportToCSV(List<Contact> contacts) that:
- Generates a CSV string with headers: name,phone,whatsapp,photo_path,position
- Returns the CSV string

Method: Future<String> exportToJSON(List<Contact> contacts, AppSettings settings) that:
- Exports both contacts and settings as a JSON object:
  {
    "version": 1,
    "exported_at": "[ISO timestamp]",
    "settings": { ...AppSettings fields... },
    "contacts": [ ...Contact fields... ]
  }
- For photos: include the photoPath as a string (not base64 for MVP)
- Returns the JSON string

Method: Future<void> saveAndShare(String content, String filename) that:
- Saves the content to a file in the app's Documents directory
- Shares it using share_plus

Add an Export section to the admin screen with two buttons:
- "Export as CSV"
- "Export as JSON Backup"
Each calls the appropriate method and shares the file.
```

#### ✅ Checklist
- [ ] CSV export opens share sheet with a valid `.csv` file
- [ ] JSON export includes both contacts and settings
- [ ] Exported CSV can be re-imported without errors

---

## PHASE 6 — Voice Guidance System

### Prompt 6.1 — Full TTS prompt catalogue

```
Expand TTSService with the full prompt catalogue from the PRD.

In lib/services/tts_service.dart, add a method:
Future<void> speakEvent(VoiceEvent event, {String? contactName}) 

Create an enum VoiceEvent:
  callingStarted,
  videoCallStarting,
  recordingStarted,
  messageSent,
  noInternet,
  whatsappMissing,
  batteryLow,
  sosTriggerCountdown,
  permissionDenied,
  noPhoneNumber,
  noWhatsappNumber,
  recordingTooShort

Create a Map<String, Map<VoiceEvent, String>> _prompts that contains
all three languages ('en', 'hi', 'te') and all VoiceEvent values.

Use the exact strings from the PRD for 'hi' and 'te'.
For 'en', use these:
- callingStarted: "Calling {name}"
- videoCallStarting: "Starting video call with {name}"
- recordingStarted: "Recording message for {name}. Tap stop when done."
- messageSent: "Message sent"
- noInternet: "No internet connection"
- whatsappMissing: "WhatsApp is not installed"
- batteryLow: "Battery is low"
- sosTriggerCountdown: "Calling emergency contact in {seconds}"
- permissionDenied: "Permission not allowed. Ask your family to fix this."
- noPhoneNumber: "This contact has no phone number saved."
- noWhatsappNumber: "No WhatsApp number saved for {name}."
- recordingTooShort: "Message too short. Please try again."

Replace all hardcoded speak() calls in AudioCallService, WhatsAppCallService,
RecordingService, and ShareService with speakEvent() calls.
```

#### ✅ Checklist
- [ ] Every action speaks the correct prompt in English
- [ ] Changing language in settings changes TTS language immediately
- [ ] `{name}` is replaced with the contact's name in all prompts

---

### Prompt 6.2 — Language setting in admin

```
In the admin settings screen, add a language selector.

Show three large toggle buttons (not a dropdown):
- తెలుగు (Telugu)
- हिन्दी (Hindi)  
- English

The selected language has a highlighted border and background.
Tapping a language:
1. Updates AppSettings.language in Hive
2. Calls ttsService.setLanguage() immediately
3. Speaks a confirmation in the newly selected language:
   - 'te': "భాష తెలుగుకు మార్చబడింది"
   - 'hi': "भाषा हिन्दी में बदल दी गई है"
   - 'en': "Language changed to English"

The language setting must persist across app restarts.
```

#### ✅ Checklist
- [ ] Language change is reflected immediately in TTS
- [ ] Setting persists after hot restart
- [ ] Confirmation is spoken in the newly selected language

---

## PHASE 7 — Admin Mode

### Prompt 7.1 — PIN entry screen

```
Create lib/features/settings/screens/pin_entry_screen.dart.

This screen is shown when the admin icon is tapped on the home screen.

Layout:
- Title: "Enter Admin PIN", 20sp, centered
- Four large digit display boxes (showing * for each entered digit), each 48×48dp
- A 3×4 numpad (digits 0-9 plus backspace and confirm):
  [1][2][3]
  [4][5][6]
  [7][8][9]
  [⌫][0][✓]
- Each numpad button: minimum 72×72dp, large font (28sp)
- No text input field — only the numpad buttons

Logic:
- On first launch (adminPin is empty in settings), show a "Set your PIN" flow:
  - Enter PIN once → confirm PIN again → if they match, save and proceed
  - If they don't match, shake the display boxes and clear
- On subsequent launches, compare entered PIN to stored PIN
- On match: navigate to admin dashboard
- On 3 failed attempts: lock for 30 seconds (show countdown), speak: "Too many attempts. Please wait."
- No fingerprint for MVP (leave as future feature stub)

Do not use a keyboard or TextField anywhere on this screen.
```

#### ✅ Checklist
- [ ] PIN is set on first launch
- [ ] Correct PIN opens admin dashboard
- [ ] Wrong PIN shows an error without crashing
- [ ] 3 failed attempts shows lockout timer

---

### Prompt 7.2 — Admin dashboard

```
Create lib/features/settings/screens/admin_screen.dart.

This screen is only accessible after PIN verification.

Layout — a scrollable list of sections:

SECTION 1: Contacts
- List of all current contacts with drag handles for reordering
- Each row: photo thumbnail, name, phone number, edit icon, delete icon
- "Add Contact" button at top (large, green)

SECTION 2: Import / Export
- "Import from CSV" button
- "Export as CSV" button
- "Export as JSON Backup" button

SECTION 3: App Settings
- Language selector (from Phase 6.2)
- Voice guidance toggle (On/Off)
- SOS Contact picker (dropdown of existing contacts)
- Location sharing toggle for SOS (On/Off)

SECTION 4: Security
- "Change PIN" button

Each section has a visible header label (18sp, bold, kTextDark).
An X or back button at the top-left dismisses and returns to home screen.
No bottom navigation bar on this screen.
```

#### ✅ Checklist
- [ ] All sections render without overflow
- [ ] Contact reordering via drag updates `positionIndex` in Hive
- [ ] Home screen reflects reordering after closing admin

---

### Prompt 7.3 — Add and edit contact

```
Create a contact form bottom sheet (not a new screen) at
lib/features/contacts/widgets/contact_form_sheet.dart.

Show this as a DraggableScrollableSheet from the bottom when "Add Contact" or "Edit" is tapped.

Form fields (NO text keyboard for photo; keyboard only for name and phone):
1. Photo: large circle (120dp) showing current photo or a placeholder. Tapping opens a dialog:
   - "Take Photo" button
   - "Choose from Gallery" button
   After selection, run image_cropper to crop to 1:1 ratio and auto-centre.

2. Name field: TextField, large font (18sp), label "Contact Name", max 30 characters.

3. Phone number: TextField, keyboardType: phone, label "Phone Number".

4. WhatsApp number: TextField, keyboardType: phone, label "WhatsApp Number (optional)".

5. Preferred action: SegmentedButton with three options: Call / Video / Message.

Bottom of sheet: two buttons:
- Cancel (outlined, grey)
- Save (filled, green)

On Save:
- Validate: name is not empty, phone matches ^\+?[0-9]{7,15}$
- Show inline errors below fields if invalid
- On success: call repo.addContact() or repo.updateContact(), close sheet, speak "Contact saved."

For edit mode, pre-fill all fields with existing contact data.
```

#### ✅ Checklist
- [ ] New contact appears on home screen after save
- [ ] Photo is cropped to square and saved locally
- [ ] Editing existing contact pre-fills fields correctly
- [ ] Validation prevents saving without a name or phone number

---

## PHASE 8 — SOS Button

### Prompt 8.1 — SOS service and countdown

```
Create lib/features/sos/services/sos_service.dart.

Create a class SosService that depends on TTSService, AudioCallService, and AppSettings.

Method: Future<void> triggerSOS(BuildContext context) that:

1. Reads sosContactId from settings
2. If no SOS contact is set:
   - Speak: "Emergency contact not set. Ask your family to set this up."
   - Return early

3. Show a full-screen countdown overlay (3 seconds):
   - Dark red background (kSosRed with 90% opacity)
   - Large white countdown number (72sp, bold) counting 3 → 2 → 1
   - Text below: "Calling Emergency Contact" (white, 20sp)
   - CANCEL button at bottom (white, large): cancels the countdown
   - Speak each second: "3", "2", "1"

4. If not cancelled, dismiss overlay and call audioCallService.makeCall(sosContact)

5. If sosLocationShare is true and location permission is granted:
   - After call is launched, get last known location using geolocator package
   - Send a WhatsApp message to the SOS contact:
     "🆘 Emergency! I need help. My location: https://maps.google.com/?q=[lat],[lng]"
   - Speak: "Location sent to [name]."

Wire the SOS button at the bottom of the home screen to sosService.triggerSOS(context).
Add geolocator: ^12.0.0 to pubspec.yaml.
```

#### ✅ Checklist
- [ ] 3-second countdown shows and speaks
- [ ] Cancel button stops the countdown
- [ ] After countdown, native dialer opens for the SOS contact
- [ ] Location message is sent if setting is enabled (test with a real number)

---

## PHASE 9 — Final Polish & Testing

### Prompt 9.1 — Offline resilience

```
Add offline detection to EasyConnect.

Add connectivity_plus: ^6.0.3 to pubspec.yaml.

Create a ConnectivityService that:
- Exposes a Stream<bool> isConnected
- On connectivity lost, speaks: "No internet connection" (only once per disconnection event, not on every check)

In WhatsAppCallService.makeVideoCall() and ShareService.sendVoiceMessage():
- Check connectivity before attempting
- If offline, speak the no-internet prompt and return early

Add a persistent top banner (AnimatedContainer, height 36dp, orange background):
- Shows when offline: "No internet — WhatsApp features unavailable"
- Hides when online
- Does NOT block any home screen interaction
```

#### ✅ Checklist
- [ ] Banner appears when WiFi/mobile data is off
- [ ] Banner disappears when connection resumes
- [ ] Video call and voice message show offline error when no internet
- [ ] Audio call still works offline

---

### Prompt 9.2 — Performance and accessibility audit

```
Perform the following performance and accessibility checks on EasyConnect:

1. TOUCH TARGETS
   Use the Flutter inspector to verify every interactive element on the home screen is at least 64×64dp.
   If any button is smaller, wrap it in a SizedBox(width: 64, height: 64) or use minimumSize in ButtonStyle.

2. CONTRAST
   Check that all text on card backgrounds meets WCAG AA (4.5:1).
   Specifically verify: contact name on white card, button icons on coloured backgrounds.

3. APP LAUNCH TIME
   Add a stopwatch print from main() to the first frame callback.
   If over 2000ms, identify the slowest Hive or image operation and optimise.

4. GRID RENDER
   Create a test with 20 contacts, each with a local photo.
   Measure time to first full grid render. Must be under 500ms.
   Use CachedNetworkImage pattern for local files if needed (use cached_network_image: ^3.3.1 or just FileImage with caching).

5. TALKBACK
   Enable TalkBack on the emulator.
   Verify all three action buttons on a contact card have meaningful semantics labels:
   - "Call [Name]"
   - "Video call [Name]"
   - "Send voice message to [Name]"
   Add Semantics widgets where needed.

Fix all issues found before proceeding to user testing.
```

#### ✅ Checklist
- [ ] All touch targets ≥ 64dp confirmed in inspector
- [ ] TalkBack reads meaningful labels for all buttons
- [ ] App cold launches in < 2 seconds
- [ ] 20-contact grid renders in < 500ms

---

### Prompt 9.3 — Error handling sweep

```
Do a full sweep of EasyConnect to ensure no unhandled exceptions can crash the app.

For every async method in:
- AudioCallService
- WhatsAppCallService
- RecordingService
- ShareService
- SosService
- CsvService
- ContactRepository

Wrap the body in try/catch(e).
On any unexpected error:
1. Log to console: debugPrint('Error in [ClassName].[methodName]: $e')
2. Speak: "Something went wrong. Please try again." (do not speak technical details)
3. Return gracefully — never rethrow to the UI layer

Also ensure:
- No Navigator.pop() is called if the context is no longer mounted
- All async gaps check if (mounted) before setState
- All Hive box operations check if the box is open before reading/writing

Run flutter analyze and fix all warnings and errors.
```

#### ✅ Checklist
- [ ] `flutter analyze` returns zero issues
- [ ] Force-closing WhatsApp mid-launch does not crash the app
- [ ] Revoking microphone permission mid-session does not crash the app
- [ ] No red error screens appear during normal use

---

## Correction Prompts

Use these when the AI goes off-track:

### When the AI adds unnecessary screens or navigation:
```
Stop. EasyConnect uses a single home screen. Do not add new routes or navigation 
for this feature. Implement it as an overlay, bottom sheet, or dialog on the 
existing home screen. Re-read the product principle: "One-screen experience."
```

### When the AI uses small touch targets:
```
All interactive elements must be a minimum of 64×64dp. This is a hard requirement 
for elderly users. Wrap this button in a SizedBox or use ButtonStyle minimumSize. 
Do not compromise on this.
```

### When the AI sorts contacts automatically:
```
Contacts must NEVER be sorted automatically. They are always displayed in the 
order of their positionIndex field, which is set manually by the admin. Remove 
any alphabetical or automatic sorting logic.
```

### When the AI adds text where a voice prompt should be:
```
EasyConnect's primary feedback for this action should be a spoken voice prompt 
via TTSService, not a text label or toast. The user cannot read. Replace the 
text feedback with a ttsService.speakEvent() call.
```

### When the AI uses a TextField where there should be none:
```
The primary user of this app cannot type. Do not use a TextField or keyboard 
input for this feature. Use large buttons, a numpad, or voice recording instead. 
Re-read Product Principle P1: No Typing.
```

---

*End of Build Prompt Sequence*  
*Estimated build time with AI assistance: 3–5 days for an experienced Flutter developer*
