import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/contacts/widgets/contact_card.dart';
import 'package:easyconnect/features/voice_message/widgets/recording_overlay.dart';
import 'package:easyconnect/features/settings/screens/admin_hub_screen.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/features/sos/services/sos_service.dart';
import 'package:easyconnect/services/connectivity_service.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/calling/models/call_log_model.dart';
import 'package:easyconnect/features/calling/repositories/call_log_repository.dart';
import 'package:easyconnect/features/calling/services/audio_call_service.dart';
import 'package:easyconnect/services/system_status_service.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easyconnect/features/wellness/widgets/wellness_check_in_dialog.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0; // Tab 0: Home (Contacts), Tab 1: Keypad, Tab 2: Logs
  String _keypadNumber = '';
  bool _overlayPermissionMissing = false;
  bool _isEditingGrid = false; // Grid reordering edit mode toggler
  late final PageController _pageController;
  Timer? _clockTimer;

  Color get _activeAccentColor => ref.watch(dynamicAccentColorProvider);

  DateTime _lastInteractionTime = DateTime.now();
  Timer? _wellnessInactivityTimer;
  bool _isWellnessCheckShowing = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _checkOverlayPermission();
    _initKioskModeOnStartup();
    _checkMissedCallsOnStartup();
    _initWellnessTimer();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _wellnessInactivityTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _initKioskModeOnStartup() async {
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    final isKiosk = settingsBox != null && settingsBox.isNotEmpty && settingsBox.values.first.activeIsKioskModeEnabled;
    if (isKiosk) {
      await Future.delayed(const Duration(milliseconds: 500));
      await ref.read(systemCallServiceProvider).startKioskMode();
    }
  }

  Future<void> _checkMissedCallsOnStartup() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    if (settingsBox == null || settingsBox.isEmpty) return;
    final settings = settingsBox.values.first;
    final missedIds = settings.activeUnreadMissedCallContactIds;
    if (missedIds.isNotEmpty) {
      final contactsBox = Hive.isBoxOpen('contacts') ? Hive.box<Contact>('contacts') : null;
      if (contactsBox == null) return;
      
      final names = <String>[];
      for (final id in missedIds) {
        final contact = contactsBox.get(id);
        if (contact != null) {
          names.add(contact.name);
        }
      }
      
      if (names.isNotEmpty) {
        final lang = settings.language;
        String alertMsg = '';
        if (lang == 'te') {
          alertMsg = "మీకు ${names.join(', ')} నుండి మిస్డ్ కాల్ ఉంది. వారి ఫోటోను నొక్కి తిరిగి కాల్ చేయండి.";
        } else if (lang == 'hi') {
          alertMsg = "आपको ${names.join(', ')} से मिस्ड कॉल आया है। वापस कॉल करने के लिए उनकी फोटो पर टैप करें।";
        } else {
          alertMsg = "You have a missed call from ${names.join(', ')}. Tap their photo to call them back.";
        }
        await ref.read(ttsServiceProvider).speak(alertMsg, forceLanguage: lang);
      }
    }
  }

  void _updateInteractionTime() {
    _lastInteractionTime = DateTime.now();
  }

  void _initWellnessTimer() {
    _wellnessInactivityTimer?.cancel();
    _wellnessInactivityTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkWellnessInactivity();
    });
  }

  Future<void> _checkWellnessInactivity() async {
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    if (settingsBox == null || settingsBox.isEmpty) return;
    final settings = settingsBox.values.first;

    if (!settings.activeWellnessCheckEnabled) return;
    if (_isWellnessCheckShowing) return;

    final now = DateTime.now();
    if (now.hour < 8 || now.hour >= 21) return;

    final diff = now.difference(_lastInteractionTime);
    final limit = Duration(hours: settings.activeWellnessIntervalHours);
    if (diff >= limit) {
      setState(() {
        _isWellnessCheckShowing = true;
      });
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => WellnessCheckInDialog(
            onCheckedIn: () {
              setState(() {
                _lastInteractionTime = DateTime.now();
                _isWellnessCheckShowing = false;
              });
            },
          ),
        );
      }
    }
  }

  Future<void> _announceTelemetry() async {
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    final lang = settingsBox != null && settingsBox.isNotEmpty ? settingsBox.values.first.language : 'en';
    final status = ref.read(systemStatusProvider);
    final batteryLevel = status.batteryLevel;
    final isCharging = status.isCharging;
    final simState = status.simState;
    final signalStrength = status.signalStrength;

    String msg = '';
    if (lang == 'te') {
      if (isCharging) {
        msg = "బ్యాటరీ ఛార్జ్ అవుతోంది, $batteryLevel శాతం ఉంది. ";
      } else {
        msg = "బ్యాటరీ $batteryLevel శాతం ఉంది. ";
      }

      if (simState != 'ready') {
        msg += "సిమ్ కార్డ్ సమస్య ఉంది.";
      } else {
        if (signalStrength == 'good') {
          msg += "సిగ్నల్ బాగుంది.";
        } else if (signalStrength == 'weak') {
          msg += "సిగ్నల్ తక్కువగా ఉంది.";
        } else {
          msg += "సిగ్నల్ లేదు.";
        }
      }
    } else if (lang == 'hi') {
      if (isCharging) {
        msg = "बैटरी चार्ज हो रही है, $batteryLevel प्रतिशत है। ";
      } else {
        msg = "बैटरी $batteryLevel प्रतिशत है। ";
      }

      if (simState != 'ready') {
        msg += "सिम कार्ड की समस्या है।";
      } else {
        if (signalStrength == 'good') {
          msg += "सिग्नल अच्छा है।";
        } else if (signalStrength == 'weak') {
          msg += "सिग्नल कमजोर है।";
        } else {
          msg += "सिग्नल नहीं है।";
        }
      }
    } else {
      if (isCharging) {
        msg = "Battery is charging, it is at $batteryLevel percent. ";
      } else {
        msg = "Battery is at $batteryLevel percent. ";
      }

      if (simState != 'ready') {
        msg += "There is a SIM card issue.";
      } else {
        if (signalStrength == 'good') {
          msg += "Network signal is good.";
        } else if (signalStrength == 'weak') {
          msg += "Network signal is weak.";
        } else {
          msg += "No network signal.";
        }
      }
    }

    await ref.read(ttsServiceProvider).speak(msg, forceLanguage: lang);
  }

  void _changeTab(int index) async {
    if (_currentIndex == index) return;

    // Dynamically manage kiosk mode when transitioning to/from Settings (Tab 3)
    if (index == 3) {
      await ref.read(systemCallServiceProvider).stopKioskMode();
    } else if (_currentIndex == 3) {
      final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
      final isKiosk = settingsBox != null && settingsBox.isNotEmpty && settingsBox.values.first.activeIsKioskModeEnabled;
      if (isKiosk) {
        await ref.read(systemCallServiceProvider).startKioskMode();
      }
    }

    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _checkOverlayPermission() async {
    final service = ref.read(systemCallServiceProvider);
    final hasOverlay = await service.checkOverlayPermissions();
    if (!hasOverlay && mounted) {
      setState(() {
        _overlayPermissionMissing = true;
      });
      // Announce via TTS
      ref.read(ttsServiceProvider).speak(
        'Permission required to show incoming calls on screen.',
      );
    }

    // Proactively check and request notification permission on Android 13+ (API 33+)
    if (Platform.isAndroid) {
      try {
        final status = await Permission.notification.status;
        if (status.isDenied) {
          await Permission.notification.request();
        }
      } catch (e) {
        debugPrint('Error checking/requesting notification permission: $e');
      }
    }
  }

  Future<void> _requestOverlayAndRecheck() async {
    final service = ref.read(systemCallServiceProvider);
    await service.requestOverlayPermission();
    // The user will be taken to settings. When they return, we recheck.
    // The recheck happens via didChangeAppLifecycleState or on resume.
    Future.delayed(const Duration(seconds: 2), () async {
      final hasOverlay = await service.checkOverlayPermissions();
      if (hasOverlay && mounted) {
        setState(() {
          _overlayPermissionMissing = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final layoutMode = settingsAsync.when(
      data: (settings) => settings.activeLayoutMode,
      loading: () => 'classic',
      error: (err, stack) => 'classic',
    );
    final activeAccentColor = _activeAccentColor;

    ref.listen<SystemStatus>(systemStatusProvider, (prev, next) {
      if (next.simState != 'ready' && next.simState != prev?.simState) {
        String alert = "";
        if (next.simState == 'absent') {
          alert = "Warning: No SIM card found. Please check your SIM card tray.";
        } else if (next.simState == 'locked') {
          alert = "Warning: SIM card is locked. PIN or PUK is required.";
        } else if (next.simState == 'error') {
          alert = "Warning: SIM card error. Your SIM card is broken or disabled.";
        } else {
          alert = "Warning: SIM card disconnected.";
        }
        ref.read(ttsServiceProvider).speak(alert);
      }
    });

    final isKiosk = settingsAsync.maybeWhen(
      data: (settings) => settings.activeIsKioskModeEnabled,
      orElse: () => false,
    );

    ref.listen<DateTime?>(deviceShakeProvider, (previous, next) {
      if (next != null && next != previous) {
        _announceTelemetry();
      }
    });

    final mediaQueryData = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQueryData.copyWith(
        textScaler: mediaQueryData.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.35,
        ),
      ),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        ),
        child: PopScope(
          canPop: !isKiosk,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && isKiosk) {
            debugPrint("Back button pressed while Kiosk Mode is active. Blocked.");
          }
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Listener(
            onPointerDown: (_) {
              _updateInteractionTime();
              ref.read(ttsServiceProvider).stop();
            },
            child: Stack(
              children: [
                SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusBar(),
                // 1. Connectivity Lost Top Banner
                Consumer(
                  builder: (context, ref, child) {
                    final isConnected = ref.watch(connectivityProvider);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: !isConnected ? 36.0 : 0.0,
                      color: Colors.orange,
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: !isConnected
                          ? Text(
                              "No internet — WhatsApp features unavailable",
                              style: GoogleFonts.nunito(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14.0,
                              ),
                              textAlign: TextAlign.center,
                            )
                          : const SizedBox.shrink(),
                    );
                  }
                ),

                // 1b. Overlay Permission Warning Banner
                if (_overlayPermissionMissing)
                  GestureDetector(
                    onTap: _requestOverlayAndRecheck,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      color: const Color(0xFFDC2626),
                      width: double.infinity,
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Incoming calls won't show on screen.\nTap here to fix this!",
                              style: GoogleFonts.nunito(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.0,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "FIX",
                              style: GoogleFonts.nunito(
                                color: const Color(0xFFDC2626),
                                fontWeight: FontWeight.bold,
                                fontSize: 13.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_currentIndex == 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 14.0, bottom: 18.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left: App name and Author
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "EasyConnect",
                              style: GoogleFonts.outfit(
                                fontSize: 26.0,
                                fontWeight: FontWeight.w900,
                                color: kTextDark,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 1.0),
                            Text(
                              "by Santhoshh",
                              style: GoogleFonts.nunito(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w800,
                                color: kTextSlate.withValues(alpha: 0.95),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                        // Right: SOS and Settings gear button
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.heavyImpact();
                                ref.read(sosServiceProvider).triggerSOS(context);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 7.0),
                                decoration: BoxDecoration(
                                  gradient: kSosRedGradient,
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF2147).withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  "SOS",
                                  style: GoogleFonts.nunito(
                                    color: Colors.white,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.07 * 11.0,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                setState(() {
                                  _isEditingGrid = !_isEditingGrid;
                                });
                                final tts = ref.read(ttsServiceProvider);
                                if (_isEditingGrid) {
                                  tts.speak("Rearranging mode active. Long press and drag cards to sort.");
                                } else {
                                  tts.speak("Rearranging mode inactive.");
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 7.0),
                                decoration: BoxDecoration(
                                  color: _isEditingGrid ? activeAccentColor : activeAccentColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: _isEditingGrid
                                      ? [
                                          BoxShadow(
                                            color: activeAccentColor.withValues(alpha: 0.35),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isEditingGrid ? Icons.check : Icons.edit,
                                      color: _isEditingGrid ? Colors.white : activeAccentColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 3. Horizontal Status Card Row (Online status, Voice guide, Battery)
                Consumer(
                    builder: (context, ref, child) {
                      final systemStatus = ref.watch(systemStatusProvider);
                      final settingsAsync = ref.watch(settingsProvider);
                      final voiceEnabled = settingsAsync.when(
                        data: (settings) => settings.voiceEnabled,
                        loading: () => true,
                        error: (err, stack) => true,
                      );

                      final signalStatus = systemStatus.signalStrength;
                      final batteryLevel = systemStatus.batteryLevel;
                      final isDark = Theme.of(context).brightness == Brightness.dark;

                      Color signalBg;
                      Color signalIconColor;
                      IconData signalIcon;
                      String signalTitle;
                      String signalSubtitle;

                      if (signalStatus == 'good') {
                        signalBg = isDark ? kGreenTintDark : kGreenTintLight;
                        signalIconColor = isDark ? kGreenIconDark : kGreenIconLight;
                        signalIcon = Icons.wifi;
                        signalTitle = "Online";
                        signalSubtitle = "Safe to Call";
                      } else if (signalStatus == 'weak') {
                        signalBg = isDark ? kAmberTintDark : kAmberTintLight;
                        signalIconColor = isDark ? kAmberIconDark : kAmberIconLight;
                        signalIcon = Icons.wifi_1_bar;
                        signalTitle = "Weak Signal";
                        signalSubtitle = "Poor Connection";
                      } else {
                        signalBg = isDark ? kRedTintDark : kRedTintLight;
                        signalIconColor = isDark ? kRedIconDark : kRedIconLight;
                        signalIcon = Icons.wifi_off;
                        signalTitle = "Offline";
                        signalSubtitle = "No Signal";
                      }

                      Color batteryBg;
                      Color batteryIconColor;
                      IconData batteryIcon;
                      String batteryTitle;
                      String batterySubtitle;

                      if (batteryLevel >= 85) {
                        batteryIcon = Icons.battery_full;
                      } else if (batteryLevel >= 70) {
                        batteryIcon = Icons.battery_5_bar;
                      } else if (batteryLevel >= 50) {
                        batteryIcon = Icons.battery_4_bar;
                      } else if (batteryLevel >= 30) {
                        batteryIcon = Icons.battery_3_bar;
                      } else {
                        batteryIcon = Icons.battery_alert;
                      }

                      if (batteryLevel < 20) {
                        batteryBg = isDark ? kRedTintDark : kRedTintLight;
                        batteryIconColor = isDark ? kRedIconDark : kRedIconLight;
                        batteryTitle = "Plug In!";
                        batterySubtitle = "Battery Low";
                      } else if (batteryLevel < 50) {
                        batteryBg = isDark ? kAmberTintDark : kAmberTintLight;
                        batteryIconColor = isDark ? kAmberIconDark : kAmberIconLight;
                        batteryTitle = "Battery OK";
                        batterySubtitle = "$batteryLevel% Charged";
                      } else {
                        batteryBg = isDark ? kGreenTintDark : kGreenTintLight;
                        batteryIconColor = isDark ? kGreenIconDark : kGreenIconLight;
                        batteryTitle = "Battery OK";
                        batterySubtitle = "$batteryLevel% Charged";
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Row(
                          children: [
                            // Card 1: Online Status (Signal)
                            Expanded(
                              child: Semantics(
                                label: "Network Connection: $signalTitle. $signalSubtitle. Tap to hear status announcement.",
                                button: true,
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    _announceTelemetry();
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: _buildStatusCard(
                                    backgroundColor: signalBg,
                                    iconColor: signalIconColor,
                                    icon: signalIcon,
                                    title: signalTitle,
                                    subtitle: signalSubtitle,
                                    customVisual: _buildConnectionVisual(signalStatus, signalIconColor),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            // Card 2: Voice Guide
                            Expanded(
                              child: Semantics(
                                label: "Voice Guide. Current state is ${voiceEnabled ? 'ON' : 'OFF'}. Tap to toggle.",
                                button: true,
                                child: InkWell(
                                  onTap: () async {
                                    final box = ref.read(settingsBoxProvider);
                                    if (box.isNotEmpty) {
                                      final settings = box.values.first;
                                      final newVal = !settings.voiceEnabled;
                                      if (!newVal) {
                                        // Speak first so it isn't blocked by the check
                                        await ref.read(ttsServiceProvider).speak("Voice guide turned off");
                                      }
                                      settings.voiceEnabled = newVal;
                                      await settings.save();
                                      if (newVal) {
                                        await ref.read(ttsServiceProvider).speak("Voice guide turned on");
                                      }
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: _buildStatusCard(
                                    backgroundColor: voiceEnabled
                                        ? (isDark ? kPurpleTintDark : kPurpleTintLight)
                                        : (isDark ? kMutedBGDark : kMutedBGLight),
                                    iconColor: voiceEnabled 
                                        ? (isDark ? kPurpleIconDark : kPurpleIconLight) 
                                        : (isDark ? kTextSecondaryDark : kTextSecondaryLight),
                                    icon: voiceEnabled ? Icons.volume_up : Icons.volume_off,
                                    title: "Voice Guide",
                                    subtitle: voiceEnabled ? "ON" : "OFF",
                                    highlightSubtitle: true,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            // Card 3: Battery Level
                            Expanded(
                              child: Semantics(
                                label: "Battery is $batteryLevel percent. Status is $batteryTitle. Tap to hear status announcement.",
                                button: true,
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    _announceTelemetry();
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: _buildStatusCard(
                                    backgroundColor: batteryBg,
                                    iconColor: batteryIconColor,
                                    icon: batteryIcon,
                                    title: batteryTitle,
                                    subtitle: batterySubtitle,
                                    customVisual: _buildBatteryVisual(batteryLevel, batteryIconColor),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  ),

                const SizedBox(height: 8.0),

                // 4. Switching View: Tab 0 (Contacts Grid) vs Tab 1 (Keypad) vs Tab 2 (Call Logs Grid) vs Tab 3 (Settings Hub)
                Expanded(
                  child: RepaintBoundary(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        Consumer(
                          builder: (context, ref, child) {
                            final contactsAsync = ref.watch(contactsStreamProvider);
                            final simState = ref.watch(systemStatusProvider.select((s) => s.simState));
                            return _buildContactsView(contactsAsync, simState, layoutMode);
                          }
                        ),
                        _buildKeypadView(),
                        Consumer(
                          builder: (context, ref, child) {
                            final logsAsync = ref.watch(callLogsStreamProvider);
                            return _buildCallLogsView(logsAsync);
                          }
                        ),
                        AdminHubScreen(
                          onBack: () => _changeTab(0),
                        ),
                      ],
                    ),
                  ),
                ),

              ],
            ),
          ),

          // No redundant floating dialer button overlay

          Consumer(
            builder: (context, ref, child) {
              final overlayState = ref.watch(voiceMessageOverlayProvider);
              if (overlayState.flowState == OverlayFlowState.closed) {
                return const SizedBox.shrink();
              }
              return RecordingOverlay(overlayState: overlayState);
            }
          ),
        ],
      ),
    ),
    bottomNavigationBar: _buildBottomNavBar(context),
  ),
  ),
  ),
  );
}

  // --- SUB-VIEWS ---

  // Contacts Grid View (2 columns, spacious)
  // Contacts Grid View (2 columns, spacious)
  Widget _buildContactsView(AsyncValue<List<Contact>> contactsAsync, String simState, String layoutMode) {
    return contactsAsync.when(
      data: (contacts) {
        final showWarning = simState != 'ready';

        if (contacts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showWarning) Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: _buildSimWarningPill(simState),
                ),
                const Icon(Icons.people_outline, size: 64.0, color: Colors.grey),
                const SizedBox(height: 12.0),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    'Ask your family member to add contacts.',
                    style: TextStyle(fontSize: 16.0, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        final sortedContacts = List<Contact>.from(contacts)
          ..sort((a, b) => a.positionIndex.compareTo(b.positionIndex));

        final double screenWidth = MediaQuery.sizeOf(context).width;
        final int crossAxisCount = layoutMode == 'classic' ? 4 : (screenWidth >= 600 ? 3 : 2);

        double childAspectRatio = 0.64;
        if (layoutMode == 'classic') {
          childAspectRatio = 0.62; // Allows 2 lines of text for long names without overflow/clipping
        } else if (screenWidth < 395) {
          childAspectRatio = 0.58; // Prevents overflow on narrow devices like Redmi Note 10 (~360dp)
        } else if (screenWidth >= 600) {
          childAspectRatio = 0.78; // Better proportion for tablets
        }

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: layoutMode == 'classic' ? 16.0 : 14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showWarning) _buildSimWarningPill(simState),
              _buildClockCard(context, layoutMode),
              if (layoutMode == 'classic')
                Padding(
                  padding: const EdgeInsets.only(left: 4.0, bottom: 12.0, top: 18.0),
                  child: Text(
                    "YOUR PEOPLE",
                    style: GoogleFonts.inter(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.06 * 10.0,
                      color: Theme.of(context).brightness == Brightness.dark ? kTextSecondaryDark : kTextSecondaryLight,
                    ),
                  ),
                ),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: layoutMode == 'classic' ? 10.0 : 8.0,
                    mainAxisSpacing: layoutMode == 'classic' ? 10.0 : 8.0,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemCount: sortedContacts.length,
                  itemBuilder: (context, index) {
                    final contact = sortedContacts[index];
                    final card = ContactCard(
                      contact: contact,
                      isEditing: _isEditingGrid,
                    );

                    if (!_isEditingGrid) {
                      return card;
                    }

                    return DragTarget<Contact>(
                      onWillAcceptWithDetails: (details) => details.data.id != contact.id,
                      onAcceptWithDetails: (details) async {
                        final draggedContact = details.data;
                        final oldIndex = sortedContacts.indexWhere((c) => c.id == draggedContact.id);
                        if (oldIndex != -1) {
                          HapticFeedback.mediumImpact();
                          setState(() {
                            final item = sortedContacts.removeAt(oldIndex);
                            sortedContacts.insert(index, item);
                          });
                          final orderedIds = sortedContacts.map((c) => c.id).toList();
                          await ref.read(contactRepositoryProvider).reorderContacts(orderedIds);
                        }
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isHovered = candidateData.isNotEmpty;
                        return LongPressDraggable<Contact>(
                          data: contact,
                          feedback: Material(
                            color: Colors.transparent,
                            child: Transform.scale(
                              scale: 1.05,
                              child: Opacity(
                                opacity: 0.85,
                                child: SizedBox(
                                  width: (screenWidth - 32 - (crossAxisCount - 1) * (layoutMode == 'classic' ? 10 : 12)) / crossAxisCount,
                                  child: ContactCard(
                                    contact: contact,
                                    isEditing: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.25,
                            child: card,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: isHovered
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF5C5BE8).withValues(alpha: 0.2),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : [],
                            ),
                            child: card,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text('Error: $error', style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  // Call History List View (Spacious scrolling list with callback buttons)
  Widget _buildCallLogsView(AsyncValue<List<CallLog>> logsAsync) {
    return logsAsync.when(
      data: (logs) {
        if (logs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off, size: 64.0, color: Colors.grey[400]),
                const SizedBox(height: 12.0),
                const Text(
                  'No call logs yet.',
                  style: TextStyle(fontSize: 18.0, color: kTextSlate, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildCallLogListItem(log);
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text('Error: $error', style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  // --- CALL LOG ITEM DESIGN ---
  Widget _buildFallbackAvatar(String name, Color contactColor) {
    final firstLetter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final tints = _getContactTints(contactColor);
    return Container(
      color: tints['bg'],
      alignment: Alignment.center,
      child: Text(
        firstLetter,
        style: GoogleFonts.inter(
          fontSize: 14.0,
          fontWeight: FontWeight.w500,
          color: tints['text'],
        ),
      ),
    );
  }

  Widget _buildCallLogListItem(CallLog log) {
    Color accentColor;
    Color badgeBgColor;
    Color badgeTextColor;
    IconData statusIcon;
    String statusLabel;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (log.type) {
      case 'missed':
        accentColor = kAccentRed;
        badgeBgColor = isDark ? kRedTintDark : kRedTintLight;
        badgeTextColor = isDark ? kRedIconDark : kRedIconLight;
        statusIcon = Icons.call_missed;
        statusLabel = "Missed";
        break;
      case 'dialed':
        accentColor = kAccentGreen;
        badgeBgColor = isDark ? kGreenTintDark : kGreenTintLight;
        badgeTextColor = isDark ? kGreenIconDark : kGreenIconLight;
        statusIcon = Icons.call_made;
        statusLabel = "Dialed";
        break;
      case 'incoming':
      default:
        accentColor = kAccentBlue;
        badgeBgColor = isDark ? kBlueTintDark : kBlueTintLight;
        badgeTextColor = isDark ? kBlueIconDark : kBlueIconLight;
        statusIcon = Icons.call_received;
        statusLabel = "Received";
        break;
    }

    Contact? matchedContact;
    final contactsMap = ref.watch(contactsMapProvider);
    final cleanLogPhone = log.phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanLogPhone.isNotEmpty && contactsMap.containsKey(cleanLogPhone)) {
      matchedContact = contactsMap[cleanLogPhone];
    } else {
      final cleanName = log.name.toLowerCase().trim();
      if (contactsMap.containsKey(cleanName)) {
        matchedContact = contactsMap[cleanName];
      }
    }

    final hasPhoto = matchedContact?.photoPath != null && matchedContact!.photoPath!.isNotEmpty;
    final contactColor = matchedContact != null 
        ? getAccentColor(matchedContact.colorTheme) 
        : _getContactColorByName(log.name);

    final avatarWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: ShapeDecoration(
            color: isDark ? kSurfaceDark : kSurfaceLight,
            shape: ContinuousRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: ClipPath(
            clipper: ShapeBorderClipper(
              shape: ContinuousRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: hasPhoto
                ? Image.file(
                    File(matchedContact.photoPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _buildFallbackAvatar(log.name, contactColor),
                  )
                : _buildFallbackAvatar(log.name, contactColor),
          ),
        ),
        // Status Badge Overlay
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isDark ? kSurfaceDark : kSurfaceLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? kBorderDark : kBorderLight,
                width: 0.5,
              ),
            ),
            child: Center(
              child: Icon(
                statusIcon,
                color: accentColor,
                size: 13,
              ),
            ),
          ),
        ),
      ],
    );

    final formattedTime = _formatTime(log.timestamp);

    return RepaintBoundary(
      child: Semantics(
        label: "Call log with ${log.name}, $statusLabel call, $formattedTime. Tap phone button on the right to call back.",
        button: true,
        excludeSemantics: true,
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Avatar
              avatarWidget,
              const SizedBox(width: 16.0),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      log.name,
                      style: GoogleFonts.inter(
                        fontSize: 18.0,
                        fontWeight: FontWeight.w500,
                        color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4.0),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeBgColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusLabel,
                            style: GoogleFonts.inter(
                              fontSize: 11.0,
                              fontWeight: FontWeight.w500,
                              color: badgeTextColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          formattedTime,
                          style: GoogleFonts.inter(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w400,
                            color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Callback Button
              Semantics(
                label: "Call back ${log.name}",
                button: true,
                child: InkWell(
                  onTap: () {
                    final contactToCall = matchedContact ?? Contact(
                      id: log.id,
                      name: log.name,
                      phoneNumber: log.phoneNumber,
                      whatsappNumber: '',
                      positionIndex: 0,
                    );
                    ref.read(audioCallServiceProvider).makeCall(context, contactToCall);
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: kCallGreen,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.phone,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inMinutes < 60) {
      if (difference.inMinutes <= 0) return "Just now";
      return "${difference.inMinutes}m ago";
    } else if (difference.inHours < 24) {
      return "${difference.inHours}h ago";
    } else {
      return "${difference.inDays}d ago";
    }
  }

  // --- BOTTOM NAV BAR (Locked, Height 60px) ---
  Widget _buildBottomNavBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? kSurfaceDark : kSurfaceLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    
    return Container(
      height: 60.0,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: borderColor, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            icon: Icons.home,
            label: "Home",
            isSelected: _currentIndex == 0,
            onTap: () {
              _changeTab(0);
              ref.read(ttsServiceProvider).speak("Showing Contacts Screen");
            },
          ),
          _buildNavItem(
            icon: Icons.dialpad,
            label: "Keypad",
            isSelected: _currentIndex == 1,
            onTap: () {
              _changeTab(1);
              ref.read(ttsServiceProvider).speak("Showing Keypad Dialer");
            },
          ),
          _buildNavItem(
            icon: Icons.history,
            label: "Logs",
            isSelected: _currentIndex == 2,
            onTap: () {
              _changeTab(2);
              ref.read(ttsServiceProvider).speak("Showing Call History");
            },
          ),
          _buildNavItem(
            icon: Icons.settings,
            label: "Settings",
            isSelected: _currentIndex == 3,
            onTap: () {
              _changeTab(3);
              ref.read(ttsServiceProvider).speak("Showing Settings");
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = _activeAccentColor;
    final inactiveColor = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final tintColor = isDark ? kPurpleTintDark : kPurpleTintLight;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
              decoration: BoxDecoration(
                color: isSelected ? tintColor : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: isSelected ? activeColor : inactiveColor,
                    size: 20,
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 6.0),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w600,
                        color: activeColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildSimWarningPill(String simState) {
    String warningMessage;
    IconData icon;

    switch (simState) {
      case 'absent':
        warningMessage = "NO SIM CARD FOUND (Check card tray)";
        icon = Icons.sim_card_alert;
        break;
      case 'locked':
        warningMessage = "SIM CARD LOCKED (PIN/PUK needed)";
        icon = Icons.lock;
        break;
      case 'error':
        warningMessage = "SIM CARD ERROR (Broken or disabled)";
        icon = Icons.error;
        break;
      default:
        warningMessage = "SIM CARD DISCONNECTED";
        icon = Icons.sim_card_alert;
        break;
    }

    final String ttsInstruction = "Warning. $warningMessage. Please ask your family to check your phone SIM card.";

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Semantics(
        label: "$warningMessage. Tap to hear instructions.",
        button: true,
        child: InkWell(
          onTap: () {
            HapticFeedback.heavyImpact();
            ref.read(ttsServiceProvider).speak(ttsInstruction);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            decoration: BoxDecoration(
              color: kSosRed,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: kSosRed.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    warningMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.volume_up,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required Color backgroundColor,
    required Color iconColor,
    required IconData icon,
    required String title,
    required String subtitle,
    bool highlightSubtitle = false,
    Widget? customVisual,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (customVisual != null) ...[
            customVisual,
            const SizedBox(height: 6.0),
          ] else ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(isDark ? 0.08 : 1.0),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(height: 6.0),
          ],
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
              color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2.0),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 9.0,
              fontWeight: FontWeight.w500,
              color: highlightSubtitle ? iconColor : (isDark ? kTextSecondaryDark : kTextSecondaryLight),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionVisual(String status, Color color) {
    IconData icon;
    if (status == 'good') {
      icon = Icons.check_circle_rounded;
    } else if (status == 'weak') {
      icon = Icons.warning_amber_rounded;
    } else {
      icon = Icons.cancel_rounded;
    }
    
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.08 : 1.0),
        border: Border.all(
          color: color.withOpacity(0.4),
          width: 0.5,
        ),
      ),
      child: Center(
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Widget _buildBatteryVisual(int level, Color color) {
    final fillPercent = (level / 100.0).clamp(0.0, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cellBorderColor = (isDark ? kTextPrimaryDark : kTextPrimaryLight).withOpacity(0.4);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 16,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5.0),
            border: Border.all(
              color: cellBorderColor,
              width: 1.5,
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 30.0 * fillPercent,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3.0),
                color: color,
              ),
            ),
          ),
        ),
        Container(
          width: 2,
          height: 6,
          decoration: BoxDecoration(
            color: cellBorderColor,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(1),
              bottomRight: Radius.circular(1),
            ),
          ),
        ),
      ],
    );
  }


  // --- KEYPAD VIEWS & LOGIC ---
  Widget _buildKeypadView() {
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value;
    final String currentLang = settings?.language ?? 'en';
    final bool voiceEnabled = settings?.voiceEnabled ?? true;

    void onKeyPressed(String digit) {
      if (_keypadNumber.length >= 15) return;
      HapticFeedback.lightImpact();
      setState(() {
        _keypadNumber += digit;
      });
      if (voiceEnabled) {
        _speakDigit(digit, currentLang);
      }
    }

    void onBackspacePressed() {
      if (_keypadNumber.isEmpty) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _keypadNumber = _keypadNumber.substring(0, _keypadNumber.length - 1);
      });
      if (voiceEnabled) {
        ref.read(ttsServiceProvider).speak(
          currentLang == 'hi' ? 'हटाया गया' : currentLang == 'te' ? 'తొలగించబడింది' : 'deleted',
        );
      }
    }

    void onBackspaceLongPressed() {
      if (_keypadNumber.isEmpty) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _keypadNumber = '';
      });
      if (voiceEnabled) {
        ref.read(ttsServiceProvider).speak(
          currentLang == 'hi' ? 'साफ़ किया गया' : currentLang == 'te' ? 'అన్నీ తొలగించబడ్డాయి' : 'cleared',
        );
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final displayHeight = 60.0;
        
        return Column(
          children: [
            // 1. Digital Display area
            Container(
              height: displayHeight,
              margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              decoration: BoxDecoration(
                color: isDark ? kMutedBGDark : kMutedBGLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? kBorderDark : kBorderLight,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Semantics(
                        label: _keypadNumber.isEmpty
                            ? (currentLang == 'hi' ? 'नंबर दर्ज करें' : currentLang == 'te' ? 'నంబర్ నమోదు చేయండి' : 'Enter number to call')
                            : _keypadNumber.split('').join(', '),
                        excludeSemantics: true,
                        child: Text(
                          _keypadNumber.isEmpty
                              ? (currentLang == 'hi' ? 'नंबर दर्ज करें' : currentLang == 'te' ? 'నంబర్ నమోదు చేయండి' : 'Enter number to call')
                              : _keypadNumber,
                          style: _keypadNumber.isEmpty
                              ? GoogleFonts.inter(
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? kTextSecondaryDark : kTextSecondaryLight,
                                )
                              : GoogleFonts.inter(
                                  fontSize: 22.0,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                                  letterSpacing: 2.0,
                                ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                  if (_keypadNumber.isNotEmpty)
                    GestureDetector(
                      onTap: onBackspacePressed,
                      onLongPress: onBackspaceLongPressed,
                      child: Container(
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: isDark ? kSurfaceDark : kSurfaceLight,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? kBorderDark : kBorderLight,
                            width: 0.5,
                          ),
                        ),
                        child: Icon(
                          Icons.backspace_outlined,
                          color: isDark ? kTextPrimaryDark : kTextPrimaryLight,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const Spacer(flex: 2),

            // 2. Keypad grid
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildDialKey('1', '', onKeyPressed),
                      const SizedBox(width: 10.0),
                      _buildDialKey('2', 'ABC', onKeyPressed),
                      const SizedBox(width: 10.0),
                      _buildDialKey('3', 'DEF', onKeyPressed),
                    ],
                  ),
                  const SizedBox(height: 10.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildDialKey('4', 'GHI', onKeyPressed),
                      const SizedBox(width: 10.0),
                      _buildDialKey('5', 'JKL', onKeyPressed),
                      const SizedBox(width: 10.0),
                      _buildDialKey('6', 'MNO', onKeyPressed),
                    ],
                  ),
                  const SizedBox(height: 10.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildDialKey('7', 'PQRS', onKeyPressed),
                      const SizedBox(width: 10.0),
                      _buildDialKey('8', 'TUV', onKeyPressed),
                      const SizedBox(width: 10.0),
                      _buildDialKey('9', 'WXYZ', onKeyPressed),
                    ],
                  ),
                  const SizedBox(height: 10.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildDialKey('*', '', onKeyPressed),
                      const SizedBox(width: 10.0),
                      _buildDialKey('0', '+', onKeyPressed, onLongPress: () {
                        HapticFeedback.lightImpact();
                        onKeyPressed('+');
                      }),
                      const SizedBox(width: 10.0),
                      _buildDialKey('#', '', onKeyPressed),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(flex: 3),

            // 3. Call Button / Actions Row
            Padding(
              padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 20.0, top: 10.0),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        if (_keypadNumber.trim().isEmpty) {
                          if (voiceEnabled) {
                            ref.read(ttsServiceProvider).speak(
                              currentLang == 'hi'
                                  ? 'कृपया पहले फ़ोन नंबर दर्ज करें।'
                                  : currentLang == 'te'
                                      ? 'దయచేసి ముందుగా ఫోన్ నంబర్ నమోదు చేయండి.'
                                      : 'Please enter a phone number first.',
                            );
                          }
                          return;
                        }
                        final contact = Contact(
                          id: 'dial',
                          name: _keypadNumber,
                          phoneNumber: _keypadNumber,
                          whatsappNumber: '',
                          positionIndex: 0,
                        );
                        ref.read(audioCallServiceProvider).makeCall(context, contact);
                      },
                      child: Container(
                        height: 58,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D9E75),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.phone,
                              color: Colors.white,
                              size: 19,
                            ),
                            const SizedBox(width: 8.0),
                            Text(
                              currentLang == 'hi'
                                  ? 'कॉल करें'
                                  : currentLang == 'te'
                                      ? 'కాల్ చేయండి'
                                      : 'Call Now',
                              style: GoogleFonts.inter(
                                fontSize: 15.0,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDialKey(
    String digit,
    String letters,
    void Function(String) onTap, {
    VoidCallback? onLongPress,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? kTextPrimaryDark : kTextPrimaryLight;
    final secondaryColor = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    final borderColor = isDark ? kBorderDark : kBorderLight;
    final bgColor = isDark ? kSurfaceDark : kSurfaceLight;

    return Expanded(
      child: Semantics(
        label: "Keypad button $digit ${letters.isNotEmpty ? letters : ''}",
        button: true,
        excludeSemantics: true,
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            margin: const EdgeInsets.all(2.0),
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: borderColor,
                width: 0.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onTap(digit),
                onLongPress: onLongPress,
                customBorder: const CircleBorder(),
                splashColor: _activeAccentColor.withOpacity(0.1),
                highlightColor: _activeAccentColor.withOpacity(0.05),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      digit,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                        color: primaryColor,
                        height: 1.0,
                      ),
                    ),
                    if (letters.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        letters,
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          fontWeight: FontWeight.w500,
                          color: secondaryColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }


  void _speakDigit(String digit, String language) {
    final tts = ref.read(ttsServiceProvider);
    String speakText = '';

    // Map digits to words in en, hi, te
    final enMap = {
      '1': 'One',
      '2': 'Two',
      '3': 'Three',
      '4': 'Four',
      '5': 'Five',
      '6': 'Six',
      '7': 'Seven',
      '8': 'Eight',
      '9': 'Nine',
      '0': 'Zero',
      '*': 'Star',
      '#': 'Hash',
      '+': 'Plus',
    };
    final hiMap = {
      '1': 'एक',
      '2': 'दो',
      '3': 'तीन',
      '4': 'चार',
      '5': 'पाँच',
      '6': 'छह',
      '7': 'सात',
      '8': 'आठ',
      '9': 'नौ',
      '0': 'शून्य',
      '*': 'स्टार',
      '#': 'हैश',
      '+': 'प्लस',
    };
    final teMap = {
      '1': 'ఒకటి',
      '2': 'రెండు',
      '3': 'మూడు',
      '4': 'నాలుగు',
      '5': 'ఐదు',
      '6': 'ఆరు',
      '7': 'ఏడు',
      '8': 'ఎనిమిది',
      '9': 'తొమ్మిది',
      '0': 'సున్నా',
      '*': 'స్టార్',
      '#': 'హాష్',
      '+': 'ప్లస్',
    };

    if (language == 'hi') {
      speakText = hiMap[digit] ?? digit;
    } else if (language == 'te') {
      speakText = teMap[digit] ?? digit;
    } else {
      speakText = enMap[digit] ?? digit;
    }

    tts.speak(speakText);
  }

  String _getTeluguDateTimeSpeech() {
    final now = DateTime.now();
    
    // Period of day in Telugu
    String period = 'ఉదయం'; // Morning
    if (now.hour >= 12 && now.hour < 16) {
      period = 'మధ్యాహ్నం'; // Afternoon
    } else if (now.hour >= 16 && now.hour < 20) {
      period = 'సాయంత్రం'; // Evening
    } else if (now.hour >= 20 || now.hour < 4) {
      period = 'రాత్రి'; // Night
    }
    
    int hour = now.hour % 12;
    if (hour == 0) hour = 12;
    
    int minute = now.minute;
    String timeStr = '';
    if (minute == 0) {
      timeStr = 'సమయం $period $hour గంటలు.';
    } else {
      timeStr = 'సమయం $period $hour గంటల $minute నిమిషాలు.';
    }
    
    const weekdays = {
      1: 'సోమవారం',
      2: 'మంగళవారం',
      3: 'బుధవారం',
      4: 'గురువారం',
      5: 'శుక్రవారం',
      6: 'శనివారం',
      7: 'ఆదివారం',
    };
    String dayName = weekdays[now.weekday] ?? '';
    
    const months = {
      1: 'జనవరి',
      2: 'ఫిబ్రవరి',
      3: 'మార్చి',
      4: 'ఏప్రిల్',
      5: 'మే',
      6: 'జూన్',
      7: 'జూలై',
      8: 'ఆగస్టు',
      9: 'సెప్టेंबर',
      10: 'అక్టోబర్',
      11: 'నవంబర్',
      12: 'డిసెంబర్',
    };
    String monthName = months[now.month] ?? '';
    
    String dateStr = 'ఈరోజు $dayName, ${now.day} $monthName.';
    
    return '$timeStr $dateStr';
  }

  Widget _buildClockCard(BuildContext context, String layoutMode) {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final timeStr = "$hour:$minute $period";
    
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final dayName = days[now.weekday - 1];
    
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final monthName = months[now.month - 1];
    final dateStr = "$dayName, ${now.day} $monthName";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Semantics(
        label: "Current time is $timeStr. Date is $dateStr. Tap to hear this in Telugu.",
        button: true,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            final speakText = _getTeluguDateTimeSpeech();
            ref.read(ttsServiceProvider).speak(speakText, forceLanguage: 'te');
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              color: const Color(0xFF3C3489),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeStr,
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -1.0,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
                // Right
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "సమయం వినండి",
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Tap to speak",
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final timeStr = "$hour:$minute $period";
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? kTextSecondaryDark : kTextSecondaryLight;
    
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            timeStr,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
          Text(
            "5G · 85%",
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Color> _getContactTints(Color contactColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hex = contactColor.value & 0xFFFFFF;
    if (hex == 0xE24B4A) {
      return {
        'bg': isDark ? kRedTintDark : kRedTintLight,
        'text': isDark ? kRedIconDark : kRedIconLight,
      };
    }
    if (hex == 0x1D9E75) {
      return {
        'bg': isDark ? kGreenTintDark : kGreenTintLight,
        'text': isDark ? kGreenIconDark : kGreenIconLight,
      };
    }
    if (hex == 0xEF9F27) {
      return {
        'bg': isDark ? kAmberTintDark : kAmberTintLight,
        'text': isDark ? kAmberIconDark : kAmberIconLight,
      };
    }
    if (hex == 0x378ADD) {
      return {
        'bg': isDark ? kBlueTintDark : kBlueTintLight,
        'text': isDark ? kBlueIconDark : kBlueIconLight,
      };
    }
    if (hex == 0xD4537E) {
      return {
        'bg': isDark ? kPurpleTintDark : kPurpleTintLight,
        'text': isDark ? kPurpleIconDark : kPurpleIconLight,
      };
    }
    return {
      'bg': isDark ? kPurpleTintDark : kPurpleTintLight,
      'text': isDark ? kPurpleIconDark : kPurpleIconLight,
    };
  }

  Color _getContactColorByName(String name) {
    final cleanName = name.toLowerCase().trim();
    if (cleanName.contains('gs reddy')) return const Color(0xFF534AB7);
    final colors = [
      const Color(0xFF534AB7),
      const Color(0xFF1D9E75),
      const Color(0xFFEF9F27),
      const Color(0xFFE24B4A),
      const Color(0xFF378ADD),
      const Color(0xFFD4537E),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}

