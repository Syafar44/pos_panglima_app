import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/app_config.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/views/pages/login_page.dart';
import 'package:pos_panglima_app/views/widgets/endShift_modal.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

List<Map<String, dynamic>> list = [
  {'label': 'Pesanan Baru', 'icon': Icon(Icons.shopping_cart)},
  // {'label': 'Open Bill', 'icon': Icon(Icons.receipt_sharp)},
  {'label': 'Riwayat Penjualan', 'icon': Icon(Icons.history)},
  // {'label': 'Pelanggan', 'icon': Icon(Icons.person)},
  // {'label': 'Karyawan', 'icon': Icon(Icons.group)},
  {'label': 'Laporan', 'icon': Icon(Icons.receipt_long)},
  {'label': 'Inventory', 'icon': Icon(Icons.inventory)},
  {'label': 'Pengaturan', 'icon': Icon(Icons.settings)},
];

class DrawerWidget extends StatefulWidget {
  const DrawerWidget({super.key, required this.value});

  final int value;

  @override
  State<DrawerWidget> createState() => _DrawerWidgetState();
}

class _DrawerWidgetState extends State<DrawerWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  bool? hasShift;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/logo.png'), context);
    });
    _loadShiftStatus();
  }

  Future<void> _loadShiftStatus() async {
    final result = await ShiftStorageService.hasActiveShift();
    setState(() {
      hasShift = result;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePress() async {
    if (_controller.isAnimating) return;

    _controller.forward(from: 0.0);

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WidgetTree()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            height: 100, // Sedikit lebih tinggi agar tidak sesak
            width: double.infinity,
            padding: const EdgeInsets.only(left: 20, right: 20),
            decoration: BoxDecoration(
              color: Colors.amber[50], // Background lembut untuk header
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                // Logo dengan Frame Cantik
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 50,
                    height: 50,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.storefront,
                      size: 40,
                      color: Colors.amber,
                    ),
                  ),
                ),
                const SizedBox(width: 16.0),
                // Info Aplikasi
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "POS Panglima",
                        style: TextStyle(
                          fontSize: 18.0,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                      Text(
                        "Versi ${AppConfig.version}",
                        style: TextStyle(
                          fontSize: 12.0,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _handlePress,
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red[50],
                        border: Border.all(color: Colors.black12),
                      ),
                      child: RotationTransition(
                        // Tambahkan baris ini untuk menghubungkan controller dengan animasi
                        turns: _controller,
                        child: Transform.flip(
                          flipX: true,
                          child: Icon(
                            Icons.sync_rounded,
                            size: 20,
                            color: Colors.red[300],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- DAFTAR MENU ---
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final isSelected = widget.value == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isSelected ? Colors.amber[100] : Colors.white,
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    selected: isSelected,
                    leading: Icon(
                      list[index]['icon'] is Icon
                          ? (list[index]['icon'] as Icon).icon
                          : Icons.circle,
                      color: isSelected ? Colors.amber[900] : Colors.grey[600],
                    ),
                    title: Text(
                      list[index]['label'],
                      style: TextStyle(
                        fontSize: 15,
                        color: isSelected
                            ? Colors.amber[900]
                            : Colors.grey[800],
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      selectedPageNotifier.value = index;
                    },
                  ),
                );
              },
            ),
          ),

          // --- FOOTER: TOMBOL SHIFT ---
          Container(
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[100]!)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: hasShift == false
                      ? Colors.green[50]
                      : Colors.red[50],
                  foregroundColor: hasShift == false
                      ? Colors.green[700]
                      : Colors.red[700],
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: hasShift == false
                        ? BorderSide(color: Colors.green[100]!)
                        : BorderSide(color: Colors.red[100]!),
                  ),
                ),
                onPressed: () {
                  if (hasShift == false) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LoginPage(title: 'Login'),
                      ),
                    );
                  } else {
                    showDialog(
                      context: context,
                      builder: (context) => const EndShiftModal(),
                    );
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      hasShift == false
                          ? Icons.play_arrow_rounded
                          : Icons.stop_circle_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasShift == false ? 'MULAI SHIFT' : 'AKHIRI SHIFT',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
