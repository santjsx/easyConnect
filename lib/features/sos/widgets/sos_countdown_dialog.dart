import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/features/calling/services/audio_call_service.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:permission_handler/permission_handler.dart';

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

class _SosCountdownDialogState extends ConsumerState<SosCountdownDialog> {
  int _secondsRemaining = 3;
  Timer? _timer;
  bool _isCancelled = false;

  @override
  void initState() {
    super.initState();
    // Mark SOS as active to auto-reject incoming calls
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sosCountdownActiveProvider.notifier).state = true;
    });
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
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

    // 3. Send emergency texts to designated message contacts
    await _sendEmergencyMessages();
  }

  Future<void> _sendEmergencyMessages() async {
    try {
      // 1. Load settings & contacts from Hive
      final Box<AppSettings> settingsBox = Hive.isBoxOpen('settings') 
          ? Hive.box<AppSettings>('settings') 
          : await Hive.openBox<AppSettings>('settings');
      
      if (settingsBox.isEmpty) return;
      final settings = settingsBox.values.first;

      final Box<Contact> contactsBox = Hive.isBoxOpen('contacts') 
          ? Hive.box<Contact>('contacts') 
          : await Hive.openBox<Contact>('contacts');

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

      // 3. Dispatch to all recipients automatically using cellular SMS
      bool hasSmsPermission = await Permission.sms.isGranted;
      if (!hasSmsPermission) {
        hasSmsPermission = await Permission.sms.request().isGranted;
      }
      const MethodChannel platform = MethodChannel('com.easyconnect.app/calling');

      for (final contact in recipients) {
        final phone = contact.phoneNumber.isNotEmpty ? contact.phoneNumber : (contact.whatsappNumber ?? '');
        final cleanedPhone = _cleanNumber(phone);
        if (cleanedPhone.isEmpty) continue;

        bool sentSuccessfully = false;
        if (hasSmsPermission) {
          try {
            final bool? success = await platform.invokeMethod<bool>('sendDirectSMS', {
              'phoneNumber': cleanedPhone,
              'message': message,
            });
            sentSuccessfully = success ?? false;
            debugPrint("Automatic SOS SMS dispatch to $cleanedPhone: $sentSuccessfully");
          } catch (e) {
            debugPrint("Failed to send direct SMS via MethodChannel: $e");
          }
        }

        // Cellular SMS UI Fallback if permission was denied or MethodChannel failed
        if (!sentSuccessfully) {
          final smsUri = Uri.parse("sms:$cleanedPhone?body=${Uri.encodeComponent(message)}");
          if (await canLaunchUrl(smsUri)) {
            await launchUrl(smsUri);
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        }
      }

      // TTS voice feedback
      final String lang = settings.language;
      if (recipients.length > 1) {
        String feedback = "Emergency messages sent";
        if (lang == 'te') {
          feedback = "అత్యవసర సమాచారం పంపించాము";
        } else if (lang == 'hi') {
          feedback = "आपातकालीन संदेश भेज दिए गए हैं";
        }
        await ref.read(ttsServiceProvider).speak(feedback, forceLanguage: lang);
      } else {
        final String name = recipients.first.name;
        String feedback = "Sent message to $name";
        if (lang == 'te') {
          feedback = "$name కి మెసేజ్ పంపించాను";
        } else if (lang == 'hi') {
          feedback = "$name को संदेश भेज दिया गया है";
        }
        await ref.read(ttsServiceProvider).speak(feedback, forceLanguage: lang);
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
    return Scaffold(
      backgroundColor: kSosRed.withValues(alpha: 0.9),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            children: [
              const Spacer(flex: 3),
              
              // Countdown Number
              Text(
                "$_secondsRemaining",
                style: const TextStyle(
                  fontSize: 72.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              
              // Subtitle Text
              const Text(
                "Calling Emergency Contact",
                style: TextStyle(
                  fontSize: 20.0,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              
              const Spacer(flex: 4),
              
              // Cancel Button at Bottom
              SizedBox(
                height: kMinTouchTarget,
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 2.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  onPressed: _cancelCountdown,
                  child: const Text(
                    "CANCEL",
                    style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
