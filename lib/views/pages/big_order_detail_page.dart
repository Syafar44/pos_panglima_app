import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pos_panglima_app/services/big_order_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/method_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';

class BigOrderDetailPage extends StatefulWidget {
  final int id;

  /// Data awal dari kartu daftar (nama, kontak, dll) untuk tampil cepat sebelum
  /// detail penuh dimuat. Endpoint detail tidak mengembalikan nama pemesan.
  final Map<String, dynamic>? initial;

  const BigOrderDetailPage({super.key, required this.id, this.initial});

  @override
  State<BigOrderDetailPage> createState() => _BigOrderDetailPageState();
}

class _BigOrderDetailPageState extends State<BigOrderDetailPage> {
  final apiClient = ApiClient();
  late final BigOrderService bigOrderService;
  late final MethodService methodService;

  bool _localeReady = false;
  bool _isLoading = true;
  bool _busy = false; // aksi (bayar/handover/cancel) sedang berjalan
  bool _changed = false; // untuk refresh daftar saat kembali

  Map<String, dynamic> _data = {};
  List _payments = [];
  List<Map<String, dynamic>> _paymentMethods = [];
  int? _shiftId;

  // Audit (untuk handover)
  String _latitude = '';
  String _longitude = '';
  String _deviceInfo = '';

  String get _status =>
      (_data['status'] ?? widget.initial?['status'] ?? '').toString();
  int get _total =>
      (_data['total_amount'] as num?)?.toInt() ??
      (widget.initial?['total_amount'] as num?)?.toInt() ??
      0;
  int get _dibayar => (_data['total_dibayar'] as num?)?.toInt() ?? 0;
  int get _sisa =>
      (_data['sisa_tagihan'] as num?)?.toInt() ?? (_total - _dibayar);

  @override
  void initState() {
    super.initState();
    bigOrderService = BigOrderService(apiClient.dio);
    methodService = MethodService(apiClient.dio);
    initializeDateFormatting('id_ID', null).then((_) {
      if (mounted) setState(() => _localeReady = true);
    });
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _load();
    _loadMethods();
    _captureAudit();
  }

  Future<void> _load() async {
    try {
      final res = await bigOrderService.getDetail(widget.id);
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      if (!mounted) return;
      setState(() {
        _data = data;
        _payments = (data['payments'] as List?) ?? [];
        _isLoading = false;
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order_detail.load');
      if (!mounted) return;
      setState(() => _isLoading = false);
      SnackbarUtil.show(
        context,
        title: 'Gagal memuat detail',
        message: BigOrderService.humanizeError(e),
        status: SnackBarStatus.error,
      );
    }
  }

  Future<void> _loadMethods() async {
    try {
      final res = await methodService.getPaymentMethods();
      final list = (res.data['data'] as List?) ?? [];
      final shiftId = await ShiftStorageService.getShiftId();
      final methods = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // Pastikan CASH / TUNAI (id 11) tersedia (mengikuti payment_page).
      if (!methods.any((m) => (m['id'] as num?)?.toInt() == 11)) {
        methods.insert(0, {'id': 11, 'name': 'CASH / TUNAI', 'is_cash': 1});
      }
      if (!mounted) return;
      setState(() {
        _paymentMethods = methods;
        _shiftId = shiftId;
      });
    } catch (_) {}
  }

  Future<void> _captureAudit() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      _deviceInfo =
          '${android.manufacturer} ${android.model} / Android ${android.version.release}';
    } catch (_) {}
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (enabled) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          );
          _latitude = pos.latitude.toStringAsFixed(6);
          _longitude = pos.longitude.toStringAsFixed(6);
        }
      }
    } catch (_) {}
  }

  bool _isCashMethod(Map<String, dynamic> m) {
    if (m['is_cash'] != null) {
      final v = m['is_cash'];
      if (v is num) return v == 1;
      if (v is bool) return v;
    }
    final name = (m['name'] ?? '').toString().toLowerCase();
    return name.contains('tunai') || name.contains('cash');
  }

  // ─── Aksi: tambah pembayaran ────────────────────────────────────────────────

  Future<void> _addPayment() async {
    if (_paymentMethods.isEmpty) {
      SnackbarUtil.show(
        context,
        title: 'Metode belum tersedia',
        message: 'Metode pembayaran belum termuat. Coba kembali.',
        status: SnackBarStatus.warning,
      );
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PaymentSheet(
        sisa: _sisa,
        methods: _paymentMethods,
        docNumber: (_data['document_number'] ?? '').toString(),
      ),
    );
    if (result == null || !mounted) return;

    final method = _paymentMethods.firstWhere(
      (m) => (m['id'] as num?)?.toInt() == result['method_id'],
      orElse: () => const {},
    );

    setState(() => _busy = true);
    try {
      await bigOrderService.addPayment(widget.id, {
        'pos_payment_method_id': result['method_id'],
        'amount': result['amount'],
        'pos_shifts_id': _shiftId,
        'is_cash': _isCashMethod(Map<String, dynamic>.from(method)) ? 1 : 0,
      });
      _changed = true;
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Pembayaran tercatat',
        message: 'Pembayaran berhasil ditambahkan.',
        status: SnackBarStatus.success,
      );
      await _load();
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order_detail.addPayment');
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Gagal menambah pembayaran',
        message: BigOrderService.humanizeError(e),
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Aksi: serah terima ─────────────────────────────────────────────────────

  Future<void> _handover() async {
    final confirm = await _confirm(
      title: 'Serah Terima & Potong Stok?',
      message:
          'Stok akan dipotong tepat saat ini dan pesanan ditutup. Lakukan hanya '
          'jika barang benar-benar diserahkan. Lanjutkan?',
      confirmText: 'Ya, Serahkan',
      confirmColor: Colors.green.shade600,
    );
    if (confirm != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await bigOrderService.handover(widget.id, {
        'latitude': _latitude,
        'longitude': _longitude,
        'device_info': _deviceInfo,
      });
      _changed = true;
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Pesanan diserahkan',
        message: 'Stok dipotong dan pesanan masuk laporan penjualan.',
        status: SnackBarStatus.success,
      );
      Navigator.pop(context, true);
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order_detail.handover');
      if (!mounted) return;
      final code = BigOrderService.errorCode(e);
      if (code.startsWith('insufficient_stock')) {
        _showStockError(code);
      } else {
        SnackbarUtil.show(
          context,
          title: 'Gagal serah terima',
          message: BigOrderService.humanizeError(e),
          status: SnackBarStatus.error,
        );
      }
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showStockError(String code) {
    // Format: "insufficient_stock: Nama (KODE): required X, stock Y; ..."
    final idx = code.indexOf(':');
    final body = idx >= 0 ? code.substring(idx + 1).trim() : code;
    final items = body
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: const Icon(
          Icons.warning_amber_rounded,
          size: 44,
          color: Colors.orange,
        ),
        title: const Text(
          'Stok Kurang',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Serah terima belum bisa diproses. Pesanan tetap Lunas dan bisa '
              'dicoba lagi setelah kiriman datang.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Text(
                        it,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF7A2018),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade600,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handover();
            },
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }

  // ─── Aksi: batalkan ─────────────────────────────────────────────────────────

  Future<void> _cancel() async {
    final alasan = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(dibayar: _dibayar),
    );
    if (alasan == null || !mounted) return;

    // Dua modal konfirmasi berurutan sebelum benar-benar mengajukan pembatalan.
    final first = await _confirm(
      title: 'Ajukan Pembatalan?',
      message:
          '${convertIDR(_dibayar)} yang sudah dibayar akan hangus dan tidak '
          'dikembalikan sistem. Lanjutkan?',
      confirmText: 'Lanjut',
      confirmColor: Colors.red.shade600,
    );
    if (first != true || !mounted) return;

    final second = await _confirm(
      title: 'Konfirmasi Pembatalan',
      message:
          'Pastikan keputusan sudah benar. Ajukan pembatalan pesanan ini '
          'sekarang?',
      confirmText: 'Ya, Ajukan',
      confirmColor: Colors.red.shade600,
    );
    if (second != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await bigOrderService.cancel(widget.id, alasan);
      _changed = true;
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Pembatalan diproses',
        message: 'Pengajuan pembatalan terkirim.',
        status: SnackBarStatus.success,
      );
      await _load();
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order_detail.cancel');
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Gagal membatalkan',
        message: BigOrderService.humanizeError(e),
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmText,
    Color? confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: Icon(
          Icons.help_outline_rounded,
          size: 44,
          color: confirmColor ?? AppColors.primary,
        ),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.only(
          bottom: 20,
          left: 20,
          right: 20,
          top: 4,
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: const Text(
                    'Batal',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: confirmColor ?? AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    confirmText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textDark,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: const Text(
            'Detail Big Order',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: Colors.grey.shade200),
          ),
        ),
        bottomNavigationBar: _isLoading ? null : _buildBottomBar(),
        body: _isLoading
            ? Center(
                child: ModernLoading(
                  timeout: const Duration(seconds: 15),
                  onRetry: () {
                    setState(() => _isLoading = true);
                    _load();
                  },
                ),
              )
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildBody()),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    final docNumber =
        (_data['document_number'] ?? widget.initial?['document_number'] ?? '-')
            .toString();
    final name = (widget.initial?['customers_name'] ?? '').toString();
    final contact = (widget.initial?['customers_contact'] ?? '').toString();
    final pickupStr = (_data['pickup_at'] ?? widget.initial?['pickup_at'] ?? '')
        .toString();
    final pickup = DateTime.tryParse(pickupStr);
    final (sColor, sBg) = _statusColors(_status);

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  docNumber,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [name, contact].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: sBg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              BigOrderService.statusLabel(_status),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: sColor,
              ),
            ),
          ),
          if (pickup != null) ...[
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _localeReady
                      ? DateFormat(
                          'EEE, dd MMM · HH.mm',
                          'id_ID',
                        ).format(pickup)
                      : DateFormat('dd MMM · HH.mm').format(pickup),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Waktu pengambilan',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // Blok uang
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _moneyCell(
                      'Total pesanan',
                      convertIDR(_total),
                      null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _moneyCell(
                      'Sudah dibayar',
                      convertIDR(_dibayar),
                      Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _sisa <= 0
                      ? Colors.green.shade50
                      : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _sisa <= 0
                        ? Colors.green.shade200
                        : const Color(0xFFFFCC80),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sisa tagihan',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: _sisa <= 0
                                ? Colors.green.shade700
                                : const Color(0xFF8A4B00),
                          ),
                        ),
                        Text(
                          'DIHITUNG SERVER',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      convertIDR(_sisa),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _sisa <= 0
                            ? Colors.green.shade700
                            : const Color(0xFF8A4B00),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Item pesanan
        if (((_data['pos_order_lines'] as List?) ?? []).isNotEmpty) ...[
          _sectionCard('Item pesanan', _buildItems()),
          const SizedBox(height: 14),
        ],

        // Keterangan
        if (((_data['keterangan'] ?? widget.initial?['keterangan'] ?? '')
                .toString())
            .isNotEmpty) ...[
          _sectionCard(
            'Keterangan',
            Text(
              (_data['keterangan'] ?? widget.initial?['keterangan']).toString(),
              style: const TextStyle(fontSize: 14.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Riwayat pembayaran
        _sectionCard(
          'Riwayat pembayaran',
          _payments.isEmpty
              ? Text(
                  'Belum ada pembayaran.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                )
              : Column(
                  children: [
                    for (int i = 0; i < _payments.length; i++)
                      _paymentTile(_payments[i], i == _payments.length - 1),
                  ],
                ),
        ),
        const SizedBox(height: 90),
      ],
    );
  }

  Widget _moneyCell(String label, String value, Color? valueColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItems() {
    final lines = (_data['pos_order_lines'] as List?) ?? [];
    return Column(
      children: [
        for (int i = 0; i < lines.length; i++)
          _itemTile(lines[i], i == lines.length - 1),
      ],
    );
  }

  Widget _itemTile(dynamic e, bool last) {
    final name = (e['pos_menus_name'] ?? e['item_name'] ?? '-').toString();
    final qty = (e['quantity'] as num?)?.toInt() ?? 0;
    final price = (e['price'] as num?)?.toInt() ?? 0;
    final total = (e['total'] as num?)?.toInt() ??
        (e['subtotal'] as num?)?.toInt() ??
        price * qty;
    final props = (e['pos_order_lines_props'] as List?) ?? [];

    return Container(
      padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 12),
      margin: EdgeInsets.only(bottom: last ? 0 : 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                convertIDR(total),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$qty × ${convertIDR(price)}',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
          ),
          if (props.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final p in props)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '• ${(p['quantity'] as num?)?.toInt() ?? 0}× ${(p['pos_menus_name'] ?? '-')}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 0.8,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _paymentTile(dynamic p, bool last) {
    final method = (p['pos_payment_method_name'] ?? '-').toString();
    final amount = (p['amount'] as num?)?.toInt() ?? 0;
    final user = (p['users_name'] ?? '').toString();
    final createdStr = (p['created_at'] ?? '').toString();
    final created = DateTime.tryParse(createdStr);
    final dateLabel = created != null
        ? (_localeReady
              ? DateFormat('dd MMM yyyy · HH.mm', 'id_ID').format(created)
              : DateFormat('dd MMM yyyy · HH.mm').format(created))
        : '-';

    return Container(
      padding: EdgeInsets.only(bottom: last ? 0 : 12, top: 4),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      margin: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.payments_rounded,
              size: 17,
              color: Colors.green.shade600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    dateLabel,
                    if (user.isNotEmpty) user,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Text(
            convertIDR(amount),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ],
      ),
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
        return (Colors.blue.shade700, Colors.blue.shade50);
    }
  }

  Widget? _buildBottomBar() {
    if (_status != 'big_pending' && _status != 'big_paid') return null;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _cancel,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Batalkan'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _status == 'big_pending'
                  ? FilledButton.icon(
                      onPressed: _busy ? null : _addPayment,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_card_rounded, size: 18),
                      label: const Text('Pelunasan'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _busy ? null : _handover,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.local_shipping_rounded, size: 18),
                      label: const Text('Serah terima & potong stok'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet: tambah pembayaran
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentSheet extends StatefulWidget {
  final int sisa;
  final List<Map<String, dynamic>> methods;
  final String docNumber;
  const _PaymentSheet({
    required this.sisa,
    required this.methods,
    required this.docNumber,
  });

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late int _methodId;
  final _amountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _methodId = (widget.methods.first['id'] as num?)?.toInt() ?? 0;
    _amountCtrl.text = widget.sisa.toString();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pelunasan',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.docNumber,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sisa tagihan',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.brown.shade700,
                          ),
                        ),
                        Text(
                          'DARI SERVER · JANGAN DIHITUNG ULANG',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      convertIDR(widget.sisa),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.brown.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Metode',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.methods.map((m) {
                  final id = (m['id'] as num?)?.toInt();
                  final active = id == _methodId;
                  return GestureDetector(
                    onTap: () => setState(() => _methodId = id ?? _methodId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: active
                              ? AppColors.primary
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        (m['name'] ?? '-').toString(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : Colors.grey[700],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nominal (pelunasan penuh)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              // Dikunci = sisa tagihan. Pelunasan = bayar penuh sisa DP.
              TextField(
                controller: _amountCtrl,
                readOnly: true,
                enabled: false,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  prefixStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  suffixIcon: Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: Colors.grey[500],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.sisa >= 1
                      ? () => Navigator.pop(context, {
                          'method_id': _methodId,
                          'amount': widget.sisa,
                        })
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Terima ${convertIDR(widget.sisa)} & lunasi',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog: batalkan
// ─────────────────────────────────────────────────────────────────────────────

class _CancelDialog extends StatefulWidget {
  final int dibayar;
  const _CancelDialog({required this.dibayar});

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Batalkan Big Order ini?',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF3B4AE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${convertIDR(widget.dibayar)} yang sudah dibayar akan hangus',
                    style: const TextStyle(
                      color: Color(0xFF8E1010),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sesuai kebijakan, DP yang sudah masuk tidak dikembalikan ke pelanggan. Jangan proses pengembalian lewat kas manual. Jelaskan hal ini ke pelanggan sebelum membatalkan pesanan.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF7A2018),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Alasan pembatalan · wajib',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Tulis alasan…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Pembatalan bisa memerlukan persetujuan atasan (status jadi "menunggu persetujuan").',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kembali'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () {
            final v = _ctrl.text.trim();
            if (v.isEmpty) {
              SnackbarUtil.show(
                context,
                title: 'Alasan wajib',
                message: 'Isi alasan pembatalan terlebih dahulu.',
                status: SnackBarStatus.warning,
              );
              return;
            }
            Navigator.pop(context, v);
          },
          child: const Text('Ajukan pembatalan'),
        ),
      ],
    );
  }
}
