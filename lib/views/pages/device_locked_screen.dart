import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';

class DeviceLockedScreen extends StatelessWidget {
  const DeviceLockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, size: 72, color: Colors.red[400]),
              const SizedBox(height: 24),
              const Text(
                'Perangkat Tidak Aman',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3436),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Perangkat ini terdeteksi telah di-root atau di-jailbreak. '
                'Aplikasi tidak dapat dijalankan demi keamanan data.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {},
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Hubungi Administrator'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
