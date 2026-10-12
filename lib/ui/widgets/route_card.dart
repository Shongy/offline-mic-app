import 'package:flutter/material.dart';
import '../../models/audio_state.dart';

/// Card displaying the current audio route and coexistence capability.
class RouteCard extends StatelessWidget {
  final AudioRouteInfo route;
  final VoidCallback onRefresh;

  const RouteCard({
    super.key,
    required this.route,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isBt = route.isBluetooth;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141923),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBt ? const Color(0xFF0D47A1) : const Color(0xFF263245),
          width: isBt ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isBt
                      ? const Color(0xFF1976D2).withOpacity(0.2)
                      : const Color(0xFF37474F).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isBt ? Icons.bluetooth_audio : Icons.volume_up_rounded,
                  color: isBt ? const Color(0xFF42A5F5) : const Color(0xFFB0BEC5),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AUDIO OUTPUT ROUTE',
                      style: TextStyle(
                        color: Color(0xFF78909C),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      route.deviceName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20, color: Color(0xFF78909C)),
                tooltip: 'Refresh Route',
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF212B3B), height: 1),
          const SizedBox(height: 10),

          // Simultaneous mixing status with YouTube
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                route.isSimultaneousMixSupported
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                size: 16,
                color: route.isSimultaneousMixSupported
                    ? const Color(0xFF00E676)
                    : const Color(0xFFFFB74D),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  route.isSimultaneousMixSupported
                      ? 'Simultaneous Playback: Live mic audio mixes with YouTube/media.'
                      : (route.mixExplanation.isNotEmpty
                          ? route.mixExplanation
                          : 'Simultaneous playback with media depends on OS audio focus.'),
                  style: TextStyle(
                    color: route.isSimultaneousMixSupported
                        ? const Color(0xFFB0BEC5)
                        : const Color(0xFFFFCC80),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),

          if (!isBt) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE65100).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBF360C).withOpacity(0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFFF9800)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Internal speaker active. Keep volume low to prevent feedback screech.',
                      style: TextStyle(color: Color(0xFFFFCC80), fontSize: 11),
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
}
