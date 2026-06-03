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
import 'package:easyconnect/features/calling/providers/is_calling_active_provider.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> _preWarmPermissionsAndAudio() async {
  try {
    final statuses = await Future.wait([
      Permission.phone.status,
      Permission.sms.status,
      Permission.contacts.status,
      Permission.microphone.status,
      Permission.notification.status,
    ]);

    if (statuses.any((status) => !status.isGranted)) {
      await [
        Permission.phone,
        Permission.sms,
        Permission.contacts,
        Permission.microphone,
        Permission.notification,
      ].request();
    }
  } catch (e) {
    debugPrint('Error in pre-warming permissions and audio: $e');
  }
}

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

  // Pre-warm permissions and system services asynchronously
  _preWarmPermissionsAndAudio();

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

  // Open boxes
  final contactsBox = await Hive.openBox<Contact>('contacts');
  final settingsBox = await Hive.openBox<AppSettings>('settings');
  final logsBox = await Hive.openBox<CallLog>('call_logs');

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
      await ttsService.init();
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

  static const MethodChannel _channel = MethodChannel('com.easyconnect.app/calling');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPushCallScreen();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  @override
  Widget build(BuildContext context) {
    ref.listen<SystemCallState?>(systemCallProvider, (previous, next) {
      if (next != null) {
        if (next.isDisconnected) {
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
