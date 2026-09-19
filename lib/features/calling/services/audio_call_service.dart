import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';
import 'package:easyconnect/features/calling/screens/calling_screen.dart';
import 'package:easyconnect/features/calling/repositories/call_log_repository.dart';
import 'package:easyconnect/main.dart';

class AudioCallService {
  final TTSService _ttsService;
  final Ref _ref;
  bool _isPlacingCall = false;

  AudioCallService(this._ttsService, this._ref);

  Future<void> makeCall(BuildContext context, Contact contact) async {
    if (_isPlacingCall) {
      debugPrint('DEBUG: Calling is debounced. Ignoring rapid tap.');
      return;
    }
    _isPlacingCall = true;

    try {
      // Check if phone number is empty
      if (contact.phoneNumber.trim().isEmpty) {
        _isPlacingCall = false;
        await _ttsService.speak("This contact has no phone number saved.");
        return;
      }

      // Trigger haptic feedback instantly!
      HapticFeedback.heavyImpact();

      // Read default dialer status synchronously (0ms delay) from the pre-cached provider
      final isDefault = _ref.read(defaultDialerProvider);

      if (isDefault) {
        // 1. Speak Calling immediately so TTS begins playback before Telecom seizes audio focus
        _ttsService.speak('Calling ${contact.name}');

        // 2. Transition to CallingScreen instantly!
        navigatorKey.currentState?.push(PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => CallingScreen(
            contact: contact,
            initialState: CallingState.outgoing,
            isSystemCall: true,
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ));

        // 3. Short 350ms lead time so the audio stream begins playing out loud before Android Telecom sets MODE_IN_CALL
        await Future.delayed(const Duration(milliseconds: 350));
        _placeNativeCall(contact.phoneNumber);
      } else {
        // App is not default dialer. Record dialed call log!
        await _ref.read(callLogRepositoryProvider).addLog(contact.name, contact.phoneNumber, 'dialed');
        _ttsService.speak('Placing call to ${contact.name}');
        await Future.delayed(const Duration(milliseconds: 350));
        _placeNativeCall(contact.phoneNumber);
      }
    } catch (e) {
      debugPrint('Error in AudioCallService.makeCall: $e');
      _ttsService.speak("Something went wrong. Please try again.");
    } finally {
      // Reset the placing call flag after 2 seconds to allow subsequent calling attempts
      Future.delayed(const Duration(seconds: 2), () {
        _isPlacingCall = false;
      });
    }
  }

  // Helper method to place the native call instantly without blocking UI transition
  void _placeNativeCall(String phoneNumber) {
    try {
      const MethodChannel channel = MethodChannel('com.easyconnect.app/calling');
      channel.invokeMethod('makeDirectCall', {
        'phoneNumber': phoneNumber,
      });
    } catch (e) {
      debugPrint('Error placing native call: $e');
    }
  }
}

final audioCallServiceProvider = Provider<AudioCallService>((ref) {
  final ttsService = ref.watch(ttsServiceProvider);
  return AudioCallService(ttsService, ref);
});
