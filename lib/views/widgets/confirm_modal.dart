// import 'package:flutter/material.dart';

// class ConfirmModal extends StatefulWidget {
//   const ConfirmModal({
//     super.key,
//     required this.title,
//     required this.description,
//   });

//   final String title;
//   final String description;

//   @override
//   State<ConfirmModal> createState() => _ConfirmModalState();
// }

// class _ConfirmModalState extends State<ConfirmModal> {
//   @override
//   Widget build(BuildContext context) {
//     return Dialog(
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//       insetPadding: EdgeInsets.all(16),
//       child: Container(
//         width: 400.0,
//         height: 300.0,
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.all(Radius.circular(20.0)),
//         ),
//         child: Padding(
//           padding: const EdgeInsets.all(20.0),
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Column(
//                 children: [
//                   Text(
//                     widget.title,
//                     style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
//                   ),
//                   SizedBox(height: 20),
//                   Text(widget.description, style: TextStyle(fontSize: 16)),
//                 ],
//               ),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Expanded(
//                     child: FilledButton(
//                       style: FilledButton.styleFrom(
//                         minimumSize: Size(double.infinity, 40.0),
//                         backgroundColor: Colors.grey,
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(14.0),
//                         ),
//                       ),
//                       onPressed: () {
//                         Navigator.pop(context, false);
//                       },
//                       child: Text(
//                         'Batal',
//                         style: TextStyle(
//                           fontWeight: FontWeight.bold,
//                           color: Colors.white,
//                           fontSize: 16,
//                         ),
//                       ),
//                     ),
//                   ),
//                   SizedBox(width: 10),
//                   Expanded(
//                     child: FilledButton(
//                       style: FilledButton.styleFrom(
//                         minimumSize: Size(double.infinity, 40.0),
//                         backgroundColor: Colors.amber,
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(14.0),
//                         ),
//                       ),
//                       onPressed: () {
//                         Navigator.pop(context, true);
//                       },
//                       child: Text(
//                         'OK',
//                         style: TextStyle(
//                           fontWeight: FontWeight.bold,
//                           color: Colors.black,
//                           fontSize: 16,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
import 'package:flutter/material.dart';

class ConfirmModal extends StatelessWidget {
  const ConfirmModal({
    super.key,
    required this.title,
    required this.description,
    this.confirmText = "Ya, Lanjutkan",
    this.cancelText = "Batal",
    this.isDanger = false, // Jika true, warna tombol jadi merah
  });

  final String title;
  final String description;
  final String confirmText;
  final String cancelText;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(
          maxWidth: 340,
        ), // Lebar maksimal yang ideal untuk mobile
        child: Column(
          mainAxisSize:
              MainAxisSize.min, // Dialog mengikuti tinggi konten (tidak kaku)
          children: [
            // Ikon Header untuk konteks visual
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDanger ? Colors.red.shade50 : Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isDanger
                    ? Icons.warning_amber_rounded
                    : Icons.help_outline_rounded,
                color: isDanger ? Colors.red : Colors.amber.shade900,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),

            // Teks Judul
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            // Deskripsi
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            // Baris Tombol
            Row(
              children: [
                // Tombol Batal
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      cancelText,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Tombol Konfirmasi
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDanger ? Colors.red : Colors.amber,
                      foregroundColor: isDanger ? Colors.white : Colors.black87,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      confirmText,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
