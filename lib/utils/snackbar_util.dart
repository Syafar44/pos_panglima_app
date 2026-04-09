import 'package:flutter/material.dart';

enum SnackBarStatus { success, error, warning, info }

class SnackbarUtil {
  static void show(
    BuildContext context, {
    required String title,
    String? message,
    SnackBarStatus status = SnackBarStatus.info,
  }) {
    // 1. Tentukan warna dan ikon berdasarkan status (Gaya Alert)
    Color backgroundColor;
    IconData icon;

    switch (status) {
      case SnackBarStatus.success:
        backgroundColor = Colors.green.shade800;
        icon = Icons.check_circle_rounded;
        break;
      case SnackBarStatus.error:
        backgroundColor =
            Colors.red.shade900; // Lebih gelap agar teks putih kontras
        icon = Icons.error_outline_rounded;
        break;
      case SnackBarStatus.warning:
        backgroundColor = Colors.orange.shade900;
        icon = Icons.warning_amber_rounded;
        break;
      case SnackBarStatus.info:
      default:
        backgroundColor = Colors.blueGrey.shade800;
        icon = Icons.info_outline_rounded;
    }

    // 2. Hapus snackbar yang sedang tampil agar tidak menumpuk (Snap Response)
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // 3. Tampilkan SnackBar dengan desain modern & floating
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 4,
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(
          seconds: 4,
        ), // Sedikit lebih lama agar user sempat membaca
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Ikon Status
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 12),

            // Konten Teks
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.3, // Memberikan ruang antar baris
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Tombol Close (Opsional namun membantu UX)
            const SizedBox(width: 8),
            InkWell(
              onTap: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
