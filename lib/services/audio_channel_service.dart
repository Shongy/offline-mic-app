import 'dart:async';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/audio_state.dart';

/// Service interfacing Flutter with native iOS and Android low-latency audio engines.
class AudioChannelService {
  static final AudioChannelService _instance = AudioChannelService._internal();
  factory AudioChannelService() => _instance;
  AudioChannelService._internal();

  static const MethodChannel _methodChannel =
      MethodChannel('com.livemic.app/audio_control');
  static const EventChannel _eventChannel =
      EventChannel('com.livemic.app/audio_events');
  static const EventChannel _meterChannel =
      EventChannel('com.livemic.app/audio_level');

  final StreamController<MicState> _stateController =
      StreamController<MicState>.broadcast();
  final StreamController<AudioRouteInfo> _routeController =
      StreamController<AudioRouteInfo>.broadcast();
  final StreamController<List<MicInputDevice>> _inputsController =
      StreamController<List<MicInputDevice>>.broadcast();
  final StreamController<double> _levelController =
      StreamController<double>.broadcast();
  final StreamController<EngineDiagnostic> _diagnosticController =
      StreamController<EngineDiagnostic>.broadcast();

  Stream<MicState> get stateStream => _stateController.stream;
  Stream<AudioRouteInfo> get routeStream => _routeController.stream;
  Stream<List<MicInputDevice>> get inputsStream => _inputsController.stream;
  Stream<double> get levelStream => _levelController.stream;
  Stream<EngineDiagnostic> get diagnosticStream => _diagnosticController.stream;

  MicState _currentState = MicState.off;
  MicState get currentState => _currentState;

  AudioRouteInfo _currentRoute = AudioRouteInfo.phoneSpeaker();
  AudioRouteInfo get currentRoute => _currentRoute;

  List<MicInputDevice> _availableInputs = [MicInputDevice.defaultBuiltIn()];
  List<MicInputDevice> get availableInputs => _availableInputs;

  MicInputDevice _selectedInput = MicInputDevice.defaultBuiltIn();
  MicInputDevice get selectedInput => _selectedInput;

  EngineDiagnostic _currentDiagnostic = const EngineDiagnostic();
  EngineDiagnostic get currentDiagnostic => _currentDiagnostic;

  double _gain = 1.0;
  double get gain => _gain;

  StreamSubscription? _eventSubscription;
  StreamSubscription? _meterSubscription;

  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Listen to native status & route events
    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            _handleNativeEvent(event);
          }
        },
        onError: (dynamic error) {
          _updateState(MicState.error);
          _diagnosticController.add(EngineDiagnostic(
            lastError: 'Event channel error: $error',
          ));
        },
      );
    } catch (_) {
      // Event channel unavailable
    }

    // Listen to real-time VU meter levels
    try {
      _meterSubscription = _meterChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is num) {
            final level = event.toDouble().clamp(0.0, 1.0);
            _levelController.add(level);
          }
        },
        onError: (_) {},
      );
    } catch (_) {
      // Meter channel unavailable
    }

    // Query initial audio route and available inputs
    refreshAudioRoute();
    refreshAvailableInputs();
  }

  void _handleNativeEvent(Map<dynamic, dynamic> event) {
    final type = event['type'] as String?;

    if (type == 'stateChange') {
      final stateStr = event['state'] as String?;
      switch (stateStr) {
        case 'starting':
          _updateState(MicState.starting);
          break;
        case 'live':
          _updateState(MicState.live);
          break;
        case 'interrupted':
          _updateState(MicState.interrupted);
          break;
        case 'error':
          _updateState(MicState.error);
          break;
        case 'off':
        default:
          _updateState(MicState.off);
          break;
      }
    } else if (type == 'routeChange') {
      if (event['route'] is Map) {
        _currentRoute = AudioRouteInfo.fromMap(event['route'] as Map);
        _routeController.add(_currentRoute);
      }
      refreshAvailableInputs();
    } else if (type == 'diagnostic') {
      if (event['diagnostic'] is Map) {
        _currentDiagnostic =
            EngineDiagnostic.fromMap(event['diagnostic'] as Map);
        _diagnosticController.add(_currentDiagnostic);
      }
    }
  }

  void _updateState(MicState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  /// Explicitly check and request microphone permission natively and via plugin
  Future<bool> checkAndRequestPermission() async {
    // 1. Try native platform request first (triggers iOS modal directly)
    try {
      final bool? nativeGranted =
          await _methodChannel.invokeMethod<bool>('requestMicrophonePermission');
      if (nativeGranted == true) return true;
    } catch (_) {}

    // 2. Try permission_handler
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Query all detected hardware microphone inputs (built-in, headset, bluetooth)
  Future<List<MicInputDevice>> refreshAvailableInputs() async {
    try {
      final rawList =
          await _methodChannel.invokeMethod<List<dynamic>>('getAvailableInputs');
      if (rawList != null && rawList.isNotEmpty) {
        final List<MicInputDevice> devices = [];
        for (final item in rawList) {
          if (item is Map) {
            final dev = MicInputDevice.fromMap(
              item,
              isSelected: item['isSelected'] as bool? ?? false,
            );
            devices.add(dev);
            if (dev.isSelected) {
              _selectedInput = dev;
            }
          }
        }
        if (devices.isNotEmpty) {
          _availableInputs = devices;
          _inputsController.add(_availableInputs);
        }
      }
    } catch (_) {
      // Fallback
    }
    return _availableInputs;
  }

  /// Select which hardware microphone to use
  Future<bool> setPreferredInput(String id) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('setPreferredInput', {
        'uid': id,
        'id': id,
      });

      _availableInputs = _availableInputs.map((d) {
        return d.copyWith(isSelected: d.id == id);
      }).toList();

      final selected = _availableInputs.firstWhere(
        (d) => d.id == id,
        orElse: () => _selectedInput,
      );
      _selectedInput = selected;
      _inputsController.add(_availableInputs);

      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Request microphone permission and start the live audio engine
  Future<bool> startMic({double? initialGain}) async {
    _updateState(MicState.starting);
    final targetGain = initialGain ?? _gain;

    try {
      final result = await _methodChannel.invokeMethod<bool>('startLiveMic', {
        'gain': targetGain,
        'preferredInputId': _selectedInput.id,
      });

      if (result == true) {
        _updateState(MicState.live);
        await refreshAudioRoute();
        await refreshAvailableInputs();
        return true;
      } else {
        _updateState(MicState.error);
        return false;
      }
    } on PlatformException catch (e) {
      _updateState(MicState.error);
      _diagnosticController.add(EngineDiagnostic(
        lastError: 'Platform start error: ${e.message} (${e.code})',
      ));
      return false;
    } catch (e) {
      _updateState(MicState.error);
      _diagnosticController.add(EngineDiagnostic(
        lastError: 'Unexpected error: $e',
      ));
      return false;
    }
  }

  /// Stop live streaming and tear down native background audio resources
  Future<bool> stopMic() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopLiveMic');
      _updateState(MicState.off);
      _levelController.add(0.0);
      return result ?? true;
    } on PlatformException catch (e) {
      _updateState(MicState.off);
      _diagnosticController.add(EngineDiagnostic(
        lastError: 'Platform stop error: ${e.message}',
      ));
      return false;
    } catch (e) {
      _updateState(MicState.off);
      return false;
    }
  }

  /// Dynamically update microphone gain
  Future<void> setGain(double gain) async {
    _gain = gain.clamp(0.0, 3.0);
    try {
      await _methodChannel.invokeMethod('setGain', {'gain': _gain});
    } catch (_) {}
  }

  /// Query the currently active audio output route from native layer
  Future<AudioRouteInfo> refreshAudioRoute() async {
    try {
      final routeMap =
          await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('getAudioRoute');
      if (routeMap != null) {
        _currentRoute = AudioRouteInfo.fromMap(routeMap);
        _routeController.add(_currentRoute);
      }
    } catch (_) {}
    return _currentRoute;
  }

  void dispose() {
    _eventSubscription?.cancel();
    _meterSubscription?.cancel();
    _stateController.close();
    _routeController.close();
    _inputsController.close();
    _levelController.close();
    _diagnosticController.close();
  }
}
