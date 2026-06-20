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

  @HiveField(17)
  String? elevenLabsApiKey;

  @HiveField(18)
  String? elevenLabsVoiceId;

  @HiveField(19)
  String? elevenLabsModelId;

  @HiveField(20)
  String? azureSpeechSubscriptionKey;

  @HiveField(21)
  String? azureSpeechRegion;

  @HiveField(22)
  String? azureSpeechTeluguVoice;

  @HiveField(23)
  String? azureSpeechHindiVoice;

  @HiveField(24)
  String? azureSpeechEnglishVoice;

  String get activeLayoutMode => layoutMode ?? 'classic';
  String get activeAccentColorHex => accentColorHex ?? '#6E44FF';
  String get activeElevenLabsApiKey => elevenLabsApiKey ?? '';
  String get activeElevenLabsVoiceId => elevenLabsVoiceId ?? 'EMxdghWQV7gqV33j4J3F';
  String get activeElevenLabsModelId => elevenLabsModelId ?? 'eleven_multilingual_v2';
  String get activeAzureSpeechSubscriptionKey => azureSpeechSubscriptionKey ?? '';
  String get activeAzureSpeechRegion => azureSpeechRegion ?? 'eastus';
  String get activeAzureSpeechTeluguVoice => azureSpeechTeluguVoice ?? 'te-IN-ShrutiNeural';
  String get activeAzureSpeechHindiVoice => azureSpeechHindiVoice ?? 'hi-IN-SwaraNeural';
  String get activeAzureSpeechEnglishVoice => azureSpeechEnglishVoice ?? 'en-IN-NeerjaNeural';
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
    this.elevenLabsApiKey = '',
    this.elevenLabsVoiceId = 'EMxdghWQV7gqV33j4J3F',
    this.elevenLabsModelId = 'eleven_multilingual_v2',
    this.azureSpeechSubscriptionKey = '',
    this.azureSpeechRegion = 'eastus',
    this.azureSpeechTeluguVoice = 'te-IN-ShrutiNeural',
    this.azureSpeechHindiVoice = 'hi-IN-SwaraNeural',
    this.azureSpeechEnglishVoice = 'en-IN-NeerjaNeural',
  });
}
