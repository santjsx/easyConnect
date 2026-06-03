import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/features/contacts/repositories/contact_repository.dart';
import 'package:easyconnect/services/tts_service.dart';

class ContactImportRow {
  final String? name;
  final String? phone;
  final String? whatsapp;
  final String? photoPath;
  final List<String> errors;

  ContactImportRow({
    this.name,
    this.phone,
    this.whatsapp,
    this.photoPath,
    required this.errors,
  });
}

class CsvService {
  final TTSService _ttsService;

  CsvService(this._ttsService);

  /// Generates a CSV string with headers: name,phone,whatsapp,photo_path,position
  Future<String> exportToCSV(List<Contact> contacts) async {
    try {
      final List<List<dynamic>> rows = [
        ['name', 'phone', 'whatsapp', 'photo_path', 'position'],
        ...contacts.map((c) => [
              c.name,
              c.phoneNumber,
              c.whatsappNumber ?? '',
              c.photoPath ?? '',
              c.positionIndex.toString(),
            ]),
      ];
      return const ListToCsvConverter().convert(rows);
    } catch (e) {
      debugPrint('Error in CsvService.exportToCSV: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
      return '';
    }
  }

  /// Exports both contacts and settings as a JSON object
  Future<String> exportToJSON(List<Contact> contacts, AppSettings settings) async {
    try {
      final Map<String, dynamic> data = {
        'version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        'settings': {
          'language': settings.language,
          'voiceEnabled': settings.voiceEnabled,
          'sosContactId': settings.sosContactId,
          'sosLocationShare': settings.sosLocationShare,
          'adminPin': settings.adminPin,
          'fingerprintEnabled': settings.fingerprintEnabled,
        },
        'contacts': contacts.map((c) => {
              'id': c.id,
              'name': c.name,
              'phoneNumber': c.phoneNumber,
              'whatsappNumber': c.whatsappNumber,
              'photoPath': c.photoPath,
              'colorTheme': c.colorTheme,
              'preferredAction': c.preferredAction,
              'positionIndex': c.positionIndex,
              'voiceLabelPath': c.voiceLabelPath,
            }).toList(),
      };
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (e) {
      debugPrint('Error in CsvService.exportToJSON: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
      return '';
    }
  }

  /// Saves the content to a file in the app's Temporary directory and shares it
  Future<void> saveAndShare(String content, String filename) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsString(content);

      final mimeType = filename.endsWith('.csv') ? 'text/csv' : 'application/json';
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mimeType)],
        text: filename.endsWith('.csv') ? 'EasyConnect Contacts CSV Export' : 'EasyConnect JSON Backup',
      );
    } catch (e) {
      debugPrint('Error in CsvService.saveAndShare: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  /// Parses CSV file at [filePath] and validates each row
  Future<List<ContactImportRow>> parseCSV(String filePath) async {
    try {
      final file = File(filePath);
      final input = await file.readAsString();
      final List<List<dynamic>> fields = const CsvToListConverter().convert(input);

      if (fields.isEmpty) {
        return [];
      }

      final headers = fields.first.map((e) => e.toString().trim().toLowerCase()).toList();

      final nameIdx = headers.indexOf('name');
      final phoneIdx = headers.indexOf('phone');
      final whatsappIdx = headers.indexOf('whatsapp');
      final photoPathIdx = headers.indexOf('photo_path');

      if (nameIdx == -1 || phoneIdx == -1) {
        return [
          ContactImportRow(
            errors: ["Invalid CSV columns: 'name' and 'phone' headers are required."],
          ),
        ];
      }

      final List<ContactImportRow> rows = [];
      final Set<String> phoneNumbersInFile = {};

      for (int i = 1; i < fields.length; i++) {
        final rowData = fields[i];
        if (rowData.isEmpty) continue;

        // Skip rows that are completely empty/blank (e.g. trailing lines)
        final bool isRowEmpty = rowData.every((val) => val.toString().trim().isEmpty);
        if (isRowEmpty) continue;

        dynamic getValue(int idx) {
          if (idx >= 0 && idx < rowData.length) {
            return rowData[idx];
          }
          return '';
        }

        final name = nameIdx >= 0 ? getValue(nameIdx).toString().trim() : '';
        final phone = phoneIdx >= 0 ? getValue(phoneIdx).toString().trim() : '';
        final whatsapp = whatsappIdx >= 0 ? getValue(whatsappIdx).toString().trim() : '';
        final photoPath = photoPathIdx >= 0 ? getValue(photoPathIdx).toString().trim() : '';

        final List<String> errors = [];

        // Validate row shape matching header length
        if (rowData.length != headers.length) {
          errors.add("Column count mismatch");
        }

        // Validate name
        if (name.isEmpty) {
          errors.add("Missing name");
        }

        // Validate phone
        final phoneRegex = RegExp(r'^\+?[0-9\s\-\(\)]{7,15}$');
        if (phone.isEmpty) {
          errors.add("Invalid phone number");
        } else if (!phoneRegex.hasMatch(phone)) {
          errors.add("Invalid phone number");
        }

        // Validate WhatsApp (if non-empty)
        if (whatsapp.isNotEmpty && !phoneRegex.hasMatch(whatsapp)) {
          errors.add("Invalid WhatsApp number");
        }

        // Duplicate phone numbers within the file
        if (phone.isNotEmpty) {
          if (phoneNumbersInFile.contains(phone)) {
            errors.add("Duplicate phone number");
          } else {
            phoneNumbersInFile.add(phone);
          }
        }

        rows.add(ContactImportRow(
          name: name.isEmpty ? null : name,
          phone: phone.isEmpty ? null : phone,
          whatsapp: whatsapp.isEmpty ? null : whatsapp,
          photoPath: photoPath.isEmpty ? null : photoPath,
          errors: errors,
        ));
      }

      return rows;
    } catch (e) {
      debugPrint('Error in CsvService.parseCSV: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
      return [];
    }
  }

  /// Imports valid rows into [repo], skipping any with errors
  Future<void> importValidRows(List<ContactImportRow> rows, ContactRepository repo) async {
    try {
      final contacts = await repo.getAllContacts();
      int maxPosition = contacts.isEmpty
          ? -1
          : contacts.map((c) => c.positionIndex).reduce((a, b) => a > b ? a : b);

      for (final row in rows) {
        if (row.errors.isNotEmpty) continue;
        maxPosition++;
        final contact = Contact(
          id: const Uuid().v4(),
          name: row.name!,
          phoneNumber: row.phone!,
          whatsappNumber: row.whatsapp,
          photoPath: row.photoPath,
          positionIndex: maxPosition,
        );
        await repo.addContact(contact);
      }
    } catch (e) {
      debugPrint('Error in CsvService.importValidRows: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }
}

final csvServiceProvider = Provider<CsvService>((ref) {
  final ttsService = ref.watch(ttsServiceProvider);
  return CsvService(ttsService);
});
