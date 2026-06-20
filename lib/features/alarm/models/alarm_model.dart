import 'package:hive/hive.dart';

class Alarm extends HiveObject {
  final String id;
  final String time; // "HH:mm" in 24-hour format
  final String label; // e.g. "Medicine", "Wake up"
  final List<int> days; // 1 = Monday, 7 = Sunday. Empty means one-time.
  bool isEnabled;
  final DateTime lastUpdated;

  Alarm({
    required this.id,
    required this.time,
    required this.label,
    required this.days,
    required this.isEnabled,
    required this.lastUpdated,
  });
}

// Manual Hive TypeAdapter to avoid build_runner overhead and compile issues
class AlarmAdapter extends TypeAdapter<Alarm> {
  @override
  final int typeId = 3;

  @override
  Alarm read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Alarm(
      id: fields[0] as String,
      time: fields[1] as String,
      label: fields[2] as String,
      days: (fields[3] as List).cast<int>(),
      isEnabled: fields[4] as bool,
      lastUpdated: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Alarm obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.time)
      ..writeByte(2)
      ..write(obj.label)
      ..writeByte(3)
      ..write(obj.days)
      ..writeByte(4)
      ..write(obj.isEnabled)
      ..writeByte(5)
      ..write(obj.lastUpdated);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlarmAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
