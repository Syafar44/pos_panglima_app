import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/update_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/pages/big_order_page.dart';
import 'package:pos_panglima_app/views/pages/inventory_page.dart';
// import 'package:pos_panglima_app/views/pages/karyawan_page.dart';
import 'package:pos_panglima_app/views/pages/laporan_page.dart';
// import 'package:pos_panglima_app/views/pages/pelanggan_page.dart';
import 'package:pos_panglima_app/views/pages/pengaturan_page.dart';
import 'package:pos_panglima_app/views/pages/pesanan_baru_page.dart';
// import 'package:pos_panglima_app/views/pages/open_bill_page.dart';
import 'package:pos_panglima_app/views/pages/riwayat_penjualan_page.dart';
import 'package:pos_panglima_app/views/widgets/drawer_widget.dart';
import 'package:pos_panglima_app/views/widgets/network_indicator.dart';

List<Map<String, dynamic>> pages = [
  {'name': 'Pesanan Baru', 'builder': () => const PesananBaruPage()},
  {'name': 'Big Order', 'builder': () => const BigOrderPage()},
  // {'name': 'Open Bill', 'builder': () => const OpenBillPage()},
  {'name': 'Riwayat Penjualan', 'builder': () => const RiwayatPenjualanPage()},
  // {'name': 'Pelanggan', 'builder': () => const PelangganPage()},
  // {'name': 'Karyawan', 'builder': () => const KaryawanPage()},
  {'name': 'Laporan', 'builder': () => const LaporanPage()},
  {'name': 'Inventory', 'builder': () => const InventoryPage()},
  {'name': 'Pengaturan', 'builder': () => const PengaturanPage()},
];

class WidgetTree extends StatefulWidget {
  const WidgetTree({super.key});

  @override
  State<WidgetTree> createState() => _WidgetTreeState();
}

class _WidgetTreeState extends State<WidgetTree> with WidgetsBindingObserver {
  bool _restartPrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingUpdate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkPendingUpdate();
    }
  }

  Future<void> _checkPendingUpdate() async {
    if (_restartPrompted) return;
    final info = await UpdateService.check();
    if (info?.installStatus != InstallStatus.downloaded) return;
    if (!mounted) return;
    _restartPrompted = true;

    SnackbarUtil.show(
      context,
      title: 'Update Siap Dipasang',
      message: 'Tap untuk memasang dan memulai ulang aplikasi.',
      status: SnackBarStatus.success,
    );

    final shouldRestart = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: const Icon(
          Icons.download_done_rounded,
          size: 48,
          color: AppColors.primary,
        ),
        title: const Text(
          'Update Selesai Diunduh',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: const Text(
          'Mulai ulang aplikasi sekarang untuk memasang versi terbaru?',
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
                    'Restart',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (shouldRestart == true) {
      await UpdateService.completeFlexible();
    } else {
      _restartPrompted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: selectedPageNotifier,
      builder: (context, value, child) {
        return SafeArea(
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                pages[value]['name'],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: false,
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/background.png"),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
              actions: const [NetworkIndicatorWidget()],
            ),
            body: pages[value]['builder'](),
            drawer: DrawerWidget(value: value),
          ),
        );
      },
    );
  }
}
