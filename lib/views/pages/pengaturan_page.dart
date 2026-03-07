import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/utils/modal_error.dart';
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
          return ModalError();
        },
      );
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
              border: Border(right: BorderSide(color: Colors.black26)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          numberPage = 1;
                        });
                      },
                      child: Container(
                        color: numberPage == 1
                            ? Colors.amber[100]
                            : Colors.white,
                        padding: EdgeInsets.all(14.0),
                        child: Row(
                          spacing: 16.0,
                          children: [
                            Icon(
                              Icons.person,
                              size: 26.0,
                              color: Colors.grey[800],
                            ),
                            Text(
                              'Profil Pengguna',
                              style: TextStyle(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          numberPage = 2;
                        });
                      },
                      child: Container(
                        color: numberPage == 2
                            ? Colors.amber[100]
                            : Colors.white,
                        padding: EdgeInsets.all(14.0),
                        child: Row(
                          spacing: 16.0,
                          children: [
                            Icon(
                              Icons.print,
                              size: 26.0,
                              color: Colors.grey[800],
                            ),
                            Text(
                              'Printer',
                              style: TextStyle(
                                fontSize: 16.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Text('V.1.0.0'),
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
        SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                color: Colors.black12,
                padding: EdgeInsets.all(10.0),
                child: Text(
                  'Informasi Pengguna',
                  style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                title: Text('Informasi Outlet'),
                subtitle: Text(profile?['name'] ?? '-'),
              ),
              ListTile(
                title: Text('Departemen'),
                subtitle: Text(profile?['department'] ?? '-'),
              ),
              Container(
                width: double.infinity,
                color: Colors.black12,
                padding: EdgeInsets.all(10.0),
                child: Text(
                  'Informasi Perangkat',
                  style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                title: Text('Nama Perangkat'),
                subtitle: FutureBuilder<String>(
                  future: getDeviceName(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return Text("Memuat...");
                    return Text(snapshot.data!);
                  },
                ),
              ),

              ListTile(
                title: Text('Outlet Terhubung'),
                subtitle: Text('Roti Gembung Panglima'),
              ),

              ListTile(
                title: Text('Alamat IP'),
                subtitle: FutureBuilder<String>(
                  future: getDeviceIP(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return Text("Memuat...");
                    return Text(snapshot.data!);
                  },
                ),
              ),
              Divider(),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          alignment: AlignmentGeometry.center,
          child: TextButton(
            onPressed: () {
              showDialog(
                context: context,
                barrierDismissible: true,
                builder: (BuildContext context) {
                  return EndsiftModal();
                },
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 10.0,
              children: [
                Icon(Icons.logout, color: Colors.black87),
                Text(
                  'Keluar Perangkat',
                  style: TextStyle(color: Colors.black87),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget printer() {
    return Column(
      children: [
        Container(
          color: Colors.black12,
          padding: EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daftar Printer',
                style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
              ),
              Row(
                spacing: 10.0,
                children: [Icon(Icons.print), Icon(Icons.more_vert)],
              ),
            ],
          ),
        ),
        Expanded(
          child: devices.isEmpty
              ? Center(child: Text("Tidak ada printer ditemukan"))
              : ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, i) {
                    final d = devices[i];
                    return ListTile(
                      leading: Icon(Icons.bluetooth),
                      title: Text(d.name ?? "Unknown"),
                      subtitle: Text(d.address ?? "-"),
                      trailing: Icon(Icons.chevron_right),
                      onTap: () => connectPrinter(d),
                    );
                  },
                ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                scanDevices();
              });
            },
            style: IconButton.styleFrom(
              backgroundColor: isScanning ? Colors.grey[300] : Colors.amber,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'Scanning Printer',
              style: TextStyle(color: Colors.black87),
            ),
          ),
        ),
      ],
    );
  }
}
