import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';
import 'package:google_fonts/google_fonts.dart';

class WellnessCheckInDialog extends ConsumerStatefulWidget {
  final VoidCallback onCheckedIn;

  const WellnessCheckInDialog({
    super.key,
    required this.onCheckedIn,
  });

  @override
  ConsumerState<WellnessCheckInDialog> createState() => _WellnessCheckInDialogState();
}

class _WellnessCheckInDialogState extends ConsumerState<WellnessCheckInDialog> with SingleTickerProviderStateMixin {
  late AnimationController _colorAnimController;
  late final Timer _ttsTimer;
  late final Timer _escalationTimer;
  int _secondsRemaining = 300; // 5 minutes countdown
  bool _isEscalated = false;

  @override
  void initState() {
    super.initState();
    // 1. Color animation for flashing screen
    _colorAnimController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    // 2. Initial TTS announcement
    _speakPrompt();

    // 3. Loop TTS announcement every 12 seconds
    _ttsTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _speakPrompt();
    });

    // 4. Escalation countdown (1 second tick)
    _escalationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        _triggerEscalation();
      }
    });
  }

  @override
  void dispose() {
    _colorAnimController.dispose();
    _ttsTimer.cancel();
    _escalationTimer.cancel();
    ref.read(ttsServiceProvider).stop();
    super.dispose();
  }

  Future<void> _speakPrompt() async {
    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    final lang = settingsBox != null && settingsBox.isNotEmpty ? settingsBox.values.first.language : 'en';

    String alertMsg = '';
    if (lang == 'te') {
      alertMsg = "దయచేసి మీరు బాగున్నారని తెలపడానికి స్క్రీన్ మీద గ్రీన్ బటన్ నొక్కండి.";
    } else if (lang == 'hi') {
      alertMsg = "कृपया यह बताने के लिए कि आप ठीक हैं, स्क्रीन पर हरा बटन दबाएं।";
    } else {
      alertMsg = "Please press the green button on the screen to confirm you are okay.";
    }

    await ref.read(ttsServiceProvider).speak(alertMsg, forceLanguage: lang);
  }

  Future<String?> _getCurrentLocationLink() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final request = await Geolocator.requestPermission();
        if (request == LocationPermission.denied || request == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      return "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";
    } catch (e) {
      debugPrint("Error getting GPS location: $e");
      return null;
    }
  }

  Future<void> _triggerEscalation() async {
    if (_isEscalated) return;
    setState(() {
      _isEscalated = true;
    });

    final settingsBox = Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    if (settingsBox == null || settingsBox.isEmpty) return;
    final settings = settingsBox.values.first;

    final contactBox = Hive.isBoxOpen('contacts') ? Hive.box<Contact>('contacts') : null;
    if (contactBox == null) return;

    final c1 = settings.sosMsgContactId1 != null ? contactBox.get(settings.sosMsgContactId1) : null;
    final c2 = settings.sosMsgContactId2 != null ? contactBox.get(settings.sosMsgContactId2) : null;

    final phoneNumbers = <String>[];
    if (c1 != null && c1.phoneNumber.isNotEmpty) phoneNumbers.add(c1.phoneNumber);
    if (c2 != null && c2.phoneNumber.isNotEmpty) phoneNumbers.add(c2.phoneNumber);

    if (phoneNumbers.isEmpty) {
      debugPrint("No emergency SMS contacts configured for wellness check-in escalation.");
      return;
    }

    final gpsLink = await _getCurrentLocationLink();
    final intervalHours = settings.activeWellnessIntervalHours;
    
    final locationPart = gpsLink != null 
        ? "Last known location: $gpsLink"
        : "GPS location unavailable.";

    final message = "Wellness Alert: Device user has been inactive for $intervalHours hours and did not respond to the wellness check-in prompt. $locationPart";

    for (final number in phoneNumbers) {
      debugPrint("Sending Wellness Escalation SMS to $number: $message");
      await ref.read(systemCallServiceProvider).sendDirectSMS(number, message);
    }

    final lang = settings.language;
    String finalSpeak = '';
    if (lang == 'te') {
      finalSpeak = "అలర్ట్ పంపబడింది. కుటుంబ సభ్యులు త్వరలో మిమ్మల్ని సంప్రదిస్తారు.";
    } else if (lang == 'hi') {
      finalSpeak = "अलर्ट भेज दिया गया है। परिवार के सदस्य जल्द ही आपसे संपर्क करेंगे।";
    } else {
      finalSpeak = "Alert sent. Your family will contact you shortly.";
    }
    await ref.read(ttsServiceProvider).speak(finalSpeak, forceLanguage: lang);

    // Call checkin callback to reset timer and dismiss dialog
    widget.onCheckedIn();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnimController,
      builder: (context, child) {
        // Soft amber/peach glow overlay transition
        final color = Color.lerp(
          const Color(0xFFFFF7ED), // Amber-50
          const Color(0xFFFFFBF7), // Warm peach-white
          _colorAnimController.value,
        );

        return PopScope(
          canPop: false, // Prevent physical back buttons dismissing
          child: Scaffold(
            backgroundColor: color,
            body: SafeArea(
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
                          Icons.accessibility_new_rounded,
                          size: 72.0,
                          color: Color(0xFFFF8C00),
                        ),
                        const SizedBox(height: 18.0),
                        Text(
                          "Are You Okay?",
                          style: GoogleFonts.fraunces(
                            fontSize: 32.0,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1B1B2E),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12.0),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            "Press the large button below to let your family know you are okay.",
                            style: GoogleFonts.nunito(
                              fontSize: 16.0,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6E6E8A),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),

                    // Massive Confirmation Button with double-ring ripple
                    Center(
                      child: Semantics(
                        label: "I am okay button. Double tap to confirm you are fine.",
                        button: true,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.heavyImpact();
                            widget.onCheckedIn();
                            Navigator.pop(context);
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Concentric ripples
                              ...List.generate(2, (index) {
                                return Container(
                                  width: 180.0 + (index + 1) * 28.0 * _colorAnimController.value,
                                  height: 180.0 + (index + 1) * 28.0 * _colorAnimController.value,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF32E08A).withValues(alpha: (1.0 - _colorAnimController.value) * 0.2),
                                      width: 2.0,
                                    ),
                                  ),
                                );
                              }),
                              // Main green button container
                              Container(
                                width: 180.0,
                                height: 180.0,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF32E08A), Color(0xFF1BAD61)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF32E08A).withValues(alpha: 0.4),
                                      blurRadius: 20.0,
                                      spreadRadius: 2.0,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_rounded,
                                      size: 64.0,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(height: 4.0),
                                    Text(
                                      "I'M OK",
                                      style: GoogleFonts.nunito(
                                        fontSize: 22.0,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Countdown Timer Badge
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 48.0),
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 20.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            "Family Escalation In:",
                            style: GoogleFonts.nunito(
                              fontSize: 13.0,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF9999B0),
                            ),
                          ),
                          const SizedBox(height: 4.0),
                          Text(
                            "${_secondsRemaining ~/ 60}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}",
                            style: GoogleFonts.nunito(
                              fontSize: 22.0,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFFF2147), // Red alert countdown
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
