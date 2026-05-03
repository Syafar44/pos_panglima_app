import 'package:flutter/material.dart';
import 'package:safe_device/safe_device.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'dart:convert';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/views/pages/device_locked_screen.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/views/pages/login_page.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final ApiClient apiClient = ApiClient();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(
        const AssetImage('assets/images/icon_launcher.png'),
        context,
      );
      checkLogin();
    });
  }

  Future<void> checkLogin() async {
    await Future.delayed(const Duration(seconds: 1));

    bool jailbroken = false;
    try {
      jailbroken = await SafeDevice.isJailBroken;
    } catch (_) {
      // Plugin tidak tersedia di platform ini (emulator / web)
    }
    if (jailbroken) {
      await const FlutterSecureStorage().deleteAll();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DeviceLockedScreen()),
      );
      return;
    }

    final token = await apiClient.getToken();
    final result = await ShiftStorageService.getShiftId();

    if (!mounted) return;

    if (token != null && !isTokenExpired(token) && result != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WidgetTree()),
      );
    } else {
      // Hapus token lama jika expired
      if (token != null && isTokenExpired(token)) {
        await ShiftStorageService.clearShift();
        await apiClient.clearToken();
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage(title: 'Login Page')),
      );
    }
  }

  bool isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final Map<String, dynamic> jsonPayload = jsonDecode(decoded);

      final exp = jsonPayload['exp'];
      if (exp == null) return false;

      final expDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(expDate);
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'splash_screen.isTokenExpired');
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.2),
                Colors.black.withValues(alpha: 0.4),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "POS PANGLIMA",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 2.0,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Panglima Roqiiqu Group",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade200,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: isTablet ? 60 : 40),
                Column(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        strokeCap: StrokeCap.round,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Memuat Data...",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
