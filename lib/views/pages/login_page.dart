import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/fcm_token_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/method_service.dart';
import 'package:pos_panglima_app/services/shift_service.dart';
import 'package:pos_panglima_app/services/storage/method_storage_service.dart';
import 'package:pos_panglima_app/services/storage/profile_storage_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/widgets/start_shift_modal.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _loginTimedOut = false;
  Timer? _loginTimer;

  late final ShiftService shiftService;

  @override
  void initState() {
    super.initState();
    authService = AuthService(apiClient.dio);
    shiftService = ShiftService(apiClient.dio);
  }

  @override
  void dispose() {
    controllerEmail.dispose();
    controllerPw.dispose();
    _loginTimer?.cancel();
    super.dispose();
  }

  void _startLoginTimeout() {
    _loginTimer?.cancel();
    _loginTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && loading) {
        setState(() => _loginTimedOut = true);
      }
    });
  }

  /// Cek apakah outlet sedang punya shift aktif.
  /// Return shiftId jika ada, atau null jika tidak ada / gagal.
  /// Saat shift aktif ditemukan, sekaligus disimpan ke SharedPreferences
  /// agar [WidgetTree] bisa langsung mengenali shift yang berjalan.
  Future<int?> _checkActiveShift(dynamic customer) async {
    try {
      final outletHubId = (customer is List && customer.isNotEmpty)
          ? int.tryParse(customer[0].toString())
          : null;
      if (outletHubId == null) return null;

      final response = await shiftService.getCurrentShift(outletHubId);
      final shiftData = response.data is Map ? response.data['data'] : null;
      if (shiftData == null || shiftData is! Map) return null;

      final shiftId = shiftData['id'] is int
          ? shiftData['id'] as int
          : int.tryParse(shiftData['id']?.toString() ?? '');
      if (shiftId == null) return null;

      final salesStartRaw = shiftData['sales_start'];
      final salesStart = salesStartRaw is int
          ? salesStartRaw
          : int.tryParse(salesStartRaw?.toString() ?? '') ?? 0;

      await ShiftStorageService.saveShiftId(shiftId, salesStart);
      return shiftId;
    } catch (e, stack) {
      // 404 / tidak ada shift aktif bukan error fatal — abaikan untuk Crashlytics.
      debugPrint('getCurrentShift: $e');
      CrashReporter.report(e, stack, reason: 'login_page._checkActiveShift');
      return null;
    }
  }

  /// Simpan profil pengguna & metode pembayaran/pesanan ke local storage saat
  /// login, supaya halaman pembayaran tetap berfungsi dan payload order tetap
  /// benar saat offline. Setiap login ulang menimpa data lama.
  /// Best-effort: setiap kegagalan dilaporkan tapi tidak menggagalkan login.
  Future<void> _cacheOfflineEssentials(Map<String, dynamic> loginData) async {
    // Profil: ambil dari endpoint profile (sumber yang sama dengan payment page)
    // agar nama, userid, dan customer/outlet id konsisten.
    try {
      final profileRes = await authService.getProfile();
      final p = profileRes.data['data'];
      final uid = p?['userid'] ?? loginData['id'];
      final userIdInt =
          uid is int ? uid : int.tryParse(uid?.toString() ?? '') ?? 0;
      final customerSource = p?['customer'] ?? loginData['customer'];
      final customerId =
          (customerSource is List && customerSource.isNotEmpty)
              ? customerSource[0].toString()
              : null;
      await ProfileStorageService.save(
        userId: userIdInt,
        userName: (p?['name'] ?? '').toString(),
        customerId: customerId,
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'login_page._cacheProfile');
    }

    // Metode pembayaran & pesanan untuk halaman pembayaran offline.
    try {
      final methodService = MethodService(apiClient.dio);
      final results = await Future.wait([
        methodService.getPaymentMethods(),
        methodService.getOrderMethods(),
      ]);
      await MethodStorageService.save(
        List.from(results[0].data['data'] ?? []),
        List.from(results[1].data['data'] ?? []),
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'login_page._cacheMethods');
    }
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

    setState(() {
      loading = true;
      _loginTimedOut = false;
    });
    _startLoginTimeout();

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

      // Provisioning data untuk mode offline (profil pengguna + metode
      // pembayaran/pesanan). Best-effort: kegagalan tidak memblok login.
      await _cacheOfflineEssentials(data);

      // Simpan alamat outlet dari customer_info[0].address untuk dipakai
      // di struk cetak (bluetooth_printer_service). Defensive parsing —
      // kalau field tidak ada, simpan string kosong.
      final customerInfo = data['customer_info'];
      String outletAddress = '';
      if (customerInfo is List && customerInfo.isNotEmpty) {
        outletAddress = (customerInfo[0]['address'] ?? '').toString();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('outlet_address', outletAddress);

      // Simpan users_id supaya FcmTokenService bisa sync token di kemudian hari
      // (saat onTokenRefresh atau retry di startup).
      final dynamic uid = data['id'];
      final int? userIdInt = uid is int
          ? uid
          : int.tryParse(uid?.toString() ?? '');
      if (userIdInt != null) {
        await FcmTokenService.saveUsersId(userIdInt);
      }

      // Fire-and-forget: FCM sync best-effort, tidak boleh memblok login flow
      // atau abort login kalau gagal.
      // ignore: unawaited_futures
      FcmTokenService.syncToken();

      if (!mounted) return;

      // Cek apakah shift sudah aktif untuk outlet ini.
      // Jika ada → langsung masuk ke WidgetTree, modal Start Shift dilewati.
      final activeShift = await _checkActiveShift(data['customer']);
      if (!mounted) return;

      if (activeShift != null) {
        selectedPageNotifier.value = 0;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WidgetTree()),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const StartShiftModal(),
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'login_page.login');
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: "Login Gagal",
        message: "Periksa kembali kredensial Anda atau koneksi internet",
        status: SnackBarStatus.error,
      );
    } finally {
      _loginTimer?.cancel();
      if (mounted) {
        setState(() {
          loading = false;
          _loginTimedOut = false;
        });
      }
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
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3)),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isTablet ? 500 : double.infinity,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(24.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
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
                        'assets/images/icon_launcher.png',
                        height: 80.0,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.storefront, size: 80),
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
                        onPressed: (loading && !_loginTimedOut) ? null : login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                        ),
                        child: loading && !_loginTimedOut
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                _loginTimedOut ? "Coba Lagi" : "Masuk",
                                style: const TextStyle(
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
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
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
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
