import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/calling/repositories/call_log_repository.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';
import 'package:easyconnect/features/calling/providers/is_calling_active_provider.dart';

/// Full call lifecycle states matching Android Telecom.
/// idle → outgoing(dialing) → ongoing(active) ↔ onHold → disconnecting → ended
/// idle → incoming(ringing) → ongoing(active) ↔ onHold → disconnecting → ended
enum CallingState { incoming, outgoing, ongoing, onHold, disconnecting }

class CallStatus {
  static const String idle = '';
  static const String incomingVoice = 'Incoming Call';
  static const String incomingVideo = 'Incoming Video Call';
  static const String calling = 'Calling...';
  static const String ringing = 'Ringing...';
  static const String connecting = 'Connecting...';
  static const String connected = 'Connected';
  static const String onHold = 'On Hold';
  static const String reconnecting = 'Reconnecting...';
  static const String ended = 'Call Ended';
  static const String declined = 'Call Declined';
  static const String noAnswer = 'No Answer';
  static const String failed = 'Call Failed';
  static const String busy = 'Busy';
  static const String unavailable = 'Unavailable';
}

const MethodChannel _channel = MethodChannel('com.easyconnect.app/calling');

// ─────────────────────────────────────────────────────────────────────────────
// CallingScreen
// ─────────────────────────────────────────────────────────────────────────────
class CallingScreen extends ConsumerStatefulWidget {
  final Contact contact;
  final CallingState initialState;
  final bool isSystemCall;

  const CallingScreen({
    super.key,
    required this.contact,
    required this.initialState,
    this.isSystemCall = false,
  });

  @override
  ConsumerState<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends ConsumerState<CallingScreen>
    with TickerProviderStateMixin {
  // ── Call State ──
  late CallingState _currentState;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isOnHold = false;
  bool _showDtmfKeypad = false;
  bool _isAllowedToPop = false;
  String _dtmfInput = '';
  bool _isDisposed = false;

  // ── Timers ──
  Timer? _stateTimer;
  Timer? _ttsTimer;
  Timer? _callDurationTimer;
  int _callSeconds = 0;
  String _language = 'en';

  // ── Animation Controllers ──
  late AnimationController _pulseController;
  late AnimationController _swipeHintController;

  @override
  void initState() {
    super.initState();
    _currentState = widget.initialState;
    _loadLanguage();
    _initAnimations();
    _handleStateInit();
    Future.microtask(() {
      if (mounted) {
        ref.read(isCallingScreenActiveProvider.notifier).state = true;
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stateTimer?.cancel();
    _ttsTimer?.cancel();
    _callDurationTimer?.cancel();
    _pulseController.dispose();
    _swipeHintController.dispose();
    // Note: Do not call ref.read(ttsServiceProvider).stop() here, because we want
    // the "Call ended" spoken feedback to play completely in the background after the screen pops.
    final activeNotifier = ref.read(isCallingScreenActiveProvider.notifier);
    Future.microtask(() {
      activeNotifier.state = false;
    });
    super.dispose();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _swipeHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (_currentState == CallingState.incoming ||
        _currentState == CallingState.outgoing) {
      _pulseController.repeat();
    }
    if (_currentState == CallingState.incoming) {
      _swipeHintController.repeat(reverse: true);
    }
  }

  void _loadLanguage() {
    final settingsBox =
        Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    if (settingsBox != null && settingsBox.isNotEmpty) {
      _language = settingsBox.values.first.language;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // State Initialization
  // ─────────────────────────────────────────────────────────────────────────
  void _handleStateInit() {
    ref.read(ttsServiceProvider).stop();

    if (_currentState == CallingState.incoming) {
      _startIncomingTtsLoop();
    } else if (_currentState == CallingState.outgoing) {
      _speakOutgoingPrompt();
      if (!widget.isSystemCall) {
        // Demo mode: simulate connection after 2.5s
        _stateTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) _handleCallConnected();
        });
      }
    } else if (_currentState == CallingState.ongoing) {
      _startCallDurationTimer();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TTS
  // ─────────────────────────────────────────────────────────────────────────
  void _speakOutgoingPrompt() {
    if (_isDisposed || !mounted) return;
    final tts = ref.read(ttsServiceProvider);
    switch (_language) {
      case 'hi':
        tts.speak('${widget.contact.name} को कॉल किया जा रहा है');
        break;
      case 'te':
        tts.speak('${widget.contact.name} కి కాల్ చేస్తున్నారు');
        break;
      default:
        tts.speak('Calling ${widget.contact.name}');
    }
  }

  void _startIncomingTtsLoop() {
    if (_isDisposed || !mounted) return;
    final tts = ref.read(ttsServiceProvider);
    void speak() {
      if (_isDisposed || !mounted) return;
      switch (_language) {
        case 'hi':
          tts.speak('${widget.contact.name} से इनकमिंग कॉल आ रही है');
          break;
        case 'te':
          tts.speak('${widget.contact.name} నుండి ఇన్‌కమింగ్ కాల్ వస్తోంది');
          break;
        default:
          tts.speak('Incoming call from ${widget.contact.name}');
      }
    }

    speak();
    _ttsTimer = Timer.periodic(const Duration(seconds: 4), (_) => speak());
  }

  void _speakCallConnected() {
    if (_isDisposed || !mounted) return;
    final tts = ref.read(ttsServiceProvider);
    switch (_language) {
      case 'hi':
        tts.speak('कॉल जुड़ गया है');
        break;
      case 'te':
        tts.speak('కాల్ కనెక్ట్ చేయబడింది');
        break;
      default:
        tts.speak('Call connected');
    }
  }

  void _speakCallEnded() {
    if (_isDisposed || !mounted) return;
    final tts = ref.read(ttsServiceProvider);
    switch (_language) {
      case 'hi':
        tts.speak('कॉल समाप्त हो गया');
        break;
      case 'te':
        tts.speak('కాల్ ముగిసింది');
        break;
      default:
        tts.speak('Call ended');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // State Transitions
  // ─────────────────────────────────────────────────────────────────────────
  void _handleCallConnected() {
    if (_isDisposed || !mounted) return;
    _ttsTimer?.cancel();
    _stateTimer?.cancel();
    try {
      _pulseController.stop();
    } catch (_) {}
    try {
      _swipeHintController.stop();
    } catch (_) {}
    _speakCallConnected();
    setState(() {
      _currentState = CallingState.ongoing;
      _isOnHold = false;
    });
    _startCallDurationTimer();
  }

  void _handleDisconnect() {
    if (_isDisposed || !mounted) return;
    if (_currentState == CallingState.disconnecting) return; // Already disconnecting
    _ttsTimer?.cancel();
    _stateTimer?.cancel();
    _callDurationTimer?.cancel();
    try {
      _pulseController.stop();
    } catch (_) {}
    try {
      _swipeHintController.stop();
    } catch (_) {}
    _speakCallEnded();
    setState(() {
      _currentState = CallingState.disconnecting;
      _showDtmfKeypad = false;
      _isAllowedToPop = true;
    });
    ref.read(systemCallProvider.notifier).clear();
    Navigator.of(context).pop();
  }

  void _handleHoldStateChange(bool isHeld) {
    if (_isDisposed || !mounted) return;
    setState(() {
      _isOnHold = isHeld;
      _currentState = isHeld ? CallingState.onHold : CallingState.ongoing;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Call Actions
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _acceptCall() async {
    _ttsTimer?.cancel();
    _stateTimer?.cancel();
    _swipeHintController.stop();
    await HapticFeedback.heavyImpact();

    if (widget.isSystemCall) {
      _channel.invokeMethod('acceptSystemCall');
      // State update will arrive from the system call listener
      return;
    }
    _handleCallConnected();
  }

  Future<void> _declineCall() async {
    _ttsTimer?.cancel();
    _stateTimer?.cancel();
    _swipeHintController.stop();
    await HapticFeedback.heavyImpact();

    await ref.read(callLogRepositoryProvider).addLog(
          widget.contact.name,
          widget.contact.phoneNumber,
          'missed',
        );

    if (widget.isSystemCall) {
      _channel.invokeMethod('hangUpSystemCall');
      _handleDisconnect();
      return;
    }

    _speakCallEnded();
    if (mounted) {
      setState(() => _isAllowedToPop = true);
      Navigator.pop(context);
    }
  }

  Future<void> _hangUp() async {
    _ttsTimer?.cancel();
    _stateTimer?.cancel();
    _callDurationTimer?.cancel();
    await HapticFeedback.heavyImpact();

    final logType =
        widget.initialState == CallingState.incoming ? 'incoming' : 'dialed';
    await ref.read(callLogRepositoryProvider).addLog(
          widget.contact.name,
          widget.contact.phoneNumber,
          logType,
        );

    if (widget.isSystemCall) {
      _channel.invokeMethod('hangUpSystemCall');
      _handleDisconnect();
      return;
    }

    _speakCallEnded();
    if (mounted) {
      setState(() => _isAllowedToPop = true);
      Navigator.pop(context);
    }
  }

  void _toggleMute() async {
    await HapticFeedback.mediumImpact();
    final next = !_isMuted;
    setState(() => _isMuted = next);
    if (widget.isSystemCall) {
      _channel.invokeMethod('setCallMute', {'mute': next});
    }
  }

  void _toggleSpeaker() async {
    await HapticFeedback.mediumImpact();
    final next = !_isSpeakerOn;
    setState(() => _isSpeakerOn = next);
    if (widget.isSystemCall) {
      _channel.invokeMethod('setCallSpeaker', {'speaker': next});
    }
  }

  void _toggleHold() async {
    await HapticFeedback.mediumImpact();
    if (widget.isSystemCall) {
      if (_isOnHold) {
        _channel.invokeMethod('unholdCall');
      } else {
        _channel.invokeMethod('holdCall');
      }
      // Native state change listener will update _isOnHold
    } else {
      _handleHoldStateChange(!_isOnHold);
    }
  }

  void _sendDtmfTone(String digit) async {
    await HapticFeedback.lightImpact();
    setState(() => _dtmfInput += digit);
    if (widget.isSystemCall) {
      _channel.invokeMethod('playDtmfTone', {'digit': digit});
      Future.delayed(const Duration(milliseconds: 200), () {
        _channel.invokeMethod('stopDtmfTone');
      });
    }
  }

  void _toggleDtmfKeypad() {
    HapticFeedback.mediumImpact();
    setState(() {
      _showDtmfKeypad = !_showDtmfKeypad;
      if (!_showDtmfKeypad) _dtmfInput = '';
    });
  }

  // ── Silence incoming ringer (TTS) without declining ──
  void _silenceRinger() {
    _ttsTimer?.cancel();
    ref.read(ttsServiceProvider).stop();
    HapticFeedback.mediumImpact();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Timer
  // ─────────────────────────────────────────────────────────────────────────
  void _startCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callSeconds = 0;
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // Read systemCallProvider during build, we trigger rebuilds via setState in the listener!
    final systemCall = widget.isSystemCall ? ref.read(systemCallProvider) : null;

    // ── System call state listener ──
    if (widget.isSystemCall) {
      ref.listen<SystemCallState?>(systemCallProvider, (prev, next) {
        if (_isDisposed || !mounted) return;
        if (next == null) return;

        if (next.isDisconnected || next.rawState == 7 || next.rawState == 10) { // 7 = DISCONNECTED, 10 = DISCONNECTING
          _handleDisconnect();
          return;
        }

        // Trigger a rebuild to update status pill and state if rawState changes
        if (next.rawState != prev?.rawState) {
          final oldState = _currentState;
          final wasOnHold = _isOnHold;

          switch (next.rawState) {
            case 2: // Call.STATE_RINGING
              setState(() {
                _currentState = CallingState.incoming;
              });
              break;
            case 8: // Call.STATE_SELECT_PHONE_ACCOUNT
            case 9: // Call.STATE_CONNECTING
            case 1: // Call.STATE_DIALING
              setState(() {
                _currentState = CallingState.outgoing;
              });
              break;
            case 4: // Call.STATE_ACTIVE
              if (oldState == CallingState.onHold || wasOnHold) {
                _handleHoldStateChange(false); // Resumed from hold
              } else if (oldState != CallingState.ongoing) {
                _handleCallConnected(); // Connected for the first time
              }
              break;
            case 3: // Call.STATE_HOLDING
              if (!wasOnHold || oldState != CallingState.onHold) {
                _handleHoldStateChange(true); // Put on hold
              }
              break;
          }
        }
      });
    }

    final ringColors = [
      const Color(0xFF4CAF50),
      const Color(0xFF9C27B0),
      const Color(0xFFE91E63),
      const Color(0xFFFF5722),
      const Color(0xFFFFC107),
      const Color(0xFF009688),
    ];
    final ringColor =
        ringColors[widget.contact.positionIndex % ringColors.length];

    return PopScope(
      canPop: _isAllowedToPop,
      child: Scaffold(
        backgroundColor: kAppBackground,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kAppBackground, Color(0xFFFCFCFE), Colors.white],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // ── Main content ──
                _buildMainContent(ringColor, systemCall),
                // ── DTMF Keypad Overlay ──
                if (_showDtmfKeypad) _buildDtmfOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Main Content Layout
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMainContent(Color ringColor, SystemCallState? systemCall) {
    final isRinging = _currentState == CallingState.incoming ||
        _currentState == CallingState.outgoing;
    final showPhoneNumber =
        widget.contact.phoneNumber != widget.contact.name &&
            widget.contact.phoneNumber.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        children: [
          const Spacer(flex: 2),

          // ── Caller Card ──
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: kAccentPurple.withValues(alpha: 0.08),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: kAccentPurple.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar with pulse
                _PulsingAvatar(
                  color: ringColor,
                  isActive: isRinging,
                  child: _buildAvatar(ringColor),
                ),
                const SizedBox(height: 24.0),

                // Name
                Semantics(
                  header: true,
                  child: Text(
                    widget.contact.name,
                    style: const TextStyle(
                      fontSize: 34.0,
                      fontWeight: FontWeight.bold,
                      color: kTextNavy,
                      letterSpacing: -0.8,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Phone number (if different from name)
                if (showPhoneNumber) ...[
                  const SizedBox(height: 6.0),
                  Text(
                    widget.contact.phoneNumber,
                    style: const TextStyle(
                      fontSize: 17.0,
                      fontWeight: FontWeight.w500,
                      color: kTextSlate,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 16.0),

                // State indicator pill
                _buildStatusPill(systemCall),
              ],
            ),
          ),

          const Spacer(flex: 3),

          // ── Controls ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _buildControls(),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatusPill(SystemCallState? systemCall) {
    Color dotColor = kAccentPurple;
    String statusText = CallStatus.idle;
    bool showSpinner = false;

    if (widget.isSystemCall && systemCall != null) {
      if (systemCall.isDisconnected) {
        switch (systemCall.disconnectCause) {
          case 6: // DisconnectCause.REJECTED
            statusText = CallStatus.declined;
            dotColor = kStopRed;
            break;
          case 5: // DisconnectCause.MISSED
            statusText = CallStatus.noAnswer;
            dotColor = kStopRed;
            break;
          case 7: // DisconnectCause.BUSY
            statusText = CallStatus.busy;
            dotColor = kStopRed;
            break;
          case 1: // DisconnectCause.ERROR
            statusText = CallStatus.failed;
            dotColor = kStopRed;
            break;
          default:
            statusText = CallStatus.ended;
            dotColor = kStopRed;
            break;
        }
      } else {
        switch (systemCall.rawState) {
          case 2: // Call.STATE_RINGING
            statusText = systemCall.isVideo ? CallStatus.incomingVideo : CallStatus.incomingVoice;
            dotColor = kCallGreen;
            break;
          case 8: // Call.STATE_SELECT_PHONE_ACCOUNT
          case 9: // Call.STATE_CONNECTING
            statusText = CallStatus.calling;
            dotColor = kAccentPurple;
            showSpinner = true;
            break;
          case 1: // Call.STATE_DIALING
            statusText = CallStatus.ringing;
            dotColor = kAccentPurple;
            showSpinner = true;
            break;
          case 4: // Call.STATE_ACTIVE
            statusText = CallStatus.connected;
            dotColor = kCallGreen;
            break;
          case 3: // Call.STATE_HOLDING
            statusText = CallStatus.onHold;
            dotColor = const Color(0xFFF59E0B);
            break;
          case 10: // Call.STATE_DISCONNECTING
            statusText = CallStatus.ended;
            dotColor = kStopRed;
            break;
          case 7: // Call.STATE_DISCONNECTED
            switch (systemCall.disconnectCause) {
              case 6:
                statusText = CallStatus.declined;
                dotColor = kStopRed;
                break;
              case 5:
                statusText = CallStatus.noAnswer;
                dotColor = kStopRed;
                break;
              case 7:
                statusText = CallStatus.busy;
                dotColor = kStopRed;
                break;
              case 1:
                statusText = CallStatus.failed;
                dotColor = kStopRed;
                break;
              default:
                statusText = CallStatus.ended;
                dotColor = kStopRed;
                break;
            }
            break;
          default:
            statusText = CallStatus.calling;
            dotColor = kAccentPurple;
            showSpinner = true;
            break;
        }
      }
    } else {
      switch (_currentState) {
        case CallingState.incoming:
          statusText = CallStatus.incomingVoice;
          dotColor = kCallGreen;
          break;
        case CallingState.outgoing:
          statusText = CallStatus.calling;
          dotColor = kAccentPurple;
          showSpinner = true;
          break;
        case CallingState.ongoing:
          statusText = CallStatus.connected;
          dotColor = kCallGreen;
          break;
        case CallingState.onHold:
          statusText = CallStatus.onHold;
          dotColor = const Color(0xFFF59E0B);
          break;
        case CallingState.disconnecting:
          statusText = CallStatus.ended;
          dotColor = kStopRed;
          break;
      }
    }

    String displayLabelText;
    final isTimer = statusText == CallStatus.connected || statusText == CallStatus.onHold;
    
    if (statusText == CallStatus.connected) {
      displayLabelText = _formatDuration(_callSeconds);
    } else if (statusText == CallStatus.onHold) {
      displayLabelText = 'On Hold · ${_formatDuration(_callSeconds)}';
    } else {
      displayLabelText = statusText;
    }

    final isError = statusText == CallStatus.failed || 
                    statusText == CallStatus.declined || 
                    statusText == CallStatus.noAnswer || 
                    statusText == CallStatus.busy ||
                    statusText == CallStatus.unavailable;

    Color textColor;
    if (isError) {
      textColor = kStopRed;
    } else if (statusText == CallStatus.connected) {
      textColor = kCallGreen;
    } else {
      textColor = kTextNavy;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: kAppBackground,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: dotColor.withValues(alpha: 0.2),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            _CallingConnectionIndicator(color: dotColor)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 10.0),
          Text(
            displayLabelText,
            style: TextStyle(
              fontSize: isTimer ? 20.0 : 16.0,
              fontWeight: FontWeight.w700,
              color: textColor,
              fontFamily: isTimer ? 'monospace' : null,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 0.3,
            ),
          ),
          if (_isMuted && _currentState != CallingState.incoming && _currentState != CallingState.disconnecting) ...[
            const SizedBox(width: 8.0),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kStopRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kStopRed.withValues(alpha: 0.2), width: 0.5),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_off, size: 10, color: kStopRed),
                  SizedBox(width: 2),
                  Text(
                    'MUTED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: kStopRed,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Controls Router
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildControls() {
    switch (_currentState) {
      case CallingState.incoming:
        return _buildIncomingControls();
      case CallingState.outgoing:
        return _buildDialingControls();
      case CallingState.ongoing:
      case CallingState.onHold:
        return _buildActiveControls();
      case CallingState.disconnecting:
        return _buildDisconnectingView();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Incoming Controls — Accept / Decline with Swipe
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildIncomingControls() {
    return Column(
      key: const ValueKey('incoming_controls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Silence button
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildControlCircle(
              icon: Icons.notifications_off_outlined,
              label: 'Silence',
              isActive: false,
              onTap: _silenceRinger,
            ),
            const SizedBox(width: 32),
            _buildControlCircle(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
              label: 'Speaker',
              isActive: _isSpeakerOn,
              onTap: _toggleSpeaker,
            ),
          ],
        ),
        const SizedBox(height: 28.0),

        // Swipe hint text
        AnimatedBuilder(
          animation: _swipeHintController,
          builder: (context, child) {
            final opacity =
                0.4 + (_swipeHintController.value * 0.6);
            return Opacity(
              opacity: opacity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chevron_left,
                      size: 18, color: kStopRed.withValues(alpha: 0.6)),
                  Text(
                    ' Swipe to Decline / Accept ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: kTextSlate.withValues(alpha: 0.7),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18,
                      color: kCallGreen.withValues(alpha: 0.6)),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12.0),

        // Accept / Decline buttons with swipe gesture
        _SwipeCallRow(
          onAccept: _acceptCall,
          onDecline: _declineCall,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dialing Controls — Speaker + End Call
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDialingControls() {
    return Column(
      key: const ValueKey('dialing_controls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildControlCircle(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
              label: 'Speaker',
              isActive: _isSpeakerOn,
              onTap: _toggleSpeaker,
            ),
          ],
        ),
        const SizedBox(height: 32.0),
        _buildEndCallButton(onTap: _hangUp),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Active / On-Hold Controls — Full Grid
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildActiveControls() {
    final bool dimControls = _currentState == CallingState.onHold;

    return Column(
      key: const ValueKey('active_controls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: Mute, Keypad, Speaker
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlCircle(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              label: _isMuted ? 'Unmute' : 'Mute',
              isActive: _isMuted,
              onTap: _toggleMute,
              dimmed: dimControls,
            ),
            _buildControlCircle(
              icon: Icons.dialpad,
              label: 'Keypad',
              isActive: _showDtmfKeypad,
              onTap: _toggleDtmfKeypad,
              dimmed: dimControls,
            ),
            _buildControlCircle(
              icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
              label: 'Speaker',
              isActive: _isSpeakerOn,
              onTap: _toggleSpeaker,
              dimmed: dimControls,
            ),
          ],
        ),
        const SizedBox(height: 20.0),

        // Row 2: Hold
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildControlCircle(
              icon: _isOnHold ? Icons.play_arrow : Icons.pause,
              label: _isOnHold ? 'Resume' : 'Hold',
              isActive: _isOnHold,
              onTap: _toggleHold,
              activeColor: const Color(0xFFF59E0B), // Amber for hold
            ),
          ],
        ),
        const SizedBox(height: 28.0),

        // End Call
        _buildEndCallButton(onTap: _hangUp),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Disconnecting View
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDisconnectingView() {
    return const Column(
      key: ValueKey('disconnecting_view'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 40),
        Icon(Icons.call_end, size: 48, color: kStopRed),
        SizedBox(height: 16),
        Text(
          'Call Ended',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: kStopRed,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DTMF Keypad Overlay
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDtmfOverlay() {
    const dtmfKeys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];
    const subLabels = {
      '2': 'ABC',
      '3': 'DEF',
      '4': 'GHI',
      '5': 'JKL',
      '6': 'MNO',
      '7': 'PQRS',
      '8': 'TUV',
      '9': 'WXYZ',
      '0': '+',
    };

    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleDtmfKeypad,
        child: Container(
          color: Colors.black.withValues(alpha: 0.3),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {}, // Prevent tap-through
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // DTMF Input display
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: kAppBackground,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _dtmfInput.isEmpty ? 'Enter digits' : _dtmfInput,
                        style: TextStyle(
                          fontSize: _dtmfInput.isEmpty ? 16 : 24,
                          fontWeight: FontWeight.w600,
                          color: _dtmfInput.isEmpty ? kTextSlate : kTextNavy,
                          letterSpacing: 2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Keypad grid
                    ...dtmfKeys.map((row) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: row
                                .map((digit) => _DtmfKey(
                                      digit: digit,
                                      subLabel: subLabels[digit],
                                      onTap: () => _sendDtmfTone(digit),
                                    ))
                                .toList(),
                          ),
                        )),

                    const SizedBox(height: 8),
                    // Close button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton(
                        onPressed: _toggleDtmfKeypad,
                        style: TextButton.styleFrom(
                          backgroundColor: kAppBackground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Close Keypad',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: kAccentPurple,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reusable Widgets
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAvatar(Color ringColor) {
    final hasPhoto = widget.contact.photoPath != null &&
        widget.contact.photoPath!.isNotEmpty;
    final initial = widget.contact.name.isNotEmpty
        ? widget.contact.name[0].toUpperCase()
        : '?';

    final avatarInner = hasPhoto
        ? Image.file(
            File(widget.contact.photoPath!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackAvatar(initial),
          )
        : _buildFallbackAvatar(initial);

    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0F172A),
        border: Border.all(color: ringColor, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: ringColor.withValues(alpha: 0.25),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(70),
        child: avatarInner,
      ),
    );
  }

  Widget _buildFallbackAvatar(String initial) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF312E81)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 56.0,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Circular toggle control button (Mute, Speaker, Hold, etc.)
  Widget _buildControlCircle({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool dimmed = false,
    Color? activeColor,
  }) {
    final effectiveActiveColor = activeColor ?? kAccentPurple;
    final double opacity = dimmed ? 0.5 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Semantics(
        label: '$label toggle. Currently ${isActive ? "on" : "off"}.',
        button: true,
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: isActive
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          effectiveActiveColor,
                          effectiveActiveColor.withValues(alpha: 0.8),
                        ],
                      )
                    : null,
                color: isActive ? null : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.3)
                      : kTextSlate.withValues(alpha: 0.2),
                  width: isActive ? 2.0 : 1.5,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: effectiveActiveColor.withValues(alpha: 0.3),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: dimmed ? null : onTap,
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Icon(
                      icon,
                      color: isActive ? Colors.white : kTextNavy,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              label,
              style: const TextStyle(
                color: kTextNavy,
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wide red "End Call" pill button
  Widget _buildEndCallButton({required VoidCallback onTap}) {
    return Semantics(
      label: 'End call',
      button: true,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        height: 60,
        margin: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEF4444), Color(0xFFC62828)],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(30),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.call_end, color: Colors.white, size: 28),
                SizedBox(width: 10),
                Text(
                  'End Call',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SWIPE-TO-ANSWER ROW
// ═══════════════════════════════════════════════════════════════════════════
class _SwipeCallRow extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _SwipeCallRow({required this.onAccept, required this.onDecline});

  @override
  State<_SwipeCallRow> createState() => _SwipeCallRowState();
}

class _SwipeCallRowState extends State<_SwipeCallRow> {
  double _dragOffset = 0;
  bool _triggered = false;
  static const double _triggerThreshold = 80.0;

  void _onDragUpdate(DragUpdateDetails details) {
    if (_triggered) return;
    setState(() {
      _dragOffset += details.delta.dx;
      _dragOffset = _dragOffset.clamp(-_triggerThreshold - 20, _triggerThreshold + 20);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_triggered) return;
    if (_dragOffset > _triggerThreshold) {
      _triggered = true;
      widget.onAccept();
    } else if (_dragOffset < -_triggerThreshold) {
      _triggered = true;
      widget.onDecline();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final acceptOpacity = (_dragOffset > 0 ? _dragOffset / _triggerThreshold : 0.0).clamp(0.0, 1.0);
    final declineOpacity = (_dragOffset < 0 ? -_dragOffset / _triggerThreshold : 0.0).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(_dragOffset * 0.3, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Decline Button
            _buildActionButton(
              icon: Icons.call_end,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(const Color(0xFFEF4444), const Color(0xFFB91C1C), declineOpacity)!,
                  const Color(0xFFC62828),
                ],
              ),
              label: 'Decline',
              onTap: widget.onDecline,
              glowColor: const Color(0xFFEF4444),
              scale: 1.0 + (declineOpacity * 0.1),
            ),
            // Accept Button
            _buildActionButton(
              icon: Icons.phone,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(const Color(0xFF10B981), const Color(0xFF059669), acceptOpacity)!,
                  const Color(0xFF047857),
                ],
              ),
              label: 'Accept',
              onTap: widget.onAccept,
              glowColor: const Color(0xFF10B981),
              scale: 1.0 + (acceptOpacity * 0.1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Gradient gradient,
    required String label,
    required VoidCallback onTap,
    required Color glowColor,
    double scale = 1.0,
  }) {
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: Transform.scale(
        scale: scale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: gradient,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Icon(icon, color: Colors.white, size: 38),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12.0),
            Text(
              label,
              style: const TextStyle(
                color: kTextNavy,
                fontSize: 16.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DTMF KEY
// ═══════════════════════════════════════════════════════════════════════════
class _DtmfKey extends StatelessWidget {
  final String digit;
  final String? subLabel;
  final VoidCallback onTap;

  const _DtmfKey({
    required this.digit,
    this.subLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: kAppBackground,
            shape: BoxShape.circle,
            border: Border.all(
              color: kTextSlate.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                digit,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: kTextNavy,
                ),
              ),
              if (subLabel != null)
                Text(
                  subLabel!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: kTextSlate.withValues(alpha: 0.6),
                    letterSpacing: 1.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PULSING AVATAR (concentric ripple rings)
// ═══════════════════════════════════════════════════════════════════════════
class _PulsingAvatar extends StatefulWidget {
  final Widget child;
  final Color color;
  final bool isActive;

  const _PulsingAvatar({
    required this.child,
    required this.color,
    this.isActive = true,
  });

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isActive) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulsingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      widget.isActive ? _controller.repeat() : _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Ripple 1
            Transform.scale(
              scale: 1.0 + (_controller.value * 0.35),
              child: Opacity(
                opacity: (1.0 - _controller.value).clamp(0.0, 1.0),
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.16),
                  ),
                ),
              ),
            ),
            // Ripple 2
            Transform.scale(
              scale:
                  1.0 + (((_controller.value + 0.5) % 1.0) * 0.35),
              child: Opacity(
                opacity: (1.0 - ((_controller.value + 0.5) % 1.0))
                    .clamp(0.0, 1.0),
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CALLING CONNECTION INDICATOR (three glowing dots pulsing sequentially)
// ═══════════════════════════════════════════════════════════════════════════
class _CallingConnectionIndicator extends StatefulWidget {
  final Color color;
  const _CallingConnectionIndicator({required this.color});

  @override
  State<_CallingConnectionIndicator> createState() => _CallingConnectionIndicatorState();
}

class _CallingConnectionIndicatorState extends State<_CallingConnectionIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Sequential delay for wave effect
            final delay = index * 0.22;
            double progress = _controller.value - delay;
            if (progress < 0) progress += 1.0;
            progress = progress % 1.0;

            // Sinusoidal scaling and breathing opacity
            final double scale = 0.65 + (math.sin(progress * math.pi * 2) * 0.35);
            final double opacity = 0.25 + ((math.sin(progress * math.pi * 2) + 1.0) / 2.0) * 0.75;

            return Opacity(
              opacity: opacity.clamp(0.2, 1.0),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.35),
                        blurRadius: 4,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

