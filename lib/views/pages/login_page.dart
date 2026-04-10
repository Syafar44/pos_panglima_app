import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/widgets/startShift_modal.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.title});

  final String title;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController controllerEmail = TextEditingController();
  final TextEditingController controllerPw = TextEditingController();
  final apiClient = ApiClient();
  late final AuthService authService;

  bool loading = false;
  bool _isObscure = true;

  @override
  void initState() {
    super.initState();
    authService = AuthService(apiClient.dio);
  }

  @override
  void dispose() {
    controllerEmail.dispose();
    controllerPw.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (controllerEmail.text.isEmpty || controllerPw.text.isEmpty) {
      SnackbarUtil.show(
        context,
        title: "Input Kosong",
        message: "Email dan kata sandi wajib diisi",
        status: SnackBarStatus.warning,
      );
      return;
    }

    setState(() => loading = true);

    try {
      final response = await authService.login({
        "email": controllerEmail.text.trim(),
        "password": controllerPw.text,
      });

      final data = response.data['data'];
      final roles = data['roles'] ?? '';

      if (!roles.toLowerCase().contains('kasir')) {
        if (!mounted) return;
        SnackbarUtil.show(
          context,
          title: "Akses Ditolak",
          message: "Akun ini tidak memiliki akses sebagai kasir",
          status: SnackBarStatus.error,
        );
        return;
      }

      await apiClient.saveToken(data['token']);

      final fcmToken = await FirebaseMessaging.instance.getToken();

      try {
        if (fcmToken != null) {
          await authService.postFcmToken({
            "users_id": data['id'],
            "fcm_token": fcmToken,
            "tipe": "android",
          });
        }
      } catch (fcmError) {
        debugPrint("FCM Error: $fcmError");
      }

      if (!mounted) return;

      // Menampilkan modal shift setelah login berhasil
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const StartShiftModal(),
      );
    } catch (e) {
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: "Login Gagal",
        message: "Periksa kembali kredensial Anda atau koneksi internet",
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => loading = false);
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
            image: AssetImage('assets/images/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(
              0.3,
            ), // Overlay gelap agar teks lebih kontras
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isTablet ? 500 : double.infinity,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(24.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/logo.png',
                        height: 80.0,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.storefront,
                          size: 80,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32.0),
                    const Text(
                      'Selamat Datang',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 24.0,
                        color: Colors.black87,
                      ),
                    ),
                    const Text(
                      'Silakan masuk ke akun Kasir Anda',
                      style: TextStyle(fontSize: 14.0, color: Colors.grey),
                    ),
                    const SizedBox(height: 24.0),

                    // Email Field
                    _buildTextField(
                      controller: controllerEmail,
                      hint: 'Email Kasir',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16.0),

                    // Password Field
                    _buildTextField(
                      controller: controllerPw,
                      hint: 'Kata Sandi',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      obscureText: _isObscure,
                      onTogglePassword: () =>
                          setState(() => _isObscure = !_isObscure),
                    ),
                    const SizedBox(height: 24.0),

                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: loading ? null : login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                        ),
                        child: loading
                            ? ModernLoading(
                                size: 24,
                                strokeWidth: 3,
                                timeout: const Duration(seconds: 10),
                                onRetry: () {},
                              ) // Menggunakan utilitas baru
                            : const Text(
                                "Masuk",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onTogglePassword,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.amber.shade700, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: onTogglePassword,
              )
            : null,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.0),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.0),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.0),
          borderSide: const BorderSide(color: Colors.amber, width: 2),
        ),
      ),
    );
  }
}
