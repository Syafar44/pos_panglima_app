import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:number_pagination/number_pagination.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/order_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:pos_panglima_app/utils/skeleton_loader.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';

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
  StreamSubscription? _bluetoothSubscription;

  @override
  void initState() {
    super.initState();

    _bluetoothSubscription = BluetoothPrinterService.bluetooth.onStateChanged().listen((state) {
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

    _fetchProfile();
  }

  Future<void> _fetchOrders(int userId) async {
    try {
      final response = await orderService.getOrderList(
        userId,
        selectedPageNumber,
        10,
        controllerSearch.text,
      );
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
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'danger',
            title: 'Gagal memuat riwayat penjualan',
            description:
                'Terjadi kesalahan saat mengambil data riwayat penjualan. Mohon periksa koneksi atau coba kembali.',
          );
        },
      );
    }
  }

  Future<void> _fetchOrderDetail(int id) async {
    try {
      setState(() => isLoadingOrdersDetail = true);

      final response = await orderService.getOrderDetail(id);
      debugPrint(response.toString());

      setState(() {
        orderId = id;
        orderDetail = response.data['data'];
        isLoadingOrdersDetail = false;
      });
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'danger',
            title: 'Gagal memuat detail',
            description:
                'Terjadi kesalahan saat mengambil detail. Mohon periksa koneksi atau coba kembali.',
          );
        },
      );
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final response = await authService.getProfile();
      final data = response.data['data'];
      final newUserId = data?['userid'];
      await _fetchOrders(newUserId);
      if (!mounted) return;
      setState(() {
        userId = data?['userid'];
        isLoadingUserId = false;
      });
    } catch (e) {
      isLoadingUserId = false;
      debugPrint("Gagal ambil user ID: $e");
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'warning',
            title: 'Gagal memuat data pengguna',
            description:
                'Terjadi kendala saat mengambil data pengguna. Mohon periksa koneksi atau coba kembali.',
          );
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
        totalQuantity: orderDetail?['jumlah_item'],
        isCash: orderDetail?['is_cash'] == 1 ? true : false,
        method: orderDetail?['pos_order_method_id'] == 1
            ? 'Takeaway'
            : 'Delivery',
        paymentMethod: orderDetail?['pos_payment_method_name'],
        totalPayment: orderDetail?['total_amount'],
        subTotal: orderDetail?['subtotal_amount'],
        payment: orderDetail?['pay_amount'],
        isPayment: false,
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'warning',
            title: 'Gagal mencetak struk',
            description:
                'Terjadi kesalahan saat mencetak struk data riwayat penjualan. Mohon coba kembali.',
          );
        },
      );
    }
  }

  @override
  void dispose() {
    _bluetoothSubscription?.cancel();
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors
                          .grey[100], // Background abu-abu muda agar terlihat kedalam
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: TextField(
                      controller: controllerSearch,
                      autofocus:
                          false, // Disarankan false agar keyboard tidak tiba-tiba muncul
                      style: const TextStyle(fontSize: 14.0),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                        ),
                        // Tombol hapus teks (muncul hanya jika ada teks)
                        suffixIcon: controllerSearch.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                onPressed: () {
                                  controllerSearch.clear();
                                  setState(() => selectedPageNumber = 1);
                                  _fetchOrders(userId!);
                                },
                              )
                            : null,
                        hintText: 'Cari nomor dokumen...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                      ),
                      onChanged: (value) {
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 800),
                          () {
                            // Debounce 800ms cukup responsif
                            setState(() => selectedPageNumber = 1);
                            _fetchOrders(userId!);
                          },
                        );
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: isLoadingOrdersList || isLoadingUserId
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14.0),
                          child: SkeletonLoader.listHistorySkeleton(),
                        )
                      : Stack(
                          children: [
                            ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16.0),
                              itemCount: orderList.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final order = orderList[index];
                                final isActive = orderId == order['id'];

                                return InkWell(
                                  onTap: () {
                                    orderId = order['id'];
                                    _fetchOrderDetail(orderId!);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? Colors.amber[50]
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isActive
                                            ? Colors.orange
                                            : Colors.grey[200]!,
                                        width: isActive ? 2 : 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.03),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      children: [
                                        // Bagian Atas: Nomor Dokumen & Waktu
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isActive
                                                        ? Colors.amber
                                                        : Colors.grey[100],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    Icons.receipt_long_outlined,
                                                    size: 20,
                                                    color: isActive
                                                        ? Colors.black87
                                                        : Colors.grey[600],
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      order['document_number'],
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15.0,
                                                      ),
                                                    ),
                                                    Text(
                                                      formatDateTime(
                                                        order['created_at'],
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey[500],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            Text(
                                              convertIDR(order['total_amount']),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16.0,
                                                color: Colors.blueAccent,
                                              ),
                                            ),
                                          ],
                                        ),

                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          child: Divider(
                                            height: 1,
                                            thickness: 0.5,
                                          ),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                _buildSmallBadge(
                                                  icon: Icons
                                                      .account_balance_wallet_outlined,
                                                  label:
                                                      order['pos_payment_method_name'],
                                                ),
                                                const SizedBox(width: 8),
                                                _buildSmallBadge(
                                                  icon: Icons.person_outline,
                                                  label: 'Kasir',
                                                ),
                                              ],
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _getMethodColor(
                                                  order['pos_order_method_id'],
                                                ).withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                _getMethodLabel(
                                                  order['pos_order_method_id'],
                                                ),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: _getMethodColor(
                                                    order['pos_order_method_id'],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 2.0,
                    horizontal: 16.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: Colors.grey[200]!,
                      ), // Garis halus di atas pagination
                    ),
                  ),
                  child: NumberPagination(
                    onPageChanged: (int pageNumber) {
                      setState(() {
                        selectedPageNumber = pageNumber;
                        isLoadingOrdersList = true;
                      });
                      _fetchOrders(userId!);
                    },
                    visiblePagesCount: 3,
                    totalPages: paginationInfo?['total_page'] ?? 0,
                    currentPage: selectedPageNumber,
                    // --- Custom Styling ---
                    buttonRadius: 12, // Membuat tombol sedikit lebih bulat
                    selectedButtonColor: Colors.amber.shade400,
                    selectedNumberColor: Colors.black,
                    unSelectedButtonColor: Colors.grey[100]!,
                    unSelectedNumberColor: Colors.grey[700]!,
                    numberButtonSize: const Size(35, 35),
                    controlButtonSize: const Size(35, 35),
                    fontSize: 14,
                    sectionSpacing: 5,
                    navigationButtonSpacing: 0,
                    // Tambahkan properti lain jika package mendukung,
                    // seperti padding atau icon panah custom.
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: isLoadingOrdersDetail || isLoadingUserId
              ? Padding(
                  padding: const EdgeInsets.all(0),
                  child: SkeletonLoader.detailHistorySkeleton(),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 12.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(
                            color: Colors.grey[200]!,
                          ), // Gunakan top border jika diletakkan di bawah
                          bottom: BorderSide(color: Colors.grey[200]!),
                        ),
                      ),
                      child: Row(
                        children: [
                          // 1. Tombol Share (Outlined)
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () {
                                  // Tambahkan fungsi share di sini
                                },
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.grey[300]!),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  foregroundColor: Colors.black87,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.share_outlined, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Share',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(
                            width: 16.0,
                          ), // Jarak antar tombol yang pas
                          // 2. Tombol Cetak (Solid Amber)
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () {
                                  // getar
                                  HapticFeedback.lightImpact();
                                  handlePrintStruk();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  foregroundColor: Colors.black87,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.print_outlined, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Cetak Struk',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 10.0,
                            children: [
                              const Text(
                                'Informasi Penjualan',
                                style: TextStyle(
                                  fontSize: 18.0,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              // Grid Informasi menggunakan Wrap atau Row
                              Container(
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        _buildInfoTile(
                                          icon: Icons.article_outlined,
                                          label: 'ID Penjualan',
                                          value:
                                              orderDetail?['document_number'] ??
                                              '-',
                                        ),
                                        _buildInfoTile(
                                          icon: Icons.person_outline,
                                          label: 'Nama Pelanggan',
                                          value:
                                              orderDetail?['customers_name'] ??
                                              '-',
                                        ),
                                      ],
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12.0,
                                      ),
                                      child: Divider(height: 1, thickness: 0.5),
                                    ),
                                    Row(
                                      children: [
                                        _buildInfoTile(
                                          icon: Icons.calendar_month_outlined,
                                          label: 'Tanggal Penjualan',
                                          value: formatDateTime(
                                            orderDetail?['created_at'],
                                          ),
                                        ),
                                        _buildInfoTile(
                                          icon: Icons.account_circle_outlined,
                                          label: 'Dibuat Oleh',
                                          value:
                                              orderDetail?['users_name'] ?? '-',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Divider(),

                              Text(
                                orderDetail?['pos_order_method_name'] ==
                                        'Compliment'
                                    ? 'Status Compliment'
                                    : 'Informasi Pembayaran',
                                style: const TextStyle(
                                  fontSize: 18.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(20.0),
                                decoration: BoxDecoration(
                                  color: Colors
                                      .white, // Ganti ke putih agar shadow terlihat bersih
                                  borderRadius: BorderRadius.circular(12.0),
                                  border: Border.all(color: Colors.grey[200]!),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.03),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child:
                                    orderDetail?['pos_order_method_name'] ==
                                        'Compliment'
                                    ? _buildComplimentStatus(
                                        orderDetail?['is_compliment_status'],
                                      )
                                    : _buildPaymentInfo(orderDetail),
                              ),

                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(height: 32),
                                  Text(
                                    orderDetail?['keterangan'] != ''
                                        ? 'Keterangan Compliment'
                                        : 'Riwayat Penerimaan',
                                    style: const TextStyle(
                                      fontSize: 18.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16.0),
                                    decoration: BoxDecoration(
                                      color: orderDetail?['keterangan'] != ''
                                          ? Colors
                                                .amber
                                                .shade50 // Beri warna berbeda untuk catatan/keterangan
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: orderDetail?['keterangan'] != ''
                                            ? Colors.amber.shade200
                                            : Colors.grey[200]!,
                                      ),
                                    ),
                                    child: orderDetail?['keterangan'] != ''
                                        ? Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.sticky_note_2_outlined,
                                                color: Colors.amber[800],
                                                size: 20,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  orderDetail?['keterangan'],
                                                  style: TextStyle(
                                                    fontSize: 15.0,
                                                    color: Colors.amber[900],
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              // Bagian Kiri: Info Transaksi
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    orderDetail?['document_number'] ??
                                                        '-',
                                                    style: const TextStyle(
                                                      fontSize: 14.0,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.blue.shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      orderDetail?['pos_payment_method_name'] ??
                                                          '-',
                                                      style: TextStyle(
                                                        fontSize: 12.0,
                                                        color: Colors.blue[700],
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // Bagian Kanan: Waktu & Nominal
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    formatDateTime(
                                                      orderDetail?['created_at'],
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 12.0,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    convertIDR(
                                                      orderDetail?['total_amount'] ??
                                                          0,
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 18.0,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                  ),
                                  const SizedBox(
                                    height: 20,
                                  ), // Padding bawah sebelum masuk ke list produk
                                ],
                              ),

                              Text(
                                'Barang & Jasa',
                                style: TextStyle(
                                  fontSize: 18.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Column(
                                children: (orderDetail?['pos_order_lines'] as List).map((
                                  line,
                                ) {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 20.0,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 1. Thumbnail / Inisial Menu
                                        Container(
                                          width:
                                              60, // Diperkecil agar proporsional
                                          height: 60,
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
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            getInitials(line['pos_menus_name']),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize:
                                                  20, // Ukuran font disesuaikan
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),

                                        // 2. Info Detail Produk
                                        // ... di dalam bagian Info Detail Produk (Expanded)
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // 1. Nama Produk & Label (jika ada)
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      line['pos_menus_name']
                                                          .toUpperCase(), // Uppercase untuk ketegasan
                                                      style: const TextStyle(
                                                        fontSize: 15.0,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Color(
                                                          0xFF2D3436,
                                                        ),
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),

                                              // 2. Harga Satuan & Kuantitas dengan Badge
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[200],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      '${line['quantity']}x',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    convertIDR(
                                                      line['price'] ?? 0,
                                                    ),
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),

                                              // 3. Section Material / Add-ons (Dibuat seperti struk fisik)
                                              if (line['pos_order_lines_material'] !=
                                                      null &&
                                                  (line['pos_order_lines_material']
                                                          as List)
                                                      .isNotEmpty)
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    top: 8,
                                                    left: 4,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 12,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    border: Border(
                                                      left: BorderSide(
                                                        color:
                                                            Colors.grey[300]!,
                                                        width: 2,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children:
                                                        (line['pos_order_lines_material']
                                                                as List)
                                                            .map((item) {
                                                              return Padding(
                                                                padding:
                                                                    const EdgeInsets.only(
                                                                      bottom: 2,
                                                                    ),
                                                                child: Text(
                                                                  '+ ${item['items_name']} (${item['quantity']})',
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .blueGrey[600],
                                                                    fontStyle:
                                                                        FontStyle
                                                                            .italic,
                                                                  ),
                                                                ),
                                                              );
                                                            })
                                                            .toList(),
                                                  ),
                                                ),

                                              // 4. Footer Item (User & Note)
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.person_outline,
                                                    size: 12,
                                                    color: Colors.black,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Admin: ${orderDetail?['users_name']}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.black,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // 3. Subtotal
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              convertIDR(line['subtotal']),
                                              style: TextStyle(
                                                fontSize: 16.0,
                                                color:
                                                    line['subtotal'] !=
                                                        line['total']
                                                    ? Colors.black45
                                                    : Colors.black,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (line['subtotal'] !=
                                                line['total'])
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    '- ${convertIDR(line['subtotal'] - line['total'])}',
                                                    style: TextStyle(
                                                      fontSize: 16.0,
                                                      color: Colors.red[300],
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  Container(
                                                    height: 1.5,
                                                    width: 100,
                                                    color: Colors.redAccent,
                                                  ),
                                                  Text(
                                                    convertIDR(line['total']),
                                                    style: const TextStyle(
                                                      fontSize: 16.0,
                                                      color: Colors.black87,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                              Container(
                                padding: const EdgeInsets.all(20.0),
                                decoration: BoxDecoration(
                                  color: Colors
                                      .grey[50], // Beri background tipis agar terpisah dari list barang
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  children: [
                                    // 1. Baris Subtotal
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Subtotal Order',
                                          style: TextStyle(
                                            fontSize: 16.0,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        Text(
                                          convertIDR(
                                            orderDetail?['subtotal_amount'] ??
                                                0,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 16.0,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),

                                    // 2. Baris Diskon (Hanya muncul jika ada diskon)
                                    if (orderDetail?['discount_amount'] !=
                                            null &&
                                        orderDetail?['discount_amount'] != 0)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 12.0,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Diskon',
                                              style: TextStyle(
                                                fontSize: 16.0,
                                                color: Colors.red[400],
                                              ),
                                            ),
                                            Text(
                                              '- ${convertIDR(orderDetail?['discount_amount'])}',
                                              style: TextStyle(
                                                fontSize: 16.0,
                                                color: Colors.red[700],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // 3. Garis Pemisah (Dash/Divider)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 15.0,
                                      ),
                                      child: Divider(
                                        color: Colors.grey[300],
                                        thickness: 1,
                                      ),
                                    ),

                                    // 4. GRAND TOTAL
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'TOTAL AKHIR',
                                          style: TextStyle(
                                            fontSize: 18.0,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                        Text(
                                          convertIDR(
                                            orderDetail?['total_amount'] ?? 0,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 24.0,
                                            color: Colors
                                                .orange, // Tetap gunakan orange sebagai aksen utama
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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

  Widget _buildSmallBadge({required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }

  // Helper untuk Label Method
  String _getMethodLabel(int id) {
    if (id == 1) return 'Takeaway';
    if (id == 2) return 'Delivery';
    return 'Compliment';
  }

  // Helper untuk Warna Method
  Color _getMethodColor(int id) {
    if (id == 1) return Colors.teal;
    if (id == 2) return Colors.orange;
    return Colors.purple;
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black.withOpacity(0.05)),
            ),
            child: Icon(icon, size: 22.0, color: Colors.blueGrey[700]),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.0,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplimentStatus(int? status) {
    bool isApproved = status == 1;
    return Center(
      child: Column(
        children: [
          Icon(
            isApproved ? Icons.check_circle : Icons.cancel,
            color: isApproved ? Colors.green : Colors.red,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            isApproved ? 'APPROVED' : 'REJECTED',
            style: TextStyle(
              color: isApproved ? Colors.green : Colors.red,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper Widget 2: Payment Info Row ---
  Widget _buildPaymentInfo(Map<String, dynamic>? detail) {
    int total = detail?['total_amount'] ?? 0;
    int bayar = detail?['pay_amount'] ?? 0;
    int kembali = bayar - total;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildAmountColumn('Total Tagihan', total, Colors.black87),
        _buildVerticalDivider(),
        _buildAmountColumn('Total Bayar', bayar, Colors.blue),
        _buildVerticalDivider(),
        _buildAmountColumn('Kembali', kembali, Colors.orange[700]!),
      ],
    );
  }

  Widget _buildAmountColumn(String label, int amount, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          FittedBox(
            // Mencegah teks terpotong jika angka terlalu besar
            fit: BoxFit.scaleDown,
            child: Text(
              convertIDR(amount),
              style: TextStyle(
                fontSize: 18.0, // Sedikit diperkecil agar lebih elegan
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(height: 30, width: 1, color: Colors.grey[200]);
  }
}
