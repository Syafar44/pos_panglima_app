import 'package:flutter/material.dart';

class StepButton extends StatelessWidget {
  const StepButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onLongPressStart(),
      onLongPressEnd: (_) => onLongPressEnd(),
      child: IconButton(
        style: IconButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          minimumSize: const Size(45, 45),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 22, color: Colors.black87),
      ),
    );
  }
}
