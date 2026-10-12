/// Current operational state of the live microphone engine.
enum MicState {
  off,
  starting,
  live,
  interrupted,
  error;

  String get displayName {
    switch (this) {
      case MicState.off:
        return 'Microphone Off';
      case MicState.starting:
        return 'Starting Engine...';
      case MicState.live:
        return 'Live in Background';
      case MicState.interrupted:
        return 'Interrupted (Call/Focus)';
      case MicState.error:
        return 'Engine Error';
    }
  }

  bool get isActive => this == MicState.live || this == MicState.starting;
}

/// Represents the active hardware audio output route.
class AudioRouteInfo {
  final String deviceName;
  final String routeType; // 'bluetooth_a2dp', 'bluetooth_sco', 'speaker', 'wired', 'unknown'
  final bool isBluetooth;
  final bool isSimultaneousMixSupported;
  final String mixExplanation;

  const AudioRouteInfo({
    required this.deviceName,
    required this.routeType,
    required this.isBluetooth,
    required this.isSimultaneousMixSupported,
    required this.mixExplanation,
  });

  factory AudioRouteInfo.phoneSpeaker() {
    return const AudioRouteInfo(
      deviceName: 'Phone Speaker',
      routeType: 'speaker',
      isBluetooth: false,
      isSimultaneousMixSupported: true,
      mixExplanation:
          'Audio routed to built-in speaker. Keep volume moderate to prevent acoustic feedback.',
    );
  }

  factory AudioRouteInfo.fromMap(Map<dynamic, dynamic> map) {
    return AudioRouteInfo(
      deviceName: map['deviceName'] as String? ?? 'Unknown Audio Output',
      routeType: map['routeType'] as String? ?? 'unknown',
      isBluetooth: map['isBluetooth'] as bool? ?? false,
      isSimultaneousMixSupported: map['isSimultaneousMixSupported'] as bool? ?? true,
      mixExplanation: map['mixExplanation'] as String? ?? '',
    );
  }
}

/// Diagnostic information about audio buffers, latency, and sample processing.
class EngineDiagnostic {
  final int sampleRate;
  final int bufferSize;
  final double estimatedLatencyMs;
  final bool isClipping;
  final String? lastError;

  const EngineDiagnostic({
    this.sampleRate = 48000,
    this.bufferSize = 256,
    this.estimatedLatencyMs = 12.0,
    this.isClipping = false,
    this.lastError,
  });

  factory EngineDiagnostic.fromMap(Map<dynamic, dynamic> map) {
    return EngineDiagnostic(
      sampleRate: map['sampleRate'] as int? ?? 48000,
      bufferSize: map['bufferSize'] as int? ?? 256,
      estimatedLatencyMs: (map['estimatedLatencyMs'] as num?)?.toDouble() ?? 12.0,
      isClipping: map['isClipping'] as bool? ?? false,
      lastError: map['lastError'] as String?,
    );
  }
}
