import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/features/alarm/models/alarm_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/services/firebase_sync_service.dart';
import 'package:google_fonts/google_fonts.dart';

class AlarmRingScreen extends ConsumerStatefulWidget {
  final Alarm alarm;

  const AlarmRingScreen({
    super.key,
    required this.alarm,
  });

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> with SingleTickerProviderStateMixin {
  static const _platform = MethodChannel('com.easyconnect.app/calling');
  late AnimationController _colorAnimController;
  late final Timer _ttsTimer;

  @override
  void initState() {
    super.initState();
    // 1. Color animation for flashing screen
    _colorAnimController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    )..repeat(reverse: true);

    // 2. Set max volume and start vibration natively
    _initNativeAlarmAlerts();

    // 3. Initial TTS announcement
    _speakPrompt();

    // 4. Loop TTS announcement every 7 seconds
    _ttsTimer = Timer.periodic(const Duration(seconds: 7), (_) {
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
    final String label = widget.alarm.label.trim();
    String alertMsg = '';
    
    // Map common labels to natural spoken Telugu reminder phrases
    final lowerLabel = label.toLowerCase();
    if (lowerLabel.contains('medicine') || lowerLabel.contains('tablet') || label.contains('మందులు') || label.contains('మాత్రలు')) {
      alertMsg = "మందులు వేసుకునే సమయం అయింది. దయచేసి మందులు వేసుకోండి.";
    } else if (lowerLabel.contains('food') || lowerLabel.contains('lunch') || lowerLabel.contains('dinner') || lowerLabel.contains('breakfast') || label.contains('భోజనం') || label.contains('అన్నం')) {
      alertMsg = "భోజనం చేసే సమయం అయింది. దయచేసి భోజనం చేయండి.";
    } else if (lowerLabel.contains('sleep') || lowerLabel.contains('bed') || label.contains('నిద్ర') || label.contains('పడుకో')) {
      alertMsg = "నిద్రపోయే సమయం అయింది. దయచేసి విశ్రాంతి తీసుకోండి.";
    } else {
      // Default fallback
      alertMsg = "అలారం! $label సమయం అయింది. అలారం ఆపడానికి స్క్రీన్ మీద నొక్కండి.";
    }

    // Force speak in Telugu as requested ("she can only understand telugu if someone tells her")
    await ref.read(ttsServiceProvider).speak(alertMsg, forceLanguage: 'te');
  }

  Future<void> _dismissAlarm() async {
    HapticFeedback.heavyImpact();
    
    // Stop native vibration and speech immediately
    await _stopNativeAlarmAlerts();

    // If it's a one-time alarm, disable it locally and sync to Firebase
    if (widget.alarm.days.isEmpty) {
      widget.alarm.isEnabled = false;
      await widget.alarm.save();
      
      // Notify Firebase of update
      await ref.read(firebaseSyncServiceProvider).updateAlarm(widget.alarm);
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
        // Flashing vibrant warning colors
        final color = Color.lerp(
          const Color(0xFF6E44FF), // Deep Purple
          const Color(0xFFFF8C00), // Vibrant Orange
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
                                  Icons.alarm_on_rounded,
                                  size: 96.0,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 24.0),
                                Text(
                                  "ALARM REMINDER",
                                  style: GoogleFonts.fraunces(
                                    fontSize: 34.0,
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
                                    widget.alarm.label.toUpperCase(),
                                    style: GoogleFonts.nunito(
                                      fontSize: 22.0,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),

                            // Massive "STOP ALARM" Button
                            Center(
                              child: Semantics(
                                label: "Stop Alarm button. Tap once to stop the alarm reminder.",
                                button: true,
                                child: GestureDetector(
                                  onTap: _dismissAlarm,
                                  child: Container(
                                    width: 220.0,
                                    height: 220.0,
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
                                          Icons.alarm_off_rounded,
                                          size: 64.0,
                                          color: Color(0xFFFF8C00),
                                        ),
                                        const SizedBox(height: 12.0),
                                        Text(
                                          "ఆపండి\n(STOP)",
                                          style: GoogleFonts.nunito(
                                            fontSize: 20.0,
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFFFF8C00),
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Display Time Info
                            Text(
                              "Alarm Time: ${widget.alarm.time}",
                              style: GoogleFonts.nunito(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.8),
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
