# EasyConnect — Database Schema Map

This document catalogues the database structures, local adapters, security constraints, and relations map for EasyConnect.

---

## 1. Local Storage (Hive NoSQL)

Local databases are built using Hive NoSQL boxes. Adapters are initialized and loaded inside [main.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/main.dart#L50).

### 1. Contacts Box (`contacts`)
* **Model Class**: [Contact](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/contacts/models/contact_model.dart)
* **TypeId**: `0`
* **Adapter Class**: `ContactAdapter` (generated in `contact_model.g.dart`)

| Field Index | Name | Type | Description |
| :--- | :--- | :--- | :--- |
| **0** | `id` | `String` | Unique UUID contact identifier. |
| **1** | `name` | `String` | Visual display name of the contact (maximum 30 characters). |
| **2** | `phoneNumber` | `String` | Telephony phone number for voice/SIP calls. |
| **3** | `whatsappNumber` | `String?` | Number designated for WhatsApp message/video calls (defaults to `phoneNumber`). |
| **4** | `photoPath` | `String?` | Local path pointing to the cached JPEG avatar file in the app sandbox. |
| **5** | `colorTheme` | `String` | Hex value string for the card border decoration (default: `#4CAF50`). |
| **6** | `preferredAction` | `String` | Default tapping action trigger (`call` \| `video` \| `message`). |
| **7** | `positionIndex` | `int` | Integer index mapping card order on the Home Grid. |
| **8** | `voiceLabelPath` | `String?` | Local path pointing to the customized audio name pronunciation file (.m4a/.mp3). |

---

### 2. Settings Box (`settings`)
* **Model Class**: [AppSettings](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/settings/models/app_settings_model.dart)
* **TypeId**: `1`
* **Adapter Class**: `AppSettingsAdapter` (generated in `app_settings_model.g.dart`)

| Field Index | Name | Type | Description |
| :--- | :--- | :--- | :--- |
| **0** | `language` | `String` | Spoken voice guide language code (`en` \| `hi` \| `te`). |
| **1** | `voiceEnabled` | `bool` | Toggle enabling name/status announcements on touch events. |
| **2** | `sosContactId` | `String?` | Contact ID matching target designated for physical phone call on SOS trigger. |
| **3** | `sosLocationShare` | `bool` | Toggle enabling attachment of GPS maps link during emergency messages. |
| **4** | `adminPin` | `String` | Passcode matching local locks protecting settings and admin layouts. |
| **5** | `fingerprintEnabled` | `bool` | Toggle enabling local Android biometric scans to bypass Admin PIN pads. |
| **6** | `sosMsgContactId1` | `String?` | Contact ID matching first recipient designated for background emergency texts. |
| **7** | `sosMsgContactId2` | `String?` | Contact ID matching second recipient designated for background emergency texts. |
| **8** | `layoutMode` | `String?` | Visual style of launcher interface (`classic` \| `modern`). |
| **9** | `accentColorHex` | `String?` | Base color theme for text/icons (Hex string format). |
| **10** | `isSyncEnabled` | `bool?` | Sync toggle enabling real-time Cloud Firestore listeners. |
| **11** | `familySyncCode` | `String?` | Unique Family identifier matching cloud Firestore documents path. |
| **12** | `isKioskModeEnabled` | `bool?` | Flag enabling default app pinning to lock physical navigation gestures. |
| **13** | `wellnessCheckEnabled` | `bool?` | Flag enabling wellness monitoring timers. |
| **14** | `wellnessIntervalHours` | `int?` | Duration interval representing inactivity thresholds before alert triggers. |
| **15** | `directTapPreferredAction` | `bool?` | Toggle bypass (single tap invokes action instantly instead of opening contact sheet). |
| **16** | `unreadMissedCallContactIds` | `List<String>?` | Array containing Contact IDs with unread missed calls to announce at launch. |
| **17** | `elevenLabsApiKey` | `String?` | API Key for ElevenLabs voice generation. |
| **18** | `elevenLabsVoiceId` | `String?` | Voice Model ID for ElevenLabs. |
| **19** | `elevenLabsModelId` | `String?` | Model version for ElevenLabs. |
| **20** | `azureSpeechSubscriptionKey` | `String?` | Subscription Key for Azure Neural Voice TTS. |
| **21** | `azureSpeechRegion` | `String?` | Endpoint Region location for Azure Speech REST API. |
| **22** | `azureSpeechTeluguVoice` | `String?` | Neural voice selection for Telugu TTS translations. |
| **23** | `azureSpeechHindiVoice` | `String?` | Neural voice selection for Hindi TTS translations. |
| **24** | `azureSpeechEnglishVoice` | `String?` | Neural voice selection for English TTS translations. |

---

### 3. Call Logs Box (`call_logs`)
* **Model Class**: [CallLog](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/calling/models/call_log_model.dart)
* **TypeId**: `2`
* **Adapter Class**: `CallLogAdapter`

| Field Index | Name | Type | Description |
| :--- | :--- | :--- | :--- |
| **0** | `id` | `String` | Log UUID entry. |
| **1** | `name` | `String` | Caller display name. |
| **2** | `phoneNumber` | `String` | Connected phone number. |
| **3** | `type` | `String` | Call type categorization (`missed` \| `dialed` \| `incoming`). |
| **4** | `timestamp` | `DateTime` | Date/time matching log entry. |

---

### 4. Alarms Box (`alarms`)
* **Model Class**: [Alarm](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/alarm/models/alarm_model.dart)
* **TypeId**: `3`
* **Adapter Class**: `AlarmAdapter`

| Field Index | Name | Type | Description |
| :--- | :--- | :--- | :--- |
| **0** | `id` | `String` | Alarm UUID entry. |
| **1** | `time` | `String` | Trigger schedule time string (`HH:mm` format). |
| **2** | `label` | `String` | Visual/audible reminder description text. |
| **3** | `days` | `List<int>` | Array of weekday indices (1 = Monday, 7 = Sunday). Empty represents one-time alarm. |
| **4** | `isEnabled` | `bool` | Trigger enabling the alarm schedule. |
| **5** | `lastUpdated` | `DateTime` | Edit timestamp to coordinate bi-directional cloud conflicts. |

---

## 2. Relationships & Caching Policies

### Entity Relationships Map

```
  ┌────────────────────────────────────────────────────────┐
  │                       AppSettings                      │
  │  - sosContactId ───────────────────┐                   │
  │  - sosMsgContactId1 ───────────────┼──────────┐        │
  │  - sosMsgContactId2 ───────────────┼──────────┼─────┐  │
  └────────────────────────────────────┼──────────┼─────┼──┘
                                       │          │     │
                                       ▼          ▼     ▼
  ┌────────────────────────────────────────────────────────┐
  │                         Contact                        │
  │  - id (Primary Key) <──────────────┴──────────┴─────┘  │
  │  - photoPath (Local file system cache link)            │
  │  - voiceLabelPath (Local file system cache link)       │
  └────────────────────────────────────────────────────────┘
```

* **Settings to Contacts**: `AppSettings` maintains foreign-key associations with `Contact` objects via string references (`sosContactId`, `sosMsgContactId1`, `sosMsgContactId2`). If a contact is deleted, the corresponding IDs inside `AppSettings` are updated or cleared.
* **File System Caches**: `Contact` objects hold relative or absolute local paths (`photoPath`, `voiceLabelPath`) pointing to media folders. When a contact is deleted, `FirebaseSyncService` reads these fields and deletes the files from storage (`photos/` and `voice_labels/`) to save space.
* **Firestore Schema Constraints**: Base64 payloads are verified by [firestore.rules](file:///c:/Users/heysa/Documents/Dev/EasyConnect/firestore.rules#L43) to be under 358,400 bytes, preventing document storage limits from being exceeded.
