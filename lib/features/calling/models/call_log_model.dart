import 'package:hive/hive.dart';

class CallLog extends HiveObject {
  final String id;
  final String name;
  final String phoneNumber;
  final String type; // 'missed', 'dialed', 'incoming'
  final DateTime timestamp;

  CallLog({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.type,
    required this.timestamp,
  });
}

// Manual Hive TypeAdapter to avoid build_runner overhead and compile issues
class CallLogAdapter extends TypeAdapter<CallLog> {
  @override
  final int typeId = 2;

  @override
  CallLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CallLog(
      id: fields[0] as String,
      name: fields[1] as String,
      phoneNumber: fields[2] as String,
      type: fields[3] as String,
      timestamp: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CallLog obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.phoneNumber)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.timestamp);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
