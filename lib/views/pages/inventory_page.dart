import 'package:flutter/material.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/inventory_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';
import 'package:pos_panglima_app/views/pages/reception_inventory_page.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  int numberPage = 1;
  final apiClient = ApiClient();
  late final AuthService authService;
  late final InventoryService inventoryService;
  String? customerId;
  bool isLoadingCustomerId = true;
  bool isLoadingInventory = true;
  bool inventoryIsEmpty = false;
  List inventoryList = [];

  @override
  void initState() {
    super.initState();
    authService = AuthService(apiClient.dio);
    inventoryService = InventoryService(apiClient.dio);
    getCustomerId();
  }

  Future<void> getCustomerId() async {
    try {
      final response = await authService.getProfile();
      final data = response.data['data'];
      final newCustomer =
          (data['customer'] is List && data['customer'].isNotEmpty)
          ? data['customer'][0]
          : null;
      await getInventoryTransfer(newCustomer);
      setState(() {
        customerId = newCustomer;
        isLoadingCustomerId = false;
      });
    } catch (e) {
      isLoadingCustomerId = false;
      debugPrint("Gagal ambil customer: $e");
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'danger',
            title: 'Gagal memuat data pengguna',
            description:
                'Terjadi kendala saat mengambil data pengguna. Mohon periksa koneksi atau coba kembali.',
          );
        },
      );
    }
  }

  Future<void> getInventoryTransfer(customerId) async {
    try {
      final response = await inventoryService.getList(
        "page=1&limit=10&to_outlet_hub_id=$customerId",
      );
      setState(() {
        inventoryList = response.data['data'];
        isLoadingInventory = false;
      });
    } catch (e) {
      inventoryIsEmpty = true;
    }
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
                      _buildMenuItem(
                        index: 1,
                        icon: Icons.all_inbox_rounded,
                        label: 'Surat Jalan',
                      ),
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
                      Text(
                        'V.1.0.0',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(flex: 2, child: suratJalan()),
      ],
    );
  }

  Widget suratJalan() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(13),
          color: Colors.grey[200],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            spacing: 20.0,
            children: [
              Text(
                'Surat Jalan',
                style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
              ),
              inventoryList.isNotEmpty
                  ? Text(
                      'Belum Diterima (${inventoryList.length}) *',
                      style: TextStyle(fontSize: 18.0, color: Colors.red),
                    )
                  : SizedBox(),
            ],
          ),
        ),
        inventoryIsEmpty
            ? Expanded(
                child: Center(child: Text('Semua Surat Jalan Sudah Diterima')),
              )
            : Expanded(
                child: isLoadingInventory || isLoadingCustomerId
                    ? SizedBox(
                        height: 400,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          spacing: 10.0,
                          children: inventoryList.map((inventory) {
                            return Card(
                              color: Colors.white70,
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) {
                                        return ReceptionInventoryPage(
                                          id: inventory['id'],
                                        );
                                      },
                                    ),
                                  );
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20.0),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            spacing: 10.0,
                                            children: [
                                              Text(
                                                'No. Po / No. SJ',
                                                style: const TextStyle(
                                                  fontSize: 18.0,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                ':  ${inventory['document_number']}',
                                                style: TextStyle(
                                                  fontSize: 18.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            spacing: 68.0,
                                            children: [
                                              Text(
                                                'Supplier',
                                                style: const TextStyle(
                                                  fontSize: 18.0,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                ':  ${inventory['from_outlet_hub_name']}',
                                                style: const TextStyle(
                                                  fontSize: 18.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            spacing: 48.0,
                                            children: [
                                              Text(
                                                'Ke Gudang',
                                                style: const TextStyle(
                                                  fontSize: 18.0,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                ':  ${inventory['to_outlet_hub_name']}',
                                                style: const TextStyle(
                                                  fontSize: 18.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            spacing: 72.0,
                                            children: [
                                              Text(
                                                'Tanggal',
                                                style: const TextStyle(
                                                  fontSize: 18.0,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                ':  ${formatDateTime(inventory['date'])}',
                                                style: const TextStyle(
                                                  fontSize: 18.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      Row(
                                        spacing: 20.0,
                                        children: [
                                          Text(
                                            'Belum Diterima *',
                                            style: const TextStyle(
                                              fontSize: 18.0,
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Icon(Icons.arrow_forward_ios),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
              ),
      ],
    );
  }

  Widget _buildMenuItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    bool isActive = numberPage == index;

    return Material(
      color: isActive ? Colors.amber[50] : Colors.transparent,
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
              width: 2,
              color: isActive ? Colors.orange : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24.0,
                color: isActive ? Colors.amber[800] : Colors.grey[500],
              ),
              const SizedBox(width: 16.0),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15.0,
                  color: isActive ? Colors.amber[900] : Colors.grey[700],
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              if (isActive) const Spacer(),
              if (isActive)
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.amber[800],
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
