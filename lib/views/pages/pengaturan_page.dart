import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';
import 'package:pos_panglima_app/views/widgets/endsift_modal.dart';

class PengaturanPage extends StatefulWidget {
  const PengaturanPage({super.key});

  @override
  State<PengaturanPage> createState() => _PengaturanPageState();
}

class _PengaturanPageState extends State<PengaturanPage> {
  int numberPage = 1;
  List<BluetoothDevice> devices = [];
  BluetoothDevice? connectedPrinter;
  bool isScanning = false;
  final apiClient = ApiClient();
  late final AuthService authService;
  Map<String, dynamic>? profile;
  bool isLoadingProfile = true;

  final List<String> _allowedKeywords = [
    'rpp',
    // tambahkan keyword lain di sini sewaktu-waktu
    // 'epson',
    // 'xprinter',
  ];

  @override
  void initState() {
    super.initState();
    authService = AuthService(apiClient.dio);
    getProfile();

    BluetoothPrinterService.bluetooth.onStateChanged().listen((state) {
      setState(() {
        connectedPrinter = BluetoothPrinterService.connectedPrinter;
      });
    });

    scanDevices().then((_) {
      BluetoothPrinterService.loadLastPrinter();
    });
  }

  Future<void> scanDevices() async {
    setState(() => isScanning = true);
    final foundDevices = await BluetoothPrinterService.scanPrinters();
    setState(() {
      isScanning = false;
      devices = foundDevices;
    });
  }

  Future<void> connectPrinter(BluetoothDevice device) async {
    bool ok = await BluetoothPrinterService.connect(device);

    if (!mounted) return;

    if (ok) {
      setState(() {
        connectedPrinter = device;
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? "Terhubung ke ${device.name}" : "Gagal")),
    );
  }

  Future<String> getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      return android.model;
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      return ios.name;
    }

    return "Unknown Device";
  }

  Future<String> getDeviceIP() async {
    final info = NetworkInfo();

    final wifiIP = await info.getWifiIP();

    return wifiIP ?? "Tidak terhubung ke WiFi";
  }

  Future<void> getProfile() async {
    try {
      final response = await authService.getProfile();

      debugPrint("PROFILE RESPONSE: ${response.data}");

      if (!mounted) return;
      setState(() {
        profile = response.data['data'];
        isLoadingProfile = false;
      });
    } catch (e) {
      isLoadingProfile = false;
      debugPrint("Gagal ambil profile: $e");
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
        //     child: Column(
        //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
        //       children: [
        //         Column(
        //           children: [
        //             InkWell(
        //               onTap: () {
        //                 setState(() {
        //                   numberPage = 1;
        //                 });
        //               },
        //               child: Container(
        //                 color: numberPage == 1
        //                     ? Colors.amber[100]
        //                     : Colors.white,
        //                 padding: EdgeInsets.all(14.0),
        //                 child: Row(
        //                   spacing: 16.0,
        //                   children: [
        //                     Icon(
        //                       Icons.person,
        //                       size: 26.0,
        //                       color: Colors.grey[800],
        //                     ),
        //                     Text(
        //                       'Profil Pengguna',
        //                       style: TextStyle(
        //                         fontSize: 16.0,
        //                         fontWeight: FontWeight.w500,
        //                       ),
        //                     ),
        //                   ],
        //                 ),
        //               ),
        //             ),
        //             InkWell(
        //               onTap: () {
        //                 setState(() {
        //                   numberPage = 2;
        //                 });
        //               },
        //               child: Container(
        //                 color: numberPage == 2
        //                     ? Colors.amber[100]
        //                     : Colors.white,
        //                 padding: EdgeInsets.all(14.0),
        //                 child: Row(
        //                   spacing: 16.0,
        //                   children: [
        //                     Icon(
        //                       Icons.print,
        //                       size: 26.0,
        //                       color: Colors.grey[800],
        //                     ),
        //                     Text(
        //                       'Printer',
        //                       style: TextStyle(
        //                         fontSize: 16.0,
        //                         fontWeight: FontWeight.w500,
        //                       ),
        //                     ),
        //                   ],
        //                 ),
        //               ),
        //             ),
        //           ],
        //         ),
        //         Text('V.1.0.0'),
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
                      // Menu 1
                      _buildMenuItem(
                        index: 1,
                        icon: Icons.person_outline_rounded,
                        label: 'Profil Pengguna',
                      ),

                      // Menu 2
                      _buildMenuItem(
                        index: 2,
                        icon: Icons.print_outlined,
                        label: 'Printer',
                      ),
                    ],
                  ),
                ),

                // BAGIAN BAWAH: VERSIONING
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
        Expanded(
          flex: 2,
          child: numberPage == 1
              ? profil()
              : numberPage == 2
              ? printer()
              : Center(child: Text('Comming Soon')),
        ),
      ],
    );
  }

  Widget profil() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- SECTION 1: INFORMASI PENGGUNA ---
                _buildSectionHeader('Informasi Pengguna'),
                _buildProfileTile(
                  icon: Icons.storefront_outlined,
                  title: 'Informasi Outlet',
                  subtitle: profile?['name'] ?? '-',
                ),
                _buildProfileTile(
                  icon: Icons.badge_outlined,
                  title: 'Departemen',
                  subtitle: profile?['department'] ?? '-',
                ),

                SizedBox(height: 20), // Memberi jarak antar section
                // --- SECTION 2: INFORMASI PERANGKAT ---
                _buildSectionHeader('Informasi Perangkat'),
                _buildProfileTile(
                  icon: Icons.important_devices_outlined,
                  title: 'Nama Perangkat',
                  subtitle: FutureBuilder<String>(
                    future: getDeviceName(),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? "Memuat...",
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      );
                    },
                  ),
                ),
                _buildProfileTile(
                  icon: Icons.lan_outlined,
                  title: 'Alamat IP',
                  subtitle: FutureBuilder<String>(
                    future: getDeviceIP(),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? "Memuat...",
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      );
                    },
                  ),
                ),
                _buildProfileTile(
                  icon: Icons.link,
                  title: 'Outlet Terhubung',
                  subtitle: 'Roti Gembung Panglima',
                ),
              ],
            ),
          ),
        ),

        // --- TOMBOL KELUAR ---
        Container(
          padding: EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[200]!)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (BuildContext context) => EndsiftModal(),
                );
              },
              icon: Icon(Icons.logout, color: Colors.red[700], size: 20),
              label: Text(
                'Keluar Perangkat',
                style: TextStyle(
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red[100]!),
                backgroundColor: Colors.red[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Helper untuk Header Section agar konsisten
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12.0,
          fontWeight: FontWeight.bold,
          color: Colors.amber[900],
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  // Helper untuk Tile agar lebih cantik
  Widget _buildProfileTile({
    required IconData icon,
    required String title,
    required dynamic subtitle,
  }) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.grey[700], size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: subtitle is Widget
          ? subtitle
          : Text(
              subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
      contentPadding: EdgeInsets.symmetric(horizontal: 20),
    );
  }

  // Widget printer() {
  //   return Column(
  //     children: [
  //       Container(
  //         color: Colors.black12,
  //         padding: EdgeInsets.all(16.0),
  //         child: Row(
  //           mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //           children: [
  //             Text(
  //               'Daftar Printer',
  //               style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
  //             ),
  //             Row(
  //               spacing: 10.0,
  //               children: [Icon(Icons.print), Icon(Icons.more_vert)],
  //             ),
  //           ],
  //         ),
  //       ),
  //       Expanded(
  //         child: devices.isEmpty
  //             ? Center(child: Text("Tidak ada printer ditemukan"))
  //             : ListView.builder(
  //                 itemCount: devices.length,
  //                 itemBuilder: (context, i) {
  //                   final d = devices[i];
  //                   return ListTile(
  //                     leading: Icon(Icons.bluetooth),
  //                     title: Text(d.name ?? "Unknown"),
  //                     subtitle: Text(d.address ?? "-"),
  //                     trailing: Icon(Icons.chevron_right),
  //                     onTap: () => connectPrinter(d),
  //                   );
  //                 },
  //               ),
  //       ),
  //       Container(
  //         width: double.infinity,
  //         padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
  //         child: ElevatedButton(
  //           onPressed: () {
  //             setState(() {
  //               scanDevices();
  //             });
  //           },
  //           style: IconButton.styleFrom(
  //             backgroundColor: isScanning ? Colors.grey[300] : Colors.amber,
  //             shape: RoundedRectangleBorder(
  //               borderRadius: BorderRadius.circular(6),
  //             ),
  //           ),
  //           child: Text(
  //             'Scanning Printer',
  //             style: TextStyle(color: Colors.black87),
  //           ),
  //         ),
  //       ),
  //     ],
  //   );
  // }

  Widget printer() {
    return Column(
      children: [
        // --- HEADER ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daftar Printer',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Pilih perangkat untuk mencetak struk',
                    style: TextStyle(fontSize: 12.0, color: Colors.grey[500]),
                  ),
                ],
              ),
              // Tombol refresh/stop scanning yang lebih kecil di pojok
              if (isScanning)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.amber,
                  ),
                )
              else
                Icon(Icons.print_rounded, color: Colors.amber[800]),
            ],
          ),
        ),

        // --- LIST PERANGKAT ---
        Expanded(
          child: devices.isEmpty
              ? _buildEmptyState()
              : Builder(
                  builder: (context) {
                    final filteredDevices = devices.where((d) {
                      final name = (d.name ?? '').toLowerCase();
                      return _allowedKeywords.any(
                        (keyword) => name.contains(keyword.toLowerCase()),
                      );
                    }).toList();

                    return filteredDevices.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: filteredDevices.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final d = filteredDevices[i];
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.02),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.amber[50],
                                    child: Icon(
                                      Icons.bluetooth,
                                      color: Colors.amber[800],
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    d.name ?? "Perangkat Tidak Dikenal",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    d.address ?? "-",
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Icon(
                                    Icons.chevron_right,
                                    color: Colors.grey[400],
                                  ),
                                  onTap: () => connectPrinter(d),
                                ),
                              );
                            },
                          );
                  },
                ),
        ),

        // --- TOMBOL SCANNING (STICKY BOTTOM) ---
        Container(
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[100]!)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: isScanning ? null : () => scanDevices(),
              icon: isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.grey,
                      ),
                    )
                  : const Icon(Icons.search_rounded),
              label: Text(
                isScanning ? 'Mencari Perangkat...' : 'Cari Ulang Printer',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isScanning
                    ? Colors.grey[200]
                    : Colors.amber[400],
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Widget untuk tampilan saat printer kosong
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.print_disabled_outlined,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            "Tidak ada printer ditemukan",
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Pastikan Bluetooth printer sudah aktif",
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    bool isActive = numberPage == index;

    return Material(
      color: isActive ? Colors.amber[50] : Colors.white,
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
              width: isActive ? 2 : 1,
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
