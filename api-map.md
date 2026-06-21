# EasyConnect — API & Interface Map

This document catalogues the communication interfaces, native method channel contracts, and cloud API endpoints utilized by EasyConnect.

---

## 1. Native Platform Channel (`com.easyconnect.app/calling`)

The mobile application communicates with the Android native layer using a binary MethodChannel.

### Flutter to Android Requests

| Method | Parameters | Return Type | Description |
| :--- | :--- | :--- | :--- |
| `makeDirectCall` | `String phoneNumber` | `Boolean` | Places a direct cellular phone call using Android `TelecomManager`. |
| `makeWhatsAppVideoCall` | `String phoneNumber` | `Boolean` | Queries the system contacts database for WhatsApp video capabilities and opens the video call screen. |
| `createSystemContact` | `String name`, `String phoneNumber` | `Boolean` | Programmatically inserts a contact card into the native address book so WhatsApp can index it. |
| `shareAudioToWhatsApp` | `String filePath`, `String phoneNumber` | `Boolean` | Automatically shares a local audio file and pre-selects the recipient's WhatsApp chat. |
| `sendDirectSMS` | `String phoneNumber`, `String message` | `Boolean` | Sends an SMS message in the background using the native `SmsManager` (requires SMS permission). |
| `getBatteryLevel` | None | `Integer` | Returns the current battery charge level (0-100). |
| `isDeviceCharging` | None | `Boolean` | Returns true if the device is plugged into a power source. |
| `getSimState` | None | `String` | Returns the SIM card status (`ready`, `absent`, `locked`, `error`, `unknown`). |
| `getSignalStrength` | None | `String` | Returns the network signal strength (`good`, `weak`, `disconnected`). |
| `isDefaultDialer` | None | `Boolean` | Returns true if EasyConnect is the system's default dialer. |
| `requestDefaultDialer` | None | `Boolean` | Requests the system role manager to set EasyConnect as the default dialer. |
| `acceptSystemCall` | None | `Boolean` | Answers the active incoming system call. |
| `hangUpSystemCall` | None | `Boolean` | Disconnects the active system call. |
| `setCallMute` | `Boolean mute` | `Boolean` | Toggles microphone mute during a call. |
| `setCallSpeaker` | `Boolean speaker` | `Boolean` | Toggles the device speakerphone. |
| `playDtmfTone` | `String digit` | `Boolean` | Plays a DTMF tone during an active call. |
| `stopDtmfTone` | None | `Boolean` | Stops playing a DTMF tone. |
| `startKioskMode` | None | `Boolean` | Locks the app to the screen using Android's task pinning. |
| `stopKioskMode` | None | `Boolean` | Unpins the app, disabling kiosk mode. |
| `checkOverlayPermissions` | None | `Boolean` | Checks if the draw-over-other-apps permission is granted. |
| `requestOverlayPermission` | None | `Boolean` | Opens system settings to request the overlay draw permission. |

### Android to Flutter Callbacks

Callbacks from the native layer are handled in [SystemCallService._handleMethodCall](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/calling/services/system_call_service.dart#L214).

#### 1. `onSystemCallEvent`
* **Arguments**: `Map<String, dynamic>` containing:
  * `event`: `"added"` \| `"removed"` \| `"stateChanged"`
  * `number` (optional): Caller phone number
  * `isIncoming` (optional): Incoming status flag
  * `state` (optional): Native call state matching Android `Call.STATE_*`
  * `disconnectCause` (optional): Disconnect code integer
* **Flutter Reaction**: Updates `systemCallProvider` state, triggering overlay routes or popping active call screens.

#### 2. `onDefaultDialerChanged`
* **Arguments**: `Boolean` (representing dialer active status)
* **Flutter Reaction**: Updates `defaultDialerProvider`.

#### 3. `onDeviceShake`
* **Arguments**: None
* **Flutter Reaction**: Triggers `_announceTelemetry()`, announcing battery, network, and SIM status over TTS.

---

## 2. Cloud Firestore Synchronization Protocols

Bi-directional syncing is mapped in [FirebaseSyncService](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/services/firebase_sync_service.dart).

### 1. Contacts Collection
* **Path**: `/families/{familyCode}/contacts/{contactId}`
* **Schema Validation** (enforced by [firestore.rules](file:///c:/Users/heysa/Documents/Dev/EasyConnect/firestore.rules#L31)):
  ```json
  {
    "id": "string",
    "name": "string (max 30 chars)",
    "phoneNumber": "string (regex validation)",
    "whatsappNumber": "string (optional)",
    "colorTheme": "string (Hex code format)",
    "preferredAction": "string ('call' | 'video' | 'message')",
    "positionIndex": "integer",
    "photoUrl": "string (base64 string < 350KB, optional)",
    "voiceLabelUrl": "string (base64 string < 350KB, optional)",
    "lastUpdated": "timestamp (server timestamp)"
  }
  ```

### 2. Alarms Collection
* **Path**: `/families/{familyCode}/alarms/{alarmId}`
* **Schema Validation** (enforced by [firestore.rules](file:///c:/Users/heysa/Documents/Dev/EasyConnect/firestore.rules#L62)):
  ```json
  {
    "id": "string",
    "time": "string (format 'HH:mm')",
    "label": "string",
    "days": "list of integers (1 = Mon, 7 = Sun)",
    "isEnabled": "boolean",
    "lastUpdated": "timestamp"
  }
  ```

### 3. Telemetry Collection (Mobile to Cloud Upload)
* **Path**: `/families/{familyCode}/telemetry/device`
* **Schema Validation** (enforced by [firestore.rules](file:///c:/Users/heysa/Documents/Dev/EasyConnect/firestore.rules#L52)):
  ```json
  {
    "batteryLevel": "integer (0-100)",
    "isCharging": "boolean",
    "signalStrength": "string ('good' | 'weak' | 'disconnected')",
    "simState": "string ('ready' | 'absent' | 'locked' | 'error' | 'unknown')",
    "gpsLocation": "string (Google Maps URL or empty)",
    "lastUpdated": "timestamp"
  }
  ```

### 4. Commands Collection (Cloud to Mobile Listener)
* **Path**: `/families/{familyCode}/commands/find_phone`
* **Schema**:
  ```json
  {
    "trigger": "boolean",
    "timestamp": "timestamp / string"
  }
  ```

---

## 3. External Third-Party Web APIs

### Azure Cognitive Speech Synthesis API
When a caregiver configures an Azure Speech subscription key, the app utilizes the **Azure Neural TTS REST API** to generate high-fidelity voice announcements.

* **Target URL**: `https://{region}.tts.speech.microsoft.com/cognitiveservices/v1`
* **HTTP Method**: `POST`
* **HTTP Headers**:
  * `Ocp-Apim-Subscription-Key`: `{azureSpeechSubscriptionKey}`
  * `Content-Type`: `application/ssml+xml`
  * `X-Microsoft-OutputFormat`: `audio-16khz-128kbitrate-mono-mp3`
  * `User-Agent`: `EasyConnectApp`
* **Payload Template (SSML XML)**:
  ```xml
  <speak version='1.0' xml:lang='{langCode}'>
    <voice xml:lang='{langCode}' xml:gender='Female' name='{voiceName}'>
      {textToSpeak}
    </voice>
  </speak>
  ```
* **Output Handling**: Synthesized audio is received as a binary stream and saved locally in `tts_cache/` as an `.mp3` file, named using the hash of the text and voice model. Future requests for the same text play instantly from the local cache.
