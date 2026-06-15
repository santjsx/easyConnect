import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/services/connectivity_service.dart';
import 'package:easyconnect/features/calling/repositories/call_log_repository.dart';

class WhatsAppCallService {
  final TTSService _ttsService;
  final CallLogRepository _callLogRepository;
  final Ref _ref;

  WhatsAppCallService(this._ttsService, this._callLogRepository, this._ref);

  Future<void> makeVideoCall(BuildContext context, Contact contact) async {
    try {
      // Check connectivity synchronously from pre-cached provider
      final isConnected = _ref.read(connectivityProvider);
      if (!isConnected) {
        await _ttsService.speak("No internet connection");
        return;
      }

      final whatsappNumber = contact.whatsappNumber;
      if (whatsappNumber == null || whatsappNumber.trim().isEmpty) {
        await _ttsService.speak("No WhatsApp number saved for ${contact.name}.");
        return;
      }

      // Trigger haptic feedback
      await HapticFeedback.heavyImpact();

      // Fetch settings to check language
      final settings = _ref.read(settingsProvider).value;
      final language = settings?.language ?? 'en';

      await _ttsService.speak('Starting video call with ${contact.name}');
      // Wait 1500ms for voice prompts to synthesize
      await Future.delayed(const Duration(milliseconds: 1500));

      final cleanedNumber = _cleanNumber(whatsappNumber);

      // 4. Request contacts permission (required to query WhatsApp specific data IDs)
      var status = await Permission.contacts.status;
      if (!status.isGranted) {
        status = await Permission.contacts.request();
      }

      if (status.isGranted) {
        // Try direct native WhatsApp video call!
        const platform = MethodChannel('com.easyconnect.app/calling');
        try {
          final success = await platform.invokeMethod<bool>('makeWhatsAppVideoCall', {
            'phoneNumber': cleanedNumber,
          }) ?? false;

          if (success) {
            await _callLogRepository.addLog(contact.name, contact.phoneNumber, 'dialed');
            return;
          } else {
            // Not found in system contacts! Let's automatically insert them programmatically!
            debugPrint("Contact not found in WhatsApp DB. Automatically adding to system contacts...");
            final added = await platform.invokeMethod<bool>('createSystemContact', {
              'name': contact.name,
              'phoneNumber': cleanedNumber,
            }) ?? false;
            
            if (added) {
              await _ttsService.speak("${contact.name} was not saved in your phone's address book. I have automatically added them now. Please wait a moment for WhatsApp to sync, then try again.");
            }
          }
        } catch (e) {
          debugPrint('Native WhatsApp video call error: $e');
        }
      }

      // Fallback: If contacts permission denied or native call fails (e.g. contact not in system address book),
      // open the WhatsApp chat screen directly.
      final Uri whatsappUri = Uri.parse("https://wa.me/$cleanedNumber");
      if (await canLaunchUrl(whatsappUri)) {
        final success = await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
        if (success) {
          await _callLogRepository.addLog(contact.name, contact.phoneNumber, 'dialed');
        } else if (context.mounted) {
          _handleLaunchFailure(context, language);
        }
      } else {
        if (context.mounted) {
          _handleLaunchFailure(context, language);
        }
      }
    } catch (e) {
      debugPrint('Error in WhatsAppCallService.makeVideoCall: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  String _cleanNumber(String number) {
    final isLeadingPlus = number.startsWith('+');
    final digitsOnly = number.replaceAll(RegExp(r'\D'), '');
    return (isLeadingPlus ? '+' : '') + digitsOnly;
  }

  void _handleLaunchFailure(BuildContext context, String language) {
    _ttsService.speak("WhatsApp is not installed.");
    
    // Check if context is still valid/mounted
    if (!context.mounted) return;

    String contentText = "WhatsApp is not installed.";
    String actionLabel = "Install WhatsApp";

    if (language == 'te') {
      contentText = "వాట్సాప్ ఇన్‌స్టాల్ అయ్యి లేదు";
      actionLabel = "ఇన్‌స్టాల్ చెయ్";
    } else if (language == 'hi') {
      contentText = "व्हाट्सएप इंस्टॉल नहीं है";
      actionLabel = "इंस्टॉल करें";
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(contentText),
        action: SnackBarAction(
          label: actionLabel,
          onPressed: () async {
            try {
              final Uri playStoreUri = Uri.parse(
                "https://play.google.com/store/apps/details?id=com.whatsapp",
              );
              if (await canLaunchUrl(playStoreUri)) {
                await launchUrl(playStoreUri, mode: LaunchMode.externalApplication);
              }
            } catch (e) {
              debugPrint('Error in WhatsAppCallService.installWhatsAppLink: $e');
              await _ttsService.speak("Something went wrong. Please try again.");
            }
          },
        ),
      ),
    );
  }


}

final whatsAppCallServiceProvider = Provider<WhatsAppCallService>((ref) {
  final ttsService = ref.watch(ttsServiceProvider);
  final callLogRepo = ref.watch(callLogRepositoryProvider);
  return WhatsAppCallService(ttsService, callLogRepo, ref);
});
