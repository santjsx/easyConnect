import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/core/theme/app_theme.dart';
import 'package:easyconnect/screens/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/calling/screens/calling_screen.dart';
import 'package:easyconnect/features/calling/screens/incoming_call_screen.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:easyconnect/services/firebase_sync_service.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';

import 'package:easyconnect/features/calling/models/call_log_model.dart';
import 'package:easyconnect/features/calling/repositories/call_log_repository.dart';
import 'package:easyconnect/features/calling/providers/is_calling_active_provider.dart';
import 'package:easyconnect/features/alarm/models/alarm_model.dart';
import 'package:easyconnect/screens/alarm_ring_screen.dart';



void main() async {
  final stopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (graceful fallback if google-services.json is missing)
  try {
    await Firebase.initializeApp();
    debugPrint('Firebase initialized successfully.');
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }



  // Enable seamless edge-to-edge fullscreen rendering (draw behind notch/cutout & gesture bars)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  await Hive.initFlutter();

  // Register adapters
  Hive.registerAdapter(ContactAdapter());
  Hive.registerAdapter(AppSettingsAdapter());
  Hive.registerAdapter(CallLogAdapter());
  Hive.registerAdapter(AlarmAdapter());

  // Open boxes with self-healing fallbacks in case of database corruption
  late final Box<Contact> contactsBox;
  late final Box<AppSettings> settingsBox;
  late final Box<CallLog> logsBox;

  try {
    contactsBox = await Hive.openBox<Contact>('contacts');
  } catch (e) {
    debugPrint('Hive: contacts box corrupted, resetting: $e');
    await Hive.deleteBoxFromDisk('contacts');
    contactsBox = await Hive.openBox<Contact>('contacts');
  }

  try {
    settingsBox = await Hive.openBox<AppSettings>('settings');
  } catch (e) {
    debugPrint('Hive: settings box corrupted, resetting: $e');
    await Hive.deleteBoxFromDisk('settings');
    settingsBox = await Hive.openBox<AppSettings>('settings');
  }

  try {
    logsBox = await Hive.openBox<CallLog>('call_logs');
  } catch (e) {
    debugPrint('Hive: call_logs box corrupted, resetting: $e');
    await Hive.deleteBoxFromDisk('call_logs');
    logsBox = await Hive.openBox<CallLog>('call_logs');
  }

  try {
    await Hive.openBox<Alarm>('alarms');
  } catch (e) {
    debugPrint('Hive: alarms box corrupted, resetting: $e');
    await Hive.deleteBoxFromDisk('alarms');
    await Hive.openBox<Alarm>('alarms');
  }

  // Clear any old mock call logs if they exist
  await logsBox.delete('log_1');
  await logsBox.delete('log_2');
  await logsBox.delete('log_3');
  await logsBox.delete('log_4');

  // Seed default settings if empty
  if (settingsBox.isEmpty) {
    await settingsBox.add(AppSettings(
      adminPin: '',
      language: 'en',
      voiceEnabled: true,
      sosLocationShare: false,
      fingerprintEnabled: false,
    ));
  }

  // Seed default contacts if empty
  if (contactsBox.isEmpty) {
    await contactsBox.putAll({
      '1': Contact(
        id: '1',
        name: "Santhosh",
        phoneNumber: "+919876543210",
        whatsappNumber: "+919876543210",
        positionIndex: 0,
      ),
      '2': Contact(
        id: '2',
        name: "Priya",
        phoneNumber: "+919123456789",
        whatsappNumber: "+919123456789",
        positionIndex: 1,
      ),
      '3': Contact(
        id: '3',
        name: "Ravi",
        phoneNumber: "+918765432100",
        whatsappNumber: "+918765432100",
        positionIndex: 2,
      ),
      '4': Contact(
        id: '4',
        name: "Amma",
        phoneNumber: "+917654321098",
        whatsappNumber: "+917654321098",
        positionIndex: 3,
      ),
    });
  }

  final container = ProviderContainer();

  // Initialize SystemCallService immediately
  container.read(systemCallServiceProvider);

  // Initialize FirebaseSyncService immediately to listen to changes
  container.read(firebaseSyncServiceProvider);

  // Run color migration to self-heal legacy contact colors
  await container.read(contactRepositoryProvider).runColorMigration();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );

  // Initialize TTS in the background so startup is instantaneous and engine is pre-warmed
  Future.microtask(() async {
    try {
      final ttsService = container.read(ttsServiceProvider);
      final settings = settingsBox.isNotEmpty ? settingsBox.values.first : null;
      final lang = settings?.language ?? 'en';
      await ttsService.init(languageCode: lang);
    } catch (e) {
      debugPrint('Error initializing TTS asynchronously: $e');
    }
  });

  WidgetsBinding.instance.addPostFrameCallback((_) {
    stopwatch.stop();
    debugPrint('App cold launch to first frame: ${stopwatch.elapsedMilliseconds}ms');
  });
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAccentColor = ref.watch(dynamicAccentColorProvider);
    return MaterialApp(
      title: 'EasyConnect',
      navigatorKey: navigatorKey,
      theme: AppTheme.getThemeData(activeAccentColor),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return SystemCallOverlayWrapper(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

class SystemCallOverlayWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const SystemCallOverlayWrapper({super.key, required this.child});

  @override
  ConsumerState<SystemCallOverlayWrapper> createState() => _SystemCallOverlayWrapperState();
}

class _SystemCallOverlayWrapperState extends ConsumerState<SystemCallOverlayWrapper> with WidgetsBindingObserver {
  bool _showIncomingCallScreen = false;
  String _incomingCallerNumber = '';
  Timer? _alarmTimer;
  String _lastTriggeredAlarmMinute = '';

  static const MethodChannel _channel = MethodChannel('com.easyconnect.app/calling');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPushCallScreen();
    });
    _initAlarmCheckLoop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("DEBUG: App resumed. Re-checking system call status...");
      ref.read(systemCallServiceProvider).init().then((_) {
        _checkAndPushCallScreen();
      });
    }
  }

  void _checkAndPushCallScreen() {
    if (!mounted) return;
    final next = ref.read(systemCallProvider);
    if (next != null && !next.isDisconnected) {
      if (next.isIncoming && next.rawState == 2) {
        // Incoming ringing — show the pre-built IncomingCallScreen via Offstage
        if (!_showIncomingCallScreen) {
          setState(() {
            _showIncomingCallScreen = true;
            _incomingCallerNumber = next.number;
          });
        }
      } else {
        // Outgoing or already connected — use Navigator push
        final isCallingActive = ref.read(isCallingScreenActiveProvider);
        if (!isCallingActive) {
          _pushCallingScreen(next);
        }
      }
    }
  }

  void _handleAcceptIncoming() {
    // Accept the call via native Android
    _channel.invokeMethod('acceptSystemCall');
    
    // Hide incoming screen and push to the ongoing CallingScreen
    setState(() {
      _showIncomingCallScreen = false;
    });

    final next = ref.read(systemCallProvider);
    if (next != null) {
      _pushCallingScreen(next);
    }
  }

  void _handleDeclineIncoming() {
    // Decline the call via native Android
    _channel.invokeMethod('hangUpSystemCall');
    
    // Hide incoming screen
    setState(() {
      _showIncomingCallScreen = false;
    });
  }

  void _pushCallingScreen(SystemCallState callState) {
    ref.read(isCallingScreenActiveProvider.notifier).state = true;
    final contactsBox = Hive.box<Contact>('contacts');
    Contact contactToCall;
    final cleanNumber = callState.number.replaceAll(RegExp(r'\D'), '');
    try {
      contactToCall = contactsBox.values.firstWhere(
        (c) {
          final cleanC = c.phoneNumber.replaceAll(RegExp(r'\D'), '');
          return cleanC.isNotEmpty && cleanNumber.isNotEmpty && (cleanC.endsWith(cleanNumber) || cleanNumber.endsWith(cleanC));
        },
      );
    } catch (_) {
      contactToCall = Contact(
        id: 'temp',
        name: callState.number,
        phoneNumber: callState.number,
        whatsappNumber: '',
        positionIndex: 0,
      );
    }

    navigatorKey.currentState?.push(PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => CallingScreen(
        contact: contactToCall,
        initialState: callState.isIncoming ? CallingState.incoming : CallingState.outgoing,
        isSystemCall: true,
      ),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ));
  }

  Future<void> _logMissedCallAndSaveSettings(String callerNumber) async {
    final contactsBox = Hive.isBoxOpen('contacts') ? Hive.box<Contact>('contacts') : await Hive.openBox<Contact>('contacts');
    final cleanNumber = callerNumber.replaceAll(RegExp(r'\D'), '');
    Contact? matchedContact;
    try {
      matchedContact = contactsBox.values.firstWhere(
        (c) {
          final cleanC = c.phoneNumber.replaceAll(RegExp(r'\D'), '');
          return cleanC.isNotEmpty && cleanNumber.isNotEmpty && (cleanC.endsWith(cleanNumber) || cleanNumber.endsWith(cleanC));
        },
      );
    } catch (_) {
      // No contact found
    }

    final name = matchedContact?.name ?? callerNumber;
    final phoneNumber = matchedContact?.phoneNumber ?? callerNumber;

    // 1. Log the missed call in CallLogRepository
    await ref.read(callLogRepositoryProvider).addLog(name, phoneNumber, 'missed');

    // 2. If it is a matched contact, add their ID to unreadMissedCallContactIds in AppSettings
    if (matchedContact != null) {
      final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : await Hive.openBox<AppSettings>('settings');
      if (settingsBox.isNotEmpty) {
        final settings = settingsBox.values.first;
        final currentMissed = List<String>.from(settings.unreadMissedCallContactIds ?? []);
        if (!currentMissed.contains(matchedContact.id)) {
          currentMissed.add(matchedContact.id);
          settings.unreadMissedCallContactIds = currentMissed;
          await settings.save();
          ref.invalidate(settingsProvider);
        }
      }
    }
  }

  void _initAlarmCheckLoop() {
    _alarmTimer?.cancel();
    _alarmTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _checkAlarms();
    });
  }

  Future<void> _checkAlarms() async {
    if (!mounted) return;
    
    final now = DateTime.now();
    final String currentMinuteStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    
    if (_lastTriggeredAlarmMinute == currentMinuteStr) return;
    
    final activeCall = ref.read(systemCallProvider);
    if (activeCall != null && !activeCall.isDisconnected) {
      return; 
    }
    
    final Box<Alarm> alarmsBox = Hive.isBoxOpen('alarms') ? Hive.box<Alarm>('alarms') : await Hive.openBox<Alarm>('alarms');
    if (alarmsBox.isEmpty) return;

    final int currentWeekday = now.weekday; // 1 = Monday, 7 = Sunday
    
    for (final alarm in alarmsBox.values) {
      if (!alarm.isEnabled) continue;
      
      if (alarm.time == currentMinuteStr) {
        if (alarm.days.isEmpty || alarm.days.contains(currentWeekday)) {
          _lastTriggeredAlarmMinute = currentMinuteStr;
          _triggerAlarmScreen(alarm);
          break;
        }
      }
    }
  }

  void _triggerAlarmScreen(Alarm alarm) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => AlarmRingScreen(alarm: alarm),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SystemCallState?>(systemCallProvider, (previous, next) {
      if (next != null) {
        if (next.isDisconnected || next.rawState == 7 || next.rawState == 10) {
          // Check if this was an unanswered incoming call (missed call)
          if (previous != null && previous.isIncoming && previous.rawState == 2) {
            _logMissedCallAndSaveSettings(previous.number);
          }
          // Hide incoming call screen if visible
          if (_showIncomingCallScreen) {
            setState(() {
              _showIncomingCallScreen = false;
            });
          }
          // The CallingScreen itself handles the smooth delayed pop and clearing of systemCallProvider.
          // We provide a safety fallback here after a 2-second delay to guarantee cleanup.
          Future.delayed(const Duration(milliseconds: 2000), () {
            if (!mounted) return;
            if (ref.read(systemCallProvider) != null) {
              navigatorKey.currentState?.popUntil((route) => route.isFirst);
              ref.read(systemCallProvider.notifier).clear();
            }
          });
        } else if (next.isIncoming && next.rawState == 2) {
          // Incoming ringing state — show the pre-built IncomingCallScreen
          if (!_showIncomingCallScreen) {
            setState(() {
              _showIncomingCallScreen = true;
              _incomingCallerNumber = next.number;
            });
          }
        } else {
          // If we were showing incoming screen and call state changed (e.g. user answered via notification)
          if (_showIncomingCallScreen) {
            setState(() {
              _showIncomingCallScreen = false;
            });
          }
          // If CallingScreen is already active, do NOT push it again!
          final isCallingActive = ref.read(isCallingScreenActiveProvider);
          if (isCallingActive) {
            debugPrint("DEBUG: CallingScreen is already active, skipping duplicate push on state update.");
            return;
          }
          _pushCallingScreen(next);
        }
      }
    });

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          // Pre-built IncomingCallScreen — shown/hidden to avoid
          // Navigator push delay and widget tree build time during ringing
          if (_showIncomingCallScreen)
            Positioned.fill(
              child: IncomingCallScreen(
                callerNumber: _incomingCallerNumber,
                onAccept: _handleAcceptIncoming,
                onDecline: _handleDeclineIncoming,
              ),
            ),
        ],
      ),
    );
  }
}
