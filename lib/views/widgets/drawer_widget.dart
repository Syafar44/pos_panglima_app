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
  final String logo = 'assets/images/logo.png';
  bool? hasShift;

  @override
  void initState() {
    super.initState();
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
    return Drawer(
      child: Column(
        children: [
          SizedBox(
            height: 100,
            child: DrawerHeader(
              margin: EdgeInsets.zero,
              child: Row(
                children: [
                  Image.asset(logo, fit: BoxFit.fill, width: 80.0),
                  SizedBox(width: 14.0),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "POS Panglima",
                        style: TextStyle(
                          fontSize: 17.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text("Version 1.0.0"),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: list.length,
              itemBuilder: (context, index) {
                final isSelected = widget.value == index;
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: Colors.amber[200],
                  selectedColor: Colors.black,
                  leading: list[index]['icon'],
                  title: Text(
                    list[index]['label'],
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    selectedPageNotifier.value = index;
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 16.0,
              horizontal: 20.0,
            ),
            child: SizedBox(
              width: double.infinity,
              child: hasShift == false
                  ? FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber,
                        padding: EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LoginPage(title: 'Login'),
                          ),
                        );
                      },
                      child: Text(
                        'Mulai Shift',
                        style: TextStyle(color: Colors.black),
                      ),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber,
                        padding: EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          barrierDismissible: true,
                          builder: (context) => const EndsiftModal(),
                        );
                      },
                      child: Text(
                        'Akhiri Shift',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
