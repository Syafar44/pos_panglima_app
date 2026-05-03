import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';

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
                color: isDanger ? Colors.red.shade50 : AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isDanger
                    ? Icons.warning_amber_rounded
                    : Icons.help_outline_rounded,
                color: isDanger ? Colors.red : AppColors.primaryDarkest,
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
                      backgroundColor: isDanger
                          ? Colors.red
                          : AppColors.primary,
                      foregroundColor: isDanger ? Colors.white : Colors.white,
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
