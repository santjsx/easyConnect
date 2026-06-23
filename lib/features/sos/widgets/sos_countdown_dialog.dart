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

class _SosCountdownDialogState extends ConsumerState<SosCountdownDialog> {
  int _secondsRemaining = 3;
  Timer? _timer;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sosCountdownActiveProvider.notifier).state = true;
    });
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    ref.read(ttsServiceProvider).stop();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startCountdown() {
    final tts = ref.read(ttsServiceProvider);
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
    navigator.pop();

    final audioCallService = ref.read(audioCallServiceProvider);
    if (navigator.context.mounted) {
      await audioCallService.makeCall(navigator.context, widget.sosContact);
    }

    await _sendEmergencyMessages(silent: true);
  }

  Future<void> _sendEmergencyMessages({bool silent = false}) async {
    try {
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

      if (recipients.isEmpty) {
        recipients.add(widget.sosContact);
      }

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
        } catch (_) {}
      }

      final String message = "🆘 Emergency Alert! I need help immediately.$locationSuffix";

      for (final contact in recipients) {
        final phone = contact.phoneNumber.isNotEmpty ? contact.phoneNumber : (contact.whatsappNumber ?? '');
        final cleanedPhone = _cleanNumber(phone);
        if (cleanedPhone.isEmpty) continue;

        final smsUri = Uri.parse("sms:$cleanedPhone?body=${Uri.encodeComponent(message)}");
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri);
          await Future.delayed(const Duration(milliseconds: 1200));
        }
      }

      if (silent) return;

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
    final settings = ref.watch(settingsProvider).value;
    String smsRecipients = "Caregiver";
    if (settings != null) {
      final contactsBox = Hive.box<Contact>('contacts');
      final List<String> names = [];
      if (settings.sosMsgContactId1 != null) {
        final c1 = contactsBox.get(settings.sosMsgContactId1);
        if (c1 != null) names.add(c1.name);
      }
      if (settings.sosMsgContactId2 != null) {
        final c2 = contactsBox.get(settings.sosMsgContactId2);
        if (c2 != null) names.add(c2.name);
      }
      if (names.isNotEmpty) {
        smsRecipients = names.join(', ');
      } else {
        smsRecipients = widget.sosContact.name;
      }
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF501313),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                // Header Label
                Text(
                  "EMERGENCY SOS",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFF09595),
                    letterSpacing: 0.08 * 10.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  "Contacting emergency services",
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFFF09595),
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),

                // Countdown Ring
                SizedBox(
                  width: 110,
                  height: 110,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 110,
                        height: 110,
                        child: CircularProgressIndicator(
                          value: _secondsRemaining / 3.0,
                          strokeWidth: 4,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE24B4A)),
                          backgroundColor: Colors.white.withOpacity(0.06),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "$_secondsRemaining",
                            style: GoogleFonts.inter(
                              fontSize: 52,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFF7C1C1),
                            ),
                          ),
                          Text(
                            "seconds",
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFFF09595),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Title
                Text(
                  "Calling emergency contact",
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFFCEBEB),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  "GPS SMS being prepared...",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFFF09595),
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),

                // Phone Call Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.phone_in_talk,
                        color: Color(0xFFE24B4A),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Calling: ${widget.sosContact.name}",
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFFFCEBEB),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.sosContact.phoneNumber,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFFF09595),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // SMS Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.message,
                        color: Color(0xFFE24B4A),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "SMS: $smsRecipients",
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFFFCEBEB),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "With Google Maps link",
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFFF09595),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Cancel SOS Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _cancelCountdown,
                    icon: const Icon(Icons.close, color: Color(0xFFF09595), size: 20),
                    label: Text(
                      "Cancel SOS",
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFF09595),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE24B4A), width: 1.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
