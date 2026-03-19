import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/convert.dart';

List<Map<String, dynamic>> laporanOutlet = [
  {'name': 'Penerimaan Penjualan', 'page': 1},
  {'name': 'Penjualan per Tipe Penjualan', 'page': 2},
  {'name': 'Penjualan Barang per Pelanggan', 'page': 3},
  {'name': 'Penjualan per Barang ', 'page': 4},
  {'name': 'Return Penjualan per Barang', 'page': 5},
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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Expanded(
        //   flex: 1,
        //   child: Container(
        //     decoration: BoxDecoration(
        //       border: Border(right: BorderSide(color: Colors.black26)),
        //     ),
        //     child: ListView(
        //       children: [
        //         ExpansionTile(
        //           initiallyExpanded: true,
        //           title: Text("Laporan Outlet"),
        //           backgroundColor: Colors.grey[200],
        //           children: laporanOutlet.map((e) {
        //             return Material(
        //               color: Colors.white,
        //               child: InkWell(
        //                 onTap: () {
        //                   setState(() {
        //                     numberPage = e['page'];
        //                   });
        //                 },
        //                 child: Container(
        //                   decoration: BoxDecoration(
        //                     border: Border(
        //                       top: BorderSide(color: Colors.black54),
        //                     ),
        //                   ),
        //                   alignment: AlignmentGeometry.centerLeft,
        //                   padding: EdgeInsets.symmetric(
        //                     vertical: 20.0,
        //                     horizontal: 10.0,
        //                   ),
        //                   child: Text(e['name']),
        //                 ),
        //               ),
        //             );
        //           }).toList(),
        //         ),
        //         ExpansionTile(
        //           title: Text("Laporan Karyawan"),
        //           backgroundColor: Colors.grey[200],
        //           children: laporanKaryawan.map((e) {
        //             return Material(
        //               color: Colors.white,
        //               child: InkWell(
        //                 onTap: () {
        //                   setState(() {
        //                     numberPage = e['page'];
        //                   });
        //                 },
        //                 child: Container(
        //                   decoration: BoxDecoration(
        //                     border: Border(
        //                       top: BorderSide(color: Colors.black54),
        //                     ),
        //                   ),
        //                   alignment: AlignmentGeometry.centerLeft,
        //                   padding: EdgeInsets.symmetric(
        //                     vertical: 20.0,
        //                     horizontal: 10.0,
        //                   ),
        //                   child: Text(e['name']),
        //                 ),
        //               ),
        //             );
        //           }).toList(),
        //         ),
        //         ExpansionTile(
        //           title: Text("Laporan Taget Penjualan"),
        //           backgroundColor: Colors.grey[200],
        //           children: laporanTarget.map((e) {
        //             return Material(
        //               color: Colors.white,
        //               child: InkWell(
        //                 onTap: () {
        //                   setState(() {
        //                     numberPage = e['page'];
        //                   });
        //                 },
        //                 child: Container(
        //                   decoration: BoxDecoration(
        //                     border: Border(
        //                       top: BorderSide(color: Colors.black54),
        //                     ),
        //                   ),
        //                   alignment: AlignmentGeometry.centerLeft,
        //                   padding: EdgeInsets.symmetric(
        //                     vertical: 20.0,
        //                     horizontal: 10.0,
        //                   ),
        //                   child: Text(e['name']),
        //                 ),
        //               ),
        //             );
        //           }).toList(),
        //         ),
        //       ],
        //     ),
        //   ),
        // ),
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
                _buildExpansionCategory(
                  title: "Laporan Karyawan",
                  icon: Icons.people_alt_rounded,
                  items: laporanKaryawan,
                ),
                _buildExpansionCategory(
                  title: "Target Penjualan",
                  icon: Icons.track_changes_rounded,
                  items: laporanTarget,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Container(
            child: numberPage == 1
                ? penerimaanPenjualan()
                : numberPage == 2
                ? penjualanperTipePenjualan()
                : numberPage == 3
                ? penjualanbarangPerPelanggan()
                : Center(child: Text('Comming Soon')),
          ),
        ),
      ],
    );
  }

  // Widget penerimaanPenjualan() {
  //   return Column(
  //     children: [
  //       LayoutBuilder(
  //         builder: (context, constraints) {
  //           return Container(
  //             width: constraints.maxWidth,
  //             decoration: BoxDecoration(
  //               border: Border(
  //                 bottom: BorderSide(color: Colors.black26),
  //                 top: BorderSide(color: Colors.black26),
  //               ),
  //             ),
  //             child: Theme(
  //               data: Theme.of(context).copyWith(
  //                 colorScheme: Theme.of(context).colorScheme.copyWith(
  //                   surface: Colors.white,
  //                   surfaceContainer: Colors.white,
  //                   onSurface: Colors.black,
  //                 ),
  //               ),
  //               child: DropdownMenu<String>(
  //                 width: constraints.maxWidth,
  //                 textStyle: TextStyle(fontWeight: FontWeight.bold),
  //                 hintText: 'Pilih Tanggal Laporan',
  //                 leadingIcon: Icon(Icons.calendar_month),
  //                 // controller: pelangganController,
  //                 enableFilter: true,
  //                 enableSearch: true,
  //                 inputDecorationTheme: const InputDecorationTheme(
  //                   border: OutlineInputBorder(
  //                     borderRadius: BorderRadius.zero,
  //                     borderSide: BorderSide.none,
  //                   ),
  //                   filled: true,
  //                   fillColor: Colors.white,
  //                   contentPadding: EdgeInsets.symmetric(horizontal: 10.0),
  //                 ),
  //                 dropdownMenuEntries: [
  //                   DropdownMenuEntry<String>(
  //                     leadingIcon: Container(
  //                       padding: EdgeInsets.all(7),
  //                       decoration: BoxDecoration(
  //                         borderRadius: BorderRadius.all(Radius.circular(13.0)),
  //                         color: Colors.grey[300],
  //                       ),
  //                       child: Text(
  //                         'Hari Ini',
  //                         style: TextStyle(fontWeight: FontWeight.bold),
  //                       ),
  //                     ),
  //                     value: '1h',
  //                     label: '28 November 2025',
  //                   ),
  //                   DropdownMenuEntry<String>(
  //                     leadingIcon: Container(
  //                       padding: EdgeInsets.all(7),
  //                       decoration: BoxDecoration(
  //                         borderRadius: BorderRadius.all(Radius.circular(13.0)),
  //                         color: Colors.grey[300],
  //                       ),
  //                       child: Text(
  //                         '7 Hari',
  //                         style: TextStyle(fontWeight: FontWeight.bold),
  //                       ),
  //                     ),
  //                     value: '7h',
  //                     label: '21 November 2025 - 28 November 2025',
  //                   ),
  //                   DropdownMenuEntry<String>(
  //                     leadingIcon: Container(
  //                       padding: EdgeInsets.all(7),
  //                       decoration: BoxDecoration(
  //                         borderRadius: BorderRadius.all(Radius.circular(13.0)),
  //                         color: Colors.grey[300],
  //                       ),
  //                       child: Text(
  //                         '30 Hari',
  //                         style: TextStyle(fontWeight: FontWeight.bold),
  //                       ),
  //                     ),
  //                     value: '30h',
  //                     label: '29 Oktober 2025 - 28 November 2025',
  //                   ),
  //                 ],
  //                 onSelected: (value) {
  //                   // setState(() {
  //                   //   category = value;
  //                   // });
  //                 },
  //               ),
  //             ),
  //           );
  //         },
  //       ),
  //       Container(
  //         padding: EdgeInsets.all(20),
  //         child: Column(
  //           children: [
  //             Row(
  //               spacing: 20.0,
  //               children: [
  //                 Expanded(
  //                   child: Container(
  //                     padding: EdgeInsets.all(20.0),
  //                     decoration: BoxDecoration(
  //                       color: Colors.grey[300],
  //                       border: Border.all(color: Colors.black26),
  //                       borderRadius: BorderRadius.all(Radius.circular(10.0)),
  //                     ),
  //                     child: Column(
  //                       children: [
  //                         Text('Total Penerimaan'),
  //                         Text(
  //                           convertIDR(76000),
  //                           style: TextStyle(
  //                             fontSize: 21.0,
  //                             fontWeight: FontWeight.bold,
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                   ),
  //                 ),
  //                 Expanded(
  //                   child: Container(
  //                     padding: EdgeInsets.all(20.0),
  //                     decoration: BoxDecoration(
  //                       color: Colors.grey[300],
  //                       border: Border.all(color: Colors.black26),
  //                       borderRadius: BorderRadius.all(Radius.circular(10.0)),
  //                     ),
  //                     child: Column(
  //                       children: [
  //                         Text('Jumlah Penerimaan'),
  //                         Text(
  //                           "20",
  //                           style: TextStyle(
  //                             fontSize: 21.0,
  //                             fontWeight: FontWeight.bold,
  //                           ),
  //                         ),
  //                       ],
  //                     ),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ],
  //         ),
  //       ),
  //       Padding(
  //         padding: const EdgeInsets.symmetric(horizontal: 20.0),
  //         child: Column(
  //           spacing: 20.0,
  //           children: [
  //             InkWell(
  //               onTap: () {
  //                 showDialog(
  //                   context: context,
  //                   builder: (context) {
  //                     return Dialog(
  //                       shape: RoundedRectangleBorder(
  //                         borderRadius: BorderRadius.circular(16),
  //                       ),
  //                       backgroundColor: Colors.white,
  //                       child: modalLIst(),
  //                     );
  //                   },
  //                 );
  //               },
  //               borderRadius: BorderRadius.all(Radius.circular(10.0)),
  //               child: Container(
  //                 padding: EdgeInsets.all(20.0),
  //                 decoration: BoxDecoration(
  //                   border: Border.all(color: Colors.black26),
  //                   borderRadius: BorderRadius.all(Radius.circular(10.0)),
  //                 ),
  //                 child: Row(
  //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //                   children: [
  //                     Column(
  //                       crossAxisAlignment: CrossAxisAlignment.start,
  //                       children: [
  //                         Text(
  //                           'Tunai',
  //                           style: TextStyle(
  //                             fontSize: 16,
  //                             fontWeight: FontWeight.bold,
  //                           ),
  //                         ),
  //                         Text('10 Penerimaan'),
  //                       ],
  //                     ),
  //                     Row(
  //                       spacing: 10.0,
  //                       children: [
  //                         Text(
  //                           convertIDR(7000028),
  //                           style: TextStyle(
  //                             fontSize: 18,
  //                             fontWeight: FontWeight.bold,
  //                           ),
  //                         ),
  //                         Icon(Icons.chevron_right),
  //                       ],
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ),
  //             InkWell(
  //               onTap: () async {
  //               },
  //               borderRadius: BorderRadius.all(Radius.circular(10.0)),
  //               child: Container(
  //                 padding: EdgeInsets.all(20.0),
  //                 decoration: BoxDecoration(
  //                   border: Border.all(color: Colors.black26),
  //                   borderRadius: BorderRadius.all(Radius.circular(10.0)),
  //                 ),
  //                 child: Row(
  //                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //                   children: [
  //                     Column(
  //                       crossAxisAlignment: CrossAxisAlignment.start,
  //                       children: [
  //                         Text(
  //                           'Qris',
  //                           style: TextStyle(
  //                             fontSize: 16,
  //                             fontWeight: FontWeight.bold,
  //                           ),
  //                         ),
  //                         Text('10 Penerimaan'),
  //                       ],
  //                     ),
  //                     Row(
  //                       spacing: 10.0,
  //                       children: [
  //                         Text(
  //                           convertIDR(7000028),
  //                           style: TextStyle(
  //                             fontSize: 18,
  //                             fontWeight: FontWeight.bold,
  //                           ),
  //                         ),
  //                         Icon(Icons.chevron_right),
  //                       ],
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ],
  //   );
  // }

  Widget penerimaanPenjualan() {
    return Column(
      children: [
        // --- FILTER TANGGAL (DROPDOWN) ---
        LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              width: constraints.maxWidth,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(
                    context,
                  ).colorScheme.copyWith(surface: Colors.white),
                ),
                child: DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  width: constraints.maxWidth,
                  menuStyle: MenuStyle(
                    backgroundColor: WidgetStateProperty.all(Colors.white),
                    surfaceTintColor: WidgetStateProperty.all(
                      Colors.white,
                    ), // Hapus tint ungu M3
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  hintText: 'Pilih Periode Laporan',
                  leadingIcon: Icon(
                    Icons.calendar_today_rounded,
                    color: Colors.amber[900],
                    size: 20,
                  ),
                  inputDecorationTheme: const InputDecorationTheme(
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
                  ),
                  dropdownMenuEntries: [
                    _buildDateEntry('1h', 'Hari Ini', '28 November 2025'),
                    _buildDateEntry('7h', '7 Hari', '21 - 28 Nov 2025'),
                    _buildDateEntry('30h', '30 Hari', '29 Okt - 28 Nov 2025'),
                  ],
                  onSelected: (value) {},
                ),
              ),
            );
          },
        ),

        // --- SUMMARY CARDS (TOTAL & JUMLAH) ---
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              _buildSummaryCard(
                title: 'Total Penerimaan',
                value: convertIDR(76000),
                icon: Icons.account_balance_wallet_rounded,
                color: Colors.amber[700]!,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                title: 'Jumlah Transaksi',
                value: '20',
                icon: Icons.confirmation_number_rounded,
                color: Colors.blue[700]!,
              ),
            ],
          ),
        ),

        // --- DAFTAR METODE PEMBAYARAN ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            children: [
              _buildPaymentMethodTile(
                label: 'Tunai',
                count: 10,
                amount: 7000028,
                icon: Icons.money_rounded,
                onTap: () => _showDetailModal(),
              ),
              const SizedBox(height: 12),
              _buildPaymentMethodTile(
                label: 'QRIS',
                count: 10,
                amount: 7000028,
                icon: Icons.qr_code_scanner_rounded,
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
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

  Widget penjualanperTipePenjualan() {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              width: constraints.maxWidth,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.black26),
                  top: BorderSide(color: Colors.black26),
                ),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    surface: Colors.white,
                    surfaceContainer: Colors.white,
                    onSurface: Colors.black,
                  ),
                ),
                child: DropdownMenu<String>(
                  width: constraints.maxWidth,
                  textStyle: TextStyle(fontWeight: FontWeight.bold),
                  hintText: 'Pilih Tanggal Laporan',
                  leadingIcon: Icon(Icons.calendar_month),
                  // controller: pelangganController,
                  enableFilter: true,
                  enableSearch: true,
                  inputDecorationTheme: const InputDecorationTheme(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10.0),
                  ),
                  dropdownMenuEntries: [
                    DropdownMenuEntry<String>(
                      leadingIcon: Container(
                        padding: EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(13.0)),
                          color: Colors.grey[300],
                        ),
                        child: Text(
                          'Hari Ini',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      value: '1h',
                      label: '28 November 2025',
                    ),
                    DropdownMenuEntry<String>(
                      leadingIcon: Container(
                        padding: EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(13.0)),
                          color: Colors.grey[300],
                        ),
                        child: Text(
                          '7 Hari',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      value: '7h',
                      label: '21 November 2025 - 28 November 2025',
                    ),
                    DropdownMenuEntry<String>(
                      leadingIcon: Container(
                        padding: EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(13.0)),
                          color: Colors.grey[300],
                        ),
                        child: Text(
                          '30 Hari',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      value: '30h',
                      label: '29 Oktober 2025 - 28 November 2025',
                    ),
                  ],
                  onSelected: (value) {
                    // setState(() {
                    //   category = value;
                    // });
                  },
                ),
              ),
            );
          },
        ),
        Container(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                spacing: 20.0,
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.all(Radius.circular(10.0)),
                      ),
                      child: Column(
                        children: [
                          Text('Total Panjualan'),
                          Text(
                            convertIDR(2206000),
                            style: TextStyle(
                              fontSize: 21.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.all(Radius.circular(10.0)),
                      ),
                      child: Column(
                        children: [
                          Text('Jumlah Transaksi'),
                          Text(
                            '40',
                            style: TextStyle(
                              fontSize: 21.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            spacing: 20.0,
            children: [
              InkWell(
                onTap: () {
                  _showDetailModal();
                },
                borderRadius: BorderRadius.all(Radius.circular(10.0)),
                child: Container(
                  padding: EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.all(Radius.circular(10.0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Takeaway',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('10 Penerimaan'),
                        ],
                      ),
                      Row(
                        spacing: 10.0,
                        children: [
                          Text(
                            convertIDR(1020028),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Icon(Icons.chevron_right),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () {},
                borderRadius: BorderRadius.all(Radius.circular(10.0)),
                child: Container(
                  padding: EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.all(Radius.circular(10.0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delivery',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('10 Penerimaan'),
                        ],
                      ),
                      Row(
                        spacing: 10.0,
                        children: [
                          Text(
                            convertIDR(1900028),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Icon(Icons.chevron_right),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget penjualanbarangPerPelanggan() {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              width: constraints.maxWidth,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.black26),
                  top: BorderSide(color: Colors.black26),
                ),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    surface: Colors.white,
                    surfaceContainer: Colors.white,
                    onSurface: Colors.black,
                  ),
                ),
                child: DropdownMenu<String>(
                  width: constraints.maxWidth,
                  textStyle: TextStyle(fontWeight: FontWeight.bold),
                  hintText: 'Pilih Tanggal Laporan',
                  leadingIcon: Icon(Icons.calendar_month),
                  // controller: pelangganController,
                  enableFilter: true,
                  enableSearch: true,
                  inputDecorationTheme: const InputDecorationTheme(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10.0),
                  ),
                  dropdownMenuEntries: [
                    DropdownMenuEntry<String>(
                      leadingIcon: Container(
                        padding: EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(13.0)),
                          color: Colors.grey[300],
                        ),
                        child: Text(
                          'Hari Ini',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      value: '1h',
                      label: '28 November 2025',
                    ),
                    DropdownMenuEntry<String>(
                      leadingIcon: Container(
                        padding: EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(13.0)),
                          color: Colors.grey[300],
                        ),
                        child: Text(
                          '7 Hari',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      value: '7h',
                      label: '21 November 2025 - 28 November 2025',
                    ),
                    DropdownMenuEntry<String>(
                      leadingIcon: Container(
                        padding: EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(13.0)),
                          color: Colors.grey[300],
                        ),
                        child: Text(
                          '30 Hari',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      value: '30h',
                      label: '29 Oktober 2025 - 28 November 2025',
                    ),
                  ],
                  onSelected: (value) {
                    // setState(() {
                    //   category = value;
                    // });
                  },
                ),
              ),
            );
          },
        ),
        Container(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                spacing: 20.0,
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.all(Radius.circular(10.0)),
                      ),
                      child: Column(
                        children: [
                          Text('Total Penjualan'),
                          Text(
                            convertIDR(2000182),
                            style: TextStyle(
                              fontSize: 21.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(20.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.all(Radius.circular(10.0)),
                      ),
                      child: Column(
                        children: [
                          Text('Jumlah Barang'),
                          Text(
                            "140",
                            style: TextStyle(
                              fontSize: 21.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            spacing: 20.0,
            children: [
              InkWell(
                onTap: () {
                  _showDetailModal();
                },
                borderRadius: BorderRadius.all(Radius.circular(10.0)),
                child: Container(
                  padding: EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.all(Radius.circular(10.0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pelanggan Umum',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text('140 Produk Terjual'),
                        ],
                      ),
                      Row(
                        spacing: 10.0,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                convertIDR(7000028),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text('40 Transkasi'),
                            ],
                          ),
                          Icon(Icons.chevron_right),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
                  onTap: () => setState(() => numberPage = e['page']),
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
