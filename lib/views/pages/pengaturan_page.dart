import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:pos_panglima_app/data/app_config.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:bluetooth_enable_fork/bluetooth_enable_fork.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/storage/error_log_manager.dart';
import 'package:pos_panglima_app/services/update_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/pages/login_page.dart';

class PengaturanPage extends StatefulWidget {
  const PengaturanPage({super.key});

  @override
  State<PengaturanPage> createState() => _PengaturanPageState();
}

class _PengaturanPageState extends State<PengaturanPage> {
  int numberPage = 1;
  List<BluetoothDevice> devices = [];
  BluetoothDevice? connectedPrinter;
  bool isScanning = false;
  StreamSubscription? _bluetoothSubscription;
  final apiClient = ApiClient();
  late final AuthService authService;
  Map<String, dynamic>? profile;
  bool isLoadingProfile = true;

  final List<String> _allowedKeywords = ['rpp', 'eps', 'xpr', 'printer'];
  int _versionTapCount = 0;
  bool _isCheckingUpdate = false;

  @override
  void initState() {
    super.initState();
    authService = AuthService(apiClient.dio);
    getProfile();

    connectedPrinter = BluetoothPrinterService.connectedPrinter;
    BluetoothPrinterService.connectedPrinterNotifier.addListener(
      _onPrinterChanged,
    );

    _bluetoothSubscription = BluetoothPrinterService.bluetooth
        .onStateChanged()
        .listen((state) {
          setState(() {
            connectedPrinter = BluetoothPrinterService.connectedPrinter;
          });
        });

    _initialScan();
  }

  Future<void> _initialScan() async {
    final isOn = await BluetoothPrinterService.bluetooth.isOn ?? false;
    if (!isOn) return;
    setState(() => isScanning = true);
    final foundDevices = await BluetoothPrinterService.scanPrinters();
    if (!mounted) return;
    setState(() {
      isScanning = false;
      devices = foundDevices;
    });
    await BluetoothPrinterService.loadLastPrinter();
  }

  void _onPrinterChanged() {
    if (!mounted) return;
    setState(() {
      connectedPrinter = BluetoothPrinterService.connectedPrinter;
    });
  }

  Future<bool> _ensureBluetoothOn() async {
    final isOn = await BluetoothPrinterService.bluetooth.isOn ?? false;
    if (isOn) return true;
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: const Icon(
          Icons.bluetooth_disabled_rounded,
          size: 48,
          color: AppColors.primary,
        ),
        title: const Text(
          'Aktifkan Bluetooth?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: const Text(
          'Bluetooth perangkat sedang nonaktif. Aktifkan sekarang untuk '
          'mencari atau menyambungkan printer?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.only(
          bottom: 20,
          left: 20,
          right: 20,
          top: 4,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(
                    'Tidak',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Aktifkan',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      final result = await BluetoothEnable.enableBluetooth;
      if (result == 'true') {
        await Future.delayed(const Duration(milliseconds: 500));
        return (await BluetoothPrinterService.bluetooth.isOn) ?? false;
      }
    } catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'pengaturan_page._ensureBluetoothOn',
      );
    }

    if (mounted) {
      SnackbarUtil.show(
        context,
        title: 'Bluetooth tidak aktif',
        message: 'Aktivasi dibatalkan. Silakan coba kembali.',
        status: SnackBarStatus.warning,
      );
    }
    return false;
  }

  Future<void> scanDevices() async {
    if (!await _ensureBluetoothOn()) return;
    setState(() => isScanning = true);
    final foundDevices = await BluetoothPrinterService.scanPrinters();
    setState(() {
      isScanning = false;
      devices = foundDevices;
    });
  }

  Future<void> connectPrinter(BluetoothDevice device) async {
    if (!await _ensureBluetoothOn()) return;
    bool ok = await BluetoothPrinterService.connect(device);

    if (!mounted) return;

    if (ok) {
      setState(() {
        connectedPrinter = device;
      });
    }

    SnackbarUtil.show(
      context,
      title: ok ? "Berhasil Terhubung" : "Koneksi Gagal",
      message: ok
          ? "Terhubung ke ${device.name}"
          : "Tidak dapat terhubung ke perangkat, silakan coba lagi",
      status: ok ? SnackBarStatus.success : SnackBarStatus.error,
    );
  }

  Future<void> disconnectPrinter() async {
    await BluetoothPrinterService.disconnect();
    if (!mounted) return;
    setState(() {
      connectedPrinter = null;
    });
    SnackbarUtil.show(
      context,
      title: 'Sambungan Diputus',
      message: 'Printer berhasil diputus sambungannya.',
      status: SnackBarStatus.warning,
    );
  }

  void _showPrinterModal(BluetoothDevice device) {
    final isConnected = connectedPrinter?.address == device.address;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 28,
                backgroundColor:
                    isConnected ? Colors.green[50] : Colors.grey[100],
                child: Icon(
                  Icons.bluetooth,
                  size: 28,
                  color: isConnected ? Colors.green : AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                device.name ?? 'Perangkat Tidak Dikenal',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                device.address ?? '-',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isConnected ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isConnected
                        ? Colors.green.shade200
                        : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isConnected ? Colors.green : Colors.red[400],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isConnected ? 'Terhubung' : 'Tidak Terhubung',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isConnected
                            ? Colors.green[700]
                            : Colors.red[400],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: isConnected
                    ? OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          disconnectPrinter();
                        },
                        icon: const Icon(
                          Icons.bluetooth_disabled,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'Putuskan Sambungan',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.red.shade200),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          connectPrinter(device);
                        },
                        icon: const Icon(Icons.bluetooth_connected),
                        label: const Text(
                          'Hubungkan',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String> getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      return android.model;
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      return ios.name;
    }

    return "Unknown Device";
  }

  Future<String> getDeviceIP() async {
    final info = NetworkInfo();

    final wifiIP = await info.getWifiIP();

    return wifiIP ?? "Tidak terhubung ke WiFi";
  }

  Future<void> _checkForUpdateManually() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);

    final info = await UpdateService.check();

    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (info == null) {
      SnackbarUtil.show(
        context,
        title: 'Gagal Memeriksa',
        message:
            'Tidak dapat memeriksa pembaruan. Pastikan terhubung ke internet dan aplikasi diinstal dari Play Store.',
        status: SnackBarStatus.error,
      );
      return;
    }

    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      SnackbarUtil.show(
        context,
        title: 'Aplikasi Sudah Terbaru',
        message: 'Anda menggunakan versi terbaru aplikasi.',
        status: SnackBarStatus.success,
      );
      return;
    }

    final shouldUpdate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: const Icon(
          Icons.system_update_rounded,
          size: 48,
          color: AppColors.primary,
        ),
        title: const Text(
          'Versi Baru Tersedia',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: const Text(
          'Versi terbaru aplikasi tersedia. Update sekarang?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.only(
          bottom: 20,
          left: 20,
          right: 20,
          top: 4,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(
                    'Nanti',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Update',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (shouldUpdate == true) {
      await UpdateService.startFlexible();
    }
  }

  Future<void> getProfile() async {
    try {
      final response = await authService.getProfile();

      if (!mounted) return;
      setState(() {
        profile = response.data['data'];
        isLoadingProfile = false;
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pengaturan_page.getProfile');
      debugPrint("Gagal ambil profile: $e");
      if (!mounted) return;
      setState(() => isLoadingProfile = false);
      SnackbarUtil.show(
        context,
        title: "Gagal memuat data pengguna",
        message:
            "Terjadi kendala saat mengambil data pengguna. Mohon periksa koneksi atau coba kembali.",
        status: SnackBarStatus.error,
      );
    }
  }

  @override
  void dispose() {
    BluetoothPrinterService.connectedPrinterNotifier.removeListener(
      _onPrinterChanged,
    );
    _bluetoothSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                right: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // BAGIAN ATAS: DAFTAR MENU
                Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    spacing: 10.0,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Menu 1
                      _buildMenuItem(
                        index: 1,
                        icon: Icons.person_outline_rounded,
                        label: 'Profil Pengguna',
                      ),

                      // Menu 2
                      _buildMenuItem(
                        index: 2,
                        icon: Icons.print_outlined,
                        label: 'Printer',
                      ),

                      // _buildMenuItem(
                      //   index: 3,
                      //   icon: Icons.error_outline,
                      //   label: 'Log Error',
                      // ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Column(
                    children: [
                      Divider(
                        color: Colors.grey[100],
                        indent: 20,
                        endIndent: 20,
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          setState(() => _versionTapCount++);
                          if (_versionTapCount >= 7) {
                            _versionTapCount = 0;
                            FirebaseCrashlytics.instance.crash();
                          }
                        },
                        child: Text(
                          'V.${AppConfig.version}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: numberPage == 1
              ? profil()
              : numberPage == 2
              ? printer()
              : numberPage == 3
              ? errorLog()
              : const Center(child: Text('Comming Soon')),
        ),
      ],
    );
  }

  Widget profil() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Informasi Pengguna'),
                _buildProfileTile(
                  icon: Icons.storefront_outlined,
                  title: 'Informasi Outlet',
                  subtitle: profile?['name'] ?? '-',
                ),
                _buildProfileTile(
                  icon: Icons.badge_outlined,
                  title: 'Departemen',
                  subtitle: profile?['department'] ?? '-',
                ),

                const SizedBox(height: 20),
                _buildSectionHeader('Informasi Perangkat'),
                _buildProfileTile(
                  icon: Icons.important_devices_outlined,
                  title: 'Nama Perangkat',
                  subtitle: FutureBuilder<String>(
                    future: getDeviceName(),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? "Memuat...",
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      );
                    },
                  ),
                ),
                _buildProfileTile(
                  icon: Icons.lan_outlined,
                  title: 'Alamat IP',
                  subtitle: FutureBuilder<String>(
                    future: getDeviceIP(),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? "Memuat...",
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      );
                    },
                  ),
                ),
                _buildProfileTile(
                  icon: Icons.link,
                  title: 'Outlet Terhubung',
                  subtitle: 'Roti Gembung Panglima',
                ),

                const SizedBox(height: 20),
                _buildSectionHeader('Aplikasi'),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Cek Pembaruan',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    'Versi saat ini: ${AppConfig.version}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  trailing: _isCheckingUpdate
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Icon(Icons.chevron_right, color: Colors.grey[400]),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  onTap: _isCheckingUpdate ? null : _checkForUpdateManually,
                ),
              ],
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[200]!)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    // Memperhalus sudut agar terlihat lebih modern
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    backgroundColor: Colors.white,
                    // Mencegah Material 3 memberikan warna tint pada background putih
                    surfaceTintColor: Colors.transparent,

                    // 1. Menambahkan Ikon Indikator
                    icon: const Icon(
                      Icons
                          .info_outline_rounded, // Gunakan warning_rounded jika ini aksi destruktif
                      size: 48,
                      color: AppColors.primary,
                    ),

                    // 2. Tipografi Judul yang Terpusat
                    title: const Text(
                      'Yakin Ingin Keluar?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),

                    // 3. Tipografi Konten yang Lebih Lembut
                    content: const Text(
                      'Anda akan keluar dari halaman ini. Lanjutkan?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        height:
                            1.5, // Memberikan ruang bernapas antar baris teks
                      ),
                    ),

                    // 4. Penataan Tombol Modern (Sejajar dan Proporsional)
                    actionsPadding: const EdgeInsets.only(
                      bottom: 24,
                      left: 20,
                      right: 20,
                      top: 10,
                    ),
                    actions: [
                      Row(
                        children: [
                          // Tombol Secondary (Batal)
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text(
                                'Batal',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Tombol Primary (Submit)
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text(
                                'Keluar',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
                if (confirmed != true) {
                  return;
                }
                if (!mounted) return;
                showDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (BuildContext context) =>
                      const LoginPage(title: "Login"),
                );
              },
              icon: Icon(Icons.logout, color: Colors.red[700], size: 20),
              label: Text(
                'Keluar Perangkat',
                style: TextStyle(
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red[100]!),
                backgroundColor: Colors.red[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Helper untuk Header Section agar konsisten
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12.0,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  // Helper untuk Tile agar lebih cantik
  Widget _buildProfileTile({
    required IconData icon,
    required String title,
    required dynamic subtitle,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: subtitle is Widget
          ? subtitle
          : Text(
              subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  Widget printer() {
    return Column(
      children: [
        // --- HEADER ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daftar Printer',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Pilih perangkat untuk mencetak struk',
                    style: TextStyle(fontSize: 12.0, color: Colors.grey[500]),
                  ),
                ],
              ),
              const Icon(Icons.print_rounded, color: AppColors.primary),
            ],
          ),
        ),

        // --- LIST PERANGKAT ---
        Expanded(
          child: devices.isEmpty
              ? _buildEmptyState()
              : Builder(
                  builder: (context) {
                    final filteredDevices = devices.where((d) {
                      final name = (d.name ?? '').toLowerCase();
                      return _allowedKeywords.any(
                        (keyword) => name.contains(keyword.toLowerCase()),
                      );
                    }).toList();

                    return filteredDevices.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: filteredDevices.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final d = filteredDevices[i];
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.02,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.grey[200],
                                    child: const Icon(
                                      Icons.bluetooth,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    d.name ?? "Perangkat Tidak Dikenal",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    d.address ?? "-",
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: connectedPrinter?.address ==
                                          d.address
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Text(
                                              'Connected',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.green,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Icon(
                                          Icons.chevron_right,
                                          color: Colors.grey[400],
                                        ),
                                  onTap: () => _showPrinterModal(d),
                                ),
                              );
                            },
                          );
                  },
                ),
        ),

        // --- TOMBOL SCANNING (STICKY BOTTOM) ---
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[100]!)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: isScanning ? null : scanDevices,
              icon: isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.search_rounded),
              label: Text(
                isScanning ? 'Mencari Perangkat...' : 'Cari Ulang Printer',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isScanning
                    ? Colors.grey[200]
                    : AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget errorLog() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Fitur Error Log sedang dalam pengembangan",
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await ErrorLogManager.saveLog(
                title: 'Test Error',
                description: 'Ini adalah deskripsi error untuk pengujian 1',
              );
            },
            child: const Text("Save Error"),
          ),
          ElevatedButton(
            onPressed: () async {
              final logs = await ErrorLogManager.getLogs();
              debugPrint(logs.toString());
            },
            child: const Text("Print Error"),
          ),
          ElevatedButton(
            onPressed: () async {
              await ErrorLogManager.clearLogs();
            },
            child: const Text("Clear Error"),
          ),
          ElevatedButton(
            onPressed: () async {
              final fcmToken = await FirebaseMessaging.instance.getToken();
              debugPrint("FCM Token: $fcmToken");
            },
            child: const Text("Print FCM Token"),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.print_disabled_outlined,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            "Tidak ada printer ditemukan",
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Pastikan Bluetooth printer sudah aktif",
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    bool isActive = numberPage == index;

    return Material(
      color: isActive ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          setState(() {
            numberPage = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              width: isActive ? 2 : 1,
              color: isActive ? AppColors.primaryDark : Colors.grey.shade500,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24.0,
                color: isActive ? AppColors.white : Colors.grey[500],
              ),
              const SizedBox(width: 16.0),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15.0,
                  color: isActive ? Colors.white : Colors.grey[700],
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              if (isActive) const Spacer(),
              if (isActive)
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
