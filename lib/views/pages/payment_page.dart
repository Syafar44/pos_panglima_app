import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:pos_panglima_app/data/app_config.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:mime/mime.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/camera_service.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/method_service.dart';
import 'package:pos_panglima_app/services/network_service.dart';
import 'package:pos_panglima_app/services/offline_cart_sync.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/services/order_service.dart';
import 'package:pos_panglima_app/services/offline_sync_manager.dart';
import 'package:pos_panglima_app/services/storage/method_storage_service.dart';
import 'package:pos_panglima_app/services/storage/offline_stock_service.dart';
import 'package:pos_panglima_app/services/storage/pending_lampiran_service.dart';
import 'package:pos_panglima_app/services/storage/pending_order_service.dart';
import 'package:pos_panglima_app/services/storage/profile_storage_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/bom_calculator.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/modal_insufficient_stock.dart';
import 'package:pos_panglima_app/utils/offline_guard.dart';
import 'package:pos_panglima_app/utils/rupiah_formatter.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/components/ui/custom_checkbox.dart';
import 'package:pos_panglima_app/views/widgets/network_indicator.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  List<Map<String, dynamic>> cartItems = [];
  int totalQuantity = 0;
  int totalPayment = 0;
  int subTotal = 0;
  int discount = 0;
  double fadeOpacity = 0.2;
  int selectedTab = 0;
  BluetoothDevice? connectedPrinter;
  List<BluetoothDevice> devices = [];
  bool isScanning = false;
  StreamSubscription? _bluetoothSubscription;
  final apiClient = ApiClient();
  late final CartService cartService;
  late final AuthService authService;
  late final OrderService orderService;
  late final MethodService methodService;
  final ScrollController _scrollController = ScrollController();
  final cameraService = CameraService();
  int? userId;
  String userName = 'Roti Gembung Panglima';
  bool isLoadingUserId = true;
  bool isLoadingCart = true;
  bool isLoadingMethod = true;
  bool isLoading = false;
  String? methodsLoadError; // null jika sukses, string jika ada error
  String? customerId;
  int? shiftId;
  late int nominalVoucher = 0;
  List<String> barcodeList = [];
  List<Map<String, dynamic>> paymentMethods = [];
  List<Map<String, dynamic>> orderMethods = [];
  final TextEditingController _customAmountController = TextEditingController();
  final TextEditingController _voucherController = TextEditingController();
  final TextEditingController _keteranganCompliment = TextEditingController();
  // Ongkos kirim — hanya dipakai & wajib saat metode order = Delivery.
  final TextEditingController _ongkirController = TextEditingController();
  int _ongkir = 0;

  /// Sementara disembunyikan sampai API ongkir dari backend siap.
  /// Set ke `true` untuk mengaktifkan kembali input & validasi ongkir.
  final bool _ongkirEnabled = false;

  /// True bila metode order yang dipilih adalah Delivery.
  bool get _isDelivery => selectedMethodName.toLowerCase().contains('delivery');
  // final FocusNode _voucherFocusNode = FocusNode();

  int roundToCashDenomination(int num) {
    if (num <= 0) return 0;
    if (num < 5000) return 5000;
    if (num < 10000) return 10000;
    if (num < 20000) return 20000;
    if (num < 50000) return 50000;
    if (num < 100000) return 100000;
    return ((num ~/ 50000) + 1) * 50000;
  }

  String selectedPayment = "exact";
  String selectedMethodName = "";
  String selectedMethodId = "";
  String selectedPaymentNonTunai = "";
  String selectedPaymentNonTunaiId = "";
  int customAmount = 0;
  int finalPayment = 0;
  // Jenis compliment: 0 = belum dipilih, 1 = Sample, 2 = Biaya Pemasaran
  int selectedComplementLabel = 0;
  bool _navigated = false;
  static const _uuid = Uuid();
  String? _idempotencyKey;
  String _latitude = "";
  String _longitude = "";
  String _deviceInfo = "";

  int get exactAmount => totalPayment;
  int get roundedAmount =>
      roundToCashDenomination(totalPayment - nominalVoucher);

  @override
  void initState() {
    super.initState();

    _bluetoothSubscription = BluetoothPrinterService.bluetooth
        .onStateChanged()
        .listen((state) {
          setState(() {
            connectedPrinter = BluetoothPrinterService.connectedPrinter;
          });
        });

    authService = AuthService(apiClient.dio);
    methodService = MethodService(apiClient.dio);
    cartService = CartService(apiClient.dio);
    orderService = OrderService(apiClient.dio);

    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;

      double maxScroll = _scrollController.position.maxScrollExtent;
      double current = _scrollController.position.pixels;

      if (current >= maxScroll - 5) {
        if (fadeOpacity != 0) setState(() => fadeOpacity = 0);
      } else {
        if (fadeOpacity != 1) setState(() => fadeOpacity = 1);
      }
    });

    _loadShiftId();

    _methods();

    getProfile();

    loadCart();

    _getLocation();

    _getDeviceInfo();
  }

  /// Bangun string identifier device untuk payload order, format:
  /// `"<Manufacturer> <Model>; <OS> <Version>; PanglimaPOS <_appVersion>"`.
  /// Best-effort: kalau plugin gagal, biarkan `_deviceInfo` tetap "".
  Future<void> _getDeviceInfo() async {
    try {
      final plugin = DeviceInfoPlugin();
      String info;
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        final brand = a.manufacturer.isNotEmpty
            ? '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)}'
            : a.manufacturer;
        info =
            "$brand ${a.model}; Android ${a.version.release}; PanglimaPOS ${AppConfig.version}";
      } else if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        info =
            "${i.utsname.machine}; iOS ${i.systemVersion}; PanglimaPOS ${AppConfig.version}";
      } else {
        info = "Unknown device; PanglimaPOS ${AppConfig.version}";
      }
      if (!mounted) return;
      setState(() => _deviceInfo = info);
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'payment_page._getDeviceInfo');
    }
  }

  /// Ambil koordinat GPS untuk payload order. Best-effort: kalau permission
  /// ditolak / service mati / timeout → biarkan `_latitude` & `_longitude`
  /// tetap "" (server menerima string kosong).
  Future<void> _getLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );

      if (!mounted) return;
      setState(() {
        _latitude = position.latitude.toStringAsFixed(6);
        _longitude = position.longitude.toStringAsFixed(6);
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'payment_page._getLocation');
    }
  }

  Future<void> loadCart() async {
    try {
      final online = await NetworkService.isOnline();
      List<Map<String, dynamic>> newItems;

      if (!online) {
        newItems = await OfflineStockService.getCartSnapshot();
      } else {
        // Hapus dulu item yang sudah dibayar offline dari cart server.
        await OfflineCartSync.flushServerCartDeletions();
        // Dorong item yang dibuat offline ke server agar ikut terbayar.
        await OfflineCartSync.migrateToServer();
        final getCart = await cartService.getCart();
        newItems = List<Map<String, dynamic>>.from(getCart.data['data'] ?? []);
        await OfflineStockService.saveCartSnapshot(newItems);
      }

      final newTotalPayment = newItems.fold<int>(0, (sum, item) {
        final int price = (item['total'] as int?) ?? 0;
        return sum + price;
      });

      final newTotalQuantity = newItems.fold<int>(0, (sum, item) {
        final int qty = (item['quantity'] as int?) ?? 0;
        final int maxQty = (item['max_qty'] as int?) ?? 0;
        if (maxQty > 0) {
          return sum + maxQty * qty;
        } else {
          return sum + qty;
        }
      });

      final newSubtotal = newItems.fold<int>(0, (sum, item) {
        final int price = (item['subtotal'] as int?) ?? 0;
        return sum + price;
      });

      final newDiscount = newItems.fold<int>(0, (sum, item) {
        final int price = (item['discount'] as int?) ?? 0;
        return sum + price;
      });

      if (!mounted) return;
      setState(() {
        cartItems = newItems;
        totalPayment = newTotalPayment;
        subTotal = newSubtotal;
        discount = newDiscount;
        isLoadingCart = false;
        totalQuantity = newTotalQuantity;
      });
    } on DioException catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'payment_page.loadCart',
        context: {
          'endpoint': e.requestOptions.path,
          'statusCode': e.response?.statusCode,
          'responseData': e.response?.data?.toString(),
        },
      );
      debugPrint('loadCart error: ${e.response?.data}');
      if (!mounted) return;
      setState(() => isLoadingCart = false);
      SnackbarUtil.show(
        context,
        title: "Gagal memuat keranjang",
        message: "Terjadi kesalahan saat mengambil data keranjang.",
        status: SnackBarStatus.error,
      );
    }
  }

  void _showSlowExecutionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.hourglass_top_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text('Proses Lambat', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: const Text(
          'Transaksi sedang diproses dan membutuhkan waktu lebih lama dari biasanya. '
          'Harap tunggu, jangan tutup aplikasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  String? _validateOrderPayload({
    required int? shiftIdVal,
    required int? userIdVal,
    required String? customerIdVal,
    required String orderMethodIdStr,
    required String? paymentMethodIdStr,
    required int subTotalVal,
    required int totalAmountVal,
    required int? payAmountVal,
  }) {
    if (shiftIdVal == null || shiftIdVal <= 0) {
      return "Shift belum dimulai. Mulai shift terlebih dahulu.";
    }
    if (userIdVal == null || userIdVal <= 0) {
      return "Sesi pengguna tidak valid. Silakan login ulang.";
    }
    final outletId = int.tryParse(customerIdVal ?? '');
    if (outletId == null || outletId <= 0) {
      return "Data outlet tidak ditemukan. Silakan login ulang.";
    }
    final orderMethodId = int.tryParse(orderMethodIdStr);
    if (orderMethodId == null || orderMethodId <= 0) {
      return "Metode pesanan belum dipilih.";
    }
    if (paymentMethodIdStr != null) {
      final pmId = int.tryParse(paymentMethodIdStr);
      if (pmId == null || pmId <= 0) {
        return "Metode pembayaran non-tunai belum dipilih.";
      }
    }
    if (subTotalVal <= 0) {
      return "Keranjang kosong atau subtotal tidak valid.";
    }
    if (totalAmountVal <= 0) {
      return "Total bayar tidak valid. Periksa voucher atau keranjang.";
    }
    if (payAmountVal != null && payAmountVal < totalAmountVal) {
      return "Nominal pembayaran tidak mencukupi total.";
    }
    return null;
  }

  /// Menjalankan future tanpa membiarkan error-nya menghentikan flow utama.
  /// Gunakan untuk operasi best-effort seperti print & upload yang sudah terlalu lambat untuk block transaksi.
  void _runBestEffort(Future<void> Function() task) {
    // ignore: unawaited_futures
    Future(() async {
      try {
        await task();
      } catch (e, stack) {
        debugPrint('[BestEffort] Terjadi error: $e');
        CrashReporter.report(e, stack, reason: 'payment_page._runBestEffort');
      }
    });
  }

  /// Validasi bahwa selectedMethodId dan selectedPaymentNonTunaiId benar-benar ada di data server.
  /// Return null jika valid, atau error message jika tidak valid.
  String? _validateSelectedMethodIds() {
    // Cek selectedMethodId di orderMethods
    final selectedId = int.tryParse(selectedMethodId);
    if (selectedId == null || selectedId <= 0) {
      return "Metode pesanan tidak valid.";
    }
    if (!orderMethods.any((m) => m['id'].toString() == selectedMethodId)) {
      return "Metode pesanan yang dipilih tidak ada. Silakan pilih ulang.";
    }

    // Cek selectedPaymentNonTunaiId di paymentMethods (jika non-tunai)
    if (selectedTab == 1) {
      final paymentId = int.tryParse(selectedPaymentNonTunaiId);
      if (paymentId == null || paymentId <= 0) {
        return "Metode pembayaran tidak valid.";
      }
      if (!paymentMethods.any(
        (m) => m['id'].toString() == selectedPaymentNonTunaiId,
      )) {
        return "Metode pembayaran yang dipilih tidak ada. Silakan pilih ulang.";
      }
    }

    return null;
  }

  /// Cari order di server berdasarkan `token_orders` (idempotency token).
  /// Return data order pertama yang cocok, atau `null` jika tidak ada / gagal cek.
  Future<Map<String, dynamic>?> _findOrderByToken(String token) async {
    try {
      if (userId == null) return null;
      // Search param di getOrderList tidak memfilter berdasarkan token, jadi
      // ambil 5 order terbaru milik user lalu cocokkan manual ke `token_orders`.
      final response = await orderService.getOrderList(userId!, 1, 5, "");
      final list = response.data['data']?['data'] as List<dynamic>?;
      if (list == null || list.isEmpty) return null;
      for (final item in list) {
        final order = Map<String, dynamic>.from(item as Map);
        if (order['token_orders']?.toString() == token) {
          return order;
        }
      }
      return null;
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'payment_page._findOrderByToken');
      return null;
    }
  }

  /// Eksekusi `postOrder` dengan rekonsiliasi idempotency.
  /// Jika `postOrder` melempar `DioException` (timeout/network/5xx), cek dulu
  /// ke server via [_findOrderByToken] apakah order dengan `token` sudah
  /// tersimpan. Jika ada → return data order existing (treat as success).
  /// Jika tidak ada → rethrow exception asli supaya flow error normal jalan.
  Future<Map<String, dynamic>> _executeOrderPost(
    Map<String, dynamic> payload,
    String token,
  ) async {
    try {
      final response = await orderService.postOrder(payload);
      final data = response.data['data'] as Map<String, dynamic>;
      return {
        'id': data['id'],
        'document_number': data['document_number'] as String,
      };
    } on DioException catch (e) {
      debugPrint(
        '[postOrder] !!! DioException '
        'type=${e.type} '
        'status=${e.response?.statusCode} '
        'statusMessage=${e.response?.statusMessage} '
        'data=${e.response?.data} '
        'message=${e.message} '
        'error=${e.error}',
      );
      final existing = await _findOrderByToken(token);
      if (existing != null) {
        debugPrint(
          '[postOrder] [Idempotency] Recovered order id=${existing['id']} '
          'document_number=${existing['document_number']} '
          'token=$token after DioException: ${e.type}',
        );
        return {
          'id': existing['id'],
          'document_number': existing['document_number'] as String,
        };
      }
      rethrow;
    }
  }

  /// Validasi metode dulu, lalu tampilkan modal konfirmasi.
  /// `handlePayment` hanya dijalankan jika kasir menekan "Bayar".
  Future<void> _confirmAndPay() async {
    if (isLoading) return;

    final methodValidationError = _validateSelectedMethodIds();
    if (methodValidationError != null) {
      SnackbarUtil.show(
        context,
        title: "Data Tidak Valid",
        message: methodValidationError,
        status: SnackBarStatus.warning,
      );
      return;
    }

    // Delivery → ongkos kirim wajib diisi (> 0).
    if (_ongkirEnabled && _isDelivery && _ongkir <= 0) {
      SnackbarUtil.show(
        context,
        title: "Ongkir Wajib",
        message: "Isi ongkos kirim terlebih dahulu untuk metode Delivery.",
        status: SnackBarStatus.warning,
      );
      return;
    }

    final confirmed = await _showPaymentConfirmationModal();
    if (!confirmed || !mounted) return;

    handlePayment();
  }

  Future<bool> _showPaymentConfirmationModal() async {
    final bool isNonTunai = selectedTab == 1;
    final String jenisTransaksi = isNonTunai ? 'Non Tunai' : 'Tunai';
    final int nominal = totalPayment - nominalVoucher;
    final double dialogWidth = (MediaQuery.of(context).size.width * 0.5).clamp(
      360.0,
      560.0,
    );

    // Warna chip: Tunai merah, Non Tunai hijau.
    final Color jenisColor = isNonTunai
        ? Colors.green.shade700
        : Colors.red.shade700;

    // Warna chip metode transaksi: Takeaway hijau, Delivery biru,
    // Compliment ungu, lainnya abu-abu.
    final String metodeLower = selectedMethodName.toLowerCase();
    final Color metodeColor = metodeLower.contains('takeaway')
        ? Colors.green.shade700
        : metodeLower.contains('delivery')
        ? Colors.blue.shade700
        : metodeLower.contains('compliment')
        ? Colors.purple.shade600
        : Colors.grey.shade700;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              title: const Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: AppColors.primary),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Konfirmasi Pembayaran',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nominal',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            convertIDR(nominal),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildConfirmationRow(
                      Icons.payment_outlined,
                      'Jenis Transaksi',
                      jenisTransaksi,
                      jenisColor,
                    ),
                    if (isNonTunai) ...[
                      const SizedBox(height: 10),
                      _buildConfirmationRow(
                        Icons.account_balance_wallet_outlined,
                        'Metode Pembayaran',
                        selectedPaymentNonTunai.isNotEmpty
                            ? selectedPaymentNonTunai
                            : '-',
                        Colors.blue.shade700,
                      ),
                    ],
                    const SizedBox(height: 10),
                    _buildConfirmationRow(
                      Icons.shopping_bag_outlined,
                      'Metode Transaksi',
                      selectedMethodName.isNotEmpty ? selectedMethodName : '-',
                      metodeColor,
                    ),
                    if (_isDelivery && _ongkirEnabled) ...[
                      const SizedBox(height: 10),
                      _buildConfirmationRow(
                        Icons.local_shipping_outlined,
                        'Ongkos Kirim',
                        convertIDR(_ongkir),
                        Colors.blue.shade700,
                      ),
                    ],
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          'Kembali',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          'Bayar',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Widget _buildConfirmationRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  void handlePayment() async {
    // Prevent concurrent payment attempts from rapid button clicks
    if (isLoading) {
      return;
    }

    _navigated = false; // Reset flag untuk payment baru

    // Idempotency token: generate sekali per attempt pembayaran.
    // Jika request sebelumnya gagal (timeout/network), retry pakai token sama
    // supaya server bisa dedupe. Direset ke null hanya saat sukses atau dispose.
    _idempotencyKey ??= _uuid.v4();
    final idempotencyKey = _idempotencyKey!;

    // Validasi bahwa selected method IDs ada di data server
    final methodValidationError = _validateSelectedMethodIds();
    if (methodValidationError != null) {
      SnackbarUtil.show(
        context,
        title: "Data Tidak Valid",
        message: methodValidationError,
        status: SnackBarStatus.warning,
      );
      return;
    }

    setState(() => isLoading = true);
    bool online = await NetworkService.isOnline();

    if (!online) {
      // ── BLOK OFFLINE ────────────────────────────────────────────────────
      // Fitur transaksi offline dimatikan → tolak pembayaran offline.
      if (!mounted) return;
      if (OfflineGuard.blocked(context)) {
        setState(() => isLoading = false);
        return;
      }
      // Hanya Compliment & Voucher yang wajib online (butuh verifikasi server).
      // Pembayaran tunai & non-tunai diperbolehkan offline.
      if (selectedMethodName == 'Compliment') {
        setState(() => isLoading = false);
        if (!mounted) return;
        SnackbarUtil.show(
          context,
          title: 'Mode Offline',
          message: 'Transaksi Compliment hanya bisa saat online.',
          status: SnackBarStatus.warning,
        );
        return;
      }
      if (barcodeList.isNotEmpty) {
        setState(() => isLoading = false);
        if (!mounted) return;
        SnackbarUtil.show(
          context,
          title: 'Mode Offline',
          message: 'Voucher hanya bisa digunakan saat online.',
          status: SnackBarStatus.warning,
        );
        return;
      }

      // Validasi stok lokal via BOM
      final lacking = await OfflineStockService.validateDetailed(cartItems);
      if (lacking.isNotEmpty) {
        setState(() => isLoading = false);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => ModalInsufficientStock(items: lacking),
        );
        return;
      }

      // Bangun payload dan simpan ke antrian
      final offlineOrder = await _buildOfflineOrderPayload(idempotencyKey);
      await PendingOrderService.enqueue(offlineOrder);
      await OfflineStockService.applyDecrement(cartItems);
      // Order sudah masuk antrian → kosongkan cart lokal agar transaksi
      // berikutnya mulai dari awal.
      await OfflineStockService.clearCartSnapshot();
      // Item yang berasal dari cart server (sudah pernah ter-migrasi, tanpa
      // flag _offline) harus dihapus juga dari server saat online — kalau tidak,
      // item yang sudah dibayar offline akan muncul lagi di keranjang.
      await OfflineCartSync.markForServerDeletion(
        cartItems
            .where((e) => e['_offline'] != true && e['id'] is int)
            .map((e) => e['id'] as int)
            .toList(),
      );

      final bool isNonTunai = selectedTab == 1;

      // Non-tunai dibayar pas (tanpa kembalian). Tunai bisa rounded/custom.
      final int payAmount = isNonTunai
          ? totalPayment
          : selectedPayment == 'rounded'
          ? roundedAmount
          : selectedPayment == 'custom'
          ? customAmount
          : totalPayment;

      int kembalian = isNonTunai ? 0 : payAmount - totalPayment;
      if (kembalian < 0) kembalian = 0;

      _idempotencyKey = null;
      isTargetNotifier.value = true;

      _runBestEffort(
        () async => BluetoothPrinterService.printStruk(
          listProduk: cartItems,
          totalQuantity: totalQuantity,
          documentNumber:
              'OFFLINE-${idempotencyKey.substring(0, 8).toUpperCase()}',
          usersName: userName,
          isCash: !isNonTunai,
          method: selectedMethodName,
          paymentMethod: isNonTunai ? selectedPaymentNonTunai : null,
          totalPayment: totalPayment,
          subTotal: subTotal,
          payment: payAmount,
          isPayment: true,
        ),
      );

      // Ambil foto lampiran & simpan lokal — wajib seperti transaksi online.
      // Diunggah otomatis saat order tersinkron ke server.
      _runBestEffort(() => _captureLampiranOffline(idempotencyKey));

      // Sync akan jalan di background saat online lagi (via OfflineSyncManager)
      OfflineSyncManager.syncNow();

      if (!mounted) return;
      setState(() => isLoading = false);
      paymentSuccessModal(kembalian);
      return;
      // ── AKHIR BLOK OFFLINE ──────────────────────────────────────────────
    }

    int? orderId;
    late Future<void> printFuture;

    late Timer slowTimer;
    slowTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) _showSlowExecutionDialog();
    });

    try {
      if (selectedMethodName != 'Compliment') {
        if (selectedTab == 0) {
          finalPayment = totalPayment - nominalVoucher;

          if (selectedPayment == 'rounded') {
            finalPayment = roundedAmount;
          } else if (selectedPayment == 'custom') {
            finalPayment = customAmount;
          }

          final totalAmount = totalPayment - nominalVoucher;

          final validationError = _validateOrderPayload(
            shiftIdVal: shiftId,
            userIdVal: userId,
            customerIdVal: customerId,
            orderMethodIdStr: selectedMethodId,
            paymentMethodIdStr: null,
            subTotalVal: subTotal,
            totalAmountVal: totalAmount,
            payAmountVal: finalPayment,
          );
          if (validationError != null) {
            if (!mounted) return;
            SnackbarUtil.show(
              context,
              title: "Data Tidak Valid",
              message: validationError,
              status: SnackBarStatus.warning,
            );
            debugPrint(
              'handlePayment validation failed (tunai): $validationError',
            );
            return;
          }

          Map<String, dynamic> payloadOrder = {
            "customers_id": 16,
            "pos_shifts_id": shiftId,
            "outlet_hub_id": int.parse(customerId!),
            "users_id": userId,
            "pos_payment_method_id": 11,
            "pos_order_method_id": int.parse(selectedMethodId),
            "subtotal_amount": subTotal,
            "discount_amount": subTotal - totalPayment + nominalVoucher,
            "tax_amount": 0.00,
            "total_amount": totalAmount,
            "pay_amount": finalPayment,
            "voucher_barcodes": barcodeList,
            "is_cash": 1,
            "token_orders": idempotencyKey,
            "latitude": _latitude,
            "longitude": _longitude,
            "device_info": _deviceInfo,
          };

          final orderData = await _executeOrderPost(
            payloadOrder,
            idempotencyKey,
          );
          orderId = orderData['id'];
          final documentNumber = orderData['document_number'] as String;

          printFuture = BluetoothPrinterService.printStruk(
            listProduk: cartItems,
            totalQuantity: totalQuantity,
            documentNumber: documentNumber,
            usersName: userName,
            isCash: true,
            method: selectedMethodName,
            totalPayment: totalPayment,
            subTotal: subTotal,
            payment: finalPayment,
            isPayment: true,
          );
        } else {
          final totalAmount = totalPayment - nominalVoucher;

          final validationError = _validateOrderPayload(
            shiftIdVal: shiftId,
            userIdVal: userId,
            customerIdVal: customerId,
            orderMethodIdStr: selectedMethodId,
            paymentMethodIdStr: selectedPaymentNonTunaiId,
            subTotalVal: subTotal,
            totalAmountVal: totalAmount,
            payAmountVal: totalAmount,
          );
          if (validationError != null) {
            if (!mounted) return;
            SnackbarUtil.show(
              context,
              title: "Data Tidak Valid",
              message: validationError,
              status: SnackBarStatus.warning,
            );
            debugPrint(
              'handlePayment validation failed (non-tunai): $validationError',
            );
            return;
          }

          Map<String, dynamic> payloadOrder = {
            "customers_id": 16,
            "pos_shifts_id": shiftId,
            "outlet_hub_id": int.parse(customerId!),
            "users_id": userId,
            "pos_payment_method_id": int.parse(selectedPaymentNonTunaiId),
            "pos_order_method_id": int.parse(selectedMethodId),
            "subtotal_amount": subTotal,
            "discount_amount": subTotal - totalPayment + nominalVoucher,
            "tax_amount": 0.00,
            "total_amount": totalAmount,
            "pay_amount": totalAmount,
            "voucher_barcodes": barcodeList,
            "is_cash": 0,
            "token_orders": idempotencyKey,
            "latitude": _latitude,
            "longitude": _longitude,
            "device_info": _deviceInfo,
          };

          final orderData = await _executeOrderPost(
            payloadOrder,
            idempotencyKey,
          );
          orderId = orderData['id'];
          final documentNumber = orderData['document_number'] as String;

          printFuture = BluetoothPrinterService.printStruk(
            listProduk: cartItems,
            totalQuantity: totalQuantity,
            documentNumber: documentNumber,
            usersName: userName,
            isCash: false,
            method: selectedMethodName,
            totalPayment: totalPayment,
            subTotal: subTotal,
            paymentMethod: selectedPaymentNonTunai,
            isPayment: true,
          );
        }
      } else {
        // Cancel slowTimer sementara — jangan trigger "Proses Lambat" saat user mengetik remarks
        slowTimer.cancel();

        final proceed = await showRemarksModal();

        if (!proceed) return;

        // Restart slowTimer setelah modal — sekarang dimulai real request
        slowTimer = Timer(const Duration(seconds: 15), () {
          if (mounted) _showSlowExecutionDialog();
        });

        final totalAmount = totalPayment - nominalVoucher;

        final validationError = _validateOrderPayload(
          shiftIdVal: shiftId,
          userIdVal: userId,
          customerIdVal: customerId,
          orderMethodIdStr: selectedMethodId,
          paymentMethodIdStr: null,
          subTotalVal: subTotal,
          totalAmountVal: totalAmount,
          payAmountVal: null,
        );
        if (validationError != null) {
          if (!mounted) return;
          SnackbarUtil.show(
            context,
            title: "Data Tidak Valid",
            message: validationError,
            status: SnackBarStatus.warning,
          );
          debugPrint(
            'handlePayment validation failed (compliment): $validationError',
          );
          return;
        }

        Map<String, dynamic> payloadOrder = {
          "customers_id": 16,
          "pos_shifts_id": shiftId,
          "outlet_hub_id": int.parse(customerId!),
          "users_id": userId,
          "pos_payment_method_id": 11,
          "pos_order_method_id": int.parse(selectedMethodId),
          "subtotal_amount": subTotal,
          "discount_amount": subTotal - totalPayment + nominalVoucher,
          "tax_amount": 0.00,
          "total_amount": totalAmount,
          "pay_amount": totalAmount,
          "is_cash": 1,
          "voucher_barcodes": barcodeList,
          "keterangan": _keteranganCompliment.text,
          "token_orders": idempotencyKey,
          "latitude": _latitude,
          "longitude": _longitude,
          "device_info": _deviceInfo,
          "compliment_label": selectedComplementLabel,
        };

        final orderData = await _executeOrderPost(payloadOrder, idempotencyKey);
        orderId = orderData['id'];
        final documentNumber = orderData['document_number'] as String;

        printFuture = BluetoothPrinterService.printStruk(
          listProduk: cartItems,
          totalQuantity: totalQuantity,
          documentNumber: documentNumber,
          usersName: userName,
          isCash: true,
          method: selectedMethodName,
          totalPayment: totalPayment,
          subTotal: subTotal,
          payment: totalPayment,
          isPayment: true,
        );
      }

      // ✓ Order sudah aman tersimpan di server. Segera tampilkan sukses & clear cart
      // sebelum menjalankan print/upload.
      // Reset idempotency token — pembayaran berikutnya harus pakai token baru.
      _idempotencyKey = null;
      isTargetNotifier.value = true;
      await clearVouchers();

      int kembalian = 0;
      if (selectedTab == 0) {
        final int yangHarusDibayar = totalPayment - nominalVoucher;
        if (selectedPayment == 'rounded') {
          kembalian = roundedAmount - yangHarusDibayar;
        } else if (selectedPayment == 'custom') {
          kembalian = customAmount - yangHarusDibayar;
        }
        if (kembalian < 0) kembalian = 0;
      }

      paymentSuccessModal(kembalian);

      // Print & upload dijalankan sebagai best-effort (fire-and-forget).
      // Jika printer/kamera error, tidak akan mengubah status order yang sudah tersimpan.
      _runBestEffort(() async => await printFuture);

      _runBestEffort(() async {
        await cameraService.initialize();
        final file = await cameraService.capture();
        if (file == null) return;

        final mimeType =
            lookupMimeType(file.path) ?? 'application/octet-stream';
        final formData = FormData.fromMap({
          "pos_orders_id": orderId,
          "name": file.path.split('/').last,
          "mime_type": mimeType,
          "file": await MultipartFile.fromFile(
            file.path,
            filename: file.path.split('/').last,
          ),
        });
        await orderService.postLampiran(formData);
      });

      if (!mounted) return;

      if (kembalian == 0 && !_navigated) {
        // Auto-navigate hanya jika user belum manual navigate dari modal
        await Future.delayed(const Duration(seconds: 5));
        if (!mounted || _navigated) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WidgetTree()),
          (route) => false,
        );
      }
    } on DioException catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'payment_page.handlePayment',
        context: {
          'endpoint': e.requestOptions.path,
          'statusCode': e.response?.statusCode,
          'responseData': e.response?.data?.toString(),
        },
      );
      if (!mounted) return;
      final String message =
          e.response?.data?['message'] ?? 'Terjadi kesalahan';
      SnackbarUtil.show(
        context,
        title: "Terjadi Kesalahan",
        message: message,
        status: SnackBarStatus.error,
      );
      paymentErrorModal();
    } catch (e, stack) {
      // Tangkap exception lain (printer disconnect, camera error, format error, dll).
      // Order mungkin sudah tersimpan jika error terjadi setelah postOrder.
      CrashReporter.report(
        e,
        stack,
        reason: 'payment_page.handlePayment (non-Dio)',
      );
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: "Terjadi Kesalahan",
        message: "Error: ${e.toString().replaceAll('Exception: ', '')}",
        status: SnackBarStatus.error,
      );
      // Jangan tampilkan paymentErrorModal di sini karena mungkin order sudah tersimpan.
      // User bisa retry atau navigasi manual.
    } finally {
      slowTimer.cancel();
      cameraService.dispose();
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Format waktu RFC3339 lengkap dengan offset zona waktu lokal, mis.
  /// `2026-06-08T09:58:49.014571+08:00`. Server (Go) menolak timestamp tanpa
  /// offset, sedangkan `DateTime.toIso8601String()` lokal tidak menyertakannya.
  static String _rfc3339WithOffset(DateTime dt) {
    final local = dt.toLocal();
    final off = local.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final h = off.inHours.abs().toString().padLeft(2, '0');
    final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${local.toIso8601String()}$sign$h:$m';
  }

  /// Ambil foto lampiran saat transaksi offline lalu simpan ke local storage
  /// (key = client_ref). File disalin ke direktori dokumen agar tidak hilang
  /// sebelum tersinkron. Diunggah otomatis oleh [PendingLampiranService] saat
  /// order-nya berhasil dikirim ke server. Best-effort: tidak memblok pembayaran.
  Future<void> _captureLampiranOffline(String clientRef) async {
    try {
      await cameraService.initialize();
      final file = await cameraService.capture();
      if (file == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final ext = file.path.contains('.') ? file.path.split('.').last : 'jpg';
      final dest = '${dir.path}/lampiran_$clientRef.$ext';
      await file.copy(dest);

      await PendingLampiranService.save(clientRef, dest);
    } catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'payment_page._captureLampiranOffline',
      );
    } finally {
      await cameraService.dispose();
    }
  }

  /// Bangun payload offline sesuai kontrak POST /pos/order/sync (§2.2 offlineMode.md).
  Future<Map<String, dynamic>> _buildOfflineOrderPayload(
    String clientRef,
  ) async {
    final snap = await OfflineStockService.getSnapshot();
    final bomIndex = snap != null
        ? BomCalculator.indexBom(snap['bom'] as List? ?? [])
        : <int, List<Map<String, dynamic>>>{};

    final lines = cartItems.map((item) {
      final materials = BomCalculator.materialsForLine(item, bomIndex);
      return <String, dynamic>{
        'pos_menus_id': item['pos_menus_id'],
        'pos_menus_name': item['pos_menus_name'],
        'quantity': item['quantity'],
        'price': item['price'],
        'subtotal': item['subtotal'] ?? 0,
        'discount': item['discount'] ?? 0,
        'tax': item['tax'] ?? 0,
        'total': item['total'] ?? 0,
        'pos_order_lines_props': (item['pos_cart_props'] as List? ?? [])
            .map(
              (p) => {
                'pos_menus_id': p['pos_menus_id'],
                // Sertakan nama sub-item/varian (untuk menu paket).
                'pos_menus_name': p['pos_menus_name'],
                'quantity': p['quantity'],
              },
            )
            .toList(),
        'pos_order_lines_material': materials.entries
            .map((e) => {'items_id': e.key, 'qty_nisik': e.value})
            .toList(),
      };
    }).toList();

    final bool isNonTunai = selectedTab == 1;

    // Non-tunai: dibayar pas. Tunai: bisa rounded/custom (ada kembalian).
    final int payAmount = isNonTunai
        ? totalPayment
        : selectedPayment == 'rounded'
        ? roundedAmount
        : selectedPayment == 'custom'
        ? customAmount
        : totalPayment;

    // Tunai → metode "cash" (11, is_cash 1). Non-tunai → metode terpilih.
    final int paymentMethodId = isNonTunai
        ? (int.tryParse(selectedPaymentNonTunaiId) ?? 11)
        : 11;

    return {
      'client_ref': clientRef,
      'created_at': _rfc3339WithOffset(DateTime.now()),
      'outlet_hub_id': int.tryParse(customerId ?? '') ?? 0,
      'pos_shifts_id': shiftId ?? 0,
      'users_id': userId ?? 0,
      'customers_id': 16,
      'pos_payment_method_id': paymentMethodId,
      'pos_order_method_id': int.tryParse(selectedMethodId) ?? 1,
      'is_cash': isNonTunai ? 0 : 1,
      'subtotal_amount': subTotal,
      'discount_amount': subTotal - totalPayment,
      'tax_amount': 0,
      'total_amount': totalPayment,
      'pay_amount': payAmount,
      'keterangan': '',
      'latitude': _latitude,
      'longitude': _longitude,
      'device_info': _deviceInfo,
      'pos_order_lines': lines,
    };
  }

  Future<void> getProfile() async {
    try {
      final response = await authService.getProfile();
      final data = response.data['data'];

      // Validasi bahwa data profile berisi field yang wajib
      final name = data?['name'];
      final uid = data?['userid'];

      if (name == null || name.toString().isEmpty) {
        throw StateError('Profile name tidak ditemukan atau kosong');
      }
      if (uid == null) {
        throw StateError('Profile userid tidak ditemukan');
      }

      final uidInt = uid is int ? uid : int.tryParse(uid.toString()) ?? 0;
      final cid =
          (data['customer'] is List && (data['customer'] as List).isNotEmpty)
          ? (data['customer'] as List)[0].toString()
          : null;

      // Segarkan cache profil agar tetap up-to-date untuk transaksi offline.
      await ProfileStorageService.save(
        userId: uidInt,
        userName: name.toString(),
        customerId: cid,
      );

      if (!mounted) return;
      setState(() {
        userName = name.toString();
        userId = uidInt;
        customerId = cid;
        isLoadingUserId = false;
      });
    } catch (e, stack) {
      // Offline / gagal → pulihkan dari profil yang disimpan saat login.
      final cached = await ProfileStorageService.get();
      if (cached != null && cached['userId'] != null) {
        if (!mounted) return;
        setState(() {
          userName = (cached['userName'] ?? userName).toString();
          userId = (cached['userId'] as num?)?.toInt();
          customerId = cached['customerId'] as String?;
          isLoadingUserId = false;
        });
        return;
      }

      CrashReporter.report(e, stack, reason: 'payment_page.getProfile');
      debugPrint("Gagal ambil user ID: $e");
      if (!mounted) return;
      setState(() => isLoadingUserId = false);
      SnackbarUtil.show(
        context,
        title: "Gagal memuat data pengguna",
        message:
            "Terjadi kendala saat mengambil data pengguna. Silakan login ulang.",
        status: SnackBarStatus.error,
      );
    }
  }

  /// Default order method ke "Takeaway" kalau user belum memilih.
  void _applyDefaultOrderMethod() {
    if (selectedMethodId.isNotEmpty) return;
    final takeaway = orderMethods.firstWhere(
      (m) => (m['name'] ?? '').toString().toLowerCase() == 'takeaway',
      orElse: () => const {},
    );
    if (takeaway.isNotEmpty) {
      selectedMethodName = takeaway['name'].toString();
      selectedMethodId = takeaway['id'].toString();
    }
  }

  Future<void> _methods() async {
    try {
      final results = await Future.wait([
        methodService.getPaymentMethods(),
        methodService.getOrderMethods(),
      ]);

      paymentMethods = List<Map<String, dynamic>>.from(results[0].data['data']);
      orderMethods = List<Map<String, dynamic>>.from(results[1].data['data']);

      // Segarkan cache supaya halaman pembayaran tetap jalan saat offline.
      await MethodStorageService.save(paymentMethods, orderMethods);

      if (!mounted) return;
      setState(() {
        isLoadingMethod = false;
        methodsLoadError = null;
        _applyDefaultOrderMethod();
      });
    } catch (e, stack) {
      // Offline / gagal → pakai metode yang disimpan saat login.
      final cachedPayment = await MethodStorageService.getPaymentMethods();
      final cachedOrder = await MethodStorageService.getOrderMethods();
      if (cachedPayment.isNotEmpty && cachedOrder.isNotEmpty) {
        paymentMethods = cachedPayment;
        orderMethods = cachedOrder;
        if (!mounted) return;
        setState(() {
          isLoadingMethod = false;
          methodsLoadError = null;
          _applyDefaultOrderMethod();
        });
        return;
      }

      CrashReporter.report(e, stack, reason: 'payment_page._methods');
      debugPrint("Error fetching methods: $e");
      if (!mounted) return;
      setState(() {
        methodsLoadError =
            "Gagal memuat metode pembayaran. Periksa koneksi internet Anda.";
      });
    }
  }

  Future<void> _loadShiftId() async {
    final result = await ShiftStorageService.getShiftId();
    if (!mounted) return;
    setState(() {
      shiftId = result;
    });
  }

  Widget _buildComplementOption({
    required String label,
    required IconData icon,
    required int value,
    required int selected,
    required VoidCallback onTap,
  }) {
    final bool isSelected = selected == value;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected ? AppColors.primary : Colors.grey.shade500,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.primary : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> showRemarksModal() async {
    // Reset tiap modal dibuka supaya user wajib memilih ulang.
    int localLabel = 0;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              title: const Row(
                children: [
                  Icon(Icons.note_add_rounded, color: AppColors.primaryDarkest),
                  SizedBox(width: 12),
                  Text(
                    "Keterangan Compliment",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Pilih jenis compliment terlebih dahulu. Wajib dipilih.",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    StatefulBuilder(
                      builder: (context, setModalState) {
                        return Row(
                          children: [
                            Expanded(
                              child: _buildComplementOption(
                                label: 'Sample',
                                icon: Icons.science_outlined,
                                value: 1,
                                selected: localLabel,
                                onTap: () =>
                                    setModalState(() => localLabel = 1),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildComplementOption(
                                label: 'Biaya Pemasaran',
                                icon: Icons.campaign_outlined,
                                value: 2,
                                selected: localLabel,
                                onTap: () =>
                                    setModalState(() => localLabel = 2),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Berikan penjelasan atau catatan terkait compliment ini. Bagian ini wajib diisi.",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _keteranganCompliment,
                      maxLines: 3,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "Contoh: Permintaan Pak Agung, dll.",
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                        labelText: "Detail Keterangan *",
                        labelStyle: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        alignLabelWithHint: true,
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
              actions: [
                TextButton(
                  onPressed: () => {Navigator.pop(context, false)},
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                  ),
                  child: const Text(
                    "Batal",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                  onPressed: () {
                    final text = _keteranganCompliment.text.trim();

                    if (localLabel == 0) {
                      SnackbarUtil.show(
                        context,
                        title: "Pilihan Wajib",
                        message: "Pilih jenis compliment terlebih dahulu",
                        status: SnackBarStatus.warning,
                      );
                      return;
                    }
                    if (text.isEmpty) {
                      SnackbarUtil.show(
                        context,
                        title: "Input Wajib",
                        message: "Silakan isi keterangan terlebih dahulu",
                        status: SnackBarStatus.warning,
                      );
                      return;
                    }
                    selectedComplementLabel = localLabel;
                    Navigator.pop(context, true);
                  },
                  child: const Text(
                    "Lanjutkan",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> paymentErrorModal() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.all(24.0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Ikon Sukses
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.dangerous_rounded,
                  color: Colors.red,
                  size: 64,
                ),
              ),
              const SizedBox(height: 20),

              // 2. Judul
              const Text(
                'Transaksi Gagal!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // 3. Deskripsi/Pesan
              Text(
                'Transaksi Gagal diproses. Anda akan di pindahkan ke halaman Utama.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    selectedPageNotifier.value = 0;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const WidgetTree()),
                      (route) => false,
                    );
                  },
                  child: const Text(
                    'Selesai',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> paymentSuccessModal(int kembalian) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.all(24.0),
          content: Column(
            mainAxisSize: MainAxisSize.min, // Agar tinggi mengikuti isi konten
            children: [
              // 1. Ikon Sukses
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 64,
                ),
              ),
              const SizedBox(height: 20),

              // 2. Judul
              const Text(
                'Transaksi Berhasil!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // 3. Deskripsi/Pesan
              Text(
                'Transaksi telah berhasil diproses. Lihat bukti pembayaran pada menu "Riwayat Penjualan".',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              if (kembalian > 0) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Kembalian',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        convertIDR(kembalian),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // 4. Tombol Aksi
              SizedBox(
                width: double.infinity, // Membuat tombol menjadi full-width
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, // Warna background tombol
                    foregroundColor: Colors.white, // Warna teks tombol
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    _navigated = true; // Set flag sebelum navigate
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const WidgetTree()),
                      (route) => false,
                    );
                  },
                  child: const Text(
                    'Selesai',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> voucherSuccessModal() async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.all(24.0),
          content: Column(
            mainAxisSize: MainAxisSize.min, // Agar tinggi mengikuti isi konten
            children: [
              // 1. Ikon Sukses
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 64,
                ),
              ),
              const SizedBox(height: 20),

              // 2. Judul
              const Text(
                'Voucher Ditambahkan!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // 3. Deskripsi/Pesan
              Text(
                'Voucher telah berhasil ditambahkan ke pembayaran',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // 4. Tombol Aksi
              SizedBox(
                width: double.infinity, // Membuat tombol menjadi full-width
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, // Warna background tombol
                    foregroundColor: Colors.white, // Warna teks tombol
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Selesai',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> voucherErrorModal() async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.all(24.0),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize:
                  MainAxisSize.min, // Agar tinggi mengikuti isi konten
              children: [
                // 1. Ikon Sukses
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.dangerous_rounded,
                    color: Colors.red,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Judul
                const Text(
                  'Voucher gagal ditambahkan!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // 3. Deskripsi/Pesan
                Text(
                  'Voucher gagal ditambahkan ke pembayaran. Voucher mungkin sudah digunakan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // 4. Tombol Aksi
                SizedBox(
                  width: double.infinity, // Membuat tombol menjadi full-width
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red, // Warna background tombol
                      foregroundColor: Colors.white, // Warna teks tombol
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'Selesai',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> checkVoucher() async {
    _dismissKeyboard();

    try {
      final payload = {"barcode": _voucherController.text};
      final response = await orderService.checkVoucher(payload);

      final data = response.data['data'];
      final String newBarcode = data['barcode'];
      final int nominal = data['nominal'];

      await saveVoucherToLocal(newBarcode, nominal);
      await getVoucherData();
    } on DioException catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'payment_page.checkVoucher',
        context: {
          'endpoint': e.requestOptions.path,
          'statusCode': e.response?.statusCode,
          'responseData': e.response?.data?.toString(),
        },
      );
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: "Voucher Gagal",
        message: "Terjadi kesalahan saat mengecek voucher.",
        status: SnackBarStatus.error,
      );
    }
  }

  Future<void> saveVoucherToLocal(String newBarcode, int nominal) async {
    final prefs = await SharedPreferences.getInstance();

    // Ambil list barcode yang sudah tersimpan
    final String? storedBarcodes = prefs.getString('voucher_barcodes');
    List<String> localBarcodes = storedBarcodes != null
        ? List<String>.from(jsonDecode(storedBarcodes))
        : [];

    // Cek apakah barcode sudah ada (mencegah double)
    if (localBarcodes.contains(newBarcode)) {
      voucherErrorModal();
      return;
    } else {
      voucherSuccessModal();
    }

    // Tambahkan barcode baru ke list
    localBarcodes.add(newBarcode);
    await prefs.setString('voucher_barcodes', jsonEncode(localBarcodes));

    // Tambahkan nominal
    final int currentNominal = prefs.getInt('voucher_nominal') ?? 0;
    await prefs.setInt('voucher_nominal', currentNominal + nominal);
  }

  Future<void> getVoucherData() async {
    final prefs = await SharedPreferences.getInstance();

    final String? storedBarcodes = prefs.getString('voucher_barcodes');
    final List<String> newBarcodeList = storedBarcodes != null
        ? List<String>.from(jsonDecode(storedBarcodes))
        : [];
    final int totalNominal = prefs.getInt('voucher_nominal') ?? 0;
    setState(() {
      barcodeList = newBarcodeList;
      nominalVoucher = totalNominal;
    });
  }

  Future<void> clearVouchers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('voucher_barcodes');
    await prefs.remove('voucher_nominal');
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _idempotencyKey = null;
    _bluetoothSubscription?.cancel();
    _customAmountController.dispose();
    _voucherController.dispose();
    _keteranganCompliment.dispose();
    _ongkirController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isLoading,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // User tried to navigate back during payment — show warning
        SnackbarUtil.show(
          context,
          title: "Transaksi Sedang Berlangsung",
          message: "Tunggu hingga pembayaran selesai",
          status: SnackBarStatus.warning,
        );
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          actions: const [NetworkIndicatorWidget()],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: Colors.grey[300], height: 1),
          ),
        ),
        body: isLoadingCart || isLoadingMethod || isLoadingUserId
            ? Center(
                child: methodsLoadError != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.error_outline_rounded,
                                color: Colors.red,
                                size: 64,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Gagal Memuat Data',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              methodsLoadError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  methodsLoadError = null;
                                  isLoadingMethod = true;
                                });
                                _methods();
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Coba Lagi'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ModernLoading(
                        timeout: const Duration(seconds: 10),
                        onRetry: () {
                          setState(() {
                            isLoadingCart = true;
                            isLoadingMethod = true;
                            isLoadingUserId = true;
                            methodsLoadError = null;
                          });
                          loadCart();
                          _methods();
                          getProfile();
                        },
                      ),
              )
            : Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Container(
                      height: double.infinity,
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: Colors.black26),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Container(
                          //   padding: EdgeInsets.all(10),
                          //   color: Colors.black12,
                          //   width: double.infinity,
                          //   child: Text('Total Produk ( $totalQuantity )'),
                          // ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors
                                  .grey[50], // Abu-abu sangat muda agar tidak "mati"
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.withValues(alpha: 0.2),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 18,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Ringkasan Pesanan ( $totalQuantity Produk )',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Expanded(
                            child: Stack(
                              children: [
                                ListView.separated(
                                  // Lebih efisien daripada SingleChildScrollView + Column
                                  controller: _scrollController,
                                  padding: const EdgeInsets.all(16),
                                  itemCount: cartItems.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final e = cartItems[index];
                                    return Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Info Produk
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  e['pos_menus_name'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),

                                                // Render Add-ons / Materials dengan style yang lebih soft
                                                if (e['pos_cart_props'] != null)
                                                  ...((e['pos_cart_props']
                                                          as List)
                                                      .where(
                                                        (item) =>
                                                            item['quantity'] !=
                                                            0,
                                                      )
                                                      .map(
                                                        (item) => Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 4,
                                                              ),
                                                          child: Text(
                                                            '• ${item['quantity']}x ${item['pos_menus_name']}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors
                                                                  .grey[600],
                                                            ),
                                                          ),
                                                        ),
                                                      )),

                                                const SizedBox(height: 8),

                                                // Harga & Diskon
                                                Row(
                                                  children: [
                                                    Text(
                                                      convertIDR(e['total']),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    if ((e['discount'] ?? 0) +
                                                            (e['discount_val'] ??
                                                                0) !=
                                                        0)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              left: 8.0,
                                                            ),
                                                        child: Text(
                                                          '-${convertIDR(e['subtotal'] - e['total'])}',
                                                          style: const TextStyle(
                                                            color: Colors.red,
                                                            fontSize: 12,
                                                            decoration:
                                                                TextDecoration
                                                                    .lineThrough,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Quantity Badge
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryLight,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${e['quantity']} PCS',
                                              style: const TextStyle(
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                                // 3. Bottom Fade Overlay (Visual Guide for Scrolling)
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: IgnorePointer(
                                    child: AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      opacity: fadeOpacity,
                                      child: Container(
                                        height: 60,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.black.withValues(alpha: 0),
                                              Colors.black.withValues(
                                                alpha: 0.1,
                                              ),
                                              Colors.black12,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1. Voucher Input Section
                              // Container(
                              //   padding: const EdgeInsets.fromLTRB(
                              //     16,
                              //     12,
                              //     16,
                              //     16,
                              //   ),
                              //   decoration: BoxDecoration(
                              //     color: Colors.white,
                              //     border: Border(
                              //       top: BorderSide(
                              //         color: Colors.grey.withValues(alpha: 0.1),
                              //       ),
                              //     ),
                              //   ),
                              //   child: Row(
                              //     children: [
                              //       Expanded(
                              //         child: SizedBox(
                              //           height:
                              //               42, // Tinggi sedikit dinaikkan agar lebih touch-friendly
                              //           child: TextField(
                              //             controller: _voucherController,
                              //             focusNode: _voucherFocusNode,
                              //             decoration: InputDecoration(
                              //               hintText: 'Punya kode voucher?',
                              //               hintStyle: TextStyle(
                              //                 fontSize: 14,
                              //                 color: Colors.grey[400],
                              //               ),
                              //               prefixIcon: const Icon(
                              //                 Icons.confirmation_number_outlined,
                              //                 size: 20,
                              //               ),
                              //               contentPadding:
                              //                   const EdgeInsets.symmetric(
                              //                     horizontal: 16,
                              //                   ),
                              //               filled: true,
                              //               fillColor: Colors.grey[50],
                              //               enabledBorder: OutlineInputBorder(
                              //                 borderRadius: BorderRadius.circular(
                              //                   10,
                              //                 ),
                              //                 borderSide: BorderSide(
                              //                   color: Colors.grey.withValues(alpha:
                              //                     0.2,
                              //                   ),
                              //                 ),
                              //               ),
                              //               focusedBorder: OutlineInputBorder(
                              //                 borderRadius: BorderRadius.circular(
                              //                   10,
                              //                 ),
                              //                 borderSide: const BorderSide(
                              //                   color: Colors.amber,
                              //                   width: 1.5,
                              //                 ),
                              //               ),
                              //             ),
                              //           ),
                              //         ),
                              //       ),
                              //       const SizedBox(width: 12),
                              //       SizedBox(
                              //         height: 42,
                              //         child: ElevatedButton(
                              //           onPressed: () async {
                              //             _voucherFocusNode.unfocus();
                              //             await checkVoucher();
                              //           },
                              //           style: ElevatedButton.styleFrom(
                              //             backgroundColor: Colors.black87,
                              //             foregroundColor: Colors.amber,
                              //             elevation: 0,
                              //             shape: RoundedRectangleBorder(
                              //               borderRadius: BorderRadius.circular(
                              //                 10,
                              //               ),
                              //             ),
                              //           ),
                              //           child: const Text(
                              //             'Cek',
                              //             style: TextStyle(
                              //               fontWeight: FontWeight.bold,
                              //             ),
                              //           ),
                              //         ),
                              //       ),
                              //     ],
                              //   ),
                              // ),

                              // 2. Billing Details Section
                              if (MediaQuery.of(context).viewInsets.bottom == 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, -5),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      // Subtotal Row
                                      _buildSummaryRow(
                                        'Subtotal',
                                        convertIDR(subTotal),
                                        isBold: false,
                                      ),

                                      // Discount Row (Conditional)
                                      if (discount > 0) ...[
                                        const SizedBox(height: 8),
                                        _buildSummaryRow(
                                          'Diskon Produk',
                                          '- ${convertIDR(discount)}',
                                          textColor: Colors.red[600],
                                        ),
                                      ],

                                      // Voucher Row (Conditional)
                                      if (nominalVoucher > 0) ...[
                                        const SizedBox(height: 8),
                                        _buildSummaryRow(
                                          'Diskon Voucher',
                                          '- ${convertIDR(nominalVoucher)}',
                                          textColor: Colors.red[600],
                                        ),
                                      ],

                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Divider(height: 1, thickness: 1),
                                      ),

                                      // Total Payment Row
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Total Bayar',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            convertIDR(
                                              totalPayment - nominalVoucher,
                                            ),
                                            style: const TextStyle(
                                              fontSize:
                                                  22, // Menonjolkan angka utama
                                              fontWeight: FontWeight.w900,
                                              color: AppColors
                                                  .primary, // Menggunakan warna tema brand
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.accent, AppColors.accentDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: const Border(
                              bottom: BorderSide(color: Colors.black26),
                            ),
                          ),
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            children: [
                              const Text(
                                'Total Penerimaan',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black45,
                                ),
                              ),
                              Text(
                                convertIDR(totalPayment - nominalVoucher),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                  fontSize: 30.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            _buildTabItem(index: 0, title: "Tunai"),
                            _buildTabItem(index: 1, title: "Non Tunai"),
                          ],
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Container(
                              padding: const EdgeInsets.all(20.0),
                              child: selectedTab == 0
                                  ? tunaiSection()
                                  : nonTunaiSection(),
                            ),
                          ),
                        ),
                        if (MediaQuery.of(context).viewInsets.bottom == 0)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, -5),
                                ),
                              ],
                            ),
                            child: SizedBox(
                              height:
                                  45, // Memberikan tinggi yang konsisten agar mudah ditekan (touch-friendly)
                              child: ElevatedButton(
                                onPressed:
                                    (isLoading ||
                                        (selectedTab == 0 &&
                                            selectedPayment == "custom" &&
                                            customAmount <
                                                totalPayment - nominalVoucher))
                                    ? null
                                    : _confirmAndPay,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primarySelected,
                                  disabledBackgroundColor: Colors
                                      .grey
                                      .shade300, // Warna saat loading/disable
                                  elevation:
                                      0, // Flat design lebih modern untuk POS
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      12,
                                    ), // Border radius sedikit lebih lembut
                                  ),
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                AppColors.primary,
                                              ),
                                        ),
                                      )
                                    : const Text(
                                        'Selesaikan Pembayaran',
                                        style: TextStyle(
                                          fontSize: 16.0,
                                          color: AppColors.white,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ), // closes Scaffold
    ); // closes PopScope
  }

  Widget tunaiSection() {
    bool isValidCustom = customAmount >= totalPayment - nominalVoucher;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Metode Penerimaan",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10.0),
        Row(
          children: [
            CustomChipCheckbox(
              label: convertIDR(exactAmount - nominalVoucher),
              isSelected: selectedPayment == "exact",
              onSelect: () => setState(() => selectedPayment = "exact"),
            ),
            const SizedBox(width: 12),
            CustomChipCheckbox(
              label: convertIDR(roundedAmount),
              isSelected: selectedPayment == "rounded",
              onSelect: () => setState(() => selectedPayment = "rounded"),
            ),
            const SizedBox(width: 12),
            CustomChipCheckbox(
              label: "Custom",
              isSelected: selectedPayment == "custom",
              onSelect: () => setState(() => selectedPayment = "custom"),
            ),
          ],
        ),
        if (selectedPayment == "custom") ...[
          const SizedBox(height: 20),
          TextField(
            controller: _customAmountController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              RupiahFormatter(),
            ],
            decoration: InputDecoration(
              labelText: "Masukkan Nominal",
              errorText: isValidCustom
                  ? null
                  : "Nominal harus lebih besar dari total penerimaan",
              border: const OutlineInputBorder(),
            ),
            onChanged: (val) {
              setState(() {
                customAmount = parseRupiah(val);
              });
            },
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          "Metode",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10.0),
        methodPaymnet(),
      ],
    );
  }

  Widget nonTunaiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Metode Penerimaan",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10.0),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: paymentMethods.map((payment) {
            String name = payment['name'] ?? '';
            int id = payment['id'] ?? 0;
            return CustomChipCheckbox(
              label: name,
              isSelected: selectedPaymentNonTunai == name,
              onSelect: () => setState(() {
                selectedPaymentNonTunai = name;
                selectedPaymentNonTunaiId = id.toString();
              }),
            );
          }).toList(),
        ),

        const SizedBox(height: 20.0),
        const Text(
          "Metode",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10.0),
        methodPaymnet(),
      ],
    );
  }

  Widget methodPaymnet() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 12,
          children: orderMethods.map((method) {
            String name = method['name'] ?? '';
            int id = method['id'] ?? 0;
            if (selectedTab == 1 && id == 4) {
              return const SizedBox.shrink();
            }
            return CustomChipCheckbox(
              label: name,
              isSelected: selectedMethodName == name,
              onSelect: () {
                setState(() {
                  selectedMethodName = name;
                  selectedMethodId = id.toString();
                });
              },
            );
          }).toList(),
        ),
        if (_isDelivery && _ongkirEnabled) _ongkirField(),
      ],
    );
  }

  /// Input ongkos kirim — tampil & wajib hanya saat metode order = Delivery.
  Widget _ongkirField() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_shipping_rounded,
                size: 18,
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                'Ongkos Kirim',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '* wajib',
                style: TextStyle(fontSize: 12, color: Colors.red.shade600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ongkirController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) =>
                setState(() => _ongkir = int.tryParse(v.trim()) ?? 0),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              prefixText: 'Rp ',
              prefixStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              hintText: '0',
              isDense: true,
              filled: true,
              fillColor: Colors.blue.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.blue.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.blue.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.blue.shade700, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    Color? textColor,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: textColor ?? Colors.grey[600],
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: textColor ?? Colors.black87,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildTabItem({required int index, required String title}) {
    bool isSelected = selectedTab == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedTab = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected
                    ? AppColors.danger
                    : Colors.grey.withValues(alpha: 0.1),
                width: 3,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 16,
              color: isSelected ? AppColors.danger : Colors.grey[500],
            ),
          ),
        ),
      ),
    );
  }
}
