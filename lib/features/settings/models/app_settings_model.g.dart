// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 1;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      language: fields[0] as String,
      voiceEnabled: fields[1] as bool,
      sosContactId: fields[2] as String?,
      sosLocationShare: fields[3] as bool,
      adminPin: fields[4] as String,
      fingerprintEnabled: fields[5] as bool,
      sosMsgContactId1: fields[6] as String?,
      sosMsgContactId2: fields[7] as String?,
      layoutMode: fields[8] as String?,
      accentColorHex: fields[9] as String?,
      isSyncEnabled: fields[10] as bool?,
      familySyncCode: fields[11] as String?,
      isKioskModeEnabled: fields[12] as bool?,
      wellnessCheckEnabled: fields[13] as bool?,
      wellnessIntervalHours: fields[14] as int?,
      directTapPreferredAction: fields[15] as bool?,
      unreadMissedCallContactIds: (fields[16] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.language)
      ..writeByte(1)
      ..write(obj.voiceEnabled)
      ..writeByte(2)
      ..write(obj.sosContactId)
      ..writeByte(3)
      ..write(obj.sosLocationShare)
      ..writeByte(4)
      ..write(obj.adminPin)
      ..writeByte(5)
      ..write(obj.fingerprintEnabled)
      ..writeByte(6)
      ..write(obj.sosMsgContactId1)
      ..writeByte(7)
      ..write(obj.sosMsgContactId2)
      ..writeByte(8)
      ..write(obj.layoutMode)
      ..writeByte(9)
      ..write(obj.accentColorHex)
      ..writeByte(10)
      ..write(obj.isSyncEnabled)
      ..writeByte(11)
      ..write(obj.familySyncCode)
      ..writeByte(12)
      ..write(obj.isKioskModeEnabled)
      ..writeByte(13)
      ..write(obj.wellnessCheckEnabled)
      ..writeByte(14)
      ..write(obj.wellnessIntervalHours)
      ..writeByte(15)
      ..write(obj.directTapPreferredAction)
      ..writeByte(16)
      ..write(obj.unreadMissedCallContactIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
