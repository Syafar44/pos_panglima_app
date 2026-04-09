import 'package:flutter/material.dart';
import 'package:number_pagination/number_pagination.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/inventory_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';
import 'package:pos_panglima_app/utils/skeleton_loader.dart';
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
  int unapprovedCount = 0;
  int selectedPageNumber = 1;
  Map<String, dynamic>? paginationInfo;

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
      if (!mounted) return;
      isLoadingCustomerId = false;
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
        "page=$selectedPageNumber&limit=10&to_outlet_hub_id=$customerId",
      );
      setState(() {
        inventoryList = response.data['data'];
        isLoadingInventory = false;
        unapprovedCount = inventoryList
            .where((item) => (item['approve'] ?? 0) == 0)
            .length;
      });
    } catch (e) {
      if (!mounted) return;
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white, // Menggunakan putih agar lebih clean
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              left: const BorderSide(
                color: Colors.amber,
                width: 5,
              ), // Aksen warna identitas POS
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Surat Jalan',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Inventory Transfer',
                    style: TextStyle(fontSize: 12.0, color: Colors.grey[500]),
                  ),
                ],
              ),
              if (unapprovedCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.pending_actions,
                        size: 16,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$unapprovedCount Menunggu',
                        style: const TextStyle(
                          fontSize: 13.0,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        inventoryIsEmpty
            ? Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 80,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Belum Ada Surat Jalan',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ],
                ),
              )
            : Expanded(
                child: isLoadingInventory || isLoadingCustomerId
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: SkeletonLoader.detailInventorySkeleton(),
                      )
                    : ListView.builder(
                        // Menggunakan ListView.builder lebih efisien memori
                        padding: const EdgeInsets.all(16),
                        itemCount: inventoryList.length,
                        itemBuilder: (context, index) {
                          final inventory = inventoryList[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                               borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(15),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ReceptionInventoryPage(
                                            id: inventory['id'],
                                          ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Header Card: No. Dokumen & Status
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              inventory['document_number'] ??
                                                  '-',
                                              style: const TextStyle(
                                                fontSize: 18.0,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blueGrey,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: inventory['approve'] == 1
                                                  ? Colors.green.shade50
                                                  : Colors.red.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              inventory['approve'] == 1
                                                  ? 'DITERIMA'
                                                  : 'BELUM DITERIMA',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: inventory['approve'] == 1
                                                    ? Colors.green
                                                    : Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 24),

                                      // Detail Section menggunakan Row yang lebih rapi
                                      _buildDetailRow(
                                        'Asal',
                                        inventory['from_outlet_hub_name'],
                                      ),
                                      const SizedBox(height: 8),
                                      _buildDetailRow(
                                        'Ke',
                                        inventory['to_outlet_hub_name'],
                                      ),
                                      const SizedBox(height: 8),
                                      _buildDetailRow(
                                        'Tanggal',
                                        formatDateTime(inventory['date']),
                                      ),

                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Detail Transaksi',
                                            style: TextStyle(
                                              color: Colors.amber.shade900,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 16,
                                            color: Colors.amber.shade900,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(
                color: Colors.grey[200]!,
              ), // Garis halus di atas pagination
            ),
          ),
          child: NumberPagination(
            onPageChanged: (int pageNumber) {
              setState(() {
                selectedPageNumber = pageNumber;
                isLoadingInventory = true;
              });
              getInventoryTransfer(customerId);
            },
            visiblePagesCount: 3,
            totalPages: paginationInfo?['total_page'] ?? 0,
            currentPage: selectedPageNumber,
            buttonRadius: 12,
            selectedButtonColor: Colors.amber.shade400,
            selectedNumberColor: Colors.black,
            unSelectedButtonColor: Colors.grey[100]!,
            unSelectedNumberColor: Colors.grey[700]!,
            numberButtonSize: const Size(35, 35),
            controlButtonSize: const Size(35, 35),
            fontSize: 14,
            sectionSpacing: 5,
            navigationButtonSpacing: 0,
            enableInteraction: inventoryList.length < 10 ? false : true,
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

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ),
        const Text(': ', style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
