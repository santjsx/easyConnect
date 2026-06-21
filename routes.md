# EasyConnect — Routing & Overlay System Map

EasyConnect uses a customized navigation model tailored for senior accessibility. Rather than standard multi-page route pushes, the interface is structured as a single-page layout with tabbed views, overlaid with zero-latency full-screen dialogs and system wrappers.

---

## 1. Primary Route Registry

The following table catalogs every user-accessible page and overlay in the application.

| Route / Screen | File Path | Type | Action Trigger | Auth Guard / PIN |
| :--- | :--- | :--- | :--- | :--- |
| **Home Screen (Contacts)** | [home_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/screens/home_screen.dart) | Root Screen | Launched at App Startup | None |
| **Keypad Dialer** | [home_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/screens/home_screen.dart) (Tab Index 1) | PageView Tab | Tapping the "Keypad" navigation tab | None |
| **Call History (Logs)** | [home_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/screens/home_screen.dart) (Tab Index 2) | PageView Tab | Tapping the "Call History" navigation tab | None |
| **Incoming Call Overlay** | [incoming_call_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/calling/screens/incoming_call_screen.dart) | Immersive Overlay | Native System Ringing Event (`onSystemCallEvent`) | None |
| **Calling Screen (Active)** | [calling_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/calling/screens/calling_screen.dart) | Route Push | Outgoing call trigger or Incoming call accepted | None |
| **Admin Hub Screen** | [admin_hub_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/settings/screens/admin_hub_screen.dart) | Route Push | Tapping the "Gear" settings icon on Home Screen | Local Admin PIN Verification |
| **Manage Contacts Screen** | [manage_contacts_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/settings/screens/manage_contacts_screen.dart) | Route Push | Tapping "Manage Contacts" card inside Admin Hub | Local Admin PIN (inherited) |
| **AppSettings Screen** | [app_settings_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/settings/screens/app_settings_screen.dart) | Route Push | Tapping "App Settings & Backup" card inside Admin Hub | Local Admin PIN (inherited) |
| **Alarm Ringing Overlay** | [alarm_ring_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/screens/alarm_ring_screen.dart) | Modal Route | Time matching active alarm schedule | None |
| **Find Phone Alarm Overlay** | [find_phone_alarm_screen.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/screens/find_phone_alarm_screen.dart) | Modal Route | Caregiver command trigger from Web Dashboard | None |
| **Wellness Check Overlay** | [wellness_check_in_dialog.dart](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/wellness/widgets/wellness_check_in_dialog.dart) | Dialog Overlay | Local inactivity duration exceeding threshold | None |

---

## 2. Navigation Architecture & Transition Dynamics

### 1. Zero-Latency Page Transitions
To ensure immediate responsiveness, calls to navigate to the calling screen bypass standard OS transition animations (slide/fade). This is done using a custom `PageRouteBuilder` with `transitionDuration` set to `Duration.zero`. This prevents layout shifts and rendering lag during critical calling events:
```dart
navigatorKey.currentState?.push(PageRouteBuilder(
  pageBuilder: (context, animation, secondaryAnimation) => CallingScreen(
    contact: contactToCall,
    initialState: CallingState.outgoing,
    isSystemCall: true,
  ),
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
));
```

### 2. Offstage Overlay Wrapper
The incoming call screen ([IncomingCallScreen](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/features/calling/screens/incoming_call_screen.dart)) bypasses the Flutter `Navigator` entirely. Because a standard page push can introduce a 150-300ms layout delay, the incoming screen is placed inside a root `Stack` in the [SystemCallOverlayWrapper](file:///c:/Users/heysa/Documents/Dev/EasyConnect/lib/main.dart#L201). When a call is received, the overlay is toggled on instantly:
```dart
return Stack(
  children: [
    widget.child, // The rest of the app's navigation tree
    if (_showIncomingCallScreen)
      Positioned.fill(
        child: IncomingCallScreen(
          callerNumber: _incomingCallerNumber,
          onAccept: _handleAcceptIncoming,
          onDecline: _handleDeclineIncoming,
        ),
      ),
  ],
);
```

### 3. Physical Key Safeguards
* **Lock Screen Bypass**: When locked, the incoming call overlay automatically wakes the device and displays on top of the lock screen using native window flags configured in [MainActivity.kt](file:///c:/Users/heysa/Documents/Dev/EasyConnect/android/app/src/main/kotlin/com/easyconnect/app/MainActivity.kt).
* **Kiosk Mode Lock**: If Kiosk Mode is active (enabled in settings), physical back buttons and home gestures are disabled using `PopScope` and native Android pinning (`startLockTask()`), keeping the senior inside the simplified interface.
