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
import 'package:pos_panglima_app/utils/modal_handling.dart';
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
  int dicount = 0;
  double fadeOpacity = 0.2;
  int selectedTab = 0;
  BluetoothDevice? connectedPrinter;
  List<BluetoothDevice> devices = [];
  bool isScanning = false;
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

  int get exactAmount => totalPayment;
  int get roundedAmount =>
      roundToNearestTenThousand(totalPayment - nominalVoucher);

  @override
  void initState() {
    super.initState();

    BluetoothPrinterService.bluetooth.onStateChanged().listen((state) {
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
        dicount = newDiscount;
        isLoadingCart = false;
        totalQuantity = newTotalQuantity;
      });
    } on DioException catch (e) {
      print(e.response?.data);
    }
  }

  void handlePayment() async {
    setState(() => isLoading = true);
    bool online = await NetworkService.isOnline();

    if (!online) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Perangkat sedang offline")));
      return;
    }

    int? orderId;

    try {
      if (selectedMethodName != 'Compliment') {
        if (selectedTab == 0) {
          int finalPayment = totalPayment;

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
          print('======================= $response');
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

      paymentSuccessModal();

      if (!mounted) return;

      await Future.delayed(const Duration(seconds: 3));

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => WidgetTree()),
        (route) => false,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Terjadi kesalahan: $e")));
      final String message =
          e.response?.data?['message'] ?? 'Terjadi kesalahan';
      print(message);
      // tandai
      paymentErrorModal();
    } finally {
      setState(() => isLoading = false);
      await cameraService.dispose();
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
      print("Error fetching methods: $e");
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
          builder: (_) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Column(
                spacing: 10.0,
                children: [
                  Text(
                    "Keterangan Compliment",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Berikan penjelasan atau catatan terkait compliment yang dilakukan (contoh: permintaan pak Agung, dll).",
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 600.0,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _keteranganCompliment,
                      onChanged: (value) {
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        labelText: "Berikan Keterangan",
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text("Batal", style: TextStyle(color: Colors.black)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.0),
                    ),
                  ),
                  onPressed: () {
                    bool allValid = true;

                    final controller = _keteranganCompliment;
                    if (controller == null || controller.text.isEmpty) {
                      allValid = false;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Keterangan Wajib Di isi")),
                      );
                    }

                    if (allValid) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: Text(
                    "Lanjutkan",
                    style: TextStyle(color: Colors.black),
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

  Future<void> paymentSuccessModal() async {
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
      print(response);
    } on DioException catch (e) {
      print(e.response);
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
      print('Voucher sudah digunakan');
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

    print('Barcode list: $localBarcodes');
    print('Total nominal: ${currentNominal + nominal}');
  }

  Future<void> getVoucherData() async {
    final prefs = await SharedPreferences.getInstance();

    final String? storedBarcodes = prefs.getString('voucher_barcodes');
    final List<String> newBarcodeList = storedBarcodes != null
        ? List<String>.from(jsonDecode(storedBarcodes))
        : [];
    final int totalNominal = prefs.getInt('voucher_nominal') ?? 0;

    print('Barcodes: $barcodeList');
    print('Total Nominal: $totalNominal');
    setState(() {
      barcodeList = newBarcodeList;
      nominalVoucher = totalNominal;
    });
  }

  // Reset semua voucher (misal setelah order selesai)
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
          ? Center(child: CircularProgressIndicator())
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
                        Container(
                          padding: EdgeInsets.all(10),
                          color: Colors.black12,
                          width: double.infinity,
                          child: Text('Total Produk ( $totalQuantity )'),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              SingleChildScrollView(
                                controller: _scrollController,
                                child: Column(
                                  children: cartItems.map((e) {
                                    return Container(
                                      padding: EdgeInsets.all(14.0),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Colors.black26,
                                          ),
                                        ),
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
                                                e['pos_menus_name'],
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              if (e['max_qty'] != 0 &&
                                                  e['pos_cart_props'] != null)
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children:
                                                      (e['pos_cart_props']
                                                              as List)
                                                          .where(
                                                            (item) =>
                                                                item['quantity'] !=
                                                                0,
                                                          )
                                                          .map<Widget>((item) {
                                                            return Text(
                                                              '${item['quantity']}x ${item['pos_menus_name']}',
                                                            );
                                                          })
                                                          .toList(),
                                                ),
                                              if (e['max_qty'] != 0 &&
                                                  e['pos_cart_materials'] !=
                                                      null)
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children:
                                                      (e['pos_cart_materials']
                                                              as List)
                                                          .where(
                                                            (item) =>
                                                                item['quantity'] !=
                                                                0,
                                                          )
                                                          .map<Widget>((item) {
                                                            return Text(
                                                              '${item['quantity']}x ${item['items_name']}',
                                                            );
                                                          })
                                                          .toList(),
                                                ),
                                              Row(
                                                children: [
                                                  Text(
                                                    convertIDR((e['total'])),
                                                  ),
                                                  (e['discount'] ?? 0) +
                                                              (e['discount_val'] ??
                                                                  0) !=
                                                          0
                                                      ? Text(
                                                          ' ( - ${convertIDR(e['subtotal'] - e['total'])} )',
                                                        )
                                                      : SizedBox(),
                                                ],
                                              ),
                                            ],
                                          ),
                                          Text(
                                            '${e['quantity']} PCS',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  child: AnimatedOpacity(
                                    duration: Duration(milliseconds: 300),
                                    opacity: fadeOpacity,
                                    child: Container(
                                      height: 40,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            // ignore: deprecated_member_use
                                            Colors.black26.withOpacity(0),
                                            Colors.black26,
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
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14.0,
                                vertical: 8.0,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 40,
                                      child: TextField(
                                        controller: _voucherController,
                                        focusNode: _voucherFocusNode,
                                        decoration: InputDecoration(
                                          hintText: 'Kode voucher...',
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  ElevatedButton(
                                    onPressed: () async {
                                      _voucherFocusNode.unfocus();
                                      await checkVoucher();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black38,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      'Check',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Colors.black26),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14.0,
                                vertical: 10.0,
                              ),
                              child: Column(
                                children: [
                                  // Baris Subtotal
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Subtotal',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      Text(
                                        convertIDR(subTotal),
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 3),
                                  if (dicount > 0)
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Diskon',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.red,
                                          ),
                                        ),
                                        Text(
                                          '- ${convertIDR(dicount)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  SizedBox(height: 3),
                                  if (nominalVoucher > 0)
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Diskon Voucher',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.red,
                                          ),
                                        ),
                                        Text(
                                          '- ${convertIDR(nominalVoucher)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  SizedBox(height: 5),
                                  Divider(color: Colors.black12, height: 1),
                                  SizedBox(height: 5),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Total Pembayaran',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        convertIDR(
                                          totalPayment - nominalVoucher,
                                        ), // Variabel total akhir
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange,
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
                              ),
                            ),
                            Text(
                              convertIDR(totalPayment - nominalVoucher),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.orange,
                                fontSize: 24.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() => selectedTab = 0);
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: selectedTab == 0
                                          ? Colors.orange
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  "Tunai",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: selectedTab == 0
                                        ? Colors.orange
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() => selectedTab = 1);
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: selectedTab == 1
                                          ? Colors.orange
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  "Non Tunai",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: selectedTab == 1
                                        ? Colors.orange
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
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
                          child: ElevatedButton(
                            onPressed: isLoading ? null : handlePayment,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.amber.shade500,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: isLoading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.black,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    'Selesaikan Pembayaran',
                                    style: TextStyle(
                                      fontSize: 16.0,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
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
}
