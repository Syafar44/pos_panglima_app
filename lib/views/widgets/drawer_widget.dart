import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/views/pages/login_page.dart';
import 'package:pos_panglima_app/views/widgets/endsift_modal.dart';

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

class _DrawerWidgetState extends State<DrawerWidget> {
  // final String logo = 'assets/images/logo.png';
  bool? hasShift;

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    // return Drawer(
    //   child: Column(
    //     children: [
    //       SizedBox(
    //         height: 100,
    //         child: DrawerHeader(
    //           margin: EdgeInsets.zero,
    //           child: Row(
    //             children: [
    //               Image(
    //                 image: const AssetImage('assets/images/logo.png'),
    //                 fit: BoxFit.fill,
    //                 width: 80.0,
    //                 gaplessPlayback: true,
    //                 frameBuilder:
    //                     (context, child, frame, wasSynchronouslyLoaded) {
    //                       // Jika sudah di-cache, langsung tampil tanpa animasi
    //                       if (wasSynchronouslyLoaded) return child;
    //                       return AnimatedOpacity(
    //                         opacity: frame == null ? 0 : 1,
    //                         duration: const Duration(milliseconds: 150),
    //                         child: child,
    //                       );
    //                     },
    //               ),
    //               SizedBox(width: 14.0),
    //               Column(
    //                 crossAxisAlignment: CrossAxisAlignment.start,
    //                 mainAxisAlignment: MainAxisAlignment.center,
    //                 children: [
    //                   Text(
    //                     "POS Panglima",
    //                     style: TextStyle(
    //                       fontSize: 17.0,
    //                       fontWeight: FontWeight.bold,
    //                     ),
    //                   ),
    //                   Text("Version 1.0.0"),
    //                 ],
    //               ),
    //             ],
    //           ),
    //         ),
    //       ),
    //       Expanded(
    //         child: ListView.builder(
    //           padding: EdgeInsets.zero,
    //           itemCount: list.length,
    //           itemBuilder: (context, index) {
    //             final isSelected = widget.value == index;
    //             return ListTile(
    //               selected: isSelected,
    //               selectedTileColor: Colors.amber[200],
    //               selectedColor: Colors.black,
    //               leading: list[index]['icon'],
    //               title: Text(
    //                 list[index]['label'],
    //                 style: TextStyle(
    //                   color: Colors.black87,
    //                   fontWeight: isSelected
    //                       ? FontWeight.bold
    //                       : FontWeight.normal,
    //                 ),
    //               ),
    //               onTap: () {
    //                 Navigator.pop(context);
    //                 selectedPageNotifier.value = index;
    //               },
    //             );
    //           },
    //         ),
    //       ),
    //       Padding(
    //         padding: const EdgeInsets.symmetric(
    //           vertical: 16.0,
    //           horizontal: 20.0,
    //         ),
    //         child: SizedBox(
    //           width: double.infinity,
    //           child: hasShift == false
    //               ? FilledButton(
    //                   style: FilledButton.styleFrom(
    //                     backgroundColor: Colors.amber,
    //                     padding: EdgeInsets.symmetric(
    //                       horizontal: 22,
    //                       vertical: 14,
    //                     ),
    //                     shape: RoundedRectangleBorder(
    //                       borderRadius: BorderRadius.circular(12),
    //                     ),
    //                   ),
    //                   onPressed: () {
    //                     Navigator.push(
    //                       context,
    //                       MaterialPageRoute(
    //                         builder: (context) => LoginPage(title: 'Login'),
    //                       ),
    //                     );
    //                   },
    //                   child: Text(
    //                     'Mulai Shift',
    //                     style: TextStyle(color: Colors.black),
    //                   ),
    //                 )
    //               : FilledButton(
    //                   style: FilledButton.styleFrom(
    //                     backgroundColor: Colors.amber,
    //                     padding: EdgeInsets.symmetric(
    //                       horizontal: 22,
    //                       vertical: 14,
    //                     ),
    //                     shape: RoundedRectangleBorder(
    //                       borderRadius: BorderRadius.circular(12),
    //                     ),
    //                   ),
    //                   onPressed: () {
    //                     showDialog(
    //                       context: context,
    //                       barrierDismissible: true,
    //                       builder: (context) => const EndsiftModal(),
    //                     );
    //                   },
    //                   child: Text(
    //                     'Akhiri Shift',
    //                     style: TextStyle(color: Colors.black),
    //                   ),
    //                 ),
    //         ),
    //       ),
    //     ],
    //   ),
    // );
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          // --- HEADER DRAWER ---
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
                        "Versi 1.0.0",
                        style: TextStyle(
                          fontSize: 12.0,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
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
                      ? Colors.amber
                      : Colors.red[50],
                  foregroundColor: hasShift == false
                      ? Colors.black
                      : Colors.red[700],
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: hasShift == false
                        ? BorderSide.none
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
                      builder: (context) => const EndsiftModal(),
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
