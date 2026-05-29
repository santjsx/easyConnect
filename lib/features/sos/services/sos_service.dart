import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/sos/widgets/sos_countdown_dialog.dart';

class SosService {
  final TTSService _ttsService;

  SosService(this._ttsService);

  Future<void> triggerSOS(BuildContext context) async {
    try {
      // 1. Read sosContactId from settings
      final Box<AppSettings> settingsBox;
      if (Hive.isBoxOpen('settings')) {
        settingsBox = Hive.box<AppSettings>('settings');
      } else {
        settingsBox = await Hive.openBox<AppSettings>('settings');
      }
      
      AppSettings? settings;
      if (settingsBox.isNotEmpty) {
        settings = settingsBox.values.first;
      }

      final sosContactId = settings?.sosContactId;

      if (sosContactId == null || sosContactId.isEmpty) {
        await _ttsService.speak("Emergency contact not set. Ask your family to set this up.");
        return;
      }

      // 2. Fetch the corresponding contact object
      final Box<Contact> contactsBox;
      if (Hive.isBoxOpen('contacts')) {
        contactsBox = Hive.box<Contact>('contacts');
      } else {
        contactsBox = await Hive.openBox<Contact>('contacts');
      }
      
      final sosContact = contactsBox.get(sosContactId);

      if (sosContact == null) {
        await _ttsService.speak("Emergency contact not set. Ask your family to set this up.");
        return;
      }

      // 3. Show full-screen countdown overlay dialog
      if (!context.mounted) return;

      await showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, anim1, anim2) {
          return SosCountdownDialog(
            sosContact: sosContact,
            locationShare: settings?.sosLocationShare ?? false,
          );
        },
      );
    } catch (e) {
      debugPrint('Error in SosService.triggerSOS: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }
}

final sosServiceProvider = Provider<SosService>((ref) {
  final ttsService = ref.watch(ttsServiceProvider);
  return SosService(ttsService);
});
