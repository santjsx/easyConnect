import 'package:hive/hive.dart';

part 'contact_model.g.dart';

@HiveType(typeId: 0)
class Contact extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String phoneNumber;

  @HiveField(3)
  String? whatsappNumber;

  @HiveField(4)
  String? photoPath;

  @HiveField(5)
  String colorTheme;

  @HiveField(6)
  String preferredAction; // 'call', 'video', 'message'

  @HiveField(7)
  int positionIndex;

  @HiveField(8)
  String? voiceLabelPath;

  Contact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.whatsappNumber,
    this.photoPath,
    this.colorTheme = '#4CAF50',
    this.preferredAction = 'call',
    required this.positionIndex,
    this.voiceLabelPath,
  });
}
