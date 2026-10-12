import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/audio_state.dart';
import '../services/audio_channel_service.dart';
import 'widgets/vu_meter.dart';
import 'widgets/mic_input_card.dart';
import 'widgets/route_card.dart';
import 'widgets/gain_slider.dart';
import 'widgets/feedback_warning.dart';

class MicScreen extends StatefulWidget {
  const MicScreen({super.key});

  @override
  State<MicScreen> createState() => _MicScreenState();
}

class _MicScreenState extends State<MicScreen> with WidgetsBindingObserver {
  final AudioChannelService _audioService = AudioChannelService();

  MicState _micState = MicState.off;
  AudioRouteInfo _currentRoute = AudioRouteInfo.phoneSpeaker();
  List<MicInputDevice> _availableInputs = [MicInputDevice.defaultBuiltIn()];
  MicInputDevice _selectedInput = MicInputDevice.defaultBuiltIn();
  double _inputLevel = 0.0;
  double _gain = 1.0;
  EngineDiagnostic _diagnostic = const EngineDiagnostic();

  StreamSubscription<MicState>? _stateSub;
  StreamSubscription<AudioRouteInfo>? _routeSub;
  StreamSubscription<List<MicInputDevice>>? _inputsSub;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<EngineDiagnostic>? _diagnosticSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _audioService.initialize();

    _micState = _audioService.currentState;
    _currentRoute = _audioService.currentRoute;
    _availableInputs = _audioService.availableInputs;
    _selectedInput = _audioService.selectedInput;
    _gain = _audioService.gain;
    _diagnostic = _audioService.currentDiagnostic;

    _stateSub = _audioService.stateStream.listen((state) {
      if (mounted) setState(() => _micState = state);
    });

    _routeSub = _audioService.routeStream.listen((route) {
      if (mounted) setState(() => _currentRoute = route);
    });

    _inputsSub = _audioService.inputsStream.listen((inputs) {
      if (mounted) {
        setState(() {
          _availableInputs = inputs;
          _selectedInput = _audioService.selectedInput;
        });
      }
    });

    _levelSub = _audioService.levelStream.listen((level) {
      if (mounted) setState(() => _inputLevel = level);
    });

    _diagnosticSub = _audioService.diagnosticStream.listen((diag) {
      if (mounted) setState(() => _diagnostic = diag);
    });

    // Automatically prompt and verify microphone permission every time app opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialPermission();
    });
  }

  Future<void> _checkInitialPermission() async {
    final granted = await _audioService.checkAndRequestPermission();
    if (!granted && mounted) {
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141923),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.mic, color: Color(0xFF00E5FF), size: 24),
              SizedBox(width: 10),
              Text(
                'Microphone Access',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: const Text(
            'Live Mic Pro requires microphone access to stream live voice directly to your Bluetooth speaker.\n\nPlease enable Microphone access in Settings to continue.',
            style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Dismiss', style: TextStyle(color: Color(0xFF78909C))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: const Color(0xFF0A0E17),
              ),
              onPressed: () async {
                Navigator.pop(context);
                final retry = await _audioService.checkAndRequestPermission();
                if (!retry) {
                  openAppSettings();
                }
              },
              child: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When returning to foreground, refresh route information and re-check permission
    if (state == AppLifecycleState.resumed) {
      _audioService.refreshAudioRoute();
      _audioService.refreshAvailableInputs();
      _audioService.checkAndRequestPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSub?.cancel();
    _routeSub?.cancel();
    _inputsSub?.cancel();
    _levelSub?.cancel();
    _diagnosticSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    HapticFeedback.heavyImpact();
    if (_micState.isActive) {
      await _audioService.stopMic();
    } else {
      await _audioService.startMic(initialGain: _gain);
    }
  }

  void _onGainChanged(double newGain) {
    setState(() => _gain = newGain);
    _audioService.setGain(newGain);
  }

  void _showDiagnosticsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141923),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Audio Engine Diagnostics',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF263245)),
              const SizedBox(height: 8),
              _buildDiagRow('Sample Rate', '${_diagnostic.sampleRate} Hz'),
              _buildDiagRow('Buffer Frame Size', '${_diagnostic.bufferSize} samples'),
              _buildDiagRow('Estimated Latency', '${_diagnostic.estimatedLatencyMs.toStringAsFixed(1)} ms'),
              _buildDiagRow('Signal Limiter / Soft-Clip', _diagnostic.isClipping ? 'Engaged' : 'Nominal Headroom'),
              _buildDiagRow('Active Mic Input', _selectedInput.name),
              _buildDiagRow('Active Output Route', _currentRoute.deviceName),
              _buildDiagRow('Route Protocol', _currentRoute.routeType),
              _buildDiagRow('Background Mode', 'Active Foreground / Audio UIBackgroundModes'),
              if (_diagnostic.lastError != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Last Platform Event: ${_diagnostic.lastError}',
                  style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 13)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLive = _micState == MicState.live;
    final isStarting = _micState == MicState.starting;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.mic, color: Color(0xFF00E5FF), size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'LIVE MIC PRO',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Color(0xFF90A4AE)),
            tooltip: 'Audio Engine Diagnostics',
            onPressed: _showDiagnosticsModal,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              // Status Badge Pill
              _buildStatusPill(),

              const SizedBox(height: 24),

              // Huge Central MIC ON / OFF Button
              _buildBigMicButton(isLive, isStarting),

              const SizedBox(height: 28),

              // Real-time VU Meter
              VuMeter(
                level: _inputLevel,
                isLive: isLive,
              ),

              const SizedBox(height: 16),

              // Microphone Input Source Selector
              MicInputCard(
                availableInputs: _availableInputs,
                selectedInput: _selectedInput,
                onSelectInput: (id) => _audioService.setPreferredInput(id),
                onRefresh: () => _audioService.refreshAvailableInputs(),
              ),

              const SizedBox(height: 16),

              // Hardware Route Display
              RouteCard(
                route: _currentRoute,
                onRefresh: () => _audioService.refreshAudioRoute(),
              ),

              const SizedBox(height: 16),

              // Gain Slider
              GainSlider(
                gain: _gain,
                onGainChanged: _onGainChanged,
              ),

              const SizedBox(height: 16),

              // Acoustic Feedback Warning Notice
              const FeedbackWarningCard(),

              const SizedBox(height: 20),

              // YouTube Background Coexistence Instructions
              _buildWorkflowCard(),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill() {
    Color pillColor;
    Color dotColor;
    IconData icon;

    switch (_micState) {
      case MicState.live:
        pillColor = const Color(0xFF00E676).withOpacity(0.15);
        dotColor = const Color(0xFF00E676);
        icon = Icons.radio_button_checked;
        break;
      case MicState.starting:
        pillColor = const Color(0xFF00E5FF).withOpacity(0.15);
        dotColor = const Color(0xFF00E5FF);
        icon = Icons.hourglass_top;
        break;
      case MicState.interrupted:
        pillColor = const Color(0xFFFFB74D).withOpacity(0.15);
        dotColor = const Color(0xFFFFB74D);
        icon = Icons.pause_circle_outline;
        break;
      case MicState.error:
        pillColor = const Color(0xFFFF5252).withOpacity(0.15);
        dotColor = const Color(0xFFFF5252);
        icon = Icons.error_outline;
        break;
      case MicState.off:
      default:
        pillColor = const Color(0xFF37474F).withOpacity(0.3);
        dotColor = const Color(0xFF78909C);
        icon = Icons.mic_off;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: pillColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dotColor.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: dotColor),
          const SizedBox(width: 8),
          Text(
            _micState.displayName.toUpperCase(),
            style: TextStyle(
              color: dotColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBigMicButton(bool isLive, bool isStarting) {
    return GestureDetector(
      onTap: isStarting ? null : _toggleMic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: 190,
        height: 190,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isLive
                ? [const Color(0xFF00E5FF), const Color(0xFF00B0FF)]
                : [const Color(0xFF1E2838), const Color(0xFF121824)],
          ),
          boxShadow: [
            BoxShadow(
              color: isLive
                  ? const Color(0xFF00E5FF).withOpacity(0.45)
                  : Colors.black.withOpacity(0.6),
              blurRadius: isLive ? 32 : 16,
              spreadRadius: isLive ? 4 : 0,
              offset: const Offset(0, 8),
            ),
            if (isLive)
              BoxShadow(
                color: const Color(0xFF00E676).withOpacity(0.3),
                blurRadius: 48,
                spreadRadius: 8,
              ),
          ],
          border: Border.all(
            color: isLive ? const Color(0xFFE0F7FA) : const Color(0xFF263245),
            width: isLive ? 3.0 : 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isStarting)
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              Icon(
                isLive ? Icons.mic : Icons.mic_none,
                size: 58,
                color: isLive ? const Color(0xFF0A0E17) : const Color(0xFF78909C),
              ),
            const SizedBox(height: 8),
            Text(
              isLive ? 'MIC ON' : 'MIC OFF',
              style: TextStyle(
                color: isLive ? const Color(0xFF0A0E17) : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
              ),
            ),
            Text(
              isLive ? 'Tap to Mute' : 'Tap to Start',
              style: TextStyle(
                color: isLive
                    ? const Color(0xFF0A0E17).withOpacity(0.7)
                    : const Color(0xFF546E7A),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkflowCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111722),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2838)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.ondemand_video_rounded, color: Color(0xFFFF5252), size: 18),
              SizedBox(width: 8),
              Text(
                'Background & YouTube Mixing',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '1. Connect your JBL speaker via phone Bluetooth settings.\n'
            '2. Select your preferred mic (Phone Built-In Mic recommended).\n'
            '3. Tap "MIC ON" and verify your voice through the speaker.\n'
            '4. Switch to YouTube and start any video.\n'
            '5. Your voice and YouTube audio stream together to the speaker.\n'
            '6. When finished, return here and tap "MIC OFF" to release the mic.',
            style: TextStyle(
              color: Color(0xFF90A4AE),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
