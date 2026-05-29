import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:easyconnect/features/calling/models/call_log_model.dart';
import 'package:uuid/uuid.dart';

class CallLogRepository {
  static const String boxName = 'call_logs';

  Future<Box<CallLog>> _getBox() async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<CallLog>(boxName);
    }
    return await Hive.openBox<CallLog>(boxName);
  }

  // Returns all logs sorted by timestamp (most recent first)
  Future<List<CallLog>> getLogs() async {
    try {
      final box = await _getBox();
      final logs = box.values.toList();
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return logs;
    } catch (e) {
      debugPrint('Error in CallLogRepository.getLogs: $e');
      return [];
    }
  }

  // Add a new call log entry
  Future<void> addLog(String name, String phoneNumber, String type) async {
    try {
      final box = await _getBox();
      final id = const Uuid().v4();
      final log = CallLog(
        id: id,
        name: name,
        phoneNumber: phoneNumber,
        type: type,
        timestamp: DateTime.now(),
      );
      await box.put(id, log);
    } catch (e) {
      debugPrint('Error in CallLogRepository.addLog: $e');
    }
  }

  // Clear all call logs (optional maintenance helper)
  Future<void> clearLogs() async {
    try {
      final box = await _getBox();
      await box.clear();
    } catch (e) {
      debugPrint('Error in CallLogRepository.clearLogs: $e');
    }
  }
}

// 1. Repository Provider
final callLogRepositoryProvider = Provider<CallLogRepository>((ref) {
  return CallLogRepository();
});

final callLogsStreamProvider = StreamProvider<List<CallLog>>((ref) async* {
  final repository = ref.watch(callLogRepositoryProvider);
  final box = await repository._getBox();

  // 1. Yield the initial list of logs immediately so the UI populates instantly
  final initialLogs = box.values.toList();
  initialLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  yield initialLogs;

  // 2. Stream subsequent updates in real-time when the database changes
  yield* box.watch().map((_) {
    final logs = box.values.toList();
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs;
  });
});
