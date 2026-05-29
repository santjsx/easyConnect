import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/calling/services/audio_call_service.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/services/connectivity_service.dart';

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

    // 3. Handle location sharing if enabled
    if (widget.locationShare) {
      await _shareLocation();
    }
  }

  Future<void> _shareLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      final lat = position.latitude;
      final lng = position.longitude;

      final isConnected = ref.read(connectivityProvider);
      final message = "🆘 Emergency! I need help. My location: https://maps.google.com/?q=$lat,$lng";

      if (isConnected) {
        // Online: Dispatch via WhatsApp
        final whatsappNumber = widget.sosContact.whatsappNumber ?? widget.sosContact.phoneNumber;
        final cleanedNumber = _cleanNumber(whatsappNumber);
        final uri = Uri.parse("https://wa.me/$cleanedNumber?text=${Uri.encodeComponent(message)}");

        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          await ref.read(ttsServiceProvider).speak("Emergency message sent via WhatsApp to ${widget.sosContact.name}.");
          return;
        }
      }

      // Offline Fallback: Dispatch via standard Cellular SMS
      final normalNumber = widget.sosContact.phoneNumber;
      final cleanedNormalNumber = _cleanNumber(normalNumber);
      final smsUri = Uri.parse("sms:$cleanedNormalNumber?body=${Uri.encodeComponent(message)}");

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
        await ref.read(ttsServiceProvider).speak("Emergency SMS sent to ${widget.sosContact.name}.");
      }
    } catch (e) {
      // Fail silently to not disrupt the call experience
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
