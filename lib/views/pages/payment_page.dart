import 'dart:async';
import 'dart:convert';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/camera_service.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/method_service.dart';
import 'package:pos_panglima_app/services/network_service.dart';
import 'package:pos_panglima_app/services/order_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/components/ui/custom_checkbox.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String? customerId;
  int? shiftId;
  late int nominalVoucher = 0;
  List<String> barcodeList = [];
  List<Map<String, dynamic>> paymentMethods = [];
  List<Map<String, dynamic>> orderMethods = [];
  final TextEditingController _customAmountController = TextEditingController();
  final TextEditingController _voucherController = TextEditingController();
  final TextEditingController _keteranganCompliment = TextEditingController();
  final FocusNode _voucherFocusNode = FocusNode();

  int roundToNearestTenThousand(int num) {
    return ((num + 9999) ~/ 10000) * 10000;
  }

  String selectedPayment = "exact";
  String selectedMethodName = "Takeaway";
  String selectedMethodId = "1";
  String selectedPaymentNonTunai = "QRIS";
  String selectedPaymentNonTunaiId = "1";
  int customAmount = 0;
  late int finalPayment = 0;

  int get exactAmount => totalPayment;
  int get roundedAmount =>
      roundToNearestTenThousand(totalPayment - nominalVoucher);

  @override
  void initState() {
    super.initState();

    _bluetoothSubscription = BluetoothPrinterService.bluetooth.onStateChanged().listen((state) {
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
  }

  Future<void> loadCart() async {
    try {
      final getCart = await cartService.getCart();
      final newItems = List<Map<String, dynamic>>.from(
        getCart.data['data'] ?? [],
      );

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

      setState(() {
        cartItems = newItems;
        totalPayment = newTotalPayment;
        subTotal = newSubtotal;
        discount = newDiscount;
        isLoadingCart = false;
        totalQuantity = newTotalQuantity;
      });
    } on DioException catch (e) {
      debugPrint('loadCart error: ${e.response?.data}');
    }
  }

  void handlePayment() async {
    setState(() => isLoading = true);
    bool online = await NetworkService.isOnline();

    if (!online) {
      setState(() => isLoading = false);
      SnackbarUtil.show(
        context,
        title: "Tidak Ada Koneksi",
        message: "Perangkat sedang offline, periksa koneksi internet Anda",
        status: SnackBarStatus.warning,
      );
      return;
    }

    int? orderId;

    try {
      if (selectedMethodName != 'Compliment') {
        if (selectedTab == 0) {
          finalPayment = totalPayment;

          if (selectedPayment == 'rounded') {
            finalPayment = roundedAmount;
          } else if (selectedPayment == 'custom') {
            finalPayment = customAmount;
          }

          Map<String, dynamic> payloadOrder = {
            "customers_id": 16, // default
            "pos_shifts_id": shiftId,
            "outlet_hub_id": int.tryParse(customerId.toString()) ?? 0,
            "users_id": userId,
            "pos_payment_method_id": 11,
            "pos_order_method_id":
                int.tryParse(selectedMethodId.toString()) ?? 0,
            "subtotal_amount": subTotal,
            "discount_amount": subTotal - totalPayment,
            "tax_amount": 0.00,
            "total_amount": totalPayment,
            "pay_amount": finalPayment,
            "voucher_barcodes": barcodeList,
            "is_cash": 1,
          };

          final response = await orderService.postOrder(payloadOrder);
          orderId = response.data['data']['id'];
          String documentNumber = response.data['data']['document_number'];

          await BluetoothPrinterService.printStruk(
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
          Map<String, dynamic> payloadOrder = {
            "customers_id": 16, // default
            "pos_shifts_id": shiftId,
            "outlet_hub_id": int.tryParse(customerId.toString()) ?? 0,
            "users_id": userId,
            "pos_payment_method_id":
                int.tryParse(selectedPaymentNonTunaiId.toString()) ?? 0,
            "pos_order_method_id":
                int.tryParse(selectedMethodId.toString()) ?? 0,
            "subtotal_amount": subTotal,
            "discount_amount": subTotal - totalPayment,
            "tax_amount": 0.00,
            "total_amount": totalPayment,
            "pay_amount": totalPayment,
            "voucher_barcodes": barcodeList,
            "is_cash": 0,
          };

          final response = await orderService.postOrder(payloadOrder);
          orderId = response.data['data']['id'];
          String documentNumber = response.data['data']['document_number'];

          await BluetoothPrinterService.printStruk(
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
        final proceed = await showRemarksModal();

        if (!proceed) return;

        Map<String, dynamic> payloadOrder = {
          "customers_id": 16, // default
          "pos_shifts_id": shiftId,
          "outlet_hub_id": int.tryParse(customerId.toString()) ?? 0,
          "users_id": userId,
          "pos_payment_method_id": 11,
          "pos_order_method_id": int.tryParse(selectedMethodId.toString()) ?? 0,
          "subtotal_amount": subTotal,
          "discount_amount": subTotal - totalPayment,
          "tax_amount": 0.00,
          "total_amount": totalPayment,
          "pay_amount": totalPayment,
          "is_cash": 1,
          "voucher_barcodes": barcodeList,
          "keterangan": _keteranganCompliment.text,
        };

        final response = await orderService.postOrder(payloadOrder);
        orderId = response.data['data']['id'];
        String documentNumber = response.data['data']['document_number'];

        await BluetoothPrinterService.printStruk(
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

      await cameraService.initialize();
      final file = await cameraService.capture();

      if (file == null) {
        return;
      }

      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';

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

      isTargetNotifier.value = true;

      await clearVouchers();

      await cameraService.dispose();

      int kembalian = 0;

      if (selectedTab == 0) {
        final int yangHarusDibayar = totalPayment - nominalVoucher;

        if (selectedPayment == 'exact') {
          kembalian = 0;
        } else if (selectedPayment == 'rounded') {
          kembalian = roundedAmount - yangHarusDibayar;
        } else if (selectedPayment == 'custom') {
          kembalian = customAmount - yangHarusDibayar;
        }

        if (kembalian < 0) kembalian = 0;
      }

      paymentSuccessModal(kembalian);

      if (!mounted) return;

      if (kembalian == 0) {
        await Future.delayed(const Duration(seconds: 5));
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => WidgetTree()),
          (route) => false,
        );
      }
    } on DioException catch (e) {
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
    }
  }

  Future<void> getProfile() async {
    try {
      final response = await authService.getProfile();
      final data = response.data['data'];

      if (!mounted) return;
      setState(() {
        userName = data?['name'];
        userId = data?['userid'];
        customerId = (data['customer'] is List && data['customer'].isNotEmpty)
            ? data['customer'][0]
            : null;
        isLoadingUserId = false;
      });
    } catch (e) {
      isLoadingUserId = false;
      debugPrint("Gagal ambil user ID: $e");
    }
  }

  Future<void> _methods() async {
    try {
      final response = await methodService.getPaymentMethods();
      paymentMethods = List<Map<String, dynamic>>.from(response.data['data']);

      final orderResponse = await methodService.getOrderMethods();
      orderMethods = List<Map<String, dynamic>>.from(
        orderResponse.data['data'],
      );
      setState(() => isLoadingMethod = false);
    } catch (e) {
      debugPrint("Error fetching methods: $e");
    }
  }

  Future<void> _loadShiftId() async {
    final result = await ShiftStorageService.getShiftId();
    setState(() {
      shiftId = result;
    });
  }

  Future<bool> showRemarksModal() async {
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
              title: Row(
                children: [
                  Icon(Icons.note_add_rounded, color: Colors.amber.shade900),
                  const SizedBox(width: 12),
                  const Text(
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
                          color: Colors.amber,
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
                            color: Colors.amber,
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
                  onPressed: () => Navigator.pop(context, false),
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
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black87,
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

                    if (text.isEmpty) {
                      SnackbarUtil.show(
                        context,
                        title: "Input Wajib",
                        message: "Silakan isi keterangan terlebih dahulu",
                        status: SnackBarStatus.warning,
                      );
                    } else {
                      Navigator.pop(context, true);
                    }
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
                  color: Colors.red.withOpacity(0.1),
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
                'Transaksi Gagal diproses. Silakan coba kembali.',
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

  Future<void> paymentSuccessModal(int kembalian) async {
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
                  color: Colors.green.withOpacity(0.1),
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

              SizedBox(height: 24),

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
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => WidgetTree()),
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
                  color: Colors.green.withOpacity(0.1),
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
                    color: Colors.red.withOpacity(0.1),
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
      debugPrint('postLampiran response: $response');
    } on DioException catch (e) {
      debugPrint('postLampiran DioException: ${e.response}');
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

    debugPrint('Barcodes: $barcodeList');
    debugPrint('Total Nominal: $totalNominal');
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
    _bluetoothSubscription?.cancel();
    _customAmountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Container(
            color: Colors.grey[300],
            height: 1, // tebal garis
          ),
        ),
      ),
      body: isLoadingCart || isLoadingMethod || isLoadingUserId
          ? Center(
              child: ModernLoading(
                timeout: const Duration(seconds: 10),
                onRetry: () {
                  setState(() {
                    isLoadingCart = true;
                    isLoadingMethod = true;
                    isLoadingUserId = true;
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
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: Colors.black26)),
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
                                color: Colors.grey.withOpacity(0.2),
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
                                        color: Colors.grey.withOpacity(0.3),
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
                                                          item['quantity'] != 0,
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
                                            color: Colors.amber[50],
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            '${e['quantity']} PCS',
                                            style: const TextStyle(
                                              color: Colors.orange,
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
                                    duration: const Duration(milliseconds: 300),
                                    opacity: fadeOpacity,
                                    child: Container(
                                      height: 60,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withOpacity(0),
                                            Colors.black.withOpacity(0.1),
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
                            //         color: Colors.grey.withOpacity(0.1),
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
                            //                   color: Colors.grey.withOpacity(
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
                                      color: Colors.black.withOpacity(0.05),
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
                                            color: Colors
                                                .amber, // Menggunakan warna tema brand
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
                          border: Border(
                            bottom: BorderSide(color: Colors.black26),
                          ),
                        ),
                        padding: EdgeInsets.all(14.0),
                        child: Column(
                          children: [
                            Text(
                              'Total Penerimaan',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black45,
                              ),
                            ),
                            Text(
                              convertIDR(totalPayment - nominalVoucher),
                              style: TextStyle(
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
                            padding: EdgeInsets.all(20.0),
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
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 10,
                                offset: const Offset(0, -5),
                              ),
                            ],
                          ),
                          child: SizedBox(
                            height:
                                45, // Memberikan tinggi yang konsisten agar mudah ditekan (touch-friendly)
                            child: ElevatedButton(
                              onPressed: isLoading ? null : handlePayment,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade500,
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
                                  ? ModernLoading(
                                      size: 24,
                                      strokeWidth: 3,
                                      timeout: const Duration(seconds: 10),
                                      onRetry: () {},
                                    )
                                  : const Text(
                                      'Selesaikan Pembayaran',
                                      style: TextStyle(
                                        fontSize: 16.0,
                                        color: Colors.black87,
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
    );
  }

  Widget tunaiSection() {
    bool isValidCustom = customAmount >= totalPayment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Metode Penerimaan",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 10.0),
        Row(
          children: [
            CustomChipCheckbox(
              label: convertIDR(exactAmount - nominalVoucher),
              isSelected: selectedPayment == "exact",
              onSelect: () => setState(() => selectedPayment = "exact"),
            ),
            SizedBox(width: 12),
            CustomChipCheckbox(
              label: convertIDR(roundedAmount),
              isSelected: selectedPayment == "rounded",
              onSelect: () => setState(() => selectedPayment = "rounded"),
            ),
            SizedBox(width: 12),
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
            decoration: InputDecoration(
              labelText: "Masukkan Nominal",
              errorText: isValidCustom
                  ? null
                  : "Nominal harus lebih besar dari total penerimaan",
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (val) {
              setState(() {
                customAmount =
                    int.tryParse(val.replaceAll(RegExp(r'\D'), "")) ?? 0;
              });
            },
          ),
        ],
        const SizedBox(height: 20),
        Text(
          "Metode",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 10.0),
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
        SizedBox(height: 10.0),
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
    return Row(
      spacing: 12,
      children: orderMethods.map((method) {
        String name = method['name'] ?? '';
        int id = method['id'] ?? 0;
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
        behavior: HitTestBehavior.opaque, // Memastikan area klik luas
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250), // Animasi transisi warna
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected
                    ? Colors.orange
                    : Colors.grey.withOpacity(0.1),
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
              color: isSelected ? Colors.orange : Colors.grey[500],
            ),
          ),
        ),
      ),
    );
  }
}
