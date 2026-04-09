import 'dart:async';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, ByteData, Uint8List;

class BluetoothPrinterService {
  static final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  static BluetoothDevice? connectedPrinter;
  static BluetoothDevice? lastConnectedPrinter;

  static Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  static Future<List<BluetoothDevice>> scanPrinters() async {
    return await bluetooth.getBondedDevices();
  }

  static Future<bool> connect(BluetoothDevice device) async {
    Completer<bool> completer = Completer();

    try {
      bool? alreadyConnected = await bluetooth.isConnected;
      if (alreadyConnected == true) {
        await bluetooth.disconnect();
      }

      bluetooth.onStateChanged().listen((state) {
        if (state == BlueThermalPrinter.CONNECTED) {
          connectedPrinter = device;
          _saveLastPrinter(device);
          if (!completer.isCompleted) completer.complete(true);
        } else if (state == BlueThermalPrinter.DISCONNECTED) {
          connectedPrinter = null;

          if (!completer.isCompleted) completer.complete(false);

          if (lastConnectedPrinter != null) {
            _autoReconnect();
          }
        }
      });

      await bluetooth.connect(device);

      return completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          connectedPrinter = null;
          return false;
        },
      );
    } catch (e) {
      
      debugPrint("Connect error: $e");
      connectedPrinter = null;
      return false;
    }
  }

  static Future<void> disconnect() async {
    await bluetooth.disconnect();
    connectedPrinter = null;
  }

  static Future<void> _autoReconnect({int retries = 3}) async {
    if (lastConnectedPrinter == null) return;

    for (int i = 0; i < retries; i++) {
      try {
        debugPrint("Mencoba reconnect (${i + 1}/$retries)...");
        bool ok = await connect(lastConnectedPrinter!);
        if (ok) {
          debugPrint("Auto-reconnect berhasil ke ${lastConnectedPrinter!.name}");
          return;
        }
      } catch (e) {
        debugPrint("Retry reconnect error: $e");
      }
      await Future.delayed(const Duration(seconds: 2));
    }

    debugPrint("Auto-reconnect gagal setelah $retries percobaan");
  }

  static Future<void> _saveLastPrinter(BluetoothDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_printer_name', device.name ?? '');
    await prefs.setString('last_printer_address', device.address ?? '');
  }

  static Future<void> loadLastPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('last_printer_address');

    if (address == null || address.isEmpty) {
      debugPrint("Tidak ada printer terakhir yang tersimpan.");
      return;
    }

    List<BluetoothDevice> devices = await bluetooth.getBondedDevices();

    BluetoothDevice? device = devices
        .where((d) => d.address == address)
        .cast<BluetoothDevice?>()
        .firstOrNull;

    if (device == null) {
      debugPrint("Printer terakhir tidak ditemukan di bonded devices.");
      return;
    }

    lastConnectedPrinter = device;
    debugPrint("Printer terakhir ditemukan: ${device.name}, mencoba reconnect...");

    _autoReconnect();
  }

  static Future<void> printLogo() async {
    final ByteData bytes = await rootBundle.load('assets/images/logojajan.jpg');
    final Uint8List list = bytes.buffer.asUint8List();
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/logo.jpg';
    final file = await File(filePath).writeAsBytes(list);

    bluetooth.printImage(file.path);
  }

  static Future<void> printStruk({
    required String documentNumber,
    required String usersName,
    required dynamic listProduk,
    required int totalQuantity,
    required bool isCash,
    required String method,
    required int totalPayment,
    required int subTotal,
    int? payment,
    String? paymentMethod,
    required bool isPayment,
  }) async {
    bool? isConn = await bluetooth.isConnected;
    await initializeDateFormatting('id_ID', null);

    if (isConn != true) {
      debugPrint("Printer belum terhubung!");
      return;
    }

    String date = DateFormat(
      "d MMM yyyy, HH.mm",
      "id_ID",
    ).format(DateTime.now());

    String pelanggan = 'General Pelanggan';

    await printLogo();
    bluetooth.printNewLine();
    bluetooth.printCustom(usersName, 1, 1);

    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom('ID Pesanan : $documentNumber', 0, 0);
    bluetooth.printCustom('Pelangan   : $pelanggan', 0, 0);
    bluetooth.printCustom('Transaksi  : $date', 0, 0);
    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom(method, 0, 1);
    bluetooth.printCustom('--------------------------------', 1, 0);

    listProduk.map((e) {
      bluetooth.printCustom(e['pos_menus_name'], 1, 0);
      if (isPayment) {
        final dynamic listProps = e['pos_cart_props'];
        listProps.forEach((e) {
          bluetooth.printCustom(
            ' ${e['quantity']}x ${e['pos_menus_name']}',
            0,
            0,
          );
        });
      } else {
        final dynamic listProps = e['pos_order_lines_material'];
        listProps.forEach((e) {
          bluetooth.printCustom(
            '   ${e['quantity']}x ${e['items_name']}',
            0,
            0,
          );
        });
      }
      bluetooth.printLeftRight(
        ' ${e['quantity']} x ${convertIDR(e['price'])}',
        convertIDR(e['price'] * e['quantity']),
        0,
      );
      bluetooth.printNewLine();
    }).toString();

    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printLeftRight('Jumlah Item :', '$totalQuantity', 0);
    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printLeftRight('Subtotal :', convertIDR(subTotal), 0);
    if (subTotal != totalPayment) {
      bluetooth.printLeftRight(
        'Diskon   :',
        '- ${convertIDR(subTotal - totalPayment)}',
        0,
      );
    }
    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom('Total : ${convertIDR(totalPayment)}', 1, 2);
    bluetooth.printCustom('--------------------------------', 1, 0);

    if (isCash == true) {
      bluetooth.printLeftRight('Tunai   :', convertIDR(payment ?? 0), 0);
      bluetooth.printLeftRight(
        'Kembali :',
        convertIDR((payment ?? 0) - totalPayment),
        0,
      );
    } else {
      bluetooth.printLeftRight('$paymentMethod :', convertIDR(totalPayment), 0);
    }

    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom(
      "Terima Kasih Telah Berbelanja di Outlet kami ya kak :)",
      1,
      1,
    );
    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom("Whatsapp  : 082220002237", 0, 0);
    bluetooth.printCustom("Instagram : @Jajanpanglima", 0, 0);
    bluetooth.printCustom("Facebook  : @Jajan Panglima", 0, 0);
    bluetooth.printCustom("Website   : www.rotigembungpanglima.com", 0, 0);

    bluetooth.printNewLine();
    bluetooth.paperCut();
  }
}
