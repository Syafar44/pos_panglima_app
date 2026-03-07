import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/views/pages/inventory_page.dart';
// import 'package:pos_panglima_app/views/pages/karyawan_page.dart';
import 'package:pos_panglima_app/views/pages/laporan_page.dart';
// import 'package:pos_panglima_app/views/pages/pelanggan_page.dart';
import 'package:pos_panglima_app/views/pages/pengaturan_page.dart';
import 'package:pos_panglima_app/views/pages/pesanan_baru_page.dart';
// import 'package:pos_panglima_app/views/pages/open_bill_page.dart';
import 'package:pos_panglima_app/views/pages/riwayat_penjualan_page.dart';
import 'package:pos_panglima_app/views/widgets/drawer_widget.dart';

List<Map<String, dynamic>> pages = [
  {'name': 'Pesanan Baru', 'page': PesananBaruPage()},
  // {'name': 'Open Bill', 'page': OpenBillPage()},
  {'name': 'Riwayat Penjualan', 'page': RiwayatPenjualanPage()},
  // {'name': 'Pelanggan', 'page': PelangganPage()},
  // {'name': 'Karyawan', 'page': KaryawanPage()},
  {'name': 'Laporan', 'page': LaporanPage()},
  {'name': 'Inventory', 'page': InventoryPage()},
  {'name': 'Pengaturan', 'page': PengaturanPage()},
];

class WidgetTree extends StatelessWidget {
  const WidgetTree({super.key});

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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              centerTitle: false,
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/background.jpg"),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
            ),
            body: pages[value]['page'],
            drawer: DrawerWidget(value: value),
          ),
        );
      },
    );
  }
}
