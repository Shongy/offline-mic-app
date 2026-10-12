import 'package:flutter/material.dart';
import '../../models/audio_state.dart';

/// Card allowing users to detect and select which microphone input to use.
class MicInputCard extends StatelessWidget {
  final List<MicInputDevice> availableInputs;
  final MicInputDevice selectedInput;
  final ValueChanged<String> onSelectInput;
  final VoidCallback onRefresh;

  const MicInputCard({
    super.key,
    required this.availableInputs,
    required this.selectedInput,
    required this.onSelectInput,
    required this.onRefresh,
  });

  IconData _getIconForType(String type) {
    switch (type) {
      case 'bluetooth':
        return Icons.bluetooth_audio_rounded;
      case 'wired':
        return Icons.headset_mic_rounded;
      case 'usb':
        return Icons.usb_rounded;
      case 'builtInMic':
      default:
        return Icons.mic_rounded;
    }
  }

  void _showSelectorModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141923),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Microphone Input',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose which microphone captures your voice:',
                style: TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: availableInputs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = availableInputs[index];
                    final isCurrent = item.id == selectedInput.id;

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        onSelectInput(item.id);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? const Color(0xFF00E5FF).withOpacity(0.12)
                              : const Color(0xFF1E2838),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent
                                ? const Color(0xFF00E5FF)
                                : const Color(0xFF263245),
                            width: isCurrent ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getIconForType(item.type),
                              color: isCurrent
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFFB0BEC5),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: TextStyle(
                                      color: isCurrent ? Colors.white : const Color(0xFFECEFF1),
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    item.isBuiltIn
                                        ? 'Phone primary voice mic (Recommended)'
                                        : 'External audio peripheral',
                                    style: const TextStyle(
                                      color: Color(0xFF78909C),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isCurrent)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF00E5FF),
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141923),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF263245)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getIconForType(selectedInput.type),
                  color: const Color(0xFF00E5FF),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MICROPHONE INPUT SOURCE',
                      style: TextStyle(
                        color: Color(0xFF78909C),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedInput.name,
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
                tooltip: 'Scan Inputs',
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF212B3B), height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${availableInputs.length} Input${availableInputs.length == 1 ? '' : 's'} Detected',
                style: const TextStyle(color: Color(0xFF78909C), fontSize: 12),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _showSelectorModal(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2838),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF37474F)),
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Change Mic',
                        style: TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.unfold_more, size: 14, color: Color(0xFF00E5FF)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
