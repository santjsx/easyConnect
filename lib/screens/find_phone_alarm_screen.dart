import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:google_fonts/google_fonts.dart';

class FindPhoneAlarmScreen extends ConsumerStatefulWidget {
  final String familyCode;

  const FindPhoneAlarmScreen({
    super.key,
    required this.familyCode,
  });

  @override
  ConsumerState<FindPhoneAlarmScreen> createState() => _FindPhoneAlarmScreenState();
}

class _FindPhoneAlarmScreenState extends ConsumerState<FindPhoneAlarmScreen> with SingleTickerProviderStateMixin {
  static const _platform = MethodChannel('com.easyconnect.app/calling');
  late AnimationController _colorAnimController;
  late final Timer _ttsTimer;

  @override
  void initState() {
    super.initState();
    // 1. Color animation for flashing screen
    _colorAnimController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);

    // 2. Set max volume and start vibration natively
    _initNativeAlarmAlerts();

    // 3. Initial TTS announcement
    _speakPrompt();

    // 4. Loop TTS announcement every 6 seconds
    _ttsTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _speakPrompt();
    });
  }

  Future<void> _initNativeAlarmAlerts() async {
    try {
      await _platform.invokeMethod('setMaxVolume');
      await _platform.invokeMethod('startVibration');
    } catch (e) {
      debugPrint("Error initializing native alarm alerts: $e");
    }
  }

  @override
  void dispose() {
    _colorAnimController.dispose();
    _ttsTimer.cancel();
    _stopNativeAlarmAlerts();
    ref.read(ttsServiceProvider).stop();
    super.dispose();
  }

  Future<void> _stopNativeAlarmAlerts() async {
    try {
      await _platform.invokeMethod('stopVibration');
      await ref.read(ttsServiceProvider).stop();
    } catch (e) {
      debugPrint("Error stopping native alarm alerts: $e");
    }
  }

  Future<void> _speakPrompt() async {
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    final lang = settingsBox != null && settingsBox.isNotEmpty ? settingsBox.values.first.language : 'en';

    String alertMsg = '';
    if (lang == 'te') {
      alertMsg = "నేను ఇక్కడ ఉన్నాను! నన్ను తీసుకో!";
    } else if (lang == 'hi') {
      alertMsg = "मैं यहाँ हूँ! मुझे उठाओ!";
    } else {
      alertMsg = "I am here! Come pick me up!";
    }

    // Direct speak at maximum volume
    await ref.read(ttsServiceProvider).speak(alertMsg, forceLanguage: lang);
  }

  Future<void> _dismissAlarm() async {
    HapticFeedback.heavyImpact();
    
    // Stop native vibration and speech immediately
    await _stopNativeAlarmAlerts();

    // Reset the Firestore trigger so it doesn't fire again
    try {
      await FirebaseFirestore.instance
          .collection('families')
          .doc(widget.familyCode)
          .collection('commands')
          .doc('find_phone')
          .set({
        'trigger': false,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error resetting Firestore find_phone command: $e");
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnimController,
      builder: (context, child) {
        // Flashing vibrant red/orange to yellow background
        final color = Color.lerp(
          const Color(0xFFFF2147), // Red
          const Color(0xFFFF8C00), // Orange
          _colorAnimController.value,
        );

        return PopScope(
          canPop: false, // Prevent physical back buttons dismissing without button press
          child: Scaffold(
            backgroundColor: color,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Warning Header
                            Column(
                              children: [
                                const Icon(
                                  Icons.ring_volume_rounded,
                                  size: 96.0,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 24.0),
                                Text(
                                  "PHONE FINDER ALARM",
                                  style: GoogleFonts.fraunces(
                                    fontSize: 36.0,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16.0),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: Text(
                                    "A caregiver triggered this alarm to locate this phone.",
                                    style: GoogleFonts.nunito(
                                      fontSize: 18.0,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),

                            // Massive "I FOUND IT" Button
                            Center(
                              child: Semantics(
                                label: "I found the phone button. Double tap to silence the alarm.",
                                button: true,
                                child: GestureDetector(
                                  onTap: _dismissAlarm,
                                  child: Container(
                                    width: 200.0,
                                    height: 200.0,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.25),
                                          blurRadius: 24.0,
                                          spreadRadius: 4.0,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 64.0,
                                          color: Color(0xFFFF2147),
                                        ),
                                        const SizedBox(height: 8.0),
                                        Text(
                                          "I FOUND IT!",
                                          style: GoogleFonts.nunito(
                                            fontSize: 22.0,
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFFFF2147),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Small indicator
                            Text(
                              "Volume set to maximum.",
                              style: GoogleFonts.nunito(
                                fontSize: 14.0,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
