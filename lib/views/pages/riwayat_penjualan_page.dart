import 'dart:async';

import 'package:flutter/material.dart';
import 'package:number_pagination/number_pagination.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/order_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:pos_panglima_app/utils/modal_error.dart';

class RiwayatPenjualanPage extends StatefulWidget {
  const RiwayatPenjualanPage({super.key});

  @override
  State<RiwayatPenjualanPage> createState() => _RiwayatPenjualanPageState();
}

class _RiwayatPenjualanPageState extends State<RiwayatPenjualanPage> {
  final ScrollController _scrollController = ScrollController();
  TextEditingController controllerSearch = TextEditingController();
  double fadeOpacity = 0.5;
  Timer? _debounce;
  final apiClient = ApiClient();
  late final OrderService orderService;
  late final AuthService authService;
  List<Map<String, dynamic>> orderList = [];
  late bool isLoadingOrdersList = true;
  late bool isLoadingOrdersDetail = true;
  late bool isLoadingUserId = true;
  late bool isFirstLoad = true;
  int? orderId;
  int? userId;
  int selectedPageNumber = 1;
  Map<String, dynamic>? orderDetail;
  Map<String, dynamic>? paginationInfo;
  BluetoothDevice? connectedPrinter;

  @override
  void initState() {
    super.initState();

    BluetoothPrinterService.bluetooth.onStateChanged().listen((state) {
      setState(() {
        connectedPrinter = BluetoothPrinterService.connectedPrinter;
      });
    });

    authService = AuthService(apiClient.dio);
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

    _fetchOrders();
    _fetchProfile();
  }

  Future<void> _fetchOrders() async {
    print(
      "🔍 Fetching: page=$selectedPageNumber, search=${controllerSearch.text}",
    );
    try {
      final response = await orderService.getOrderList(
        userId ?? 0,
        selectedPageNumber,
        10,
        controllerSearch.text,
      );
      print("✅ Response: ${response.data}");
      final raw = response.data['data']['data'] as List<dynamic>;
      final pagination = response.data['data']['metadata'];
      final mapped = raw.map((e) => Map<String, dynamic>.from(e)).toList();

      setState(() {
        orderList = mapped;
        paginationInfo = pagination;
        isLoadingOrdersList = false;
      });

      if (mapped.isNotEmpty && isFirstLoad) {
        orderId = mapped.first['id'];
        await _fetchOrderDetail(orderId!);
        setState(() => isFirstLoad = false);
      }
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
        },
      );
    }
  }

  Future<void> _fetchOrderDetail(int id) async {
    try {
      setState(() => isLoadingOrdersDetail = true);

      final response = await orderService.getOrderDetail(id);

      setState(() {
        orderId = id;
        orderDetail = response.data['data'];
        isLoadingOrdersDetail = false;
      });
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
        },
      );
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final response = await authService.getProfile();
      final data = response.data['data'];

      if (!mounted) return;
      setState(() {
        userId = data?['userid'];
        isLoadingUserId = false;
      });
    } catch (e) {
      isLoadingUserId = false;
      debugPrint("Gagal ambil user ID: $e");
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
        },
      );
    }
  }

  Future<void> handlePrintStruk() async {
    try {
      await BluetoothPrinterService.printStruk(
        documentNumber: orderDetail?['document_number'],
        usersName: orderDetail?['users_name'], 
        listProduk: orderDetail?['pos_order_lines'],
        totalQuantity: 0, // harus di isi
        isCash: orderDetail?['is_cash'] == 1 ? true : false,
        method: orderDetail?['pos_order_method_id'] == 1 ? 'Takeaway' : 'Delivery',
        paymentMethod: orderDetail?['pos_payment_method_name'],
        totalPayment: orderDetail?['total_amount'],
        subTotal: orderDetail?['subtotal_amount'],
        payment: orderDetail?['pay_amount'],
        isPayment: false,
      );
    } catch (e) {
      print("❌ Failed to print struk: $e");
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    controllerSearch.dispose();
    super.dispose();
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
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.0),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.black26)),
                  ),
                  child: TextField(
                    controller: controllerSearch,
                    autofocus: true,
                    decoration: const InputDecoration(
                      icon: Icon(Icons.search),
                      hintText: 'Cari Riwayat Penjualan...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 6,
                      ),
                    ),
                    onChanged: (value) {
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      _debounce = Timer(const Duration(milliseconds: 1000), () {
                        print(
                          '======================== debounce aktif ================================',
                        );
                        setState(() => selectedPageNumber = 1);
                        _fetchOrders();
                      });
                    },
                  ),
                ),
                Expanded(
                  child: isLoadingOrdersList || isLoadingUserId
                      ? Center(child: CircularProgressIndicator())
                      : Stack(
                          children: [
                            SingleChildScrollView(
                              controller: _scrollController,
                              child: Column(
                                spacing: 10.0,
                                children: orderList.map((order) {
                                  final isActive = orderId == order['id'];
                                  return InkWell(
                                    onTap: () {
                                      orderId = order['id'];
                                      _fetchOrderDetail(orderId!);
                                    },
                                    child: Container(
                                      color: isActive
                                          ? Colors.amber[100]
                                          : Colors.grey[100],
                                      padding: EdgeInsets.symmetric(
                                        vertical: 10.0,
                                        horizontal: 20.0,
                                      ),
                                      width: double.infinity,
                                      child: Column(
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.payment,
                                                    size: 60.0,
                                                    color: Colors.black87,
                                                  ),
                                                  SizedBox(width: 5.0),
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        order['document_number'],
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16.0,
                                                        ),
                                                      ),
                                                      Text(
                                                        'Total ${convertIDR(order['total_amount'])}',
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                formatDateTime(
                                                  order['created_at'],
                                                ),
                                              ),
                                            ],
                                          ),
                                          Divider(),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.payment,
                                                        color: Colors.black87,
                                                      ),
                                                      SizedBox(width: 5.0),
                                                      Text(
                                                        order['pos_payment_method_name'],
                                                        style: TextStyle(
                                                          color: Colors.black87,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  SizedBox(width: 10.0),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.person,
                                                        color: Colors.black87,
                                                      ),
                                                      SizedBox(width: 5.0),
                                                      Text(
                                                        'Kasir',
                                                        style: TextStyle(
                                                          color: Colors.black87,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                order['pos_order_method_id'] ==
                                                        1
                                                    ? 'Takeaway'
                                                    : 'Delivery',
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
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
                                          Colors.black45.withOpacity(0),
                                          Colors.black45,
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
                NumberPagination(
                  onPageChanged: (int pageNumber) {
                    //To optimize further, use a package that supports partial updates instead of setState (e.g. riverpod)
                    setState(() {
                      selectedPageNumber = pageNumber;
                      isLoadingOrdersList = true;
                    });
                    _fetchOrders();
                  },
                  visiblePagesCount: 3,
                  totalPages: paginationInfo?['total_page'] ?? 0,
                  currentPage: selectedPageNumber,
                  enableInteraction: false,
                  buttonRadius: 10,
                  selectedButtonColor: Colors.amber,
                  selectedNumberColor: Colors.black,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: isLoadingOrdersDetail || isLoadingUserId
              ? Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 20.0),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black26),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {},
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.share, color: Colors.black87),
                                  SizedBox(width: 5),
                                  Text(
                                    'Share Struk',
                                    style: TextStyle(color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 20.0),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                handlePrintStruk();
                              },
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.amber,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.print, color: Colors.black87),
                                  SizedBox(width: 5),
                                  Text(
                                    'Cetak Struk',
                                    style: TextStyle(color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Container(
                          padding: EdgeInsets.all(20.0),
                          child: Column(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 10.0,
                                children: [
                                  Text(
                                    'Informasi Penjualan',
                                    style: TextStyle(
                                      fontSize: 18.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          spacing: 20.0,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              spacing: 10.0,
                                              children: [
                                                Icon(
                                                  Icons.article,
                                                  size: 50.0,
                                                  color: Colors.black87,
                                                ),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text('ID Penjualan'),
                                                    Text(
                                                      orderDetail?['document_number'] ??
                                                          '-',
                                                      style: TextStyle(
                                                        fontSize: 16.0,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            Row(
                                              spacing: 10.0,
                                              children: [
                                                Icon(
                                                  Icons.calendar_month,
                                                  size: 50.0,
                                                  color: Colors.black87,
                                                ),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text('Tanggal Penjualan'),
                                                    Text(
                                                      formatDateTime(
                                                        orderDetail?['created_at'],
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 16.0,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          spacing: 20.0,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              spacing: 10.0,
                                              children: [
                                                Icon(
                                                  Icons.group,
                                                  size: 50.0,
                                                  color: Colors.black87,
                                                ),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text('Nama Pelanggan'),
                                                    Text(
                                                      orderDetail?['customers_name'] ??
                                                          '-',
                                                      style: TextStyle(
                                                        fontSize: 16.0,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            Row(
                                              spacing: 10.0,
                                              children: [
                                                Icon(
                                                  Icons.person,
                                                  size: 50.0,
                                                  color: Colors.black87,
                                                ),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text('Dibuat Oleh'),
                                                    Text(
                                                      orderDetail?['users_name'] ??
                                                          '-',
                                                      style: TextStyle(
                                                        fontSize: 16.0,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Divider(),
                                  Text(
                                    'Informasi Penerimaan',
                                    style: TextStyle(
                                      fontSize: 18.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.all(20.0),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      border: Border.all(color: Colors.black26),
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(10.0),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        Column(
                                          children: [
                                            Text('Total Penerimaan'),
                                            Text(
                                              convertIDR(
                                                orderDetail?['total_amount'] ??
                                                    0,
                                              ),
                                              style: TextStyle(
                                                fontSize: 21.0,
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(
                                          height: 50.0,
                                          child: VerticalDivider(
                                            thickness: 1,
                                            color: Colors.black26,
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            Text('Total Bayar'),
                                            Text(
                                              convertIDR(
                                                orderDetail?['pay_amount'] ?? 0,
                                              ),
                                              style: TextStyle(
                                                fontSize: 21.0,
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(
                                          height: 50.0,
                                          child: VerticalDivider(
                                            thickness: 1,
                                            color: Colors.black26,
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            Text('Kembali'),
                                            Text(
                                              convertIDR(
                                                orderDetail?['pay_amount'] -
                                                        orderDetail?['total_amount'] ??
                                                    0,
                                              ),
                                              style: TextStyle(
                                                fontSize: 21.0,
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'Riwayat Penerimaan',
                                    style: TextStyle(
                                      fontSize: 18.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.only(bottom: 20.0),
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
                                              orderDetail?['document_number'] ??
                                                  '-',
                                              style: TextStyle(
                                                fontSize: 18.0,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              orderDetail?['pos_payment_method_name'] ??
                                                  '-',
                                              style: TextStyle(fontSize: 16.0),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              formatDateTime(
                                                orderDetail?['created_at'],
                                              ),
                                              style: TextStyle(fontSize: 16.0),
                                            ),
                                            Text(
                                              convertIDR(
                                                orderDetail?['total_amount'] ??
                                                    0,
                                              ),
                                              style: TextStyle(
                                                fontSize: 22.0,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'Barang & Jasa',
                                    style: TextStyle(
                                      fontSize: 18.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Column(
                                    spacing: 12,
                                    children: (orderDetail?['pos_order_lines'] as List).map((
                                      line,
                                    ) {
                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            spacing: 15.0,
                                            children: [
                                              Container(
                                                width: 170,
                                                height: 100,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      secondColor(
                                                        line['pos_menus_name'],
                                                      ),
                                                      baseColor(
                                                        line['pos_menus_name'],
                                                      ),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  getInitials(
                                                    line['pos_menus_name'],
                                                  ),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 60,
                                                  ),
                                                ),
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                spacing: 22.0,
                                                children: [
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        line['pos_menus_name'],
                                                        style: TextStyle(
                                                          fontSize: 18.0,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      Text(
                                                        '${line['quantity']} Pcs',
                                                      ),
                                                    ],
                                                  ),
                                                  Text(
                                                    'Diinput Oleh: ${orderDetail?['users_name']}',
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          Text(
                                            convertIDR(line['total']),
                                            style: TextStyle(
                                              fontSize: 20.0,
                                              color: Colors.orange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 20.0,
                                    ),
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
                                        Text(
                                          'Subtotal Order',
                                          style: TextStyle(
                                            fontSize: 18.0,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          convertIDR(
                                            orderDetail?['subtotal_amount'],
                                          ),
                                          style: TextStyle(
                                            fontSize: 20.0,
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 20.0,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.black26,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      spacing: 10,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Subtotal',
                                              style: TextStyle(
                                                fontSize: 18.0,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              convertIDR(
                                                orderDetail?['subtotal_amount'],
                                              ),
                                              style: TextStyle(
                                                fontSize: 20.0,
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (orderDetail?['discount_amount'] !=
                                            0)
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Diskon',
                                                style: TextStyle(
                                                  fontSize: 18.0,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                convertIDR(
                                                  orderDetail?['discount_amount'],
                                                ),
                                                style: TextStyle(
                                                  fontSize: 20.0,
                                                  color: Colors.orange,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 20.0,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'GRAND TOTAL',
                                          style: TextStyle(
                                            fontSize: 20.0,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          convertIDR(
                                            orderDetail?['total_amount'],
                                          ),
                                          style: TextStyle(
                                            fontSize: 22.0,
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                          ),
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
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
