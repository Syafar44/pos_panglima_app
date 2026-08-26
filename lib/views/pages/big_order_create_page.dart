import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/big_order_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/menu_service.dart';
import 'package:pos_panglima_app/services/method_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';

/// Satu baris item pesanan Big Order.
class _BigLine {
  final Map<String, dynamic> menu; // {id, title, price, props}
  int qty;
  final List<Map<String, dynamic>> props; // props terpilih {id, title, quantity}
  _BigLine({required this.menu, required this.qty, required this.props});

  int get price => (menu['price'] as num?)?.toInt() ?? 0;
  int get total => price * qty;
}

class BigOrderCreatePage extends StatefulWidget {
  const BigOrderCreatePage({super.key});

  @override
  State<BigOrderCreatePage> createState() => _BigOrderCreatePageState();
}

class _BigOrderCreatePageState extends State<BigOrderCreatePage> {
  final apiClient = ApiClient();
  late final BigOrderService bigOrderService;
  late final MenuService menuService;
  late final MethodService methodService;
  late final AuthService authService;

  bool _localeReady = false;
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Master data
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _paymentMethods = [];
  int? _orderMethodId;
  int? _outletHubId;
  int? _shiftId;

  // Form state
  Map<String, dynamic>? _customer;
  final List<_BigLine> _lines = [];
  DateTime _pickupDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _pickupTime = const TimeOfDay(hour: 12, minute: 0);
  final _keteranganCtrl = TextEditingController();
  final _ongkirCtrl = TextEditingController(text: '0');
  int _ongkir = 0;

  /// Sementara disembunyikan sampai API ongkir dari backend siap.
  /// Set ke `true` untuk mengaktifkan kembali input & rincian ongkir.
  final bool _ongkirEnabled = false;
  int _dpAmount = 0;
  bool _dpTouched = false;
  int? _paymentMethodId;

  // Audit
  String _latitude = '';
  String _longitude = '';
  String _deviceInfo = '';

  int get _total => _lines.fold(0, (s, l) => s + l.total);

  @override
  void initState() {
    super.initState();
    bigOrderService = BigOrderService(apiClient.dio);
    menuService = MenuService(apiClient.dio);
    methodService = MethodService(apiClient.dio);
    authService = AuthService(apiClient.dio);
    initializeDateFormatting('id_ID', null).then((_) {
      if (mounted) setState(() => _localeReady = true);
    });
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _bootstrap();
    _captureAudit();
  }

  @override
  void dispose() {
    _keteranganCtrl.dispose();
    _ongkirCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        menuService.getList(),
        methodService.getPaymentMethods(),
        methodService.getOrderMethods(),
        authService.getProfile(),
      ]);

      // Menu → flatten produk dari tiap kategori.
      // Response: data = [ { category, data: [ {product}, ... ] }, ... ].
      final menuData = results[0].data['data'];
      final products = <Map<String, dynamic>>[];
      if (menuData is List) {
        for (final cat in menuData) {
          final prods = (cat is Map) ? cat['data'] : null;
          if (prods is List) {
            for (final p in prods) {
              if (p is Map) products.add(Map<String, dynamic>.from(p));
            }
          }
        }
      }

      final payMethods = <Map<String, dynamic>>[];
      final payData = results[1].data['data'];
      if (payData is List) {
        for (final m in payData) {
          if (m is Map) payMethods.add(Map<String, dynamic>.from(m));
        }
      }
      // Pastikan CASH / TUNAI (id 11) tersedia (mengikuti payment_page).
      if (!payMethods.any((m) => (m['id'] as num?)?.toInt() == 11)) {
        payMethods.insert(0, {'id': 11, 'name': 'CASH / TUNAI', 'is_cash': 1});
      }

      int? orderMethodId;
      final orderData = results[2].data['data'];
      if (orderData is List && orderData.isNotEmpty) {
        // Default: "Takeaway" bila ada, kalau tidak ambil pertama.
        final takeaway = orderData.firstWhere(
          (m) => (m['name'] ?? '').toString().toLowerCase() == 'takeaway',
          orElse: () => orderData.first,
        );
        orderMethodId = (takeaway['id'] as num?)?.toInt();
      }

      final profile = results[3].data['data'];
      final cust =
          (profile?['customer'] is List &&
              (profile['customer'] as List).isNotEmpty)
          ? profile['customer'][0]
          : null;
      final outletHubId = int.tryParse(cust?.toString() ?? '');

      final shiftId = await ShiftStorageService.getShiftId();

      if (!mounted) return;
      setState(() {
        _products = products;
        _paymentMethods = payMethods;
        _orderMethodId = orderMethodId;
        _outletHubId = outletHubId;
        _shiftId = shiftId;
        // Default metode pembayaran pertama.
        if (payMethods.isNotEmpty) {
          _paymentMethodId = (payMethods.first['id'] as num?)?.toInt();
        }
        _isLoading = false;
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order_create.bootstrap');
      if (!mounted) return;
      setState(() => _isLoading = false);
      SnackbarUtil.show(
        context,
        title: 'Gagal memuat data',
        message: 'Tidak dapat memuat menu / metode pembayaran. Coba kembali.',
        status: SnackBarStatus.error,
      );
    }
  }

  Future<void> _captureAudit() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      _deviceInfo =
          '${android.manufacturer} ${android.model} / Android ${android.version.release}';
    } catch (_) {}
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
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

  bool get _canSubmit =>
      _customer != null &&
      _lines.isNotEmpty &&
      _total > 0 &&
      _dpAmount > 0 &&
      _dpAmount <= _total &&
      _paymentMethodId != null &&
      !_isSubmitting;

  int get _effectiveDp {
    // Sebelum user menyentuh DP, default = total (lunas) supaya selalu valid.
    if (!_dpTouched) return _total;
    return _dpAmount;
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

  // ─── Submit ─────────────────────────────────────────────────────────────────

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    String confirmText = 'Ya',
  }) {
    return showDialog<bool>(
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
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.only(bottom: 20, left: 20, right: 20, top: 4),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: const Text('Batal',
                      style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(confirmText,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (_outletHubId == null || _shiftId == null || _orderMethodId == null) {
      SnackbarUtil.show(
        context,
        title: 'Data belum lengkap',
        message:
            'Outlet / shift / metode order tidak tersedia. Pastikan sudah mulai shift.',
        status: SnackBarStatus.warning,
      );
      return;
    }

    // Dua modal konfirmasi berurutan sebelum menyimpan.
    // Modal pertama: rincian ulang (pemesan, item, DP, ongkir).
    final first = await showDialog<bool>(
      context: context,
      builder: (_) => _ReviewDialog(
        customerName: (_customer?['name'] ?? '-').toString(),
        customerContact: (_customer?['contact'] ?? '').toString(),
        lines: _lines,
        total: _total,
        dp: _effectiveDp,
        ongkir: _ongkir,
        showOngkir: _ongkirEnabled,
      ),
    );
    if (first != true || !mounted) return;

    final second = await _confirmDialog(
      title: 'Konfirmasi Pembuatan',
      message: 'Pastikan data pesanan dan DP sudah benar. Simpan sekarang?',
      confirmText: 'Ya, Simpan',
    );
    if (second != true || !mounted) return;

    final method = _paymentMethods.firstWhere(
      (m) => (m['id'] as num?)?.toInt() == _paymentMethodId,
      orElse: () => const {},
    );
    final isCash = _isCashMethod(Map<String, dynamic>.from(method));

    final lines = _lines.map((l) {
      final subtotal = l.total;
      return {
        'pos_menus_id': l.menu['id'],
        'quantity': l.qty,
        'price': l.price,
        'subtotal': subtotal,
        'discount': 0,
        'tax': 0,
        'total': subtotal,
        'props': l.props
            .map((p) => {'pos_menus_id': p['id'], 'quantity': p['quantity']})
            .toList(),
      };
    }).toList();

    final pickupAt =
        '${DateFormat('yyyy-MM-dd').format(_pickupDate)} '
        '${_pickupTime.hour.toString().padLeft(2, '0')}:${_pickupTime.minute.toString().padLeft(2, '0')}:00';

    final payload = <String, dynamic>{
      'customers_id': _customer!['id'],
      'outlet_hub_id': _outletHubId,
      'pos_shifts_id': _shiftId,
      'pos_order_method_id': _orderMethodId,
      'pickup_at': pickupAt,
      'keterangan': _keteranganCtrl.text.trim(),
      'pos_payment_method_id': _paymentMethodId,
      'pay_amount': _effectiveDp,
      'is_cash': isCash ? 1 : 0,
      'latitude': _latitude,
      'longitude': _longitude,
      'device_info': _deviceInfo,
      'lines': lines,
    };

    setState(() => _isSubmitting = true);
    try {
      await bigOrderService.createBigOrder(payload);
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Big Order tersimpan',
        message: 'Pesanan dibuat & DP tercatat. Nomor dokumen dibuat server.',
        status: SnackBarStatus.success,
      );
      Navigator.pop(context, true);
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order_create.submit');
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Gagal menyimpan',
        message: BigOrderService.humanizeError(e),
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── Pemesan ────────────────────────────────────────────────────────────────

  Future<void> _pickCustomer() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CustomerSheet(service: bigOrderService),
    );
    if (selected != null && mounted) {
      setState(() => _customer = selected);
    }
  }

  // ─── Item ───────────────────────────────────────────────────────────────────

  Future<void> _addItem() async {
    if (_products.isEmpty) {
      SnackbarUtil.show(
        context,
        title: 'Menu belum tersedia',
        message: 'Daftar produk belum termuat. Coba kembali.',
        status: SnackBarStatus.warning,
      );
      return;
    }
    final line = await showModalBottomSheet<_BigLine>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ItemSheet(products: _products),
    );
    if (line != null && mounted) {
      setState(() => _lines.add(line));
    }
  }

  void _removeLine(int index) {
    setState(() => _lines.removeAt(index));
  }

  Future<void> _pickDate() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final firstDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickupDate.isBefore(firstDate) ? firstDate : _pickupDate,
      firstDate: firstDate,
      lastDate: firstDate.add(const Duration(days: 365)),
      helpText: 'Tanggal Pengambilan (paling cepat besok)',
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
    if (picked != null) setState(() => _pickupDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _pickupTime,
    );
    if (picked != null) setState(() => _pickupTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        title: const Text(
          'Big Order Baru',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: _isLoading
          ? Center(
              child: ModernLoading(
                timeout: const Duration(seconds: 15),
                onRetry: () {
                  setState(() => _isLoading = true);
                  _bootstrap();
                },
              ),
            )
          : Row(
              children: [
                Expanded(child: _buildForm()),
                _buildSummary(),
              ],
            ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _card(
          num: '1',
          title: 'Pemesan',
          child: _customer == null
              ? _pickRow(
                  icon: Icons.person_outline,
                  title: 'Cari pemesan',
                  subtitle:
                      'Ketik nama, kontak, atau kode. Bisa buat baru juga.',
                  onTap: _pickCustomer,
                  highlight: true,
                )
              : _selectedCustomer(),
        ),
        _card(
          num: '2',
          title: 'Item pesanan',
          trailing: _lines.isEmpty
              ? 'belum ada baris'
              : '${_lines.length} baris',
          child: Column(
            children: [
              for (int i = 0; i < _lines.length; i++) _lineTile(i),
              const SizedBox(height: 4),
              InkWell(
                onTap: _addItem,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      width: 1.5,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      '+ Tambah item',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Stok belum dipotong sekarang. Pemotongan terjadi saat serah terima.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        _card(
          num: '3',
          title: 'Waktu pengambilan',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _fieldBox(
                      label: 'Tanggal ambil',
                      value: _localeReady
                          ? DateFormat(
                              'EEE, dd MMM yyyy',
                              'id_ID',
                            ).format(_pickupDate)
                          : DateFormat('dd MMM yyyy').format(_pickupDate),
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _fieldBox(
                      label: 'Jam',
                      value: _pickupTime.format(context),
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Paling cepat besok (H+1). Server menolak tanggal hari ini atau sebelumnya.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (_ongkirEnabled)
          _card(
          num: '4',
          title: 'Ongkos kirim',
          trailing: 'default 0',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ongkirCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) =>
                    setState(() => _ongkir = int.tryParse(v.trim()) ?? 0),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
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
              const SizedBox(height: 8),
              Text(
                'Isi 0 bila tanpa ongkir. Nilai final mengikuti aturan server.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey[500],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        _card(
          num: _ongkirEnabled ? '5' : '4',
          title: 'Keterangan',
          trailing: 'opsional',
          child: TextField(
            controller: _keteranganCtrl,
            maxLines: 3,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  'Contoh: 60 pcs, kemasan terpisah, label nama tiap kotak',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
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
      ],
    );
  }

  Widget _lineTile(int index) {
    final l = _lines[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  (l.menu['title'] ?? '-').toString(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _removeLine(index),
                icon: const Icon(Icons.close_rounded, color: Colors.grey),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${l.qty} pcs',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '× ${convertIDR(l.price)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const Spacer(),
              Text(
                convertIDR(l.total),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (l.props.isNotEmpty) ...[
            const Divider(height: 16),
            Text(
              'Tambahan: ${l.props.map((p) => '${p['title']} × ${p['quantity']}').join(' · ')}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final total = _total;
    final dp = _effectiveDp;
    final sisa = total - dp;

    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: const Text(
              'RINGKASAN & PEMBAYARAN PERTAMA',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: total == 0
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_rounded,
                            size: 40,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tambahkan item dulu.\nRingkasan & DP muncul di sini.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _sumRow(
                        'Subtotal ${_lines.length} baris',
                        convertIDR(total),
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total pesanan',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            convertIDR(total),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Estimasi. Nilai final dihitung ulang server dari daftar item.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[500],
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDpBox(total, dp, sisa),
                      const SizedBox(height: 16),
                      const Text(
                        'Metode pembayaran pertama',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _paymentMethods.map((m) {
                          final id = (m['id'] as num?)?.toInt();
                          final active = id == _paymentMethodId;
                          return GestureDetector(
                            onTap: () => setState(() => _paymentMethodId = id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.primary
                                    : Colors.white,
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
                                  color: active
                                      ? Colors.white
                                      : Colors.grey[700],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _canSubmit
                                ? 'Simpan & terima ${convertIDR(dp)}'
                                : 'Simpan & terima DP',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _canSubmit
                      ? 'Minimal DP dibaca dari pengaturan server. Jika kurang, ikuti pesan errornya.'
                      : (_customer == null
                            ? 'Pilih pemesan dulu untuk melanjutkan.'
                            : (_lines.isEmpty
                                  ? 'Tambahkan minimal satu item.'
                                  : 'Lengkapi DP & metode pembayaran.')),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _canSubmit
                        ? Colors.grey[500]
                        : Colors.orange.shade800,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDpBox(int total, int dp, int sisa) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'DP dibayar sekarang',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.brown.shade700,
                ),
              ),
              Text(
                convertIDR(dp),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.brown.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _dpChip('Lunas', () {
                setState(() {
                  _dpTouched = true;
                  _dpAmount = total;
                });
              }, selected: _dpTouched && _dpAmount == total),
              const SizedBox(width: 8),
              _dpChip(
                'Nominal lain',
                () => _promptDpAmount(total),
                selected: _dpTouched && _dpAmount != total,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sisa dibayar sebelum diambil',
                style: TextStyle(fontSize: 12.5, color: Colors.brown.shade600),
              ),
              Text(
                convertIDR(sisa),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _promptDpAmount(int total) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _DpAmountDialog(
        total: total,
        // Default terisi 50% dari total (minimum DP umum). User bisa mengubah.
        initial: (_dpTouched && _dpAmount > 0) ? _dpAmount : (total / 2).ceil(),
      ),
    );
    if (result == null || !mounted) return;
    if (result > total) {
      SnackbarUtil.show(
        context,
        title: 'DP terlalu besar',
        message:
            'DP tidak boleh melebihi total pesanan (${convertIDR(total)}).',
        status: SnackBarStatus.warning,
      );
      return;
    }
    setState(() {
      _dpTouched = true;
      _dpAmount = result;
    });
  }

  Widget _dpChip(String label, VoidCallback onTap, {required bool selected}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : const Color(0xFFFFE082),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.brown.shade700,
          ),
        ),
      ),
    );
  }

  Widget _sumRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ─── Widget kecil ─────────────────────────────────────────────────────────

  Widget _card({
    required String num,
    required String title,
    String? trailing,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  num,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                Text(
                  trailing,
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _pickRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: highlight ? const Color(0xFFFFFBF0) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highlight ? const Color(0xFFF9A825) : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _selectedCustomer() {
    final name = (_customer!['name'] ?? '-').toString();
    final contact = (_customer!['contact'] ?? '').toString();
    final code = (_customer!['code'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: const Color(0xFFFDECEA),
            child: Text(
              _initials(name),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [contact, code].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          TextButton(onPressed: _pickCustomer, child: const Text('Ganti')),
        ],
      ),
    );
  }

  Widget _fieldBox({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  static String _initials(String n) {
    final parts = n.split(RegExp(r'[\s-]+')).where((w) => w.length > 1).take(2);
    return parts.map((w) => w[0]).join().toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog: input nominal DP (mengurus controller sendiri agar tidak
// use-after-dispose saat dialog ditutup)
// ─────────────────────────────────────────────────────────────────────────────

class _DpAmountDialog extends StatefulWidget {
  final int total;
  final int? initial;
  const _DpAmountDialog({required this.total, this.initial});

  @override
  State<_DpAmountDialog> createState() => _DpAmountDialogState();
}

class _DpAmountDialogState extends State<_DpAmountDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.initial != null ? widget.initial.toString() : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width * 0.5).clamp(
      400.0,
      620.0,
    );
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: const Text(
        'Nominal DP',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total pesanan ${convertIDR(widget.total)}',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: 'Rp ',
                prefixStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                hintText: '0',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () =>
              Navigator.pop(context, int.tryParse(_ctrl.text.trim()) ?? 0),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog: rincian ulang sebelum simpan (modal konfirmasi pertama)
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewDialog extends StatefulWidget {
  final String customerName;
  final String customerContact;
  final List<_BigLine> lines;
  final int total;
  final int dp;
  final int ongkir;
  final bool showOngkir;
  const _ReviewDialog({
    required this.customerName,
    required this.customerContact,
    required this.lines,
    required this.total,
    required this.dp,
    required this.ongkir,
    required this.showOngkir,
  });

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width * 0.55).clamp(
      420.0,
      640.0,
    );
    final lines = widget.lines;
    final visible = _showAll ? lines : lines.take(2).toList();
    final hiddenCount = lines.length - visible.length;
    final sisa = widget.total - widget.dp;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: const Text(
        'Periksa Big Order',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pemesan
              _sectionLabel('Pemesan'),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.customerContact.isEmpty
                          ? widget.customerName
                          : '${widget.customerName} · ${widget.customerContact}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Produk
              _sectionLabel('Produk (${lines.length} baris)'),
              const SizedBox(height: 6),
              for (final l in visible) _productRow(l),
              if (hiddenCount > 0 || _showAll)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      _showAll
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                    ),
                    label: Text(
                      _showAll
                          ? 'Sembunyikan'
                          : 'Lihat semua ($hiddenCount lagi)',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              const Divider(height: 22),

              // Total / DP / Sisa
              _amountRow('Total pesanan', widget.total),
              const SizedBox(height: 6),
              _amountRow('DP dibayar sekarang', widget.dp),
              const SizedBox(height: 6),
              _amountRow('Sisa sebelum diambil', sisa),
              // Ongkir — diperbesar biar jelas (disembunyikan sampai API siap)
              if (widget.showOngkir) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F1FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB6D4FF)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_shipping_rounded,
                        color: Colors.blue.shade700,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ongkos kirim',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ),
                      Text(
                        convertIDR(widget.ongkir),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
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
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Lanjut',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String t) => Text(
    t.toUpperCase(),
    style: const TextStyle(
      fontSize: 11.5,
      letterSpacing: 0.6,
      fontWeight: FontWeight.bold,
      color: Colors.grey,
    ),
  );

  Widget _productRow(_BigLine l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (l.menu['title'] ?? '-').toString(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${l.qty} pcs × ${convertIDR(l.price)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (l.props.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Tambahan: ${l.props.map((p) => '${p['title']} × ${p['quantity']}').join(' · ')}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            convertIDR(l.total),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountRow(String label, int value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13.5, color: Colors.grey[700])),
        Text(
          convertIDR(value),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet: cari / buat pemesan
// ─────────────────────────────────────────────────────────────────────────────

class _CustomerSheet extends StatefulWidget {
  final BigOrderService service;
  const _CustomerSheet({required this.service});

  @override
  State<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends State<_CustomerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _creating = false;
  bool _submitting = false;

  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final res = await widget.service.searchCustomers(search: q);
      final list = (res.data['data'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        _results = list
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order.customerSearch');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(v.trim()),
    );
  }

  Future<void> _createCustomer() async {
    final name = _nameCtrl.text.trim();
    final contact = _contactCtrl.text.trim();
    if (name.isEmpty || contact.isEmpty) {
      SnackbarUtil.show(
        context,
        title: 'Data wajib',
        message: 'Nama dan kontak wajib diisi.',
        status: SnackBarStatus.warning,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await widget.service.createCustomer({
        'name': name,
        'contact': contact,
        if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
      });
      final data = res.data['data'];
      if (!mounted) return;
      Navigator.pop(context, Map<String, dynamic>.from(data as Map));
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'big_order.customerCreate');
      if (!mounted) return;
      setState(() => _submitting = false);
      SnackbarUtil.show(
        context,
        title: 'Gagal membuat pemesan',
        message: BigOrderService.humanizeError(e),
        status: SnackBarStatus.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _creating ? 'Pemesan baru' : 'Cari pemesan',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _creating ? _buildCreateForm() : _buildSearch()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onChanged,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Nama, nomor kontak, atau kode…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : _results.isEmpty
              ? Center(
                  child: Text(
                    'Tidak ada pemesan cocok.\nBuat baru lewat tombol di bawah.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500], height: 1.5),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = _results[i];
                    final name = (c['name'] ?? '-').toString();
                    return InkWell(
                      onTap: () => Navigator.pop(context, c),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFFFDECEA),
                              child: Text(
                                _CustomerSheetState._ini(name),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
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
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [c['contact'], c['code']]
                                        .where(
                                          (s) =>
                                              s != null &&
                                              s.toString().isNotEmpty,
                                        )
                                        .join(' · '),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _creating = true),
              icon: const Icon(
                Icons.person_add_alt_1_rounded,
                color: AppColors.primary,
              ),
              label: const Text(
                'Pemesan tidak ditemukan — buat baru',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateForm() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _lbl('Wajib'),
              _input(_nameCtrl, 'Nama pemesan'),
              _input(
                _contactCtrl,
                'Nomor kontak / WhatsApp',
                keyboard: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              _lbl('Opsional'),
              _input(_emailCtrl, 'Email', keyboard: TextInputType.emailAddress),
              const SizedBox(height: 4),
              Text(
                'Kode pelanggan dibuat otomatis oleh server.',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _creating = false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Kembali'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _createCustomer,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Simpan & pakai',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lbl(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      t,
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 0.8,
        fontWeight: FontWeight.bold,
        color: Colors.grey,
      ),
    ),
  );

  Widget _input(
    TextEditingController c,
    String hint, {
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );

  static String _ini(String n) {
    final parts = n.split(RegExp(r'[\s-]+')).where((w) => w.length > 1).take(2);
    return parts.map((w) => w[0]).join().toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet: pilih item + qty + props
// ─────────────────────────────────────────────────────────────────────────────

class _ItemSheet extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  const _ItemSheet({required this.products});

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  Map<String, dynamic>? _selected;
  final _qtyCtrl = TextEditingController();
  // Kuantitas per varian tambahan (props). Key = prop id → controller.
  final Map<dynamic, TextEditingController> _propQty = {};
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    for (final c in _propQty.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleProp(dynamic id) {
    setState(() {
      _error = null;
      if (_propQty.containsKey(id)) {
        _propQty.remove(id)!.dispose();
      } else {
        // Tidak diisi default — user isi sendiri (maks = jumlah item).
        _propQty[id] = TextEditingController();
      }
    });
  }

  void _clearProps() {
    for (final c in _propQty.values) {
      c.dispose();
    }
    _propQty.clear();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return widget.products;
    final q = _query.toLowerCase();
    return widget.products
        .where((p) => (p['title'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  int get _qty => int.tryParse(_qtyCtrl.text.trim()) ?? 0;

  // Total jumlah semua varian yang dicentang.
  int get _propSum {
    int s = 0;
    for (final c in _propQty.values) {
      s += int.tryParse(c.text.trim()) ?? 0;
    }
    return s;
  }

  int get _lineTotal {
    if (_selected == null) return 0;
    final price = (_selected!['price'] as num?)?.toInt() ?? 0;
    return price * _qty;
  }

  void _confirm() {
    if (_selected == null) return;
    if (_qty < 1) {
      setState(() => _error = 'Isi jumlah item terlebih dahulu.');
      return;
    }
    final propsList = (_selected!['props'] as List?) ?? [];
    final hasProps = propsList.isNotEmpty;

    if (hasProps) {
      // Paket wajib pilih minimal satu varian.
      final anySelected = propsList.any((p) => _propQty.containsKey(p['id']));
      if (!anySelected) {
        setState(
          () => _error = 'Paket ini wajib memilih varian tambahannya dulu.',
        );
        return;
      }
      // Tiap varian yang dicentang wajib diisi jumlahnya.
      for (final p in propsList) {
        if (!_propQty.containsKey(p['id'])) continue;
        final q = int.tryParse(_propQty[p['id']]!.text.trim()) ?? 0;
        final title = (p['title'] ?? 'varian').toString();
        if (q < 1) {
          setState(
            () => _error =
                'Isi jumlah untuk varian "$title", atau hapus centangnya.',
          );
          return;
        }
      }
      // Total varian harus PAS dengan jumlah item.
      if (_propSum != _qty) {
        final selisih = _propSum - _qty;
        final arah = selisih > 0 ? 'kelebihan' : 'kurang';
        setState(
          () => _error =
              'Total varian harus pas $_qty pcs (sekarang $_propSum pcs, '
              '$arah ${selisih.abs()} pcs).',
        );
        return;
      }
    }

    final chosen = propsList
        .where((p) => _propQty.containsKey(p['id']))
        .map(
          (p) => {
            'id': p['id'],
            'title': p['title'],
            'quantity': int.tryParse(_propQty[p['id']]!.text.trim()) ?? 0,
          },
        )
        .toList()
        .cast<Map<String, dynamic>>();
    Navigator.pop(
      context,
      _BigLine(menu: _selected!, qty: _qty, props: chosen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  if (_selected != null)
                    IconButton(
                      onPressed: () => setState(() => _selected = null),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  Expanded(
                    child: Text(
                      _selected == null
                          ? 'Pilih produk'
                          : (_selected!['title'] ?? '-').toString(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _selected == null ? _buildPicker() : _buildConfig(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPicker() {
    final items = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: 'Cari produk…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'Produk tidak ditemukan',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = items[i];
                    final price = (p['price'] as num?)?.toInt() ?? 0;
                    return InkWell(
                      onTap: () => setState(() {
                        _selected = p;
                        _qtyCtrl.text = '';
                        _clearProps();
                      }),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                (p['title'] ?? '-').toString(),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${convertIDR(price)} / pcs',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConfig() {
    final propsList = (_selected!['props'] as List?) ?? [];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Jumlah',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _qtyCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() => _error = null),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  suffixText: 'pcs',
                  hintText: '0',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [25, 50, 60, 100].map((n) {
                  return ActionChip(
                    label: Text('$n'),
                    onPressed: () => setState(() => _qtyCtrl.text = '$n'),
                  );
                }).toList(),
              ),
              if (propsList.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      'Tambahan untuk baris ini',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    if (_qty > 0)
                      Text(
                        'Terisi $_propSum / $_qty pcs',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: _propSum == _qty
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ...propsList.map((p) {
                  final id = p['id'];
                  final on = _propQty.containsKey(id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: on ? const Color(0xFFFFFAFA) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: on ? AppColors.primary : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () => _toggleProp(id),
                            borderRadius: BorderRadius.circular(6),
                            child: Icon(
                              on
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: on
                                  ? AppColors.primary
                                  : Colors.grey.shade400,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _toggleProp(id),
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                (p['title'] ?? '-').toString(),
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Input jumlah per varian (ujung kanan).
                          SizedBox(
                            width: 88,
                            child: on
                                ? TextField(
                                    controller: _propQty[id],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    textAlign: TextAlign.center,
                                    onChanged: (v) {
                                      // Batasi maksimal = jumlah item.
                                      final n = int.tryParse(v.trim()) ?? 0;
                                      if (_qty > 0 && n > _qty) {
                                        final c = _propQty[id]!;
                                        c.text = '$_qty';
                                        c.selection = TextSelection.collapsed(
                                          offset: c.text.length,
                                        );
                                      }
                                      setState(() => _error = null);
                                    },
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: 'Qty',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 9,
                                          ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                          color: AppColors.primary,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox(height: 40),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
                Text(
                  'Total semua varian harus pas dengan jumlah item ($_qty pcs).',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF3B4AE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: Color(0xFF8E1010),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF7A2018),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_qty pcs',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          convertIDR(_lineTotal),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: FilledButton(
                      onPressed: _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: Colors.grey.shade300,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Tambahkan baris',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
