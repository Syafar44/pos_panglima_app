import 'dart:async';
import 'dart:convert';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pos_panglima_app/data/app_config.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, ByteData, Uint8List;

class BluetoothPrinterService {
  static final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  static final ValueNotifier<BluetoothDevice?> connectedPrinterNotifier =
      ValueNotifier<BluetoothDevice?>(null);
  static BluetoothDevice? get connectedPrinter =>
      connectedPrinterNotifier.value;
  static set connectedPrinter(BluetoothDevice? device) =>
      connectedPrinterNotifier.value = device;
  static BluetoothDevice? lastConnectedPrinter;
  // ignore: cancel_subscriptions
  static StreamSubscription? _stateSubscription;

  // ─── Reconnect State ───────────────────────────────────────────────────────
  static Timer? _reconnectTimer;
  static Timer? _heartbeatTimer;
  static int _reconnectAttempt = 0;
  static int _heartbeatFailures = 0;
  static bool _userDisconnected = false;

  static const _baseReconnectDelay = Duration(seconds: 2);
  static const _maxReconnectDelay = Duration(seconds: 60);
  static const _heartbeatInterval = Duration(seconds: 15);
  static const _maxHeartbeatFailures = 2;

  // ─── Print Queue ───────────────────────────────────────────────────────────
  static final List<Map<String, dynamic>> _printQueue = [];
  static Timer? _queueTimer;

  // ─── Permissions ───────────────────────────────────────────────────────────

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

  // ─── Save / Load Printer ───────────────────────────────────────────────────

  /// Simpan printer ke SharedPreferences dan set lastConnectedPrinter.
  /// Dipanggil saat user memilih printer — sebelum connect attempt.
  static Future<void> setLastPrinter(BluetoothDevice device) async {
    lastConnectedPrinter = device;
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
    debugPrint(
      "Printer terakhir ditemukan: ${device.name}, mencoba reconnect...",
    );

    _scheduleReconnect();
  }

  // ─── Connect / Disconnect ──────────────────────────────────────────────────

  static Future<bool> connect(BluetoothDevice device) async {
    _userDisconnected = false;
    await setLastPrinter(device);

    final completer = Completer<bool>();

    try {
      // Cancel listener LAMA dulu — supaya bluetooth.disconnect() di bawah
      // tidak men-trigger handler lama yang akan _scheduleReconnect() ganda
      await _safeCancelStateSubscription();

      // Force disconnect untuk membersihkan socket stale di plugin native —
      // mencegah error "read failed, socket might closed" pada attempt berikutnya
      try {
        await bluetooth.disconnect();
      } catch (_) {
        // Abaikan: mungkin tidak connected
      }
      // Beri waktu BT subsystem untuk cleanup socket sebelum reconnect
      await Future.delayed(const Duration(milliseconds: 500));

      _stateSubscription = bluetooth.onStateChanged().listen((state) {
        if (state == BlueThermalPrinter.CONNECTED) {
          connectedPrinter = device;
          _reconnectAttempt = 0;
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          _startHeartbeat();
          if (!completer.isCompleted) completer.complete(true);
        } else if (state == BlueThermalPrinter.DISCONNECTED) {
          connectedPrinter = null;
          if (!completer.isCompleted) completer.complete(false);
          _scheduleReconnect();
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
    } catch (e, stack) {
      debugPrint("Connect error: $e");
      // Error transient (socket cleanup, timeout) sering terjadi saat reconnect
      // dan akan diretry otomatis — jangan spam Crashlytics
      final msg = e.toString();
      final isTransient =
          msg.contains('read failed') ||
          msg.contains('socket might closed') ||
          msg.contains('timeout');
      if (!isTransient) {
        CrashReporter.report(
          e,
          stack,
          reason: 'bluetooth_printer_service.connect',
        );
      }
      connectedPrinter = null;
      return false;
    }
  }

  static Future<void> disconnect() async {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectAttempt = 0;
    await bluetooth.disconnect();
    connectedPrinter = null;
  }

  // ─── Auto-Reconnect ────────────────────────────────────────────────────────

  static void _scheduleReconnect() {
    if (_userDisconnected) return;
    if (lastConnectedPrinter == null) return;
    if (_reconnectTimer?.isActive == true) return;

    // Exponential backoff: 2s, 4s, 8s, 16s, 32s, lalu cap di 60s
    final delaySeconds =
        (_baseReconnectDelay.inSeconds * (1 << _reconnectAttempt)).clamp(
          _baseReconnectDelay.inSeconds,
          _maxReconnectDelay.inSeconds,
        );
    final delay = Duration(seconds: delaySeconds);

    debugPrint(
      "Reconnect dijadwalkan dalam ${delay.inSeconds}s (attempt #${_reconnectAttempt + 1})",
    );

    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;

      if (lastConnectedPrinter == null || _userDisconnected) return;

      // Sanity check terakhir sebelum disconnect-reconnect cycle:
      // kalau ternyata masih connected (heartbeat false alarm), batalkan
      // reconnect dan restart heartbeat — supaya tidak memutus koneksi sehat.
      final isConn = await bluetooth.isConnected;
      if (isConn == true) {
        debugPrint("Reconnect skip: ternyata masih connected");
        _reconnectAttempt = 0;
        _startHeartbeat();
        return;
      }

      debugPrint("Mencoba reconnect ke ${lastConnectedPrinter!.name}...");
      final ok = await connect(lastConnectedPrinter!);

      if (ok) {
        debugPrint("Auto-reconnect berhasil");
        _reconnectAttempt = 0;
      } else {
        _reconnectAttempt++;
        _scheduleReconnect();
      }
    });
  }

  // ─── Heartbeat ─────────────────────────────────────────────────────────────

  /// Aktif memeriksa status koneksi setiap 15 detik.
  /// Diperlukan karena Android tidak selalu fire DISCONNECTED event saat
  /// printer dimatikan secara fisik (socket "hang", state listener diam).
  static void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatFailures = 0;
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      if (_userDisconnected || lastConnectedPrinter == null) {
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        return;
      }

      final isConn = await bluetooth.isConnected;
      if (isConn == true) {
        // Koneksi sehat — reset counter false negative
        _heartbeatFailures = 0;
        return;
      }

      // Plugin bilang tidak connected — bisa jadi false negative (cached state).
      // Hanya trigger reconnect setelah beberapa kali gagal beruntun supaya
      // tidak memutus koneksi yang sebenarnya masih hidup.
      _heartbeatFailures++;
      debugPrint(
        "Heartbeat failure #$_heartbeatFailures/$_maxHeartbeatFailures",
      );

      if (_heartbeatFailures >= _maxHeartbeatFailures) {
        debugPrint(
          "Heartbeat: $_heartbeatFailures kali gagal beruntun, schedule reconnect",
        );
        connectedPrinter = null;
        _heartbeatFailures = 0;
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        _scheduleReconnect();
      }
    });
  }

  /// Cancel state subscription dengan aman.
  /// Plugin native bisa throw PlatformException("No active stream to cancel")
  /// kalau platform stream sudah dibersihkan duluan (misal printer dimatikan).
  static Future<void> _safeCancelStateSubscription() async {
    final sub = _stateSubscription;
    _stateSubscription = null;
    if (sub == null) return;
    try {
      await sub.cancel();
    } catch (e) {
      debugPrint("Ignore cancel state subscription error: $e");
    }
  }

  // ─── Dispose ───────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _queueTimer?.cancel();
    _queueTimer = null;
    await _safeCancelStateSubscription();
  }

  // ─── Print Queue ───────────────────────────────────────────────────────────

  static Future<void> loadPrintQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('print_queue');
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        _printQueue.clear();
        _printQueue.addAll(decoded.cast<Map<String, dynamic>>());
        if (_printQueue.isNotEmpty) {
          debugPrint("Print queue dimuat: ${_printQueue.length} item pending");
          _startQueueTimer();
        }
      }
    } catch (e, stack) {
      debugPrint("Error loading print queue: $e");
      CrashReporter.report(
        e,
        stack,
        reason: 'bluetooth_printer_service.loadPrintQueue',
      );
    }
  }

  static Future<void> _savePrintQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('print_queue', jsonEncode(_printQueue));
    } catch (e, stack) {
      debugPrint("Error saving print queue: $e");
      CrashReporter.report(
        e,
        stack,
        reason: 'bluetooth_printer_service._savePrintQueue',
      );
    }
  }

  static void _startQueueTimer() {
    if (_queueTimer?.isActive == true) return;
    _queueTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _processQueue();
    });
  }

  static Future<void> _processQueue() async {
    if (_printQueue.isEmpty) {
      _queueTimer?.cancel();
      _queueTimer = null;
      return;
    }

    bool? isConn = await bluetooth.isConnected;
    if (isConn != true) return;

    while (_printQueue.isNotEmpty) {
      final payload = _printQueue.first;
      try {
        await _executePrint(
          documentNumber: payload['documentNumber'] as String,
          usersName: payload['usersName'] as String,
          listProduk: payload['listProduk'],
          totalQuantity: payload['totalQuantity'] as int,
          isCash: payload['isCash'] as bool,
          method: payload['method'] as String,
          totalPayment: payload['totalPayment'] as int,
          subTotal: payload['subTotal'] as int,
          payment: payload['payment'] as int?,
          paymentMethod: payload['paymentMethod'] as String?,
          isPayment: payload['isPayment'] as bool,
        );
        _printQueue.removeAt(0);
        await _savePrintQueue();
        debugPrint(
          "Print queue: item berhasil dicetak, sisa ${_printQueue.length}",
        );
      } catch (e, stack) {
        debugPrint("Error memproses print queue: $e");
        CrashReporter.report(
          e,
          stack,
          reason: 'bluetooth_printer_service._processQueue',
        );
        break;
      }
    }

    if (_printQueue.isEmpty) {
      _queueTimer?.cancel();
      _queueTimer = null;
    }
  }

  // ─── Print ─────────────────────────────────────────────────────────────────

  /// Cetak teks dengan ukuran custom via raw ESC/POS command.
  ///
  /// Memberikan kontrol jauh lebih halus daripada `printCustom(text, size, align)`
  /// bawaan plugin (yang hanya menyediakan 6 preset 0-5).
  ///
  /// - [widthX]: pengali lebar karakter, 1..8 (1 = normal, 8 = sangat lebar).
  /// - [heightX]: pengali tinggi karakter, 1..8 (1 = normal, 8 = sangat tinggi).
  /// - [align]: 0 = left, 1 = center, 2 = right.
  ///
  /// Contoh ukuran umum:
  /// - Body normal: `printSized(text, 1, 1, 0)`
  /// - Header sedang: `printSized(text, 2, 2, 1)`
  /// - Total bayar besar: `printSized(text, 2, 3, 1)` (lebar 2x, tinggi 3x)
  /// - Heading sangat besar: `printSized(text, 3, 3, 1)`
  ///
  /// Setelah cetak, ukuran & align di-reset ke default supaya tidak bocor ke
  /// `printCustom` berikutnya.
  static Future<void> printSized(
    String text,
    int widthX,
    int heightX,
    int align,
  ) async {
    final w = widthX.clamp(1, 8);
    final h = heightX.clamp(1, 8);
    final n = ((w - 1) << 4) | (h - 1);
    final a = align.clamp(0, 2);

    // ESC a <align>  → set alignment
    // GS  ! <n>      → set char size (high nibble = width, low nibble = height)
    // <text>\n
    // GS  ! 0        → reset size
    // ESC a 0        → reset align ke left
    final bytes = Uint8List.fromList([
      0x1B,
      0x61,
      a,
      0x1D,
      0x21,
      n,
      ...text.codeUnits,
      0x0A,
      0x1D,
      0x21,
      0x00,
      0x1B,
      0x61,
      0x00,
    ]);
    await bluetooth.writeBytes(bytes);
  }

  static Future<void> printLogo({required String usersName}) async {
    final lower = usersName.toLowerCase();
    String assetPath;
    if (lower.contains('roti gembung panglima')) {
      assetPath = 'assets/images/logojajan.jpg';
    } else if (lower.contains('gerai panglima')) {
      assetPath = 'assets/images/logogerai.jpg';
    } else {
      assetPath = 'assets/images/logojajan.jpg';
    }

    final ByteData bytes = await rootBundle.load(assetPath);
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
    bool? isCopy,
    String? dateTime,
    required bool isPayment,
  }) async {
    bool? isConn = await bluetooth.isConnected;

    if (isConn != true) {
      debugPrint(
        "Printer belum terhubung! Melewati cetak (antrian dinonaktifkan).",
      );
      // [QUEUE-DISABLED] Simpan ke antrian belum diaktifkan
      // _printQueue.add({
      //   'documentNumber': documentNumber,
      //   'usersName': usersName,
      //   'listProduk': listProduk,
      //   'totalQuantity': totalQuantity,
      //   'isCash': isCash,
      //   'method': method,
      //   'totalPayment': totalPayment,
      //   'subTotal': subTotal,
      //   'payment': payment,
      //   'paymentMethod': paymentMethod,
      //   'isPayment': isPayment,
      // });
      // await _savePrintQueue();
      // _startQueueTimer();
      return;
    }

    await _executePrint(
      documentNumber: documentNumber,
      usersName: usersName,
      listProduk: listProduk,
      totalQuantity: totalQuantity,
      isCash: isCash,
      method: method,
      totalPayment: totalPayment,
      subTotal: subTotal,
      payment: payment,
      paymentMethod: paymentMethod,
      isPayment: isPayment,
      isCopy: isCopy,
      dateTime: dateTime,
    );
  }

  /// Cetak struk Big Order. Format mirip struk pembayaran: logo, header outlet,
  /// info pesanan, daftar item, lalu Total / DP / Sisa.
  ///
  /// [data] = gabungan detail Big Order (lines, total_amount, total_dibayar,
  /// sisa_tagihan, pickup_at, document_number) + nama pelanggan dari daftar.
  /// Return false bila printer tidak terhubung (biar pemanggil bisa memberi tahu).
  static Future<bool> printBigOrder({
    required Map<String, dynamic> data,
    String usersName = '',
  }) async {
    final bool? isConn = await bluetooth.isConnected;
    if (isConn != true) {
      debugPrint("Printer belum terhubung! Melewati cetak Big Order.");
      return false;
    }

    await initializeDateFormatting('id_ID', null);

    final String docNumber = (data['document_number'] ?? '-').toString();
    final String pelanggan = (data['customers_name'] ?? 'General Pelanggan')
        .toString();
    final int total = (data['total_amount'] as num?)?.toInt() ?? 0;
    final int dibayar = (data['total_dibayar'] as num?)?.toInt() ?? 0;
    final int sisa =
        (data['sisa_tagihan'] as num?)?.toInt() ?? (total - dibayar);

    // Daftar item bisa datang dengan nama key berbeda tergantung backend.
    List lines = const [];
    for (final key in const [
      'lines',
      'items',
      'pos_order_lines',
      'order_lines',
      'big_order_lines',
      'big_order_details',
      'details',
    ]) {
      final v = data[key];
      if (v is List && v.isNotEmpty) {
        lines = v;
        break;
      }
    }

    // Waktu pengambilan.
    String waktuAmbil = '-';
    final pickupStr = data['pickup_at']?.toString();
    if (pickupStr != null && pickupStr.isNotEmpty) {
      final parsed = DateTime.tryParse(pickupStr);
      if (parsed != null) {
        waktuAmbil = DateFormat("d MMM yyyy, HH.mm", "id_ID").format(parsed);
      }
    }

    final String printedAt = DateFormat(
      "d MMM yyyy, HH.mm",
      "id_ID",
    ).format(DateTime.now());

    final String user = usersName.replaceFirst(RegExp(r'^Kasir\s+'), '');
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('outlet_address') ?? '';

    await printLogo(usersName: user.isEmpty ? 'panglima' : user);
    bluetooth.printCustom(user.isEmpty ? 'BIG ORDER' : user, 5, 1);
    bluetooth.printNewLine();
    if (address.isNotEmpty) {
      bluetooth.printCustom(address, 0, 1);
    }

    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom('BIG ORDER', 1, 1);
    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom('ID Pesanan  : $docNumber', 0, 0);
    bluetooth.printCustom('Pelanggan   : $pelanggan', 0, 0);
    bluetooth.printCustom('Waktu Ambil : $waktuAmbil', 0, 0);
    bluetooth.printCustom('--------------------------------', 1, 0);

    if (lines.isEmpty) {
      bluetooth.printCustom('(rincian item tidak tersedia)', 0, 1);
    } else {
      for (final e in lines) {
        if (e is! Map) continue;
        final String nama =
            (e['pos_menus_name'] ??
                    e['item_name'] ??
                    e['name'] ??
                    e['title'] ??
                    '-')
                .toString();
        final int qty =
            (e['quantity'] as num?)?.toInt() ??
            (e['qty'] as num?)?.toInt() ??
            0;
        final int price = (e['price'] as num?)?.toInt() ?? 0;
        final int lineTotal =
            (e['total'] as num?)?.toInt() ??
            (e['subtotal'] as num?)?.toInt() ??
            price * qty;

        bluetooth.printCustom(nama, 1, 0);

        // Varian / tambahan (props).
        final dynamic props = e['props'] ?? e['pos_order_lines_props'];
        if (props is List) {
          for (final prop in props) {
            if (prop is! Map) continue;
            final pName =
                (prop['pos_menus_name'] ?? prop['title'] ?? prop['name'] ?? '-')
                    .toString();
            final pQty = (prop['quantity'] as num?)?.toInt() ?? 0;
            bluetooth.printCustom('   ${pQty}x $pName', 0, 0);
          }
        }

        bluetooth.printLeftRight(
          ' $qty x ${convertIDR(price)}',
          convertIDR(lineTotal),
          0,
        );
        bluetooth.printNewLine();
      }
    }

    final bool lunas = sisa <= 0;
    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printLeftRight('Total   :', convertIDR(total), 0);
    bluetooth.printLeftRight('Dibayar :', convertIDR(dibayar), 0);
    if (!lunas) {
      bluetooth.printLeftRight('Sisa    :', convertIDR(sisa), 0);
    }
    bluetooth.printCustom('--------------------------------', 1, 0);
    // Penanda LUNAS hanya saat sudah lunas.
    if (lunas) {
      bluetooth.printCustom('*** LUNAS ***', 2, 1);
      bluetooth.printCustom('--------------------------------', 1, 0);
    }
    // Catatan bawa struk — selalu tampil.
    bluetooth.printCustom('HARAP MEMBAWA STRUK INI', 1, 1);
    bluetooth.printCustom('SAAT PENGAMBILAN PESANAN', 1, 1);
    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom('Dicetak: $printedAt', 0, 1);
    bluetooth.printNewLine();
    bluetooth.paperCut();
    return true;
  }

  /// Cetak DAFTAR transaksi (untuk laporan per-kategori di laporan_page).
  /// Memakai pengaturan/format yang sama dengan struk: cek koneksi, logo,
  /// alamat outlet, garis pemisah, `printLeftRight`, dan `paperCut`.
  static Future<void> printTransactionReport({
    required String title,
    required String subtitle,
    required List transactions,
  }) async {
    bool? isConn = await bluetooth.isConnected;
    if (isConn != true) {
      debugPrint("Printer belum terhubung! Melewati cetak laporan transaksi.");
      return;
    }

    await initializeDateFormatting('id_ID', null);
    final String printedAt = DateFormat(
      "d MMM yyyy, HH.mm",
      "id_ID",
    ).format(DateTime.now());

    // Identitas outlet untuk pemilihan logo & header — ambil dari transaksi
    // pertama (field users_name).
    final String usersName = transactions.isNotEmpty
        ? (transactions.first['users_name']?.toString() ?? '')
        : '';
    final String user = usersName.replaceFirst(RegExp(r'^Kasir\s+'), '');

    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('outlet_address') ?? '';

    await printLogo(usersName: user.isEmpty ? 'panglima' : user);
    bluetooth.printCustom(user.isEmpty ? 'LAPORAN' : user, 5, 1);
    bluetooth.printNewLine();
    if (address.isNotEmpty) {
      bluetooth.printCustom(address, 0, 1);
    }

    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom('LAPORAN TRANSAKSI', 1, 1);
    bluetooth.printCustom(title, 0, 1);
    if (subtitle.isNotEmpty) {
      bluetooth.printCustom(subtitle, 0, 1);
    }
    bluetooth.printCustom('Dicetak: $printedAt', 0, 1);
    bluetooth.printCustom('--------------------------------', 1, 0);

    num total = 0;
    for (final t in transactions) {
      final String doc = t['document_number']?.toString() ?? '-';
      final amount = t['total_amount'] ?? 0;
      if (amount is num) total += amount;

      String tanggal = '';
      String waktu = '';
      final ca = t['created_at']?.toString();
      if (ca != null && ca.isNotEmpty) {
        final parsed = DateTime.tryParse(ca);
        if (parsed != null) {
          tanggal = DateFormat("d MMM yyyy", "id_ID").format(parsed);
          waktu = DateFormat("HH.mm", "id_ID").format(parsed);
        }
      }

      // Baris 1: ID pesanan (kiri) | tanggal (kanan)
      bluetooth.printLeftRight(doc, tanggal, 0);
      // Baris 2: nominal (kiri) | waktu (kanan)
      bluetooth.printLeftRight(
        convertIDR(amount is num ? amount : 0),
        waktu,
        0,
      );
      bluetooth.printCustom('--------------------------------', 1, 0);
    }

    bluetooth.printCustom('Jumlah Transaksi : ${transactions.length}', 0, 0);
    bluetooth.printNewLine();
    bluetooth.printCustom('Total :', 2, 0);
    bluetooth.printCustom(convertIDR(total), 2, 0);
    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printNewLine();
    bluetooth.paperCut();
  }

  static Future<void> _executePrint({
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
    bool? isCopy = false,
    String? dateTime,
  }) async {
    final lower = usersName.toLowerCase();

    await initializeDateFormatting('id_ID', null);

    String date = DateFormat(
      "d MMM yyyy, HH.mm",
      "id_ID",
    ).format(DateTime.now());

    // Tanggal transaksi untuk struk copy (re-print dari riwayat). `dateTime`
    // berupa string ISO (mis. created_at). Untuk struk live (bukan copy) pakai
    // waktu sekarang. Format tanpa toLocal agar konsisten dengan tampilan riwayat.
    String trxDate = date;
    if (isCopy == true && dateTime != null && dateTime.isNotEmpty) {
      final parsed = DateTime.tryParse(dateTime);
      if (parsed != null) {
        trxDate = DateFormat("d MMM yyyy, HH.mm", "id_ID").format(parsed);
      }
    }

    String pelanggan = 'General Pelanggan';
    String user = usersName.replaceFirst(RegExp(r'^Kasir\s+'), '');

    // Alamat outlet disimpan oleh login_page ke key 'outlet_address'.
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('outlet_address') ?? '';

    await printLogo(usersName: user);
    bluetooth.printCustom(user, 5, 1);
    bluetooth.printNewLine();
    if (address.isNotEmpty) {
      bluetooth.printCustom(address, 0, 1);
    }

    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom('ID Pesanan : $documentNumber', 0, 0);
    bluetooth.printCustom('Pelangan   : $pelanggan', 0, 0);
    bluetooth.printCustom('Transaksi  : $trxDate', 0, 0);
    if (isCopy == true) {
      bluetooth.printCustom('--------------------------------', 1, 0);
      bluetooth.printCustom("Copy - $date", 0, 1);
    }
    bluetooth.printCustom('--------------------------------', 1, 0);
    bluetooth.printCustom(method, 0, 1);
    bluetooth.printCustom('--------------------------------', 1, 0);

    for (final e in listProduk) {
      bluetooth.printCustom(e['pos_menus_name'], 1, 0);

      // Variant items dari cart (saat re-print dari cart) — `pos_cart_props`.
      if (isPayment) {
        final dynamic cartProps = e['pos_cart_props'];
        if (cartProps is List) {
          for (final prop in cartProps) {
            bluetooth.printCustom(
              '   ${prop['quantity']}x ${prop['pos_menus_name']}',
              0,
              0,
            );
          }
        }
      }

      // Variant items dari order response — `pos_order_lines_props`.
      // Format sama: " <qty>x <nama_variant>" per baris.
      final dynamic orderLinesProps = e['pos_order_lines_props'];
      if (orderLinesProps is List) {
        for (final prop in orderLinesProps) {
          bluetooth.printCustom(
            '   ${prop['quantity']}x ${prop['pos_menus_name']}',
            0,
            0,
          );
        }
      }

      // pos_order_lines_material (packaging dll.) tidak ditampilkan di struk
      bluetooth.printLeftRight(
        ' ${e['quantity']} x ${convertIDR(e['price'])}',
        convertIDR(e['price'] * e['quantity']),
        0,
      );
      bluetooth.printNewLine();
    }

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
    bluetooth.printCustom('Total : ${convertIDR(totalPayment)}', 3, 2);
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
    bluetooth.printCustom("Whatsapp  : ${AppConfig.whatsapp}", 0, 0);
    if (lower.contains('roti gembung panglima')) {
      bluetooth.printCustom("Instagram : ${AppConfig.instagramRGP}", 0, 0);
      bluetooth.printCustom("Facebook  : ${AppConfig.facebookRGP}", 0, 0);
      bluetooth.printCustom("Website   : ${AppConfig.websiteRGP}", 0, 0);
    } else if (lower.contains('gerai panglima')) {
      bluetooth.printCustom("Instagram : ${AppConfig.instagramGP}", 0, 0);
      bluetooth.printCustom("Facebook  : ${AppConfig.facebookGP}", 0, 0);
      bluetooth.printCustom("Website   : ${AppConfig.websiteGP}", 0, 0);
    } else {
      bluetooth.printCustom("Instagram : ${AppConfig.instagramRGP}", 0, 0);
      bluetooth.printCustom("Facebook  : ${AppConfig.facebookRGP}", 0, 0);
      bluetooth.printCustom("Website   : ${AppConfig.websiteRGP}", 0, 0);
    }

    bluetooth.printNewLine();
    bluetooth.paperCut();
  }
}
