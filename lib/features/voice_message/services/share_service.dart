import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/services/tts_service.dart';

class ShareService {
  final TTSService _ttsService;

  ShareService(this._ttsService);

  Future<void> sendVoiceMessage(String filePath, Contact contact) async {
    try {
      // Check connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final isConnected = connectivityResult.isNotEmpty &&
          connectivityResult.any((r) => r != ConnectivityResult.none);
      if (!isConnected) {
        await _ttsService.speak("No internet connection");
        return;
      }

      // Check if WhatsApp is installed using deep link scheme
      final whatsappNumber = contact.whatsappNumber ?? '';
      final cleanedNumber = _cleanNumber(whatsappNumber);
      final Uri whatsappUri = Uri.parse("https://wa.me/$cleanedNumber");

      final isInstalled = await canLaunchUrl(whatsappUri);
      if (!isInstalled) {
        await _ttsService.speak("WhatsApp is not installed. Cannot send message.");
        return;
      }

      // Try direct WhatsApp sharing (pre-selects recipient chat and attaches audio)!
      const platform = MethodChannel('com.example.easyconnect/calling');
      try {
        final success = await platform.invokeMethod<bool>('shareAudioToWhatsApp', {
          'filePath': filePath,
          'phoneNumber': cleanedNumber,
        }) ?? false;
        
        if (success) {
          await _ttsService.speak("Sending message");
          return;
        }
      } catch (e) {
        debugPrint('Direct WhatsApp share failed: $e');
      }

      // Fallback: Open Android/iOS system share sheet using share_plus
      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'audio/m4a')],
        text: '',
      );

      // Spoken feedback after share sheet completes/closes
      await _ttsService.speak("Message sent");
    } catch (e) {
      debugPrint('Error in ShareService.sendVoiceMessage: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  String _cleanNumber(String number) {
    final isLeadingPlus = number.startsWith('+');
    final digitsOnly = number.replaceAll(RegExp(r'\D'), '');
    return (isLeadingPlus ? '+' : '') + digitsOnly;
  }
}

final shareServiceProvider = Provider<ShareService>((ref) {
  final ttsService = ref.watch(ttsServiceProvider);
  return ShareService(ttsService);
});
