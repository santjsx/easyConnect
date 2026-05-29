import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';

final settingsBoxProvider = Provider<Box<AppSettings>>((ref) {
  return Hive.box<AppSettings>('settings');
});

final settingsProvider = StreamProvider<AppSettings>((ref) async* {
  final box = ref.watch(settingsBoxProvider);
  
  if (box.isNotEmpty) {
    yield box.values.first;
  }
  
  yield* box.watch().map((_) {
    return box.values.first;
  });
});
