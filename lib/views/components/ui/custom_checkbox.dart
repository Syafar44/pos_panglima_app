import 'package:flutter/material.dart';

class CustomChipCheckbox extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelect;

  const CustomChipCheckbox({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.black26,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.orange.shade900 : Colors.black87,
          ),
        ),
      ),
    );
  }
}