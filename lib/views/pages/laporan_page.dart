import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_error.dart';

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
        Expanded(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.black26)),
            ),
            child: ListView(
              children: [
                ExpansionTile(
                  initiallyExpanded: true,
                  title: Text("Laporan Outlet"),
                  backgroundColor: Colors.grey[200],
                  children: laporanOutlet.map((e) {
                    return Material(
                      color: Colors.white,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            numberPage = e['page'];
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.black54),
                            ),
                          ),
                          alignment: AlignmentGeometry.centerLeft,
                          padding: EdgeInsets.symmetric(
                            vertical: 20.0,
                            horizontal: 10.0,
                          ),
                          child: Text(e['name']),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                ExpansionTile(
                  title: Text("Laporan Karyawan"),
                  backgroundColor: Colors.grey[200],
                  children: laporanKaryawan.map((e) {
                    return Material(
                      color: Colors.white,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            numberPage = e['page'];
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.black54),
                            ),
                          ),
                          alignment: AlignmentGeometry.centerLeft,
                          padding: EdgeInsets.symmetric(
                            vertical: 20.0,
                            horizontal: 10.0,
                          ),
                          child: Text(e['name']),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                ExpansionTile(
                  title: Text("Laporan Taget Penjualan"),
                  backgroundColor: Colors.grey[200],
                  children: laporanTarget.map((e) {
                    return Material(
                      color: Colors.white,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            numberPage = e['page'];
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.black54),
                            ),
                          ),
                          alignment: AlignmentGeometry.centerLeft,
                          padding: EdgeInsets.symmetric(
                            vertical: 20.0,
                            horizontal: 10.0,
                          ),
                          child: Text(e['name']),
                        ),
                      ),
                    );
                  }).toList(),
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

  Widget penerimaanPenjualan() {
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
                        color: Colors.grey[100],
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.all(Radius.circular(10.0)),
                      ),
                      child: Column(
                        children: [
                          Text('Total Penerimaan'),
                          Text(
                            convertIDR(76000),
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
                        color: Colors.grey[100],
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.all(Radius.circular(10.0)),
                      ),
                      child: Column(
                        children: [
                          Text('Jumlah Penerimaan'),
                          Text(
                            "20",
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
                  showDialog(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: Colors.white,
                        child: modalLIst(),
                      );
                    },
                  );
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
                            'Tunai',
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
                            convertIDR(7000028),
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
                            'Qris',
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
                            convertIDR(7000028),
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
                        color: Colors.grey[100],
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
                        color: Colors.grey[100],
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
                  showDialog(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: Colors.white,
                        child: modalLIst(),
                      );
                    },
                  );
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
                        color: Colors.grey[100],
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
                        color: Colors.grey[100],
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
                  showDialog(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: Colors.white,
                        child: modalLIst(),
                      );
                    },
                  );
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

  Widget modalLIst() {
    return SizedBox(
      width: 600.0,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.black87)),
            ),
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pembayaran Tunai',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20.0,
                      ),
                    ),
                    Text(
                      '10 Transaksi Penerimaan',
                      style: TextStyle(fontSize: 15.0),
                    ),
                  ],
                ),
                Icon(Icons.search, size: 30.0),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      padding: EdgeInsets.all(20.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'jpashjdgsdfh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 20.0,
                                ),
                              ),
                              Text('Diterima Kasir'),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('10 Okt 2025, 13:34'),
                              Text(
                                convertIDR(20000),
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
