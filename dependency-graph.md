# EasyConnect — Dependency Graph & Critical Files

This document maps import hierarchies, provider bindings, and files that are critical to the execution of EasyConnect.

---

## 1. Import Hierarchies

EasyConnect is designed around features and system-level services.

### Shared Services Interaction Map
```
               [main.dart]
               ├── [FirebaseSyncService]
               │   ├── [ContactRepository] -> [Hive Contacts Box]
               │   ├── [SystemStatusNotifier]
               │   └── [Geolocator]
               ├── [SystemCallService]
               │   └── [SystemCallState]
               └── [TTSService]
                   ├── [FlutterTts]
                   ├── [AudioPlayer]
                   └── [Telugu / Hindi / English Phrases]
```

### Feature Architecture Map

#### 1. Calling Feature Flow
```
[calling_screen.dart]
├── [system_call_service.dart] ──(calls MethodChannel)──> Android Native (Telecom)
├── [audio_call_service.dart]
├── [tts_service.dart]
├── [call_log_repository.dart] -> [Hive CallLogs Box]
└── [settings_provider.dart]
```

#### 2. SOS Feature Flow
```
[sos_countdown_dialog.dart]
├── [sos_service.dart]
├── [audio_call_service.dart]
├── [tts_service.dart]
├── [connectivity_provider.dart]
└── [settings_provider.dart]
```

#### 3. Wellness Check Flow
```
[home_screen.dart] (Pointer Listener)
└── [wellness_check_in_dialog.dart] (Inactivity Timer)
    ├── [system_call_service.dart] ──(calls MethodChannel)──> sendDirectSMS
    ├── [tts_service.dart]
    └── [settings_provider.dart]
```

---

## 2. Riverpod State Providers Dependency Graph

Riverpod acts as the app's state manager. Below is the dependency and listening tree.

```
                  [settingsBoxProvider] (Box<AppSettings>)
                            │
                            ▼
                    [settingsProvider] (AsyncNotifier<AppSettings>)
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
[firebaseSyncService] [dynamicAccentColor] [contactRepository]
  (Auto-listens to      (Watches hex tag     (Auto-synced via
   sync status &         for app theme)       cloud changes)
   family code)
```

* **Core Settings Dependency**: `settingsProvider` is the root provider. Any changes to settings (e.g., toggling cloud sync, changing the accent color, or updating Azure TTS keys) trigger automatic updates in dependent providers.

---

## 3. Critical Files Index

These core files are essential to the application's stability and should not be modified lightly:

| File Name | File Path | Impact Area | Risk of Modification |
| :--- | :--- | :--- | :--- |
| [main.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/main.dart) | [main.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/main.dart) | Application boot, database initializations, MethodChannel call interceptor, overlay rendering tree. | **CRITICAL**: Any breaking change can crash the app on startup or prevent incoming call alerts from showing. |
| [MainActivity.kt](file:///c:/Users/heysa/Documents/Dev/EasyConnect/android/app/src/main/kotlin/com/easyconnect/app/MainActivity.kt) | [MainActivity.kt](file:///c:/Users/heysa/Documents/Dev/EasyConnect/android/app/src/main/kotlin/com/easyconnect/app/MainActivity.kt) | Native Android MethodChannel handlers, window flags, telephony utilities, biometric integration, kiosk mode, shake sensor. | **CRITICAL**: Controls native hardware access and platform-specific capabilities. |
| [InCallService.kt](file:///c:/Users/heysa/Documents/Dev/EasyConnect/android/app/src/main/kotlin/com/easyconnect/app/EasyConnectInCallService.kt) | [EasyConnectInCallService.kt](file:///c:/Users/heysa/Documents/Dev/EasyConnect/android/app/src/main/kotlin/com/easyconnect/app/EasyConnectInCallService.kt) | Android Telecom native connection. | **CRITICAL**: Directly handles active telephonic call bindings. Errors will disrupt calling functionality. |
| [firebase_sync_service.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/services/firebase_sync_service.dart) | [firebase_sync_service.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/services/firebase_sync_service.dart) | Real-time Firestore sync pipelines, Mutex sequential queue, worker isolates. | **HIGH**: Modifying the sync queue or isolate decoding code can cause race conditions or UI freezes. |
| [tts_service.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/services/tts_service.dart) | [tts_service.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/services/tts_service.dart) | Regional translation dictionaries, Azure neural REST requests, caching layer. | **HIGH**: Key accessibility feature. Failures can silence user prompts or introduce latency. |
| [system_status_service.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/services/system_status_service.dart) | [system_status_service.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/services/system_status_service.dart) | Hardware polling (battery, network, SIM), call warnings queue. | **MEDIUM**: Handles telemetry updates and battery warnings. |
| [home_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/screens/home_screen.dart) | [home_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/screens/home_screen.dart) | Home layout grid, keypad, call history list, pointer listener for inactivity timeouts. | **HIGH**: App shell containing user controls and layouts. |
| [index.html](file:///c:/Users/heysa/Documents/Dev/EasyConnect/web_dashboard/index.html) | [index.html](file:///c:/Users/heysa/Documents/Dev/EasyConnect/web_dashboard/index.html) | Caregiver dashboard rendering, base64 uploads, real-time Firestore listeners. | **HIGH**: Key entry point for remote app management. |
