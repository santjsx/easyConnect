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
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(10)
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
      ..write(obj.accentColorHex);
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
