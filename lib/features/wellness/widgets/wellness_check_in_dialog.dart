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

class _WellnessCheckInDialogState extends ConsumerState<WellnessCheckInDialog>
    with TickerProviderStateMixin {
  late AnimationController _rippleController;
  late final Timer _ttsTimer;
  late final Timer _escalationTimer;
  int _secondsRemaining = 300; // 5 minutes countdown
  bool _isEscalated = false;

  @override
  void initState() {
    super.initState();
    
    // Immersive fullscreen mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Ripple animation for pulsing heart rate icon
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _speakPrompt();

    _ttsTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _speakPrompt();
    });

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
    _rippleController.dispose();
    _ttsTimer.cancel();
    _escalationTimer.cancel();
    ref.read(ttsServiceProvider).stop();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

    widget.onCheckedIn();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    final formattedTime = "$minutes:${seconds.toString().padLeft(2, '0')}";

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF412402),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                // Header
                Text(
                  "WELLNESS CHECK-IN",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFEF9F27),
                    letterSpacing: 0.08 * 10.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),

                // Pulsing Icon
                _buildPulsingHeartRateIcon(),
                const SizedBox(height: 36),

                // Title
                Text(
                  "Are you okay?",
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFFAEEDA),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),

                // Telugu Title
                Text(
                  "మీరు బాగున్నారా?",
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFFEF9F27),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Body
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    "No activity detected for 4 hours. Please confirm you are safe.",
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFFFAEEDA).withOpacity(0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Spacer(),

                // GPS Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Color(0xFFEF9F27),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "GPS location ready",
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFFFAEEDA),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Will be sent to caregiver if unanswered",
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFFBA7517),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // "I am okay" button (full-width)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      widget.onCheckedIn();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check, color: Color(0xFFE1F5EE), size: 20),
                    label: Text(
                      "I am okay",
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFE1F5EE),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D9E75),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Warning note below button
                Text(
                  "No response in $formattedTime → family notified",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFFFAEEDA).withOpacity(0.35),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPulsingHeartRateIcon() {
    const double baseSize = 90.0;
    final colorTint = const Color(0xFFEF9F27);

    return AnimatedBuilder(
      animation: _rippleController,
      builder: (context, child) {
        final progress = _rippleController.value;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Concentric Ring 3
            Container(
              width: baseSize + 60.0 * (1.0 + progress * 0.1),
              height: baseSize + 60.0 * (1.0 + progress * 0.1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorTint.withOpacity((0.05 * (1.0 - progress)).clamp(0.0, 1.0)),
              ),
            ),
            // Concentric Ring 2
            Container(
              width: baseSize + 40.0 * (1.0 + progress * 0.1),
              height: baseSize + 40.0 * (1.0 + progress * 0.1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorTint.withOpacity((0.10 * (1.0 - progress)).clamp(0.0, 1.0)),
              ),
            ),
            // Concentric Ring 1
            Container(
              width: baseSize + 20.0 * (1.0 + progress * 0.1),
              height: baseSize + 20.0 * (1.0 + progress * 0.1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorTint.withOpacity((0.15 * (1.0 - progress)).clamp(0.0, 1.0)),
              ),
            ),

            // Center circle
            Container(
              width: baseSize,
              height: baseSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorTint.withOpacity(0.15),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.favorite_rounded,
                color: colorTint,
                size: 42,
              ),
            ),
          ],
        );
      },
    );
  }
}
