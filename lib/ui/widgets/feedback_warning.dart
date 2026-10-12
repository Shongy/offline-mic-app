import 'package:flutter/material.dart';

/// Educational card explaining acoustic feedback prevention.
class FeedbackWarningCard extends StatefulWidget {
  const FeedbackWarningCard({super.key});

  @override
  State<FeedbackWarningCard> createState() => _FeedbackWarningCardState();
}

class _FeedbackWarningCardState extends State<FeedbackWarningCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1712),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF5D4037)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.sensors_off_rounded,
                    color: Color(0xFFFFB74D),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Acoustic Feedback Safety Notice',
                      style: TextStyle(
                        color: Color(0xFFFFE082),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFFFFB74D),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            const Padding(
              padding: EdgeInsets.only(left: 14, right: 14, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: Color(0xFF4E342E), height: 1),
                  SizedBox(height: 10),
                  Text(
                    'What causes feedback screech?\n'
                    'When live microphone sound is output from a nearby speaker, that sound enters the microphone again, creating an infinite loop known as the Larsen Effect.\n\n'
                    'Prevention Tips:\n'
                    '• Maintain at least 2 meters (6 feet) distance between your phone and the JBL speaker.\n'
                    '• Point the bottom of the phone (where the primary voice microphone is located) away from the speaker drivers.\n'
                    '• Keep microphone gain at 1.0x (safe default) and increase volume on the physical JBL speaker instead of over-boosting digital gain.\n'
                    '• Software limiting prevents digital clipping, but physical sound loop feedback must be managed acoustically.',
                    style: TextStyle(
                      color: Color(0xFFFFCC80),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
