import 'package:hive/hive.dart';

part 'app_settings_model.g.dart';

@HiveType(typeId: 1)
class AppSettings extends HiveObject {
  @HiveField(0)
  String language; // 'en', 'hi', 'te'

  @HiveField(1)
  bool voiceEnabled;

  @HiveField(2)
  String? sosContactId;

  @HiveField(3)
  bool sosLocationShare;

  @HiveField(4)
  String adminPin;

  @HiveField(5)
  bool fingerprintEnabled;

  AppSettings({
    this.language = 'en',
    this.voiceEnabled = true,
    this.sosContactId,
    this.sosLocationShare = false,
    required this.adminPin,
    this.fingerprintEnabled = false,
  });
}
