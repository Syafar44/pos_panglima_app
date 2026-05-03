import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';

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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(12),
          splashColor: AppColors.white,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              // Background berubah halus
              color: isSelected ? AppColors.primarySelected : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                // Border lebih tegas saat terpilih
                color: isSelected
                    ? AppColors.primarySelected
                    : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
              // Tambahkan bayangan halus saat terpilih
              // boxShadow: isSelected
              //     ? [
              //         BoxShadow(
              //           color: AppColors.primary,
              //           blurRadius: 4,
              //           offset: const Offset(0, 2),
              //         ),
              //       ]
              //     : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon check m uncul hanya saat dipilih
                if (isSelected) ...[
                  const Icon(Icons.check_circle, size: 18, color: AppColors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? AppColors.white : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
