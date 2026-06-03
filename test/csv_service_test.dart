import 'package:flutter_test/flutter_test.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/services/csv_service.dart';
import 'package:easyconnect/services/tts_service.dart';

class MockTTSService implements TTSService {
  @override
  Future<void> init({String languageCode = 'en'}) async {}
  @override
  Future<void> speak(String text, {String? forceLanguage, bool isDuringActiveCall = false, bool useSystemTts = false}) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setLanguage(String langCode) async {}
  @override
  void dispose() {}
}

void main() {
  group('CsvService Tests', () {
    late CsvService csvService;

    setUp(() {
      csvService = CsvService(MockTTSService());
    });

    test('exportToCSV converts contact list to valid CSV string with headers', () async {
      final contacts = [
        Contact(
          id: '1',
          name: 'John Doe',
          phoneNumber: '+919876543210',
          whatsappNumber: '+919876543210',
          photoPath: '/path/to/photo.jpg',
          positionIndex: 0,
        ),
        Contact(
          id: '2',
          name: 'Jane Smith',
          phoneNumber: '+919123456789',
          positionIndex: 1,
        ),
      ];

      final csvString = await csvService.exportToCSV(contacts);
      
      // Expected CSV output:
      // name,phone,whatsapp,photo_path,position
      // John Doe,+919876543210,+919876543210,/path/to/photo.jpg,0
      // Jane Smith,+919123456789,,,1
      
      expect(csvString, contains('name,phone,whatsapp,photo_path,position'));
      expect(csvString, contains('John Doe,+919876543210,+919876543210,/path/to/photo.jpg,0'));
      expect(csvString, contains('Jane Smith,+919123456789,,,1'));
    });

    test('exportToJSON exports settings and contacts into structured backup format', () async {
      final contacts = [
        Contact(
          id: '1',
          name: 'John Doe',
          phoneNumber: '+919876543210',
          positionIndex: 0,
        ),
      ];

      final settings = AppSettings(
        language: 'hi',
        voiceEnabled: false,
        adminPin: '4321',
      );

      final jsonString = await csvService.exportToJSON(contacts, settings);
      
      expect(jsonString, contains('"version": 1'));
      expect(jsonString, contains('"exported_at"'));
      expect(jsonString, contains('"settings"'));
      expect(jsonString, contains('"contacts"'));
      expect(jsonString, contains('"language": "hi"'));
      expect(jsonString, contains('"adminPin": "4321"'));
      expect(jsonString, contains('"name": "John Doe"'));
    });
  });
}
