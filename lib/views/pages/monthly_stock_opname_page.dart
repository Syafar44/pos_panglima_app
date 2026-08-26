import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/monthly_stock_opname_service.dart';
import 'package:pos_panglima_app/services/network_service.dart';
import 'package:pos_panglima_app/services/storage/monthly_so_storage_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

/// Halaman Stock Opname Bulanan.
///
/// Dua mode, ditentukan status dokumen:
/// - `Draft` → mode hitung: baris diunduh sekali, disimpan lokal, diisi
///   petugas (bisa offline penuh), lalu disinkronkan dan disubmit.
/// - selain Draft → riwayat read-only (tanpa baris item).
///
/// Aturan yang sengaja DITEGAKKAN di halaman ini:
/// - Tidak ada `system_qty`, tidak ada selisih, tidak ada layar review selisih.
///   Angka opname hanya berarti kalau dihasilkan tanpa melihat angka sistem.
/// - Kolom isian kosong berarti BELUM dihitung — bukan 0. Baris yang stoknya
///   habis diisi `0` oleh petugas, dan artinya berbeda.
/// - Satuan hanya label. Tidak ada konversi angka di aplikasi.
/// - Baris tidak bisa ditambah/dihapus dari HP.
class MonthlyStockOpnamePage extends StatefulWidget {
  final int id;

  /// Data baris dari halaman daftar (nomor dokumen, gudang, status) supaya
  /// header sudah terisi sebelum request pertama selesai.
  final Map<String, dynamic>? initial;

  const MonthlyStockOpnamePage({super.key, required this.id, this.initial});

  @override
  State<MonthlyStockOpnamePage> createState() => _MonthlyStockOpnamePageState();
}

/// Satu baris opname beserta isian lokalnya.
class _SoLine {
  final int lineId;
  final String itemCode;
  final String itemName;

  /// Bisa null untuk item lama tanpa UoM schema.
  final String? uomCode;

  /// Nilai yang sudah tersimpan di server (null = belum pernah dihitung).
  double? serverQty;
  String? serverRemarks;
  String? countedAt;

  final TextEditingController qtyController;
  final TextEditingController remarksController;

  _SoLine({
    required this.lineId,
    required this.itemCode,
    required this.itemName,
    this.uomCode,
    this.serverQty,
    this.serverRemarks,
    this.countedAt,
    double? localQty,
    String? localRemarks,
  }) : qtyController = TextEditingController(
         text: localQty != null ? _fmtQty(localQty) : '',
       ),
       remarksController = TextEditingController(text: localRemarks ?? '');

  /// Isian saat ini. `null` = kolom kosong = baris belum dihitung.
  double? get localQty {
    final raw = qtyController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  String get localRemarks => remarksController.text.trim();

  bool get isCounted => localQty != null;

  /// Perlu dikirim ke server. Kolom yang dikosongkan kembali tidak dikirim —
  /// tidak ada cara membatalkan hitungan lewat API.
  bool get isDirty {
    final qty = localQty;
    if (qty == null) return false;
    final remarksChanged = localRemarks != (serverRemarks ?? '');
    return qty != serverQty || remarksChanged;
  }

  Map<String, dynamic> toSyncPayload() => {
    'line_id': lineId,
    // Apa adanya, TANPA konversi satuan.
    'actual_qty': localQty,
    'remarks': localRemarks.isEmpty ? null : localRemarks,
  };

  Map<String, dynamic> toJson() => {
    'line_id': lineId,
    'item_code': itemCode,
    'item_name': itemName,
    'uom_code': uomCode,
    'server_qty': serverQty,
    'server_remarks': serverRemarks,
    'counted_at': countedAt,
    'local_qty': localQty,
    'local_remarks': localRemarks.isEmpty ? null : localRemarks,
    'dirty': isDirty,
  };

  factory _SoLine.fromLocalJson(Map<String, dynamic> json) => _SoLine(
    lineId: (json['line_id'] as num).toInt(),
    itemCode: json['item_code']?.toString() ?? '',
    itemName: json['item_name']?.toString() ?? '',
    uomCode: json['uom_code']?.toString(),
    serverQty: (json['server_qty'] as num?)?.toDouble(),
    serverRemarks: json['server_remarks']?.toString(),
    countedAt: json['counted_at']?.toString(),
    localQty: (json['local_qty'] as num?)?.toDouble(),
    localRemarks: json['local_remarks']?.toString(),
  );

  factory _SoLine.fromApi(Map<String, dynamic> json) {
    final qty = (json['actual_qty'] as num?)?.toDouble();
    final remarks = json['remarks']?.toString();
    return _SoLine(
      lineId: (json['line_id'] as num).toInt(),
      itemCode: json['item_code']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      uomCode: json['uom_code']?.toString(),
      serverQty: qty,
      serverRemarks: remarks,
      countedAt: json['counted_at']?.toString(),
      localQty: qty,
      localRemarks: remarks,
    );
  }

  void dispose() {
    qtyController.dispose();
    remarksController.dispose();
  }

  /// Isian sudah tersimpan di server — jadikan nilai lokal sebagai baseline.
  void commitSynced() {
    serverQty = localQty;
    serverRemarks = localRemarks.isEmpty ? null : localRemarks;
    countedAt ??= DateTime.now().toIso8601String();
  }
}

/// Tampilkan angka tanpa `.0` yang tidak perlu (maks. 4 desimal).
String _fmtQty(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v
      .toStringAsFixed(4)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

class _MonthlyStockOpnamePageState extends State<MonthlyStockOpnamePage> {
  final ApiClient apiClient = ApiClient();
  late final MonthlyStockOpnameService service;

  bool _localeReady = false;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isSubmitting = false;
  bool _isPortrait = false;
  bool _isOnline = true;

  /// Gagal memuat dan tidak ada data lokal sama sekali.
  String? _loadError;

  Map<String, dynamic>? _header;
  List<_SoLine> _lines = [];

  final _searchController = TextEditingController();
  String _search = '';
  bool _onlyUncounted = false;

  Timer? _persistDebounce;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    service = MonthlyStockOpnameService(apiClient.dio);
    _header = widget.initial != null
        ? Map<String, dynamic>.from(widget.initial!)
        : null;
    initializeDateFormatting('id_ID', null).then((_) {
      if (mounted) setState(() => _localeReady = true);
    });
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _watchConnectivity();
    _bootstrap();
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _connectivitySub?.cancel();
    _searchController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  // ─── Status koneksi ─────────────────────────────────────────────────────────

  void _watchConnectivity() {
    _refreshOnlineStatus();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((_) async {
      final online = await NetworkService.isOnline(force: true);
      if (!mounted) return;
      setState(() => _isOnline = online);
      // Sinkronkan otomatis begitu koneksi kembali.
      if (online && _dirtyCount > 0 && !_isSyncing) {
        _sync(silent: true);
      }
    });
  }

  Future<void> _refreshOnlineStatus({bool force = false}) async {
    final online = await NetworkService.isOnline(force: force);
    if (!mounted) return;
    setState(() => _isOnline = online);
  }

  // ─── Muat dokumen ───────────────────────────────────────────────────────────

  bool get _isDraft =>
      (_header?['status'] ?? 'Draft').toString().toLowerCase() == 'draft';

  int get _countedCount => _lines.where((l) => l.isCounted).length;
  int get _dirtyCount => _lines.where((l) => l.isDirty).length;
  int get _uncountedCount => _lines.length - _countedCount;

  Future<void> _bootstrap() async {
    setState(() => _isLoading = true);
    await _refreshOnlineStatus(force: true);

    // Isian lokal selalu diprioritaskan: kalau masih ada baris yang belum
    // tersinkron, jangan pernah ditimpa data server.
    final localLines = await MonthlySoStorageService.getLines(widget.id);
    final localDoc = await MonthlySoStorageService.getDoc(widget.id);
    final hasLocalDirty = localLines.any((l) => l['dirty'] == true);

    if (localLines.isNotEmpty) {
      _applyLocal(localDoc, localLines);
      if (hasLocalDirty || !_isOnline) {
        setState(() => _isLoading = false);
        if (_isOnline && hasLocalDirty) _sync(silent: true);
        return;
      }
    }

    await _fetchFromServer(keepLocalOnFailure: localLines.isNotEmpty);
  }

  void _applyLocal(
    Map<String, dynamic>? doc,
    List<Map<String, dynamic>> localLines,
  ) {
    for (final line in _lines) {
      line.dispose();
    }
    final header = doc?['header'];
    _lines = localLines.map(_SoLine.fromLocalJson).toList();
    _header = header is Map
        ? Map<String, dynamic>.from(header)
        : (_header ?? {});
    for (final line in _lines) {
      line.qtyController.addListener(_onLineEdited);
      line.remarksController.addListener(_onLineEdited);
    }
  }

  Future<void> _fetchFromServer({bool keepLocalOnFailure = false}) async {
    try {
      // Dokumen non-Draft tidak punya baris — cukup riwayatnya.
      final statusKnown = _header?['status']?.toString();
      if (statusKnown != null &&
          statusKnown.isNotEmpty &&
          statusKnown.toLowerCase() != 'draft') {
        final res = await service.getDetail(widget.id);
        final data = Map<String, dynamic>.from(res.data['data'] as Map);
        if (!mounted) return;
        setState(() {
          _header = data;
          _isLoading = false;
          _loadError = null;
        });
        return;
      }

      final res = await service.getLines(widget.id);
      final data = Map<String, dynamic>.from(res.data['data'] as Map);
      final apiLines = (data['lines'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Baris sudah diurutkan item_name A→Z, sama dengan urutan cetak.
      // Jangan diurutkan ulang.
      for (final line in _lines) {
        line.dispose();
      }
      final header = Map<String, dynamic>.from(data)..remove('lines');
      final newLines = apiLines.map(_SoLine.fromApi).toList();
      for (final line in newLines) {
        line.qtyController.addListener(_onLineEdited);
        line.remarksController.addListener(_onLineEdited);
      }

      if (!mounted) return;
      setState(() {
        _header = header;
        _lines = newLines;
        _isLoading = false;
        _loadError = null;
      });

      await MonthlySoStorageService.saveDoc(
        widget.id,
        header: header,
        lines: newLines.map((l) => l.toJson()).toList(),
      );
    } catch (e, stack) {
      final isNetwork = MonthlyStockOpnameService.isNetworkFailure(e);
      if (!isNetwork) {
        CrashReporter.report(
          e,
          stack,
          reason: 'monthly_stock_opname_page.fetch',
        );
      }
      if (!mounted) return;

      // 409: dokumen sudah bukan Draft (mis. di-submit dari web) → tampilkan
      // sebagai riwayat, bukan layar error.
      if (MonthlyStockOpnameService.statusCode(e) == 409) {
        setState(() {
          _header = {...?_header, 'status': 'Submitted'};
        });
        await _fetchFromServer();
        return;
      }

      setState(() {
        _isLoading = false;
        _loadError = keepLocalOnFailure
            ? null
            : MonthlyStockOpnameService.humanizeError(e);
      });
      if (keepLocalOnFailure) {
        SnackbarUtil.show(
          context,
          title: isNetwork ? 'Memakai data tersimpan' : 'Gagal menyegarkan',
          message: MonthlyStockOpnameService.humanizeError(e),
          status: isNetwork ? SnackBarStatus.warning : SnackBarStatus.error,
        );
      }
    }
  }

  // ─── Isian & penyimpanan lokal ──────────────────────────────────────────────

  /// Setiap isian tersimpan lokal seketika (didebounce sedikit supaya tidak
  /// menulis pada tiap ketukan tombol), sebelum ada permintaan jaringan apa pun.
  void _onLineEdited() {
    setState(() {});
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 300), _persistLines);
  }

  Future<void> _persistLines() async {
    await MonthlySoStorageService.saveLines(
      widget.id,
      _lines.map((l) => l.toJson()).toList(),
    );
  }

  // ─── Sinkronisasi ───────────────────────────────────────────────────────────

  /// Kirim baris yang belum tersinkron, dipecah per 500 baris.
  ///
  /// Aman ditekan kapan saja dan sesering apa pun — server idempoten, jadi
  /// tidak perlu melacak "tadi kekirim atau belum".
  Future<bool> _sync({bool silent = false}) async {
    if (_isSyncing || !_isDraft) return false;
    final dirty = _lines.where((l) => l.isDirty).toList();
    if (dirty.isEmpty) {
      if (!silent) {
        SnackbarUtil.show(
          context,
          title: 'Sudah tersinkron',
          message: 'Semua isian sudah tersimpan di server.',
          status: SnackBarStatus.info,
        );
      }
      return true;
    }

    setState(() => _isSyncing = true);
    try {
      const chunkSize = MonthlyStockOpnameService.maxLinesPerBatch;
      for (var i = 0; i < dirty.length; i += chunkSize) {
        final chunk = dirty.sublist(
          i,
          (i + chunkSize) > dirty.length ? dirty.length : i + chunkSize,
        );
        await service.syncLines(
          widget.id,
          chunk.map((l) => l.toSyncPayload()).toList(),
        );
        // Satu batch = satu transaksi: sampai di sini seluruh baris chunk
        // dipastikan tersimpan.
        for (final line in chunk) {
          line.commitSynced();
        }
      }
      await _persistLines();
      if (!mounted) return true;
      setState(() => _isSyncing = false);
      if (!silent) {
        SnackbarUtil.show(
          context,
          title: 'Tersinkron',
          message: '${dirty.length} baris terkirim ke server.',
          status: SnackBarStatus.success,
        );
      }
      return true;
    } catch (e, stack) {
      final isNetwork = MonthlyStockOpnameService.isNetworkFailure(e);
      if (!isNetwork) {
        CrashReporter.report(
          e,
          stack,
          reason: 'monthly_stock_opname_page.sync',
        );
      }
      if (!mounted) return false;
      setState(() {
        _isSyncing = false;
        // Kegagalan jaringan sekaligus menandakan perangkat sedang offline,
        // supaya indikator & kunci Submit ikut menyesuaikan tanpa menunggu
        // perubahan status konektivitas.
        if (isNetwork) _isOnline = false;
      });

      // Gagal-jaringan ≠ gagal-aturan. Isian tetap aman di HP.
      if (isNetwork) {
        if (!silent) {
          SnackbarUtil.show(
            context,
            title: 'Server tidak bisa dihubungi',
            message:
                'Isian Anda tersimpan di HP dan akan dikirim otomatis saat '
                'koneksi kembali.',
            status: SnackBarStatus.warning,
          );
        }
        return false;
      }

      final code = MonthlyStockOpnameService.statusCode(e);
      // 422/409/403: pesan server sudah ditulis untuk pengguna akhir.
      await _showRuleError(
        title: code == 409
            ? 'Dokumen sudah tidak bisa diubah'
            : 'Isian tidak tersimpan',
        message: MonthlyStockOpnameService.humanizeError(e),
        hint: code == 422
            ? 'Data lokal tidak sinkron dengan server. Tutup lalu buka '
                  'kembali dokumen ini.'
            : null,
      );
      return false;
    }
  }

  Future<void> _showRuleError({
    required String title,
    required String message,
    String? hint,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: const Icon(
          Icons.report_gmailerrorred_rounded,
          size: 48,
          color: Colors.orange,
        ),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 10),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
        actionsPadding: const EdgeInsets.only(
          bottom: 20,
          left: 20,
          right: 20,
          top: 10,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Mengerti',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Submit ─────────────────────────────────────────────────────────────────

  /// Alasan tombol Submit dikunci — ditampilkan di layar, bukan baru muncul
  /// setelah tombol ditekan.
  List<String> get _submitBlockers {
    final reasons = <String>[];
    if (_uncountedCount > 0) {
      reasons.add('$_uncountedCount baris belum dihitung');
    }
    if (_dirtyCount > 0) {
      reasons.add('$_dirtyCount isian belum tersinkron');
    }
    if (!_isOnline) reasons.add('sedang offline');
    return reasons;
  }

  Future<void> _submit() async {
    if (!_isDraft || _isSubmitting || _isSyncing) return;
    if (_submitBlockers.isNotEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: const Icon(
          Icons.info_outline_rounded,
          size: 48,
          color: AppColors.primary,
        ),
        title: const Text(
          'Submit Stock Opname?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: Text(
          'Seluruh ${_lines.length} baris akan diajukan untuk approval dan '
          'tidak bisa diubah lagi dari HP. Lanjutkan?',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.only(
          bottom: 24,
          left: 20,
          right: 20,
          top: 10,
        ),
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
                  onPressed: () => Navigator.pop(ctx, false),
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
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Ya, Submit',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      // Satu UUID per dokumen, dipakai ulang untuk setiap percobaan ulang.
      final key = await MonthlySoStorageService.idempotencyKey(widget.id);
      final res = await service.submit(widget.id, key);
      final message =
          res.data['message']?.toString() ?? 'Stock opname dikirim.';

      await MonthlySoStorageService.clearDoc(widget.id);
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Stock opname dikirim',
        message: message,
        status: SnackBarStatus.success,
      );
      _navigateBack();
    } catch (e, stack) {
      final isNetwork = MonthlyStockOpnameService.isNetworkFailure(e);
      if (!isNetwork) {
        CrashReporter.report(
          e,
          stack,
          reason: 'monthly_stock_opname_page.submit',
        );
      }
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      if (isNetwork) {
        SnackbarUtil.show(
          context,
          title: 'Server tidak bisa dihubungi',
          message:
              'Submit belum terkirim. Isian Anda tetap aman di HP — coba lagi '
              'saat koneksi kembali.',
          status: SnackBarStatus.warning,
        );
        return;
      }
      await _showRuleError(
        title: 'Belum bisa disubmit',
        message: MonthlyStockOpnameService.humanizeError(e),
      );
      return;
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  // ─── Navigasi ───────────────────────────────────────────────────────────────

  void _navigateBack() {
    isBackSO.value = false;
    selectedPageInventoryNotifier.value = 5;
    selectedPageNotifier.value = 4;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WidgetTree()),
      (route) => false,
    );
  }

  Future<void> _handleBack() async {
    if (_dirtyCount == 0) {
      _navigateBack();
      return;
    }

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: const Icon(
          Icons.cloud_upload_outlined,
          size: 48,
          color: Colors.orange,
        ),
        title: const Text(
          'Ada Isian Belum Tersinkron',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: Text(
          '$_dirtyCount isian tersimpan di HP tapi belum terkirim ke server. '
          'Isian tidak akan hilang, tapi lebih aman dikirim sekarang.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.only(
          bottom: 24,
          left: 20,
          right: 20,
          top: 10,
        ),
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
                  onPressed: () => Navigator.pop(ctx, 'leave'),
                  child: const Text(
                    'Keluar Saja',
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
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, 'sync'),
                  child: const Text(
                    'Sinkronkan',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'leave') {
      _navigateBack();
    } else if (action == 'sync') {
      final ok = await _sync();
      if (!mounted) return;
      if (ok) _navigateBack();
    }
  }

  void _toggleOrientation() {
    final toPortrait = !_isPortrait;
    setState(() => _isPortrait = toPortrait);
    SystemChrome.setPreferredOrientations(
      toPortrait
          ? [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
          : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
  }

  // ─── UI ─────────────────────────────────────────────────────────────────────

  List<_SoLine> get _visibleLines {
    final q = _search.toLowerCase();
    return _lines.where((line) {
      if (_onlyUncounted && line.isCounted) return false;
      if (q.isEmpty) return true;
      return line.itemName.toLowerCase().contains(q) ||
          line.itemCode.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textDark,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
            tooltip: 'Kembali ke Menu Utama',
          ),
          title: Text(
            _header?['document_number']?.toString() ?? 'Monthly Stock Opname',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isPortrait
                    ? Icons.stay_current_landscape_outlined
                    : Icons.stay_current_portrait_outlined,
              ),
              tooltip: _isPortrait ? 'Mode Landscape' : 'Mode Potret',
              onPressed: _toggleOrientation,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: Colors.grey.shade200),
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _loadError != null
            ? _buildLoadError()
            : !_isDraft
            ? _buildHistory()
            : Column(
                children: [
                  _buildHeader(),
                  _buildToolbar(),
                  Expanded(child: _buildItemList()),
                  _buildBottomBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 72, color: Colors.grey[350]),
            const SizedBox(height: 16),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  /// Header: nama gudang & nomor dokumen selalu terlihat — petugas harus tahu
  /// ia sedang menghitung untuk gudang mana. Progres & status sinkronisasi
  /// permanen di layar, ini pengganti tumpukan kertas.
  Widget _buildHeader() {
    final warehouse = _header?['warehouse_name']?.toString() ?? '-';
    final docNumber = _header?['document_number']?.toString() ?? '-';
    final periodLabel = _periodLabel();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        warehouse,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildStatusChip(
                      (_header?['status'] ?? 'Draft').toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  periodLabel.isEmpty
                      ? docNumber
                      : '$docNumber  ·  Periode $periodLabel',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildProgressBadges(),
        ],
      ),
    );
  }

  Widget _buildProgressBadges() {
    return Row(
      children: [
        _buildBadge(
          icon: Icons.fact_check_outlined,
          label: '$_countedCount / ${_lines.length} terhitung',
          color: _uncountedCount == 0
              ? Colors.green.shade700
              : AppColors.primaryDark,
          background: _uncountedCount == 0
              ? Colors.green.shade50
              : AppColors.primaryLight,
        ),
        const SizedBox(width: 8),
        _buildBadge(
          icon: _dirtyCount == 0
              ? Icons.cloud_done_outlined
              : Icons.cloud_upload_outlined,
          label: _dirtyCount == 0
              ? 'Tersinkron'
              : '$_dirtyCount belum tersinkron',
          color: _dirtyCount == 0
              ? Colors.green.shade700
              : Colors.orange.shade800,
          background: _dirtyCount == 0
              ? Colors.green.shade50
              : Colors.orange.shade50,
        ),
        const SizedBox(width: 8),
        _buildBadge(
          icon: _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          label: _isOnline ? 'Online' : 'Offline',
          color: _isOnline ? Colors.green.shade700 : Colors.grey.shade700,
          background: _isOnline ? Colors.green.shade50 : Colors.grey.shade200,
        ),
      ],
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final (color, background) = _statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        MonthlyStockOpnameService.statusLabel(status),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  (Color, Color) _statusColors(String status) {
    switch (status) {
      case 'Draft':
        return (Colors.blueGrey, Colors.blueGrey.shade50);
      case 'Submitted':
        return (Colors.orange.shade800, Colors.orange.shade50);
      case 'Approved':
        return (Colors.green.shade700, Colors.green.shade50);
      case 'Rejected':
        return (Colors.red.shade700, Colors.red.shade50);
      default:
        return (Colors.grey.shade700, Colors.grey.shade100);
    }
  }

  String _periodLabel() {
    final month = (_header?['period_month'] as num?)?.toInt();
    final year = (_header?['period_year'] as num?)?.toInt();
    if (month != null && year != null) {
      final date = DateTime(year, month);
      return _localeReady
          ? DateFormat('MMMM yyyy', 'id_ID').format(date)
          : DateFormat('MMMM yyyy').format(date);
    }
    final parsed = DateTime.tryParse(_header?['date']?.toString() ?? '');
    if (parsed == null) return '';
    return _localeReady
        ? DateFormat('MMMM yyyy', 'id_ID').format(parsed)
        : DateFormat('MMMM yyyy').format(parsed);
  }

  /// Pencarian nama/kode item + filter "belum terhitung". Untuk dokumen ratusan
  /// baris, mencari sisa yang terlewat tanpa filter adalah pekerjaan tersendiri.
  Widget _buildToolbar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _search = v.trim()),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Cari nama atau kode item',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        ),
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
          GestureDetector(
            onTap: () => setState(() => _onlyUncounted = !_onlyUncounted),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _onlyUncounted ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _onlyUncounted
                      ? AppColors.primary
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    size: 17,
                    color: _onlyUncounted ? Colors.white : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Belum terhitung ($_uncountedCount)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _onlyUncounted ? Colors.white : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    if (_lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Belum ada item pada dokumen ini',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    final visible = _visibleLines;
    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 14),
            Text(
              _onlyUncounted
                  ? 'Semua item sudah dihitung'
                  : 'Item tidak ditemukan',
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: visible.length,
      itemBuilder: (context, index) => _buildItemCard(visible[index]),
    );
  }

  Widget _buildItemCard(_SoLine line) {
    final counted = line.isCounted;
    return Container(
      key: ValueKey(line.lineId),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border(
          left: BorderSide(
            // Penanda visual baris yang belum dihitung.
            color: counted ? Colors.green.shade400 : Colors.orange.shade400,
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        line.itemCode,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!counted)
                      Text(
                        'Belum dihitung',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                        ),
                      )
                    else if (line.isDirty)
                      Text(
                        'Belum tersinkron',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey.shade400,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  line.itemName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Qty Aktual'),
                _buildTextField(
                  controller: line.qtyController,
                  hint: '',
                  // Satuan hanya label — tidak bisa diubah, tidak ada konversi.
                  uomCode: (line.uomCode?.isNotEmpty ?? false)
                      ? line.uomCode
                      : '–',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    // Maksimal 4 desimal (lebih dari itu dibulatkan server).
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*[.,]?\d{0,4}'),
                    ),
                  ],
                  highlight: !counted,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Keterangan'),
                _buildTextField(
                  controller: line.remarksController,
                  hint: 'Keterangan (opsional)',
                  maxLength: 255,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    String? uomCode,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    bool highlight = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      buildCounter:
          (_, {required currentLength, required isFocused, maxLength}) => null,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        suffixIcon: uomCode != null
            ? Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: Text(
                  uomCode,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            : null,
        suffixIconConstraints: uomCode != null
            ? const BoxConstraints(minWidth: 0, minHeight: 0)
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        filled: true,
        fillColor: highlight ? Colors.orange.shade50 : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: highlight ? Colors.orange.shade200 : Colors.grey.shade300,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final blockers = _submitBlockers;
    final canSubmit = blockers.isEmpty && !_isSubmitting && !_isSyncing;
    final busy = _isSyncing || _isSubmitting;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (blockers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 15,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Submit terkunci: ${blockers.join(' · ')}.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _sync,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(
                            Icons.sync_rounded,
                            color: AppColors.primary,
                          ),
                    label: Text(
                      _isSyncing
                          ? 'Mengirim...'
                          : _dirtyCount > 0
                          ? 'Sinkronkan ($_dirtyCount)'
                          : 'Sinkronkan',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canSubmit ? _submit : null,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, color: Colors.white),
                    label: Text(
                      _isSubmitting ? 'Mengirim...' : 'Submit',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
  }

  /// Dokumen non-Draft: riwayat read-only, tanpa baris item.
  Widget _buildHistory() {
    final status = (_header?['status'] ?? '').toString();
    final currentLevel = (_header?['current_approval_level'] as num?)?.toInt();
    final maxLevel = (_header?['max_approval_level'] as num?)?.toInt();
    final submittedAt = DateTime.tryParse(
      _header?['submitted_date']?.toString() ?? '',
    );
    final total = (_header?['total_lines'] as num?)?.toInt() ?? 0;
    final counted = (_header?['counted_lines'] as num?)?.toInt() ?? 0;
    final remarks = _header?['remarks']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _header?['document_number']?.toString() ?? '-',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    _buildStatusChip(status),
                  ],
                ),
                const Divider(height: 24),
                _buildHistoryRow(
                  'Gudang',
                  _header?['warehouse_name']?.toString() ?? '-',
                ),
                const SizedBox(height: 8),
                _buildHistoryRow('Periode', _periodLabel()),
                const SizedBox(height: 8),
                _buildHistoryRow('Item terhitung', '$counted / $total'),
                if (submittedAt != null) ...[
                  const SizedBox(height: 8),
                  _buildHistoryRow(
                    'Disubmit',
                    _localeReady
                        ? DateFormat(
                            'dd MMM yyyy HH:mm',
                            'id_ID',
                          ).format(submittedAt)
                        : DateFormat('dd MMM yyyy HH:mm').format(submittedAt),
                  ),
                ],
                if ((_header?['source']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildHistoryRow('Sumber', _header!['source'].toString()),
                ],
                if (remarks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildHistoryRow('Keterangan', remarks),
                ],
                if (status == 'Submitted' &&
                    currentLevel != null &&
                    maxLevel != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          size: 18,
                          color: Colors.orange.shade800,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Menunggu approval level $currentLevel dari '
                            '$maxLevel. Approval dilakukan di web/Telegram.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade900,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Dokumen yang sudah disubmit tidak menampilkan baris item di HP. '
            'Rincian dan selisihnya dilihat approver di web.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
