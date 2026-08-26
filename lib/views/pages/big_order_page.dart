import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:number_pagination/number_pagination.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/big_order_service.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/storage/profile_storage_service.dart';
import 'package:pos_panglima_app/views/pages/big_order_create_page.dart';
import 'package:pos_panglima_app/views/pages/big_order_detail_page.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/skeleton_loader.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';

class BigOrderPage extends StatefulWidget {
  const BigOrderPage({super.key});

  @override
  State<BigOrderPage> createState() => _BigOrderPageState();
}

class _BigOrderPageState extends State<BigOrderPage> {
  final apiClient = ApiClient();
  late final BigOrderService bigOrderService;
  late final AuthService authService;

  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  // Filter status: '' = semua.
  String _status = '';
  String _search = '';
  DateTimeRange? _pickupRange;
  int _page = 1;
  bool _localeReady = false;

  // Outlet hub (customer) id — wajib dikirim ke API daftar Big Order supaya
  // hanya pesanan outlet ini yang tampil.
  int? _outletHubId;

  List _list = [];
  bool _isLoading = true;
  bool _isEmpty = false;
  Map<String, dynamic>? _pagination;

  static const _statusFilters = [
    {'label': 'Semua', 'value': ''},
    {'label': 'Belum lunas', 'value': 'big_pending'},
    {'label': 'Lunas', 'value': 'big_paid'},
    {'label': 'Selesai', 'value': 'active'},
    {'label': 'Batal', 'value': 'big_cancelled'},
  ];

  @override
  void initState() {
    super.initState();
    bigOrderService = BigOrderService(apiClient.dio);
    authService = AuthService(apiClient.dio);
    initializeDateFormatting('id_ID', null).then((_) {
      if (mounted) setState(() => _localeReady = true);
    });
    _bootstrap();
  }

  /// Ambil outlet hub id dulu, baru muat daftar — id ini wajib pada query API.
  Future<void> _bootstrap() async {
    await _resolveOutletHubId();
    if (!mounted) return;
    await _fetch();
  }

  /// Sumber utama: endpoint profil (`/me` → `data.customer[0]`), sama seperti
  /// halaman lain. Bila gagal (offline), pakai profil yang disimpan saat login.
  Future<void> _resolveOutletHubId() async {
    try {
      final response = await authService.getProfile();
      final data = response.data['data'];
      final cust =
          (data?['customer'] is List && (data['customer'] as List).isNotEmpty)
          ? (data['customer'] as List)[0]
          : null;
      final id = int.tryParse(cust?.toString() ?? '');
      if (id != null) {
        _outletHubId = id;
        return;
      }
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order_page.resolveOutletHub');
    }
    final cached = await ProfileStorageService.get();
    _outletHubId = int.tryParse(cached?['customerId']?.toString() ?? '');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fmtApiDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Outlet hub bisa belum terisi bila resolusi awal gagal — coba sekali lagi.
      if (_outletHubId == null) await _resolveOutletHubId();
      final response = await bigOrderService.getList(
        page: _page,
        limit: 10,
        status: _status,
        search: _search,
        outletHubId: _outletHubId,
        pickupFrom: _pickupRange != null
            ? _fmtApiDate(_pickupRange!.start)
            : null,
        pickupTo: _pickupRange != null ? _fmtApiDate(_pickupRange!.end) : null,
      );
      List list = [];
      Map<String, dynamic>? pagination;
      if (response.data['data'] is List) {
        list = response.data['data'];
        pagination = response.data['metadata'] ?? response.data['pagination'];
      }
      if (!mounted) return;
      setState(() {
        _list = list;
        _isLoading = false;
        _isEmpty = list.isEmpty;
        _pagination = pagination;
      });
    } on DioException catch (e, stack) {
      // 404 "data kosong" = keadaan normal (bukan error).
      if (e.response?.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          _list = [];
          _isLoading = false;
          _isEmpty = true;
          _pagination = e.response?.data is Map
              ? (e.response?.data['metadata'] as Map<String, dynamic>?)
              : null;
        });
        return;
      }
      CrashReporter.report(e, stack, reason: 'big_order_page.fetch');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isEmpty = true;
      });
      SnackbarUtil.show(
        context,
        title: 'Gagal memuat Big Order',
        message: BigOrderService.humanizeError(e),
        status: SnackBarStatus.error,
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order_page.fetch');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isEmpty = true;
      });
      SnackbarUtil.show(
        context,
        title: 'Gagal memuat Big Order',
        message: 'Terjadi kendala saat mengambil data.',
        status: SnackBarStatus.error,
      );
    }
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _search = v.trim();
      _page = 1;
      _fetch();
    });
  }

  void _selectStatus(String value) {
    setState(() {
      _status = value;
      _page = 1;
    });
    _fetch();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _pickupRange,
      helpText: 'Rentang Tanggal Ambil',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            onSurface: Color(0xFF2D3436),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _pickupRange = picked;
        _page = 1;
      });
      _fetch();
    }
  }

  void _clearFilters() {
    setState(() {
      _status = '';
      _search = '';
      _searchCtrl.clear();
      _pickupRange = null;
      _page = 1;
    });
    _fetch();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BigOrderCreatePage()),
    );
    if (created == true && mounted) {
      setState(() => _page = 1);
      _fetch();
    }
  }

  final Set<dynamic> _printing = {};

  Future<void> _printStruk(dynamic item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null || _printing.contains(id)) return;
    setState(() => _printing.add(id));
    try {
      // Detail dibutuhkan untuk daftar item + nilai uang terbaru.
      final res = await bigOrderService.getDetail(id);
      final detail = Map<String, dynamic>.from(res.data['data'] as Map);

      // Nama kasir (untuk logo/header) — detail & list bisa kosong, jadi
      // fallback ke kasir pada riwayat pembayaran.
      final payments = (detail['payments'] as List?) ?? [];
      String usersName = (item['users_name'] ?? '').toString();
      if (usersName.isEmpty) {
        usersName = (detail['users_name'] ?? '').toString();
      }
      if (usersName.isEmpty && payments.isNotEmpty) {
        usersName = (payments.first['users_name'] ?? '').toString();
      }

      final data = <String, dynamic>{
        ...detail,
        // Nama pelanggan tidak ada di detail → ambil dari kartu daftar.
        'customers_name': (detail['customers_name']?.toString().isNotEmpty ?? false)
            ? detail['customers_name']
            : item['customers_name'],
        'document_number':
            detail['document_number'] ?? item['document_number'],
        'pickup_at': detail['pickup_at'] ?? item['pickup_at'],
      };
      final ok = await BluetoothPrinterService.printBigOrder(
        data: data,
        usersName: usersName,
      );
      if (!mounted) return;
      if (!ok) {
        SnackbarUtil.show(
          context,
          title: 'Printer tidak terhubung',
          message: 'Hubungkan printer Bluetooth terlebih dahulu.',
          status: SnackBarStatus.warning,
        );
      }
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order_page.printStruk');
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Gagal mencetak',
        message: 'Terjadi kendala saat mencetak struk. Coba kembali.',
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => _printing.remove(id));
    }
  }

  Future<void> _openDetail(dynamic item) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BigOrderDetailPage(
          id: id,
          initial: Map<String, dynamic>.from(item as Map),
        ),
      ),
    );
    if (changed == true && mounted) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _buildFilterBar(),
            _buildInfoBar(),
            Expanded(
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: SkeletonLoader.detailInventorySkeleton(
                        timeout: const Duration(seconds: 10),
                        onRetry: _fetch,
                      ),
                    )
                  : _isEmpty
                  ? _buildEmpty()
                  : _buildList(),
            ),
            _buildPager(),
          ],
        ),
        Positioned(
          right: 24,
          bottom: 24,
          child: FloatingActionButton.extended(
            heroTag: 'big_order_fab',
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            onPressed: _openCreate,
            icon: const Icon(Icons.add),
            label: const Text(
              'Big Order Baru',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final rangeLabel = _pickupRange == null
        ? 'Semua tanggal'
        : (_fmtApiDate(_pickupRange!.start) == _fmtApiDate(_pickupRange!.end)
              ? _dLabel(_pickupRange!.start)
              : '${_dLabel(_pickupRange!.start)} – ${_dLabel(_pickupRange!.end)}');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Cari no. dokumen, nama, atau kontak',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: _pickDateRange,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        rangeLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_pickupRange != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _pickupRange = null;
                              _page = 1;
                            });
                            _fetch();
                          },
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _statusFilters) ...[
                  _buildChip(f['label']!, f['value']!),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, String value) {
    final active = _status == value;
    return GestureDetector(
      onTap: () => _selectStatus(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.primary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBar() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF8E1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Color(0xFF7A5200),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Halaman ini terpisah dari kasir. Membuat Big Order tidak mengisi '
              'keranjang, jadi kasir tetap bisa melayani pembeli lain.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.brown.shade700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Color(0xFFFDECEA),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_rounded,
                size: 44,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Tidak ada Big Order',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Coba longgarkan filter tanggal atau status, atau buat pesanan baru.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: _clearFilters,
                  child: const Text('Hapus filter'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: _openCreate,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Big Order Baru'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: _list.length,
      itemBuilder: (context, index) => _buildCard(_list[index]),
    );
  }

  Widget _buildCard(dynamic item) {
    final status = (item['status'] ?? '').toString();
    final total = (item['total_amount'] as num?)?.toInt() ?? 0;
    final dibayar = (item['total_dibayar'] as num?)?.toInt() ?? 0;
    final sisa = (item['sisa_tagihan'] as num?)?.toInt() ?? 0;
    final lunas = sisa <= 0;
    final name = (item['customers_name'] ?? '-').toString();
    final contact = (item['customers_contact'] ?? '').toString();
    final pickupStr = item['pickup_at']?.toString() ?? '';
    final pickup = DateTime.tryParse(pickupStr);

    final timeLabel = pickup != null
        ? (_localeReady
              ? DateFormat('HH.mm').format(pickup)
              : DateFormat('HH.mm').format(pickup))
        : '--.--';
    final dateLabel = pickup != null ? _dLabel(pickup) : '-';

    final (statusColor, statusBg) = _statusColors(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openDetail(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Jam + tanggal — lebar tetap 90
                SizedBox(
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Nama + kontak
                Expanded(  
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (contact.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          contact,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Nominal total — lebar tetap 140, rata kanan, digit tabular
                SizedBox(
                  width: 140,
                  child: Text(
                    convertIDR(total),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Status pembayaran (Sisa/Dibayar/Lunas) — lebar tetap 160, rata kiri
                SizedBox(
                  width: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lunas ? '✓ Lunas' : 'Sisa ${convertIDR(sisa)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: lunas
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (dibayar > 0 && !lunas) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Dibayar ${convertIDR(dibayar)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Badge status + tombol aksi — lebar tetap 230, rata kanan
                SizedBox(
                  width: 230,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          BigOrderService.statusLabel(status),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildActionButton(status, item),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Cetak struk (ujung paling kanan)
                _printing.contains((item['id'] as num?)?.toInt())
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : IconButton(
                        onPressed: () => _printStruk(item),
                        icon: const Icon(Icons.print_outlined),
                        color: Colors.grey.shade600,
                        tooltip: 'Cetak struk',
                        visualDensity: VisualDensity.compact,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String status, dynamic item) {
    String label;
    Color bg;
    Color fg = Colors.white;
    switch (status) {
      case 'big_pending':
        label = 'Pelunasan';
        bg = AppColors.primary;
        break;
      case 'big_paid':
        label = 'Serah terima';
        bg = Colors.green.shade600;
        break;
      default:
        label = 'Detail';
        bg = Colors.white;
        fg = Colors.grey.shade700;
    }
    final isOutline = status != 'big_pending' && status != 'big_paid';
    // minWidth sama untuk semua tombol supaya selebar sama antar baris.
    const minSize = Size(120, 34);
    final textStyle = const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold);
    return isOutline
        ? OutlinedButton(
            onPressed: () => _openDetail(item),
            style: OutlinedButton.styleFrom(
              foregroundColor: fg,
              minimumSize: minSize,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(label, style: textStyle),
          )
        : FilledButton(
            onPressed: () => _openDetail(item),
            style: FilledButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              minimumSize: minSize,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(label, style: textStyle),
          );
  }

  (Color, Color) _statusColors(String status) {
    switch (status) {
      case 'big_pending':
        return (const Color(0xFF8A4B00), const Color(0xFFFFF3E0));
      case 'big_paid':
        return (Colors.green.shade700, Colors.green.shade50);
      case 'active':
        return (Colors.blueGrey.shade600, Colors.blueGrey.shade50);
      case 'big_cancelled':
        return (Colors.red.shade700, Colors.red.shade50);
      default:
        return (Colors.grey.shade700, Colors.grey.shade100);
    }
  }

  String _dLabel(DateTime d) => _localeReady
      ? DateFormat('dd MMM yyyy', 'id_ID').format(d)
      : DateFormat('dd MMM yyyy').format(d);

  Widget _buildPager() {
    int totalPages = 1;
    final p = _pagination;
    if (p != null) {
      if (p['total_page'] != null) {
        totalPages = (p['total_page'] as num).toInt();
      } else if (p['total_pages'] != null) {
        totalPages = (p['total_pages'] as num).toInt();
      } else if (p['total'] != null) {
        final total = (p['total'] as num).toInt();
        final limit = (p['limit'] as num?)?.toInt() ?? 10;
        totalPages = (total / limit).ceil();
      }
    }
    if (totalPages <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: NumberPagination(
        onPageChanged: (int pageNumber) {
          setState(() => _page = pageNumber);
          _fetch();
        },
        visiblePagesCount: totalPages < 3 ? totalPages : 3,
        totalPages: totalPages,
        currentPage: _page.clamp(1, totalPages),
        buttonRadius: 12,
        selectedButtonColor: AppColors.primarySelected,
        selectedNumberColor: Colors.black,
        unSelectedButtonColor: Colors.grey[100]!,
        unSelectedNumberColor: Colors.grey[700]!,
        numberButtonSize: const Size(35, 35),
        controlButtonSize: const Size(35, 35),
        fontSize: 14,
        sectionSpacing: 5,
        navigationButtonSpacing: 0,
      ),
    );
  }
}
