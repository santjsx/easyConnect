# EasyConnect — Architecture Specification

This document details the architectural design patterns, native platform bindings, and data synchronization topology of the EasyConnect system.

---

## 1. Architectural Topology

EasyConnect is designed around an **Offline-First Hybrid Cloud Architecture**. The mobile app remains fully functional (calling, native voice guidance, local alarms) even when disconnected from the internet, syncing changes to the cloud when a connection is restored.

```
                  ┌────────────────────────────────────────┐
                  │          Caregiver Web Portal          │
                  │         (Vanilla JS / Tailwind)        │
                  └──────────────────┬─────────────────────┘
                                     │ (JSON over HTTPS)
                                     ▼
                  ┌────────────────────────────────────────┐
                  │            Google Firestore            │
                  │             (Cloud State)              │
                  └──────────────────▲─────────────────────┘
                                     │ (Bi-directional Stream)
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        FLUTTER APPLICATION LAYER                       │
│                                                                        │
│   ┌──────────────────────┐  Updates   ┌────────────────────────────┐   │
│   │ [FirebaseSyncService]├───────────>│    [Local Hive NoSQL]      │   │
│   │                      │            │  (Contacts, Alarms, Logs)  │   │
│   └──────────▲───────────┘            └─────────────┬──────────────┘   │
│              │ Stream Listener                      │ Watch Listener   │
│              │                                      ▼                  │
│    ┌─────────┴───────────┐            ┌────────────────────────────┐   │
│    │  [SystemCallState]  │            │     Riverpod Providers     │   │
│    │  (Reactive State)   │            │   (Dynamic Theme & Lists)  │   │
│    └─────────▲───────────┘            └─────────────┬──────────────┘   │
│              │                                      │                  │
│              │ Platform Channel                     ▼                  │
│              │ Event Stream                  ┌─────────────┐           │
│              │                               │  UI Grid &  │           │
│              │                               │  Overlays   │           │
│              │                               └─────────────┘           │
└──────────────┼─────────────────────────────────────────────────────────┘
               │ MethodChannel Events
               ▼ (onSystemCallEvent, onDeviceShake)
┌────────────────────────────────────────────────────────────────────────┐
│                          ANDROID NATIVE LAYER                          │
│                                                                        │
│  ┌───────────────────────┐            ┌─────────────────────────────┐  │
│  │   [MainActivity.kt]   │───────────>│ [EasyConnectInCallService]  │  │
│  │  (Method Call Handler)│            │      (Telecom Binding)      │  │
│  └───────────────────────┘            └─────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Platform Channels & Telephony Bridge

To function as a primary Android dialer, EasyConnect implements custom native code that binds directly to the **Android Telecom Framework**. Communication is managed via a dedicated `MethodChannel` (`com.easyconnect.app/calling`).

### Dialer Registration Lifecycle
1. **Role Verification**: On startup, [MainActivity.kt](file:///c:/Users/heysa/Documents/Dev/EasyConnect/android/app/src/main/kotlin/com/easyconnect/app/MainActivity.kt) queries `isDefaultDialer()`. On Android 10 (Q) and above, it checks if `ROLE_DIALER` is held via `RoleManager`. On older versions, it queries `TelecomManager.getDefaultDialerPackage()`.
2. **Default Request**: If permissions are missing, `requestDefaultDialer()` launches the system role dialog. Once approved, the app becomes the system receiver for phone intents.
3. **Immersive Rendering over Lock Screen**: To display the calling overlay when the screen is locked, `onCreate()` applies:
   * `setShowWhenLocked(true)` and `setTurnScreenOn(true)` (on API 27+)
   * Legacy window flags `FLAG_SHOW_WHEN_LOCKED`, `FLAG_TURN_SCREEN_ON`, `FLAG_KEEP_SCREEN_ON`, and `FLAG_DISMISS_KEYGUARD` (pre-API 27).

### Native Telephony InCallService
When a telephone call is placed or received, the Android system binds to [EasyConnectInCallService.kt](file:///c:/Users/heysa/Documents/Dev/EasyConnect/android/app/src/main/kotlin/com/easyconnect/app/EasyConnectInCallService.kt), a subclass of `android.telecom.InCallService`.

* **Lifecycle Hooks**:
  * `onCallAdded(call)`: Captures the active call object, registers a state listener, and dispatches an `added` event to Flutter via the MethodChannel.
  * `onCallRemoved(call)`: Dispatches a `removed` event to clean up Flutter calling states.
* **Low-Latency Event Delivery**: Call state changes are dispatched to Flutter using `mainHandler.postAtFrontOfQueue` on the main thread, bypassing other UI updates to ensure the calling overlay renders instantly.

### Dart VM Keep-Alive Ping
To prevent the Android OS from suspending the Dart VM during long periods of inactivity, [system_call_service.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/calling/services/system_call_service.dart) runs a background `Timer` that triggers a no-op method channel call every 25 seconds. This keeps the isolate active and ready to process incoming calls without startup delays.

---

## 3. Data Synchronization Topology

Synchronization between the local Hive store and Firestore is handled by the [FirebaseSyncService](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/services/firebase_sync_service.dart).

```
                      CAREGIVER (Web Dashboard)
                               │
                       Write to Firestore
                               │
                      Real-time Snapshot
                               │
                  FirebaseSyncService (Mobile)
                               │
            Queue Check / Mutex Queue (Sequential Task)
                               │
             Download Base64 Photo / Audio URL
                               │
              Isolate Decode (compute() worker)
                               │
            Write to sandboxed files / Update Hive
                               │
                     Rebuild Flutter UI
```

### Mutex Queue
To prevent race conditions from rapid concurrent edits, `FirebaseSyncService` queues incoming snapshots using a sequential execution lock:
```dart
Future<void>? _activeSyncFuture;
// ...
_firestoreSubscription = collection.snapshots().listen((snapshot) {
  Future<void> syncTask() => _syncFromFirestore(snapshot.docs, familyCode);
  if (_activeSyncFuture == null) {
    _activeSyncFuture = syncTask();
  } else {
    _activeSyncFuture = _activeSyncFuture!.whenComplete(syncTask);
  }
});
```

### Multithreaded Base64 Processing
Photos and voice recordings are uploaded to Firestore as Base64 strings. Because decoding heavy strings on the main UI thread causes frame drops, the app uses Flutter `compute()` isolates to run these operations on separate background threads:
```dart
static List<int> _decodeBase64Helper(String base64Str) => base64Decode(base64Str);
// ...
final bytes = await compute(_decodeBase64Helper, base64String);
```
Once decoded, files are written atomically to the app's document sandbox (`${appDocumentsDir}/photos/` and `${appDocumentsDir}/voice_labels/`) and the paths are saved in the local Hive database.

---

## 4. Web Dashboard Integration

The caregiver dashboard is a lightweight Single Page Application (SPA).
* **Direct Firestore Binding**: Reads and writes to Firestore collections (`contacts` and `alarms`) under `/families/{familyCode}`.
* **Atomic Telemetry Listener**: Binds to `/families/{familyCode}/telemetry/device` to show live device statistics (battery, charging status, signal strength, and GPS coordinates) in real-time.
* **Commands Pipe**: When "Find Mom's Phone" is clicked, the dashboard writes `trigger: true` and a `timestamp` to `/families/{familyCode}/commands/find_phone`. The mobile app listens for changes, verifies the timestamp, and triggers a full-volume alert if the command was sent within the last 5 minutes.
