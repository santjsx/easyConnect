import 'dart:io';
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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0; // Tab 0: Home (Contacts), Tab 1: Keypad, Tab 2: Logs
  String _keypadNumber = '';
  bool _overlayPermissionMissing = false;

  @override
  void initState() {
    super.initState();
    _checkOverlayPermission();
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
        'ఫోన్ కాల్ వచ్చినప్పుడు స్క్రీన్ మీద చూపించడానికి పర్మిషన్ ఇవ్వు. ఆ పెద్ద బటన్ నొక్కు',
        forceLanguage: 'te',
      );
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
      data: (settings) => settings.layoutMode,
      loading: () => 'classic',
      error: (err, stack) => 'classic',
    );

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

    return Scaffold(
      backgroundColor: layoutMode == 'classic' ? const Color(0xFF0F1B2E) : kAppBackground,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                          ? const Text(
                              "No internet — WhatsApp features unavailable",
                              style: TextStyle(
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
                          const Expanded(
                            child: Text(
                              "Incoming calls won't show on screen.\nTap here to fix this!",
                              style: TextStyle(
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
                            child: const Text(
                              "FIX",
                              style: TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.bold,
                                fontSize: 13.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 2. Custom Dashboard Header (Left Aligned Logo / Classic Mockup Header)
                if (layoutMode == 'classic')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: Round phone button matching mockup
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.0),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.phone_in_talk,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        // Right: 4 white icons: Group Add, Add Contact, Settings, More Menu
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.group_add, color: Colors.white, size: 28),
                              onPressed: () {
                                _navigateToSettings(context);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 28),
                              onPressed: () {
                                _navigateToSettings(context);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.white, size: 28),
                              onPressed: () {
                                _navigateToSettings(context);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert, color: Colors.white, size: 28),
                              onPressed: () {
                                _navigateToSettings(context);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: kAccentPurple,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(14),
                              topRight: Radius.circular(14),
                              bottomLeft: Radius.circular(14),
                              bottomRight: Radius.circular(3), // speech bubble style
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: kAccentPurple.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.phone,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "EasyConnect",
                              style: TextStyle(
                                fontSize: 24.0,
                                fontWeight: FontWeight.bold,
                                color: kTextNavy,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              "One tap. Stay connected.",
                              style: TextStyle(
                                fontSize: 12.0,
                                fontWeight: FontWeight.w500,
                                color: kTextSlate,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // 3. Horizontal Status Card Row (Online status, Voice guide, Battery)
                if (layoutMode != 'classic')
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

                      Color signalBg;
                      Color signalIconColor;
                      IconData signalIcon;
                      String signalTitle;
                      String signalSubtitle;

                      if (signalStatus == 'good') {
                        signalBg = const Color(0xFFF3FBEF);
                        signalIconColor = const Color(0xFF4CAF50);
                        signalIcon = Icons.wifi;
                        signalTitle = "Online";
                        signalSubtitle = "Safe to Call";
                      } else if (signalStatus == 'weak') {
                        signalBg = const Color(0xFFFFF7ED); // Soft Orange Card
                        signalIconColor = const Color(0xFFF97316);
                        signalIcon = Icons.wifi_1_bar;
                        signalTitle = "Weak Signal";
                        signalSubtitle = "Poor Connection";
                      } else {
                        signalBg = const Color(0xFFFFF0F0); // Red Card
                        signalIconColor = const Color(0xFFEF4444);
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
                        batteryBg = const Color(0xFFFFF0F0); // Red Card
                        batteryIconColor = const Color(0xFFEF4444);
                        batteryTitle = "Plug In!";
                        batterySubtitle = "Battery Low";
                      } else if (batteryLevel < 50) {
                        batteryBg = const Color(0xFFFFFBEB); // Soft Amber Card
                        batteryIconColor = const Color(0xFFF59E0B);
                        batteryTitle = "Battery OK";
                        batterySubtitle = "$batteryLevel% Charged";
                      } else {
                        batteryBg = const Color(0xFFF0F7FF); // Soft Blue Card
                        batteryIconColor = const Color(0xFF10B981); // Green Battery
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
                                label: "Network Connection: $signalTitle. $signalSubtitle.",
                                container: true,
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
                                  borderRadius: BorderRadius.circular(20),
                                  child: _buildStatusCard(
                                    backgroundColor: voiceEnabled
                                        ? const Color(0xFFF5F3FF)
                                        : const Color(0xFFF1F5F9),
                                    iconColor: voiceEnabled ? kAccentPurple : kTextSlate,
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
                                label: "Battery is $batteryLevel percent. Status is $batteryTitle.",
                                container: true,
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
                          ],
                        ),
                      );
                    }
                  ),

                const SizedBox(height: 8.0),

                // 4. Switching View: Tab 0 (Contacts Grid) vs Tab 1 (Keypad) vs Tab 2 (Call Logs Grid)
                Expanded(
                  child: RepaintBoundary(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _currentIndex == 0
                          ? Consumer(
                              builder: (context, ref, child) {
                                final contactsAsync = ref.watch(contactsStreamProvider);
                                final simState = ref.watch(systemStatusProvider.select((s) => s.simState));
                                return _buildContactsView(contactsAsync, simState, layoutMode);
                              }
                            )
                          : _currentIndex == 1
                              ? _buildKeypadView()
                              : Consumer(
                                  builder: (context, ref, child) {
                                    final logsAsync = ref.watch(callLogsStreamProvider);
                                    return _buildCallLogsView(logsAsync);
                                  }
                                ),
                    ),
                  ),
                ),

                if (_currentIndex == 0 && layoutMode != 'classic')
                  Padding(
                    padding: EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 8.0,
                      bottom: 84.0 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Row(
                      children: [
                        // Left: SOS Action Card
                        Expanded(
                          child: Semantics(
                            label: "S O S. Double tap to trigger emergency alert countdown.",
                            button: true,
                            child: InkWell(
                              onTap: () {
                                ref.read(sosServiceProvider).triggerSOS(context);
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: _buildActionCard(
                                backgroundColor: const Color(0xFFFFF0F0),
                                iconBgColor: const Color(0xFFEF4444),
                                icon: Icons.notifications_active,
                                title: "SOS",
                                subtitle: "Emergency Help",
                                arrowColor: const Color(0xFFEF4444),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        // Right: Voice Message Action Card
                        Expanded(
                          child: Semantics(
                            label: "Voice Message. Tap to record and send an emergency audio message.",
                            button: true,
                            child: InkWell(
                              onTap: () async {
                                final Box<AppSettings> settingsBox = Hive.isBoxOpen('settings')
                                    ? Hive.box<AppSettings>('settings')
                                    : await Hive.openBox<AppSettings>('settings');
                                final settings = settingsBox.isEmpty ? null : settingsBox.values.first;

                                if (settings != null && settings.sosContactId != null) {
                                  final Box<Contact> contactBox = Hive.isBoxOpen('contacts')
                                      ? Hive.box<Contact>('contacts')
                                      : await Hive.openBox<Contact>('contacts');
                                  final sosContact = contactBox.get(settings.sosContactId);
                                  
                                  if (sosContact != null) {
                                    ref.read(voiceMessageOverlayProvider.notifier).open(sosContact);
                                    return;
                                  }
                                }
                                // Fallback: Guidance
                                ref.read(ttsServiceProvider).speak(
                                      "Tap the voice button on any contact card above to record and send them a message.",
                                    );
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: _buildActionCard(
                                backgroundColor: const Color(0xFFF4F0FF),
                                iconBgColor: kAccentPurple,
                                icon: Icons.mic,
                                title: "Voice Message",
                                subtitle: "Tap to record and send",
                                arrowColor: kAccentPurple,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: (layoutMode == 'classic' ? 16.0 : 84.0) + MediaQuery.paddingOf(context).bottom,
                  ),
              ],
            ),
          ),

          // 6. Floating Bottom Navigation Bar
          if (layoutMode != 'classic')
            _buildFloatingBottomNavBar(context),

          // 6b. Floating Dialer Toggler Button for Classic Mode
          if (layoutMode == 'classic')
            Positioned(
              right: 20,
              bottom: 20 + MediaQuery.paddingOf(context).bottom,
              child: Semantics(
                label: _currentIndex == 0 ? "Open Keypad Dialer" : "Close Keypad Dialer",
                button: true,
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: FloatingActionButton(
                    backgroundColor: const Color(0xFF4DB6AC), // Vibrant mockup teal/cyan
                    foregroundColor: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 6,
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      setState(() {
                        _currentIndex = _currentIndex == 0 ? 1 : 0;
                      });
                      final tts = ref.read(ttsServiceProvider);
                      if (_currentIndex == 1) {
                        tts.speak("కీప్యాడ్ చూపించబడుతోంది", forceLanguage: 'te');
                      } else {
                        tts.speak("కాంటాక్ట్స్ చూపించబడుతున్నాయి", forceLanguage: 'te');
                      }
                    },
                    child: Icon(
                      _currentIndex == 0 ? Icons.dialpad : Icons.grid_view,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),

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

        double childAspectRatio = 0.72;
        if (layoutMode == 'classic') {
          childAspectRatio = 0.68; // Compact aspect ratio for 4 columns with 2-line name support
        } else if (screenWidth < 395) {
          childAspectRatio = 0.65; // Prevents overflow on narrow devices like Redmi Note 10 (~360dp)
        } else if (screenWidth >= 600) {
          childAspectRatio = 0.85; // Better proportion for tablets
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              if (showWarning) _buildSimWarningPill(simState),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: layoutMode == 'classic' ? 8 : 12,
                    mainAxisSpacing: layoutMode == 'classic' ? 8 : 12,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemCount: sortedContacts.length,
                  itemBuilder: (context, index) {
                    final contact = sortedContacts[index];
                    return ContactCard(contact: contact);
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
  Widget _buildFallbackAvatar(String name) {
    final firstLetter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFFF1F5F9), // Slate-100 placeholder background
      alignment: Alignment.center,
      child: Text(
        firstLetter,
        style: const TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.bold,
          color: kTextNavy,
        ),
      ),
    );
  }

  Widget _buildCallLogListItem(CallLog log) {
    Color statusBgColor;
    Color accentColor;
    IconData statusIcon;
    String statusLabel;

    switch (log.type) {
      case 'missed':
        statusBgColor = const Color(0xFFFFF0F0); // Red
        accentColor = const Color(0xFFEF4444);
        statusIcon = Icons.call_missed;
        statusLabel = "Missed";
        break;
      case 'dialed':
        statusBgColor = const Color(0xFFF3FBEF); // Outgoing Green
        accentColor = const Color(0xFF4CAF50);
        statusIcon = Icons.call_made;
        statusLabel = "Dialed";
        break;
      case 'incoming':
      default:
        statusBgColor = const Color(0xFFFFFBEB); // Received Yellow
        accentColor = const Color(0xFFF59E0B);
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

    final avatarWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: hasPhoto
                ? Image.file(
                    File(matchedContact.photoPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _buildFallbackAvatar(log.name),
                  )
                : _buildFallbackAvatar(log.name),
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
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
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
          color: statusBgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.1),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      log.name,
                      style: const TextStyle(
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                        color: kTextNavy,
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          formattedTime,
                          style: const TextStyle(
                            fontSize: 12.0,
                            fontWeight: FontWeight.bold,
                            color: kTextSlate,
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: kCallGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kCallGreen.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.phone,
                      color: Colors.white,
                      size: 20,
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

  // --- FLOATING NAV BAR Redesign (Switches Home/Keypad/Logs) ---
  Widget _buildFloatingBottomNavBar(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + MediaQuery.paddingOf(context).bottom,
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Home (Tab 0)
            _buildNavItem(
              icon: Icons.home,
              label: "Home",
              isSelected: _currentIndex == 0,
              onTap: () {
                setState(() {
                  _currentIndex = 0;
                });
                ref.read(ttsServiceProvider).speak("Showing Contacts Screen");
              },
            ),
            // Keypad (Tab 1)
            _buildNavItem(
              icon: Icons.dialpad,
              label: "Keypad",
              isSelected: _currentIndex == 1,
              onTap: () {
                setState(() {
                  _currentIndex = 1;
                });
                ref.read(ttsServiceProvider).speak("Showing Keypad Dialer");
              },
            ),
            // Call Logs (Tab 2)
            _buildNavItem(
              icon: Icons.history,
              label: "Logs",
              isSelected: _currentIndex == 2,
              onTap: () {
                setState(() {
                  _currentIndex = 2;
                });
                ref.read(ttsServiceProvider).speak("Showing Call History");
              },
            ),
            // Settings
            _buildNavItem(
              icon: Icons.settings,
              label: "Settings",
              isSelected: false,
              onTap: () {
                _navigateToSettings(context);
              },
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? kAccentPurple : kTextSlate,
              size: 24,
            ),
            const SizedBox(height: 2.0),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? kAccentPurple : kTextSlate,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 2.0),
              Container(
                width: 16,
                height: 2,
                decoration: BoxDecoration(
                  color: kAccentPurple,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _navigateToSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AdminHubScreen(),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.1),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Large visual element (Custom battery cell or connection ring)
          if (customVisual != null) ...[
            customVisual,
            const SizedBox(height: 10.0),
          ] else ...[
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 10.0),
          ],
          
          // 2. High-contrast bold status text
          Text(
            title,
            style: const TextStyle(
              fontSize: 14.0,
              fontWeight: FontWeight.bold,
              color: kTextNavy,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2.0),
          
          // 3. Simple description
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10.0,
              fontWeight: FontWeight.bold,
              color: highlightSubtitle ? iconColor : kTextSlate,
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
      icon = Icons.check;
    } else if (status == 'weak') {
      icon = Icons.warning_amber_rounded;
    } else {
      icon = Icons.close;
    }
    
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Center(
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildBatteryVisual(int level, Color color) {
    final fillPercent = (level / 100.0).clamp(0.0, 1.0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Outer cell frame
        Container(
          width: 48,
          height: 22,
          padding: const EdgeInsets.all(2.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6.0),
            border: Border.all(
              color: kTextNavy.withValues(alpha: 0.3),
              width: 2.0,
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 40.0 * fillPercent,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3.0),
                color: color,
              ),
            ),
          ),
        ),
        // Nipple
        Container(
          width: 3,
          height: 8,
          decoration: BoxDecoration(
            color: kTextNavy.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(2),
              bottomRight: Radius.circular(2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required Color backgroundColor,
    required Color iconBgColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color arrowColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      height: 72,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.0,
                    fontWeight: FontWeight.bold,
                    color: iconBgColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.w600,
                    color: kTextSlate,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.chevron_right, color: arrowColor, size: 16),
          ),
        ],
      ),
    );
  }

  // --- KEYPAD VIEWS & LOGIC ---
  Widget _buildKeypadView() {
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value;
    final String currentLang = settings?.language ?? 'en';
    final bool voiceEnabled = settings?.voiceEnabled ?? true;

    // Helper for key pressed
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

    // Helper for backspace
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

    // Helper for clear
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
        // Compute sizes from available height to prevent overflow
        final availableHeight = constraints.maxHeight;
        final displayHeight = 72.0; // Display area
        final callButtonHeight = 58.0; // Call button
        final gaps = 20.0; // Total spacing between sections
        final gridHeight = availableHeight - displayHeight - callButtonHeight - gaps;
        // Each dial key row gets 1/4 of the grid area
        final keySize = (gridHeight / 4 - 8).clamp(48.0, 76.0);
        final digitFontSize = (keySize * 0.4).clamp(20.0, 30.0);
        final letterFontSize = (keySize * 0.12).clamp(8.0, 10.0);

        return Column(
          children: [
            // 1. Digital Display area
            Container(
              height: displayHeight,
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              margin: const EdgeInsets.symmetric(horizontal: 16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: kAccentPurple.withValues(alpha: 0.08),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Text(
                        _keypadNumber.isEmpty
                            ? (currentLang == 'hi' ? 'नंबर दर्ज करें' : currentLang == 'te' ? 'నంబర్ నమోదు చేయండి' : 'Enter Number')
                            : _keypadNumber,
                        style: TextStyle(
                          fontSize: 34.0,
                          fontWeight: FontWeight.bold,
                          color: _keypadNumber.isEmpty ? kTextSlate.withValues(alpha: 0.4) : kTextNavy,
                          letterSpacing: 2.0,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ),
                  if (_keypadNumber.isNotEmpty)
                    GestureDetector(
                      onTap: onBackspacePressed,
                      onLongPress: onBackspaceLongPressed,
                      child: Container(
                        padding: const EdgeInsets.all(10.0),
                        decoration: const BoxDecoration(
                          color: kAppBackground,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.backspace_outlined,
                          color: kTextNavy,
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 8.0),

            // 2. Responsive 3x4 grid of buttons
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildDialKey('1', '', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                        _buildDialKey('2', 'A B C', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                        _buildDialKey('3', 'D E F', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildDialKey('4', 'G H I', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                        _buildDialKey('5', 'J K L', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                        _buildDialKey('6', 'M N O', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildDialKey('7', 'P Q R S', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                        _buildDialKey('8', 'T U V', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                        _buildDialKey('9', 'W X Y Z', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildDialKey('*', '', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                        _buildDialKey('0', '+', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize, onLongPress: () {
                          onKeyPressed('+');
                        }),
                        _buildDialKey('#', '', onKeyPressed, keySize: keySize, digitFontSize: digitFontSize, letterFontSize: letterFontSize),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 6.0),

            // 3. Call Button
            Center(
              child: InkWell(
                onTap: () {
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
                borderRadius: BorderRadius.circular(36),
                child: Container(
                  width: 240,
                  height: callButtonHeight,
                  decoration: BoxDecoration(
                    color: kCallGreen,
                    borderRadius: BorderRadius.circular(36),
                    boxShadow: [
                      BoxShadow(
                        color: kCallGreen.withValues(alpha: 0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.phone,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12.0),
                      Text(
                        currentLang == 'hi'
                            ? 'कॉल करें'
                            : currentLang == 'te'
                                ? 'కాల్ చేయండి'
                                : 'Call Now',
                        style: const TextStyle(
                          fontSize: 20.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6.0),
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
    required double keySize,
    required double digitFontSize,
    required double letterFontSize,
  }) {
    return Semantics(
      label: "Keypad button $digit ${letters.isNotEmpty ? letters : ''}",
      button: true,
      excludeSemantics: true,
      child: Container(
        width: keySize,
        height: keySize,
        margin: const EdgeInsets.all(3.0),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: kAccentPurple.withValues(alpha: 0.08),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onTap(digit),
            onLongPress: onLongPress,
            customBorder: const CircleBorder(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  digit,
                  style: TextStyle(
                    fontSize: digitFontSize,
                    fontWeight: FontWeight.bold,
                    color: kTextNavy,
                  ),
                ),
                if (letters.isNotEmpty)
                  Text(
                    letters,
                    style: TextStyle(
                      fontSize: letterFontSize,
                      fontWeight: FontWeight.w600,
                      color: kTextSlate.withValues(alpha: 0.6),
                      letterSpacing: 1.0,
                    ),
                  ),
              ],
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
}

