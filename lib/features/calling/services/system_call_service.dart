import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/features/sos/widgets/sos_countdown_dialog.dart';

class SystemCallState {
  final String number;
  final bool isIncoming;
  final int rawState; // Android Call.STATE_*
  final bool isDisconnected;
  final bool isVideo;
  final int disconnectCause;

  SystemCallState({
    required this.number,
    required this.isIncoming,
    required this.rawState,
    this.isDisconnected = false,
    this.isVideo = false,
    this.disconnectCause = -1,
  });
}

class SystemCallNotifier extends StateNotifier<SystemCallState?> {
  SystemCallNotifier() : super(null);

  void setCall(String number, bool isIncoming, int rawCallState, {bool isVideo = false}) {
    state = SystemCallState(
      number: number,
      isIncoming: isIncoming,
      rawState: rawCallState,
      isVideo: isVideo,
    );
  }

  void updateState(int rawState, {int disconnectCause = -1}) {
    if (state != null) {
      state = SystemCallState(
        number: state!.number,
        isIncoming: state!.isIncoming,
        rawState: rawState,
        isVideo: state!.isVideo,
        disconnectCause: disconnectCause,
      );
    }
  }

  void removeCall({int disconnectCause = -1}) {
    if (state != null) {
      state = SystemCallState(
        number: state!.number,
        isIncoming: state!.isIncoming,
        rawState: state!.rawState,
        isVideo: state!.isVideo,
        isDisconnected: true,
        disconnectCause: disconnectCause,
      );
    }
  }

  void clear() {
    state = null;
  }
}

final systemCallProvider = StateNotifierProvider<SystemCallNotifier, SystemCallState?>((ref) {
  return SystemCallNotifier();
});

final defaultDialerProvider = StateProvider<bool>((ref) => false);

class SystemCallService {
  static const MethodChannel _channel = MethodChannel('com.example.easyconnect/calling');
  final Ref _ref;
  Timer? _keepAliveTimer;

  SystemCallService(this._ref) {
    _channel.setMethodCallHandler(_handleMethodCall);
    _startKeepAlivePing();
  }

  /// Periodic 25-second no-op ping to keep the Dart Isolate warm.
  /// This prevents Android from freezing the Dart VM during idle periods,
  /// ensuring instant method channel event delivery when calls arrive.
  void _startKeepAlivePing() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      debugPrint('DartVM keep-alive ping at ${DateTime.now().toIso8601String()}');
    });
  }

  Future<void> init() async {
    try {
      final isDefault = await isDefaultDialer();
      _ref.read(defaultDialerProvider.notifier).state = isDefault;
    } catch (e) {
      // Ignored
    }
    try {
      final activeCall = await _channel.invokeMethod('getActiveSystemCall');
      if (activeCall != null) {
        final map = Map<String, dynamic>.from(activeCall);
        final number = map['number'] as String;
        final isIncoming = map['isIncoming'] as bool;
        final state = map['state'] as int;
        final isVideo = map['isVideo'] as bool? ?? false;
        _ref.read(systemCallProvider.notifier).setCall(number, isIncoming, state, isVideo: isVideo);
      }
    } catch (e) {
      // Ignored
    }
  }

  Future<bool> isDefaultDialer() async {
    try {
      final res = await _channel.invokeMethod<bool>('isDefaultDialer') ?? false;
      debugPrint('DEBUG: isDefaultDialer result: $res');
      return res;
    } catch (e) {
      debugPrint('DEBUG: Error in isDefaultDialer: $e');
      return false;
    }
  }

  Future<void> requestDefaultDialer() async {
    try {
      debugPrint('DEBUG: requestDefaultDialer invoking method channel...');
      await _channel.invokeMethod('requestDefaultDialer');
      debugPrint('DEBUG: requestDefaultDialer channel call finished.');
      final isDefault = await isDefaultDialer();
      _ref.read(defaultDialerProvider.notifier).state = isDefault;
    } catch (e, stack) {
      debugPrint('DEBUG: Error requesting default dialer: $e');
      debugPrint('$stack');
    }
  }

  /// Check if overlay (draw-over-other-apps) permission is granted.
  Future<bool> checkOverlayPermissions() async {
    try {
      final result = await _channel.invokeMethod<bool>('checkOverlayPermissions') ?? false;
      return result;
    } catch (e) {
      debugPrint('DEBUG: Error checking overlay permissions: $e');
      return false;
    }
  }

  /// Open system settings to request overlay permission.
  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('DEBUG: Error requesting overlay permission: $e');
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSystemCallEvent':
        final args = Map<String, dynamic>.from(call.arguments);
        final event = args['event'] as String;
        if (event == 'added') {
          final number = args['number'] as String;
          final isIncoming = args['isIncoming'] as bool;
          final state = args['state'] as int? ?? (isIncoming ? 2 : 1);
          final isVideo = args['isVideo'] as bool? ?? false;

          // SOS auto-rejection: silently hang up incoming calls during SOS countdown
          if (isIncoming) {
            final sosActive = _ref.read(sosCountdownActiveProvider);
            if (sosActive) {
              debugPrint('DEBUG: SOS active — auto-rejecting incoming call from $number');
              try {
                await _channel.invokeMethod('hangUpSystemCall');
              } catch (e) {
                debugPrint('DEBUG: Error auto-rejecting call: $e');
              }
              return;
            }
          }

          _ref.read(systemCallProvider.notifier).setCall(number, isIncoming, state, isVideo: isVideo);
        } else if (event == 'removed') {
          final disconnectCause = args['disconnectCause'] as int? ?? -1;
          _ref.read(systemCallProvider.notifier).removeCall(disconnectCause: disconnectCause);
        } else if (event == 'stateChanged') {
          final state = args['state'] as int;
          final disconnectCause = args['disconnectCause'] as int? ?? -1;
          _ref.read(systemCallProvider.notifier).updateState(state, disconnectCause: disconnectCause);
        }
        break;
      case 'onDefaultDialerChanged':
        final isHeld = call.arguments as bool;
        _ref.read(defaultDialerProvider.notifier).state = isHeld;
        break;
    }
  }
}

final systemCallServiceProvider = Provider<SystemCallService>((ref) {
  final service = SystemCallService(ref);
  service.init();
  return service;
});
