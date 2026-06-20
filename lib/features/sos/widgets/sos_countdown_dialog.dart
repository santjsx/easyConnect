import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hive/hive.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/features/calling/services/audio_call_service.dart';
import 'package:easyconnect/services/tts_service.dart';

/// Global provider tracking whether SOS countdown is active.
/// When true, incoming calls should be silently auto-rejected to protect the emergency flow.
final sosCountdownActiveProvider = StateProvider<bool>((ref) => false);

class SosCountdownDialog extends ConsumerStatefulWidget {
  final Contact sosContact;
  final bool locationShare;

  const SosCountdownDialog({
    super.key,
    required this.sosContact,
    required this.locationShare,
  });

  @override
  ConsumerState<SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends ConsumerState<SosCountdownDialog> with SingleTickerProviderStateMixin {
  int _secondsRemaining = 3;
  Timer? _timer;
  bool _isCancelled = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    // Mark SOS as active to auto-reject incoming calls
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sosCountdownActiveProvider.notifier).state = true;
    });
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    ref.read(ttsServiceProvider).stop();
    super.dispose();
  }

  void _startCountdown() {
    final tts = ref.read(ttsServiceProvider);
    
    // Announce first second immediately
    tts.speak("3");

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isCancelled) {
        timer.cancel();
        return;
      }
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
        tts.speak("$_secondsRemaining");
      } else {
        timer.cancel();
        _triggerSOSCall();
      }
    });
  }

  void _cancelCountdown() {
    _isCancelled = true;
    _timer?.cancel();
    ref.read(sosCountdownActiveProvider.notifier).state = false;
    ref.read(ttsServiceProvider).stop();
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _triggerSOSCall() async {
    ref.read(sosCountdownActiveProvider.notifier).state = false;
    final navigator = Navigator.of(context);
    // 1. Pop the countdown overlay
    navigator.pop();

    // 2. Make the emergency audio call
    final audioCallService = ref.read(audioCallServiceProvider);
    if (navigator.context.mounted) {
      await audioCallService.makeCall(navigator.context, widget.sosContact);
    }

    // 3. Send emergency texts to designated message contacts (silently, to not overlap audio guides)
    await _sendEmergencyMessages(silent: true);
  }

  Future<void> _sendEmergencyMessages({bool silent = false}) async {
    try {
      // 1. Load settings synchronously from Provider
      final settings = ref.read(settingsProvider).value;
      if (settings == null) return;

      final contactsBox = Hive.box<Contact>('contacts');
      final List<Contact> recipients = [];
      if (settings.sosMsgContactId1 != null) {
        final c1 = contactsBox.get(settings.sosMsgContactId1);
        if (c1 != null) recipients.add(c1);
      }
      if (settings.sosMsgContactId2 != null) {
        final c2 = contactsBox.get(settings.sosMsgContactId2);
        if (c2 != null) recipients.add(c2);
      }

      // If no messaging recipients set, fallback to the main call recipient
      if (recipients.isEmpty) {
        recipients.add(widget.sosContact);
      }

      // 2. Determine GPS location if enabled
      String locationSuffix = "";
      if (widget.locationShare) {
        try {
          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
          if (serviceEnabled) {
            LocationPermission permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied) {
              permission = await Geolocator.requestPermission();
            }
            if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
              final Position position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
                timeLimit: const Duration(seconds: 5),
              );
              locationSuffix = " Live location: https://maps.google.com/?q=${position.latitude},${position.longitude}";
            }
          }
        } catch (_) {
          // GPS failed, proceed with generic text
        }
      }

      final String message = "🆘 Emergency Alert! I need help immediately.$locationSuffix";

      // 3. Dispatch to all recipients using user-initiated platform INTENT (Play Store compliant, no permissions required)
      for (final contact in recipients) {
        final phone = contact.phoneNumber.isNotEmpty ? contact.phoneNumber : (contact.whatsappNumber ?? '');
        final cleanedPhone = _cleanNumber(phone);
        if (cleanedPhone.isEmpty) continue;

        final smsUri = Uri.parse("sms:$cleanedPhone?body=${Uri.encodeComponent(message)}");
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri);
          // Small delay to prevent intents overlapping in a loop
          await Future.delayed(const Duration(milliseconds: 1200));
        }
      }

      if (silent) return; // Skip voice feedback during active emergency dialing

      // TTS voice feedback
      if (recipients.length > 1) {
        await ref.read(ttsServiceProvider).speak("Emergency messages sent");
      } else {
        final String name = recipients.first.name;
        await ref.read(ttsServiceProvider).speak("Sent message to $name");
      }

    } catch (e) {
      debugPrint("Error in SOS message dispatch: $e");
    }
  }

  String _cleanNumber(String number) {
    final isLeadingPlus = number.startsWith('+');
    final digitsOnly = number.replaceAll(RegExp(r'\D'), '');
    return (isLeadingPlus ? '+' : '') + digitsOnly;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQueryData = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQueryData.copyWith(
        textScaler: mediaQueryData.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.35,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              colors: [
                Color(0xFFE11D48), // vibrant rose 600
                Color(0xFF9F1239), // deep rose 800
                Color(0xFF4C0519), // dark rose 950
              ],
              center: Alignment.center,
              radius: 1.2,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  
                  // Pulse animation stack
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Concentric pulsing rings
                      ...List.generate(3, (index) {
                        return AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final progress = (_pulseController.value + index / 3) % 1.0;
                            return Container(
                              width: 140.0 + progress * 160.0,
                              height: 140.0 + progress * 160.0,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: (1.0 - progress) * 0.25),
                                  width: 2.0,
                                ),
                              ),
                            );
                          },
                        );
                      }),
                      // Central countdown number
                      Container(
                        width: 130.0,
                        height: 130.0,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "$_secondsRemaining",
                          style: GoogleFonts.fraunces(
                            fontSize: 64.0,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFE11D48),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  
                  // Subtitle Text
                  Text(
                    "Calling Emergency Contact",
                    style: GoogleFonts.nunito(
                      fontSize: 22.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(alpha: 0.95),
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const Spacer(flex: 4),
                  
                  // Cancel Button at Bottom
                  SizedBox(
                    height: 58,
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF9F1239),
                        elevation: 8,
                        shadowColor: Colors.black.withValues(alpha: 0.25),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28.0),
                        ),
                      ),
                      onPressed: _cancelCountdown,
                      child: Text(
                        "CANCEL",
                        style: GoogleFonts.nunito(
                          fontSize: 22.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
