// import 'package:flutter/material.dart';

// class CustomChipCheckbox extends StatelessWidget {
//   final String label;
//   final bool isSelected;
//   final VoidCallback onSelect;

//   const CustomChipCheckbox({
//     super.key,
//     required this.label,
//     required this.isSelected,
//     required this.onSelect,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: onSelect,
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//         decoration: BoxDecoration(
//           color: isSelected ? Colors.amber.shade100 : Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           border: Border.all(
//             color: isSelected ? Colors.amber : Colors.black26,
//             width: 2,
//           ),
//         ),
//         child: Text(
//           label,
//           style: TextStyle(
//             fontWeight: FontWeight.bold,
//             color: isSelected ? Colors.amber.shade900 : Colors.black87,
//           ),
//         ),
//       ),
//     );
//   }
// }

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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(12),
          splashColor: Colors.amber.withOpacity(0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              // Background berubah halus
              color: isSelected ? Colors.amber.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                // Border lebih tegas saat terpilih
                color: isSelected ? Colors.amber : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
              // Tambahkan bayangan halus saat terpilih
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon check m uncul hanya saat dipilih
                if (isSelected) ...[
                  const Icon(Icons.check_circle, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.amber.shade800 : Colors.black54,
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
