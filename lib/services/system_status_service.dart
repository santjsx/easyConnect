import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';
import 'package:easyconnect/features/calling/providers/is_calling_active_provider.dart';

class SystemStatus {
  final int batteryLevel;
  final String signalStrength; // 'good', 'weak', 'disconnected'
  final String simState; // 'ready', 'absent', 'locked', 'error', 'unknown'
  final bool isCharging;

  SystemStatus({
    required this.batteryLevel,
    required this.signalStrength,
    required this.simState,
    required this.isCharging,
  });
}

class SystemStatusNotifier extends StateNotifier<SystemStatus> {
  static const _platform = MethodChannel('com.easyconnect.app/calling');
  final Ref _ref;
  Timer? _timer;
  
  // Track announced thresholds in the current discharge cycle
  final Set<int> _announcedThresholds = {};
  bool _wasCharging = false;
  int? _queuedThreshold;
  bool _isInit = true;

  SystemStatusNotifier(this._ref)
      : super(SystemStatus(
          batteryLevel: 80,
          signalStrength: 'good',
          simState: 'ready',
          isCharging: false,
        )) {
    _updateStatus();
    // Poll every 30 seconds for battery-saving real-time updates (never faster)
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _updateStatus());

    // Listen to call events to fire queued warning immediately when a call finishes
    _ref.listen<bool>(isCallingScreenActiveProvider, (prev, next) {
      if (next == false) {
        _triggerQueuedWarningIfCallEnded();
      }
    });

    _ref.listen<SystemCallState?>(systemCallProvider, (prev, next) {
      if (next == null) {
        _triggerQueuedWarningIfCallEnded();
      }
    });
  }

  void updateBatteryFromNative(int battery, bool isCharging) {
    if (state.batteryLevel != battery || state.isCharging != isCharging) {
      state = SystemStatus(
        batteryLevel: battery,
        signalStrength: state.signalStrength,
        simState: state.simState,
        isCharging: isCharging,
      );
      _processBatteryStatus(battery, isCharging);
    }
  }

  Future<void> _updateStatus() async {
    try {
      final int battery = await _platform.invokeMethod<int>('getBatteryLevel') ?? 80;
      final String signal = await _platform.invokeMethod<String>('getSignalStrength') ?? 'good';
      final String sim = await _platform.invokeMethod<String>('getSimState') ?? 'ready';
      final bool charging = await _platform.invokeMethod<bool>('isDeviceCharging') ?? false;

      state = SystemStatus(
        batteryLevel: battery,
        signalStrength: signal,
        simState: sim,
        isCharging: charging,
      );

      _processBatteryStatus(battery, charging);
    } catch (_) {
      // Safe fallbacks on platform error
    }
  }

  void _processBatteryStatus(int battery, bool isCharging) {
    if (isCharging) {
      // Clear announced discharge warnings when plugged in
      _announcedThresholds.clear();
      _queuedThreshold = null;

      // Single shot plugged in warning when first plugged in
      if (!_wasCharging) {
        _wasCharging = true;
        // Do not announce "charging" on app initial cold launch to avoid spoken noise
        if (!_isInit) {
          _triggerChargingAnnouncement(battery);
        }
      }
    } else {
      // Single shot unplugged warning when unplugged
      if (_wasCharging) {
        _wasCharging = false;
        if (!_isInit) {
          // If a threshold warning is about to be triggered, we can skip the standard discharging announcement
          // to avoid duplicate/overlapping announcements.
          final hasLowBatteryWarning = (battery <= 20 && !_announcedThresholds.contains(20)) ||
                                       (battery <= 10 && !_announcedThresholds.contains(10)) ||
                                       (battery <= 5 && !_announcedThresholds.contains(5));
          if (!hasLowBatteryWarning) {
            _triggerDischargingAnnouncement(battery);
          }
        }
      }

      // Battery warning threshold logic
      int? targetThreshold;
      if (battery <= 5) {
        if (!_announcedThresholds.contains(5)) {
          targetThreshold = 5;
        }
      } else if (battery <= 10) {
        if (!_announcedThresholds.contains(10)) {
          targetThreshold = 10;
        }
      } else if (battery <= 20) {
        if (!_announcedThresholds.contains(20)) {
          targetThreshold = 20;
        }
      }

      // Re-arm thresholds if battery goes back up
      if (battery > 20) {
        _announcedThresholds.remove(20);
        _announcedThresholds.remove(10);
        _announcedThresholds.remove(5);
      } else if (battery > 10) {
        _announcedThresholds.remove(10);
        _announcedThresholds.remove(5);
      } else if (battery > 5) {
        _announcedThresholds.remove(5);
      }

      // If app is launched at a low battery level, trigger warning immediately
      if (targetThreshold != null) {
        final isCalling = _ref.read(isCallingScreenActiveProvider) || _ref.read(systemCallProvider) != null;
        if (isCalling) {
          // Queue the warning, picking the most critical/lowest threshold
          if (_queuedThreshold == null || targetThreshold < _queuedThreshold!) {
            _queuedThreshold = targetThreshold;
          }
        } else {
          _triggerThresholdWarning(targetThreshold);
        }
      }
    }
    _isInit = false;
  }

  void _triggerQueuedWarningIfCallEnded() {
    final isCalling = _ref.read(isCallingScreenActiveProvider) || _ref.read(systemCallProvider) != null;
    if (!isCalling && _queuedThreshold != null) {
      _triggerThresholdWarning(_queuedThreshold!);
      _queuedThreshold = null;
    }
  }

  Future<void> _triggerChargingAnnouncement(int battery) async {
    final tts = _ref.read(ttsServiceProvider);
    final Box<AppSettings> settingsBox = _ref.read(settingsBoxProvider);
    final lang = settingsBox.isNotEmpty ? settingsBox.values.first.language : 'en';

    String msg = '';
    if (lang == 'te') {
      msg = "బ్యాటరీ ఛార్జ్ అవుతోంది, $battery శాతం ఉంది.";
    } else if (lang == 'hi') {
      msg = "बैटरी चार्ज हो रही है, $battery प्रतिशत है।";
    } else {
      msg = "Battery is charging, it is at $battery percent.";
    }

    await tts.speak(msg);
    await HapticFeedback.lightImpact();
  }

  Future<void> _triggerDischargingAnnouncement(int battery) async {
    final tts = _ref.read(ttsServiceProvider);
    final Box<AppSettings> settingsBox = _ref.read(settingsBoxProvider);
    final lang = settingsBox.isNotEmpty ? settingsBox.values.first.language : 'en';

    String msg = '';
    if (lang == 'te') {
      msg = "ఛార్జర్ తొలగించబడింది, బ్యాటరీ $battery శాతం ఉంది.";
    } else if (lang == 'hi') {
      msg = "चार्जिंग बंद हो गई है, बैटरी $battery प्रतिशत है।";
    } else {
      msg = "Charger disconnected, battery is at $battery percent.";
    }

    await tts.speak(msg);
    await HapticFeedback.lightImpact();
  }

  Future<void> _triggerThresholdWarning(int threshold) async {
    _announcedThresholds.add(threshold);
    final tts = _ref.read(ttsServiceProvider);

    if (threshold == 20) {
      await tts.speak('battery_20');
      await HapticFeedback.vibrate();
    } else if (threshold == 10) {
      await tts.speak('battery_10');
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      await HapticFeedback.heavyImpact();
    } else if (threshold == 5) {
      await tts.speak('battery_5');
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final systemStatusProvider = StateNotifierProvider<SystemStatusNotifier, SystemStatus>((ref) {
  return SystemStatusNotifier(ref);
});
