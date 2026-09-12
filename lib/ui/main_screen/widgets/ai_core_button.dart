import 'package:flutter/material.dart';

/// Center nav button: tap to start a quick voice recording, tap again to
/// stop and submit it.
class AICoreButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isRecording;

  const AICoreButton({
    super.key,
    required this.onTap,
    this.isRecording = false,
  });

  @override
  State<AICoreButton> createState() => _AICoreButtonState();
}

class _AICoreButtonState extends State<AICoreButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.9,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _scaleController.animateTo(0.9).then((_) {
      if (mounted) {
        _scaleController.animateTo(1.0);
        widget.onTap();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isRecording ? const Color(0xFFEF4444) : const Color(0xFF5B6CFF);
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scaleController,
        child: Container(
          width: 88,
          height: 88,
          padding: const EdgeInsets.all(10),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 6,
                  spreadRadius: -2,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              widget.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}
