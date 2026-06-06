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

  @HiveField(10)
  bool? isSyncEnabled;

  @HiveField(11)
  String? familySyncCode;

  @HiveField(12)
  bool? isKioskModeEnabled;

  @HiveField(13)
  bool? wellnessCheckEnabled;

  @HiveField(14)
  int? wellnessIntervalHours;

  @HiveField(15)
  bool? directTapPreferredAction;

  @HiveField(16)
  List<String>? unreadMissedCallContactIds;

  String get activeLayoutMode => layoutMode ?? 'classic';
  String get activeAccentColorHex => accentColorHex ?? '#6E44FF';
  bool get activeIsSyncEnabled => isSyncEnabled ?? false;
  String get activeFamilySyncCode => familySyncCode ?? '';
  bool get activeIsKioskModeEnabled => isKioskModeEnabled ?? false;
  bool get activeWellnessCheckEnabled => wellnessCheckEnabled ?? false;
  int get activeWellnessIntervalHours => wellnessIntervalHours ?? 12;
  bool get activeDirectTapPreferredAction => directTapPreferredAction ?? false;
  List<String> get activeUnreadMissedCallContactIds => unreadMissedCallContactIds ?? const [];

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
    this.isSyncEnabled = false,
    this.familySyncCode = '',
    this.isKioskModeEnabled = false,
    this.wellnessCheckEnabled = false,
    this.wellnessIntervalHours = 12,
    this.directTapPreferredAction = false,
    this.unreadMissedCallContactIds = const [],
  });
}
