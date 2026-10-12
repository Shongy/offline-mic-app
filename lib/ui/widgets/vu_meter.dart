import 'dart:math';
import 'package:flutter/material.dart';

/// Real-time VU meter with peak hold and audio level bar.
class VuMeter extends StatefulWidget {
  final double level; // 0.0 to 1.0
  final bool isLive;

  const VuMeter({
    super.key,
    required this.level,
    required this.isLive,
  });

  @override
  State<VuMeter> createState() => _VuMeterState();
}

class _VuMeterState extends State<VuMeter> with SingleTickerProviderStateMixin {
  double _peakLevel = 0.0;
  DateTime _lastPeakTime = DateTime.now();

  @override
  void didUpdateWidget(VuMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isLive) {
      _peakLevel = 0.0;
      return;
    }

    if (widget.level > _peakLevel) {
      _peakLevel = widget.level;
      _lastPeakTime = DateTime.now();
    } else {
      final elapsed = DateTime.now().difference(_lastPeakTime).inMilliseconds;
      if (elapsed > 400) {
        // Smooth peak decay
        _peakLevel = max(0.0, _peakLevel - 0.03);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveLevel = widget.isLive ? widget.level : 0.0;
    final effectivePeak = widget.isLive ? _peakLevel : 0.0;

    // Convert normalized RMS to approx decibels
    final db = effectiveLevel > 0.001
        ? (20 * log(effectiveLevel) / ln10).clamp(-48.0, 0.0)
        : -48.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141923),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF263245)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.graphic_eq,
                    size: 18,
                    color: widget.isLive ? const Color(0xFF00E5FF) : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'INPUT LEVEL',
                    style: TextStyle(
                      color: Color(0xFF90A4AE),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              Text(
                widget.isLive ? '${db.toStringAsFixed(1)} dB' : '-∞ dB',
                style: TextStyle(
                  color: db > -3.0
                      ? const Color(0xFFFF5252)
                      : (db > -12.0
                          ? const Color(0xFFFFD740)
                          : const Color(0xFF00E676)),
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 16,
            child: CustomPaint(
              painter: _VuMeterPainter(
                level: effectiveLevel,
                peakLevel: effectivePeak,
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('-48 dB', style: TextStyle(color: Color(0xFF546E7A), fontSize: 10)),
              Text('-24 dB', style: TextStyle(color: Color(0xFF546E7A), fontSize: 10)),
              Text('-12 dB', style: TextStyle(color: Color(0xFF546E7A), fontSize: 10)),
              Text('-6 dB', style: TextStyle(color: Color(0xFF546E7A), fontSize: 10)),
              Text('0 dB', style: TextStyle(color: Color(0xFFFF5252), fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _VuMeterPainter extends CustomPainter {
  final double level;
  final double peakLevel;

  _VuMeterPainter({
    required this.level,
    required this.peakLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const int totalSegments = 32;
    const double segmentSpacing = 2.0;
    final double totalSpacing = segmentSpacing * (totalSegments - 1);
    final double segmentWidth = (size.width - totalSpacing) / totalSegments;

    final activeCount = (level * totalSegments).round();
    final peakIndex = (peakLevel * totalSegments).round() - 1;

    for (int i = 0; i < totalSegments; i++) {
      final x = i * (segmentWidth + segmentSpacing);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 0, segmentWidth, size.height),
        const Radius.circular(2.0),
      );

      final ratio = i / totalSegments;
      Color segmentColor;
      if (ratio < 0.70) {
        segmentColor = const Color(0xFF00E676); // Green
      } else if (ratio < 0.88) {
        segmentColor = const Color(0xFFFFD740); // Yellow/Amber
      } else {
        segmentColor = const Color(0xFFFF5252); // Red (clipping risk)
      }

      final isFilled = i < activeCount;
      final isPeak = i == peakIndex;

      final paint = Paint()
        ..color = isFilled
            ? segmentColor
            : (isPeak
                ? segmentColor.withOpacity(0.9)
                : const Color(0xFF1E2838));

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VuMeterPainter oldDelegate) {
    return oldDelegate.level != level || oldDelegate.peakLevel != peakLevel;
  }
}
