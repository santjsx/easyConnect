import 'package:hive/hive.dart';

part 'contact_model.g.dart';

@HiveType(typeId: 0)
class Contact extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String phoneNumber;

  @HiveField(3)
  final String? whatsappNumber;

  @HiveField(4)
  final String? photoPath;

  @HiveField(5)
  final String colorTheme;

  @HiveField(6)
  final String preferredAction; // 'call', 'video', 'message'

  @HiveField(7)
  final int positionIndex;

  @HiveField(8)
  final String? voiceLabelPath;

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

  Contact copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? whatsappNumber,
    String? photoPath,
    String? colorTheme,
    String? preferredAction,
    int? positionIndex,
    String? voiceLabelPath,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
      photoPath: photoPath ?? this.photoPath,
      colorTheme: colorTheme ?? this.colorTheme,
      preferredAction: preferredAction ?? this.preferredAction,
      positionIndex: positionIndex ?? this.positionIndex,
      voiceLabelPath: voiceLabelPath ?? this.voiceLabelPath,
    );
  }
}
