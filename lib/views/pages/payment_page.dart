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
import 'package:pos_panglima_app/views/components/ui/custom_checkbox.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

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
  bool isLoadingUserId = true;
  bool isLoadingCart = true;
  bool isLoadingMethod = true;
  String? customerId;
  int? shiftId;
  List<Map<String, dynamic>> paymentMethods = [];
  List<Map<String, dynamic>> orderMethods = [];
  final TextEditingController _customAmountController = TextEditingController();

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
  int get roundedAmount => roundToNearestTenThousand(totalPayment);

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

    _initCamera();

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

      final newDiscount = newItems.fold<int>(0, (sum, item) {
        final int price = (item['subtotal'] as int?) ?? 0;
        return sum + price;
      });

      setState(() {
        cartItems = newItems;
        totalPayment = newTotalPayment;
        subTotal = newDiscount;
        isLoadingCart = false;
        totalQuantity = newTotalQuantity;
      });
    } on DioException catch (e) {
      print(e.response?.data);
    }
  }

  Future<void> _initCamera() async {
    await CameraService().initialize();
  }

  void handlePayment() async {
    bool online = await NetworkService.isOnline();

    if (!online) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Perangkat sedang offline")));
      return;
    }

    int? orderId;

    await cameraService.initialize();
    final file = await cameraService.capture();

    if (file == null) {
      print("❌ Capture gagal");
      return;
    }

    try {
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
          "pos_order_method_id": int.tryParse(selectedMethodId.toString()) ?? 0,
          "subtotal_amount": subTotal,
          "discount_amount": subTotal - totalPayment,
          "tax_amount": 0.00,
          "total_amount": totalPayment,
          "pay_amount": finalPayment,
          "is_cash": 1,
        };

        final response = await orderService.postOrder(payloadOrder);
        orderId = response.data['data']['id'];
        
        await BluetoothPrinterService.printStruk(
          listProduk: cartItems,
          totalQuantity: totalQuantity,
          documentNumber: 'Testing Document',
          usersName: 'Masih Testing',
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
          "pos_order_method_id": int.tryParse(selectedMethodId.toString()) ?? 0,
          "subtotal_amount": subTotal,
          "discount_amount": subTotal - totalPayment,
          "tax_amount": 0.00,
          "total_amount": totalPayment,
          "pay_amount": totalPayment,
          "is_cash": 0,
        };

        final response = await orderService.postOrder(payloadOrder);
        orderId = response.data['data']['id'];

        await BluetoothPrinterService.printStruk(
          listProduk: cartItems,
          totalQuantity: totalQuantity,
          documentNumber: 'Testing Document',
          usersName: 'Masih Testing',
          isCash: false,
          method: selectedMethodName,
          totalPayment: totalPayment,
          subTotal: subTotal,
          paymentMethod: selectedPaymentNonTunai,
          isPayment: true,
        );
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
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => WidgetTree()),
        (route) => false,
      );
    } catch (e) {
      print('================================ Terjadi Kesalahan $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Terjadi kesalahan: $e")));
    } finally {
      await cameraService.dispose();
    }
  }

  Future<void> getProfile() async {
    try {
      final response = await authService.getProfile();
      final data = response.data['data'];
      print("========================== Fetched user profile: $data");

      if (!mounted) return;
      setState(() {
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
      print("Payment Methods: ${response.data}");
      paymentMethods = List<Map<String, dynamic>>.from(response.data['data']);

      final orderResponse = await methodService.getOrderMethods();
      print("Order Methods: ${orderResponse.data}");
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
    print("Loaded shift ID: $result");
    setState(() {
      shiftId = result;
    });
  }

  @override
  void dispose() async {
    _customAmountController.dispose();
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
      body: isLoadingCart || isLoadingMethod
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
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.black26),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14.0,
                            vertical: 20.0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Subtotal',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                convertIDR(totalPayment),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
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
                              convertIDR(totalPayment),
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
                            onPressed: () {
                              handlePayment();
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.amber,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: Text(
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
    bool isValidCustom = customAmount >= totalQuantity;
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
              label: convertIDR(exactAmount),
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
