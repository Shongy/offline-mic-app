import 'dart:math';
import 'package:flutter/material.dart';

/// Microphone gain slider with dB feedback and safe default indicator.
class GainSlider extends StatelessWidget {
  final double gain;
  final ValueChanged<double> onGainChanged;

  const GainSlider({
    super.key,
    required this.gain,
    required this.onGainChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Convert linear gain multiplier (0.0 to 3.0) to decibels
    final db = gain > 0.001 ? (20 * log(gain) / ln10) : -40.0;
    final isDefault = (gain - 1.0).abs() < 0.05;
    final isHigh = gain > 1.8;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              const Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: Color(0xFF90A4AE)),
                  SizedBox(width: 8),
                  Text(
                    'MICROPHONE GAIN',
                    style: TextStyle(
                      color: Color(0xFF90A4AE),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (isDefault)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'SAFE DEFAULT',
                        style: TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text(
                    '${gain.toStringAsFixed(1)}x (${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB)',
                    style: TextStyle(
                      color: isHigh ? const Color(0xFFFF9800) : Colors.white,
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: isHigh ? const Color(0xFFFF9800) : const Color(0xFF00E5FF),
              inactiveTrackColor: const Color(0xFF263245),
              thumbColor: isHigh ? const Color(0xFFFFB74D) : const Color(0xFF00E5FF),
              overlayColor: const Color(0xFF00E5FF).withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: Slider(
              value: gain,
              min: 0.0,
              max: 3.0,
              divisions: 30,
              onChanged: onGainChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('0.0x (Mute)', style: TextStyle(color: Color(0xFF546E7A), fontSize: 10)),
              GestureDetector(
                onTap: () => onGainChanged(1.0),
                child: const Text(
                  '1.0x (Normal / 0 dB)',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const Text('3.0x (+9.5 dB Boost)', style: TextStyle(color: Color(0xFF546E7A), fontSize: 10)),
            ],
          ),
          if (isHigh) ...[
            const SizedBox(height: 8),
            const Text(
              'High gain increases sensitivity and risk of acoustic feedback. Soft-limiting is active.',
              style: TextStyle(color: Color(0xFFFFB74D), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
