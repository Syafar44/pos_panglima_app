import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/report_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';
import 'package:pos_panglima_app/utils/skeleton_loader.dart';

List<Map<String, dynamic>> laporanOutlet = [
  {'name': 'Penerimaan Penjualan', 'page': 1},
  {'name': 'Penjualan per Tipe Penjualan', 'page': 2},
  {'name': 'Penjualan Barang per Pelanggan', 'page': 3},
  {'name': 'Penjualan per Barang ', 'page': 4},
];

List<Map<String, dynamic>> laporanKaryawan = [
  {'name': 'Penerimaan Penjualan', 'page': 6},
  {'name': 'Penginputan Barang', 'page': 7},
  {'name': 'Return Penjualan', 'page': 8},
];

List<Map<String, dynamic>> laporanTarget = [
  {
    'name': 'Target Pendapatan Harian',
    'type': 'daily',
    'target': 1000000,
    'page': 12,
  },
  {
    'name': 'Target Pendapatan Mingguan',
    'type': 'weekly',
    'target': 7000000,
    'page': 13,
  },
  {
    'name': 'Target Pendapatan Bulanan',
    'type': 'monthly',
    'target': 30000000,
    'page': 14,
  },
];

class LaporanPage extends StatefulWidget {
  const LaporanPage({super.key});

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  int numberPage = 1;
  final apiClient = ApiClient();
  late final AuthService authService;
  late final ReportService reportService;
  int? shiftId;
  bool isLoadingCustomerId = true;
  bool isLoadingData = true;
  bool inventoryIsEmpty = false;
  Map<String, dynamic> reportData = {};

  @override
  void initState() {
    super.initState();
    authService = AuthService(apiClient.dio);
    reportService = ReportService(apiClient.dio);
    getShiftId();
  }

  Future<void> getShiftId() async {
    try {
      final result = await ShiftStorageService.getShiftId();
      await getData(result);
      setState(() {
        shiftId = result;
      });
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) => ModalHandling(
          type: 'danger',
          title: 'Gagal memuat data pengguna',
          description:
              'Terjadi kendala saat mengambil data pengguna. Mohon periksa koneksi atau coba kembali.',
        ),
      );
    }
  }

  Future<void> getData(shiftId) async {
    setState(() {
      isLoadingData = true;
      inventoryIsEmpty = false;
      reportData = {};
    });
    try {
      dynamic response;
      if (numberPage == 1) {
        response = await reportService.getPenerimaan(shiftId);
      } else if (numberPage == 2) {
        response = await reportService.getPenjualan(shiftId);
      } else if (numberPage == 3) {
        response = await reportService.getPelanggan(shiftId);
      } else if (numberPage == 4) {
        response = await reportService.getBarang(shiftId);
      }
      setState(() {
        reportData = response.data['data'] ?? {};
        isLoadingData = false;
      });
    } catch (e) {
      setState(() {
        inventoryIsEmpty = true;
        isLoadingData = false;
      });
      debugPrint("Gagal ambil data laporan: $e");
      debugPrint("Gagal ambil data laporan: $e");
    }
  }

  void _onChangePage(int page) {
    setState(() => numberPage = page);
    if (shiftId != null) getData(shiftId);
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
                right: BorderSide(color: Colors.grey[200]!, width: 1.5),
              ),
            ),
            child: ListView(
              children: [
                _buildExpansionCategory(
                  title: "Laporan Outlet",
                  icon: Icons.storefront_rounded,
                  items: laporanOutlet,
                  initiallyExpanded: true,
                ),
              ],
            ),
          ),
        ),

        Expanded(
          flex: 2,
          child: isLoadingData
              ? Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: SkeletonLoader.detailLaporanSkeleton(),
                )
              : inventoryIsEmpty
              ? _buildEmptyState()
              : _buildPageContent(),
        ),
      ],
    );
  }

  Widget _buildPageContent() {
    switch (numberPage) {
      case 1:
        return _buildLaporanPenerimaan();
      case 2:
        return _buildLaporanPenjualanTipe();
      case 3:
        return _buildLaporanPelanggan();
      case 4:
        return _buildLaporanBarang();
      default:
        return const Center(child: Text('Coming Soon'));
    }
  }

  Widget _buildLaporanPenerimaan() {
    final double totalPenerimaan = (reportData['total_penerimaan'] ?? 0)
        .toDouble();
    final int jumlahTransaksi = reportData['jumlah_transaksi'] ?? 0;
    final List breakdown = reportData['breakdown'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // _buildPeriodFilter(),
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              _buildSummaryCard(
                title: 'Total Penerimaan',
                value: convertIDR(totalPenerimaan),
                icon: Icons.account_balance_wallet_rounded,
                color: Colors.amber[700]!,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                title: 'Jumlah Transaksi',
                value: '$jumlahTransaksi',
                icon: Icons.confirmation_number_rounded,
                color: Colors.blue[700]!,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            children: breakdown.map<Widget>((item) {
              final String name = item['pos_payment_method_name'] ?? '-';
              final int count = item['jumlah_transaksi'] ?? 0;
              final double amount = (item['total_amount'] ?? 0).toDouble();
              final IconData icon =
                  name.toLowerCase().contains('cash') ||
                      name.toLowerCase().contains('tunai')
                  ? Icons.money_rounded
                  : Icons.qr_code_scanner_rounded;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildBreakdownTile(
                  label: name,
                  subtitle: '$count Penerimaan',
                  amount: amount,
                  icon: icon,
                  onTap: () => _showTransactionDetailModal(
                    title: name,
                    type: numberPage,
                    subtitle: '$count Penerimaan',
                    id: item['pos_payment_method_id'],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── PAGE 2: PENJUALAN PER TIPE PENJUALAN ───────────────────────────────────

  Widget _buildLaporanPenjualanTipe() {
    final double totalPenjualan = (reportData['total_penjualan'] ?? 0)
        .toDouble();
    final int jumlahTransaksi = reportData['jumlah_transaksi'] ?? 0;
    final List breakdown = reportData['breakdown'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // _buildPeriodFilter(),
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              _buildSummaryCard(
                title: 'Total Penjualan',
                value: convertIDR(totalPenjualan),
                icon: Icons.point_of_sale_rounded,
                color: Colors.amber[700]!,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                title: 'Jumlah Transaksi',
                value: '$jumlahTransaksi',
                icon: Icons.confirmation_number_rounded,
                color: Colors.blue[700]!,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            children: breakdown.map<Widget>((item) {
              final String name = item['pos_order_method_name'] ?? '-';
              final int count = item['jumlah_transaksi'] ?? 0;
              final double amount = (item['total_amount'] ?? 0).toDouble();

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildBreakdownTile(
                  label: name,
                  subtitle: '$count Transaksi',
                  amount: amount,
                  icon: Icons.shopping_bag_rounded,
                  onTap: () {
                    _showTransactionDetailModal(
                      title: name,
                      type: numberPage,
                      subtitle: '$count Transaksi',
                      id: item['pos_order_method_id'],
                    );
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── PAGE 3: PENJUALAN BARANG PER PELANGGAN ─────────────────────────────────

  Widget _buildLaporanPelanggan() {
    final double totalPenjualan = (reportData['total_penjualan'] ?? 0)
        .toDouble();
    final int jumlahBarang = reportData['jumlah_barang'] ?? 0;
    final List breakdown = reportData['breakdown'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // _buildPeriodFilter(),
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              _buildSummaryCard(
                title: 'Total Penjualan',
                value: convertIDR(totalPenjualan),
                icon: Icons.point_of_sale_rounded,
                color: Colors.amber[700]!,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                title: 'Jumlah Barang',
                value: '$jumlahBarang',
                icon: Icons.inventory_2_rounded,
                color: Colors.green[700]!,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            children: breakdown.map<Widget>((item) {
              final String name = item['customers_name'] ?? '-';
              final int jumlahProduk = item['jumlah_produk'] ?? 0;
              final int count = item['jumlah_transaksi'] ?? 0;
              final double amount = (item['total_amount'] ?? 0).toDouble();

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildBreakdownTile(
                  label: name,
                  subtitle: '$jumlahProduk Produk · $count Transaksi',
                  amount: amount,
                  icon: Icons.person_rounded,
                  onTap: () => _showTransactionDetailModal(
                    title: name,
                    type: numberPage,
                    subtitle: '$count Transaksi',
                    id: item['customers_id'],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── PAGE 4: PENJUALAN PER BARANG ───────────────────────────────────────────

  Widget _buildLaporanBarang() {
    final double totalPenjualan = (reportData['total_penjualan'] ?? 0)
        .toDouble();
    final int jumlahBarang = reportData['jumlah_barang'] ?? 0;
    final List breakdown = reportData['breakdown'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // _buildPeriodFilter(),
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              _buildSummaryCard(
                title: 'Total Penjualan',
                value: convertIDR(totalPenjualan),
                icon: Icons.point_of_sale_rounded,
                color: Colors.amber[700]!,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                title: 'Jumlah Barang',
                value: '$jumlahBarang',
                icon: Icons.inventory_2_rounded,
                color: Colors.green[700]!,
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: ListView.separated(
              itemCount: breakdown.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = breakdown[index];
                final String name = item['pos_menus_name'] ?? '-';
                final int qty = item['total_qty'] ?? 0;
                final double amount = (item['total_amount'] ?? 0).toDouble();

                return _buildBreakdownTile(
                  label: name,
                  subtitle: '$qty Unit Terjual',
                  amount: amount,
                  icon: Icons.fastfood_rounded,
                  onTap: () => _showTransactionDetailModal(
                    title: name,
                    type: numberPage,
                    subtitle: '$qty Unit Terjual',
                    id: item['pos_menus_id'],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ─── SHARED WIDGETS ──────────────────────────────────────────────────────────

  // Widget _buildPeriodFilter() {
  //   return LayoutBuilder(
  //     builder: (context, constraints) {
  //       return Container(
  //         width: constraints.maxWidth,
  //         decoration: BoxDecoration(
  //           color: Colors.white,
  //           border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
  //         ),
  //         child: Theme(
  //           data: Theme.of(context).copyWith(
  //             colorScheme: Theme.of(
  //               context,
  //             ).colorScheme.copyWith(surface: Colors.white),
  //           ),
  //           child: DropdownMenu<String>(
  //             expandedInsets: EdgeInsets.zero,
  //             width: constraints.maxWidth,
  //             menuStyle: MenuStyle(
  //               backgroundColor: WidgetStateProperty.all(Colors.white),
  //               surfaceTintColor: WidgetStateProperty.all(Colors.white),
  //               shape: WidgetStateProperty.all(
  //                 RoundedRectangleBorder(
  //                   borderRadius: BorderRadius.only(
  //                     bottomLeft: Radius.circular(12),
  //                     bottomRight: Radius.circular(12),
  //                   ),
  //                 ),
  //               ),
  //             ),
  //             textStyle: const TextStyle(
  //               fontWeight: FontWeight.bold,
  //               fontSize: 14,
  //             ),
  //             hintText: 'Pilih Periode Laporan',
  //             leadingIcon: Icon(
  //               Icons.calendar_today_rounded,
  //               color: Colors.amber[900],
  //               size: 20,
  //             ),
  //             inputDecorationTheme: const InputDecorationTheme(
  //               border: InputBorder.none,
  //               filled: true,
  //               fillColor: Colors.white,
  //               contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
  //             ),
  //             dropdownMenuEntries: [
  //               _buildDateEntry('1h', 'Hari Ini', '28 November 2025'),
  //               _buildDateEntry('7h', '7 Hari', '21 - 28 Nov 2025'),
  //               _buildDateEntry('30h', '30 Hari', '29 Okt - 28 Nov 2025'),
  //             ],
  //             onSelected: (value) {},
  //           ),
  //         ),
  //       );
  //     },
  //   );
  // }

  /// Tile generik untuk semua breakdown
  Widget _buildBreakdownTile({
    required String label,
    required String subtitle,
    required double amount,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[50],
                child: Icon(icon, color: Colors.grey[700], size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    convertIDR(amount),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Tidak ada data',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Coba ubah periode atau periksa koneksi',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future _showTransactionDetailModal({
    required String title,
    required int type,
    required dynamic id,
    required String subtitle,
  }) {
    return showDialog(
      context: context,
      builder: (context) {
        Future<Response> fetchDetail() {
          final int parsedId = (id is int) ? id : (id as num).toInt();
          switch (type) {
            case 1:
              return reportService.getDetailPenerimaan(shiftId!, parsedId);
            case 2:
              return reportService.getDetailPenjualan(shiftId!, parsedId);
            case 3:
              return reportService.getDetailPelanggan(shiftId!, parsedId);
            case 4:
              return reportService.getDetailBarang(shiftId!, parsedId);
            default:
              throw Exception("Tipe tidak valid");
          }
        }

        debugPrint('reportData: $reportData');

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 600.0,
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                _buildModalHeader(title, subtitle),
                Expanded(
                  child: FutureBuilder(
                    future: fetchDetail(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.orange,
                          ),
                        );
                      }
                      if (snapshot.hasError ||
                          snapshot.data?.data['data'] == null) {
                        return const Center(
                          child: Text("Gagal memuat data atau data kosong"),
                        );
                      }

                      final List transactions = snapshot.data!.data['data'];

                      return ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: transactions.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final item = transactions[index];
                          String subtitleInfo = item['users_name'] ?? '-';
                          if (item['quantity'] != null)
                            subtitleInfo += " • ${item['quantity']} Qty";
                          if (item['jumlah_produk'] != null)
                            subtitleInfo +=
                                " • ${item['jumlah_produk']} Produk";
                          return InkWell(
                            onTap: () {},
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                                vertical: 20.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['document_number'] ?? '-',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16.0,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitleInfo,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        formatDateTime(item['created_at']),
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        convertIDR(
                                          (item['total_amount'] ?? 0)
                                              .toDouble(),
                                        ),
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModalHeader(String title, dynamic subtitle) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18.0,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 28.0),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // --- HELPER WIDGETS ---

  DropdownMenuEntry<String> _buildDateEntry(
    String value,
    String badge,
    String label,
  ) {
    return DropdownMenuEntry<String>(
      value: value,
      label: label,
      // Memberikan style teks label agar lebih clean
      labelWidget: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      leadingIcon: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          // Gunakan warna background yang kontras dengan teks badge
          color: Colors.amber[50]?.withOpacity(0.8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber[200]!, width: 1),
        ),
        child: Text(
          badge,
          style: TextStyle(
            color: Colors.amber[900],
            fontWeight: FontWeight.bold,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[300]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodTile({
    required String label,
    required int count,
    required double amount,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[50],
                child: Icon(icon, color: Colors.grey[700], size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$count Penerimaan',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    convertIDR(amount),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future _showDetailModal() {
    // Simulasi data (nanti bisa diganti dengan data dari API/Provider)
    final List<Map<String, dynamic>> transactions = List.generate(
      10,
      (index) => {
        'id': 'TRX-82934$index',
        'status': 'Diterima Kasir',
        'date': '10 Okt 2026, 13:34',
        'amount': 20000.0,
      },
    );

    return showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: Colors.white,
          clipBehavior:
              Clip.antiAlias, // Biar header tidak nabrak border radius
          child: SizedBox(
            width: 600.0,
            height:
                MediaQuery.of(context).size.height * 0.7, // Batasi tinggi modal
            child: Column(
              children: [
                // --- HEADER ---
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 20.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pembayaran Tunai',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20.0,
                            ),
                          ),
                          Text(
                            '${transactions.length} Transaksi Penerimaan',
                            style: TextStyle(
                              fontSize: 14.0,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.search, size: 28.0),
                        onPressed: () {
                          // Logika search di sini
                        },
                      ),
                    ],
                  ),
                ),

                // --- LIST TRANSAKSI ---
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: transactions.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final item = transactions[index];
                      return InkWell(
                        onTap: () {
                          // Aksi saat item diklik
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 20.0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['id'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16.0,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['status'],
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    item['date'],
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    convertIDR(item['amount']),
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16.0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpansionCategory({
    required String title,
    required IconData icon,
    required List items,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      // Menghilangkan garis divider dan splash highlight bawaan yang kaku
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: Colors.amber[900]),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
            letterSpacing: 0.3,
          ),
        ),
        // Atur padding agar sejajar dengan desain sidebar modern
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
        children: items.map<Widget>((e) {
          bool isActive = numberPage == e['page'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4), // Jarak antar item
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isActive ? Colors.amber[50] : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isActive ? Colors.orange : Colors.transparent,
                  width: isActive ? 2 : 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _onChangePage(e['page']),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12.0,
                      horizontal: 16.0,
                    ),
                    child: Row(
                      children: [
                        Text(
                          e['name'],
                          style: TextStyle(
                            fontSize: isActive ? 15 : 13,
                            color: isActive
                                ? Colors.amber[800]
                                : Colors.grey[600],
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.w500,
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
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
