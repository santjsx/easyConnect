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

  @HiveField(6)
  String? sosMsgContactId1;

  @HiveField(7)
  String? sosMsgContactId2;

  @HiveField(8)
  String? layoutMode; // 'modern' | 'classic'

  @HiveField(9)
  String? accentColorHex; // Custom accent color (null defaults to '#6E44FF')

  String get activeLayoutMode => layoutMode ?? 'classic';
  String get activeAccentColorHex => accentColorHex ?? '#6E44FF';

  AppSettings({
    this.language = 'en',
    this.voiceEnabled = true,
    this.sosContactId,
    this.sosLocationShare = false,
    required this.adminPin,
    this.fingerprintEnabled = false,
    this.sosMsgContactId1,
    this.sosMsgContactId2,
    this.layoutMode = 'classic',
    this.accentColorHex = '#6E44FF',
  });
}
