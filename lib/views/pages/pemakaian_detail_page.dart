import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/pemakaian_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

/// Item hasil pencarian katalog.
class _CatalogItem {
  final int id;
  final String code;
  final String name;
  _CatalogItem({required this.id, required this.code, required this.name});
}

/// Pilihan satuan dari `uom_options` (NISIK = satuan dasar, NISIB = satuan besar).
class _UomOption {
  final int id;
  final String code;
  final String type;
  final num volume;
  _UomOption({
    required this.id,
    required this.code,
    required this.type,
    required this.volume,
  });
}

/// Satu baris pemakaian barang (dengan 1 foto per item).
///
/// Catatan: lampiran di API bersifat level-dokumen. Asosiasi foto ke item
/// dipertahankan lewat field `name` lampiran yang memuat `item<itemId>`.
class _PemakaianItemEntry {
  int? itemId;
  String? itemCode;
  String? itemName;
  List<_UomOption> uomOptions = [];
  int? selectedUomId;
  num stock = 0;
  num avgPrice = 0;
  bool isLoadingDetail = false;
  bool isDeleting = false;
  List<_CatalogItem>? filteredCatalog;
  bool isCatalogSearching = false;
  Timer? _searchTimer;

  // Foto / lampiran
  File? imageFile; // preview lokal setelah ambil foto
  Uint8List? imageBytes; // bytes hasil fetch dari server
  int? lampiranId;
  String? lampiranUrl;
  bool isLoadingLampiran = false;
  bool isUploadingLampiran = false;

  final TextEditingController itemNameController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController remarksController = TextEditingController();

  void scheduleSearch(String query, VoidCallback onFire) {
    _searchTimer?.cancel();
    if (query.isEmpty) {
      filteredCatalog = null;
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 600), onFire);
  }

  void dispose() {
    _searchTimer?.cancel();
    itemNameController.dispose();
    quantityController.dispose();
    remarksController.dispose();
  }
}

class PemakaianDetailPage extends StatefulWidget {
  final int id;
  final String outletName;
  const PemakaianDetailPage({
    super.key,
    required this.id,
    this.outletName = '',
  });

  @override
  State<PemakaianDetailPage> createState() => _PemakaianDetailPageState();
}

class _PemakaianDetailPageState extends State<PemakaianDetailPage> {
  final ApiClient apiClient = ApiClient();
  late final PemakaianService pemakaianService;

  bool _localeReady = false;
  bool _isLoadingDetail = true;
  bool isSavingDraft = false;
  bool isSubmitting = false;

  final List<_PemakaianItemEntry> _items = [];
  String? _tglPemakaian; // yyyy-MM-dd
  int? _customerId;
  String _status = 'Draft';
  String _statusLabel = 'Draft';
  String? _documentNumber;
  bool get _isLocked => _status.toLowerCase() != 'draft';

  // Snapshot data baris saat terakhir dimuat/disimpan draft — untuk deteksi
  // perubahan yang belum tersimpan (dirty) saat user menekan kembali.
  String _baselineSignature = '';

  final _numFmt = NumberFormat.decimalPattern('id_ID');

  @override
  void initState() {
    super.initState();
    pemakaianService = PemakaianService(apiClient.dio);
    _loadDetail();
    initializeDateFormatting('id_ID', null).then((_) {
      if (mounted) setState(() => _localeReady = true);
    });
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  // Nama lampiran memuat item id sebagai kunci asosiasi foto↔item.
  String _lampiranName(int itemId) =>
      'gc${widget.id}_item${itemId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

  int? _parseItemIdFromName(String name) {
    final m = RegExp(r'item(\d+)').firstMatch(name);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  Future<void> _loadDetail() async {
    try {
      final res = await pemakaianService.getDetailPemakaian(widget.id);
      final data = res.data['data'] as Map<String, dynamic>;
      final lines = (data['lines'] as List?) ?? [];
      final lampirans = (data['lampirans'] as List?) ?? [];

      // Map itemId -> {id, url} dari lampiran (dipetakan lewat name).
      final lampMap = <int, Map<String, dynamic>>{};
      for (final l in lampirans) {
        final m = l as Map;
        final name = m['name']?.toString() ?? '';
        final itemId = _parseItemIdFromName(name);
        final id = (m['id'] as num?)?.toInt();
        final url = m['file_url']?.toString();
        if (itemId != null && id != null && url != null && url.isNotEmpty) {
          lampMap[itemId] = {'id': id, 'url': url};
        }
      }

      final rawDate = data['date']?.toString();
      if (rawDate != null && rawDate.isNotEmpty) {
        final parsed = DateTime.tryParse(rawDate);
        _tglPemakaian = parsed != null
            ? DateFormat('yyyy-MM-dd').format(parsed)
            : rawDate;
      }
      _customerId = (data['customers_id'] as num?)?.toInt();
      _status = (data['status'] ?? 'Draft').toString();
      _statusLabel = (data['status_label'] ?? _status).toString();
      _documentNumber = data['document_number']?.toString();

      if (!mounted) return;
      setState(() {
        for (final line in lines) {
          final m = line as Map;
          final entry = _createItem();
          entry.itemId = (m['items_id'] as num?)?.toInt();
          entry.itemCode = m['item_code']?.toString();
          entry.itemName = m['item_name']?.toString();
          if (entry.itemName != null) {
            entry.itemNameController.text = entry.itemName!;
          }
          entry.selectedUomId = (m['uoms_id'] as num?)?.toInt();
          final uomCode = m['uom_code']?.toString() ?? '-';
          if (entry.selectedUomId != null) {
            entry.uomOptions = [
              _UomOption(
                id: entry.selectedUomId!,
                code: uomCode,
                type: 'NISIK',
                volume: 1,
              ),
            ];
          }
          final qty = m['qty'];
          if (qty != null) entry.quantityController.text = qty.toString();
          final remarks = m['remarks'];
          if (remarks != null) {
            entry.remarksController.text = remarks.toString();
          }

          if (entry.itemId == null) {
            entry.dispose();
            continue;
          }

          // Pasang lampiran (kalau ada) berdasarkan pemetaan name.
          final lamp = lampMap[entry.itemId];
          if (lamp != null) {
            entry.lampiranId = lamp['id'] as int;
            entry.lampiranUrl = lamp['url'] as String;
          }

          _items.add(entry);
        }
        if (!_isLocked) _items.add(_createItem());
      });
      _baselineSignature = _currentSignature();

      // Lengkapi uom_options/stok/harga + fetch foto untuk tiap baris.
      for (int i = 0; i < _items.length; i++) {
        if (_items[i].itemId != null) _fetchItemDetail(i);
        final url = _items[i].lampiranUrl;
        if (url != null && url.isNotEmpty) _fetchLampiran(i);
      }
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pemakaian_detail.loadDetail');
      if (mounted) {
        SnackbarUtil.show(
          context,
          title: 'Gagal memuat data',
          message: PemakaianService.humanizeError(e),
          status: SnackBarStatus.error,
        );
        setState(() => _items.add(_createItem()));
      }
    } finally {
      if (mounted) setState(() => _isLoadingDetail = false);
    }
  }

  _PemakaianItemEntry _createItem() {
    final entry = _PemakaianItemEntry();
    entry.itemNameController.addListener(() {
      if (!mounted) return;
      final idx = _items.indexOf(entry);
      if (idx == -1) return;
      final text = entry.itemNameController.text.trim();
      if (entry.itemName != null && text == entry.itemName) return;
      // User mengubah teks → reset pilihan + foto (item berubah).
      if (entry.itemId != null) {
        final oldLampId = entry.lampiranId;
        if (oldLampId != null) _bestEffortDeleteLampiran(oldLampId);
        entry.itemId = null;
        entry.itemCode = null;
        entry.itemName = null;
        entry.uomOptions = [];
        entry.selectedUomId = null;
        entry.stock = 0;
        entry.avgPrice = 0;
        entry.filteredCatalog = null;
        entry.imageFile = null;
        entry.imageBytes = null;
        entry.lampiranId = null;
        entry.lampiranUrl = null;
      }
      entry.scheduleSearch(text, () => _searchItems(idx, text));
      setState(() {});
    });
    return entry;
  }

  Future<void> _searchItems(int index, String query) async {
    if (index >= _items.length) return;
    setState(() => _items[index].isCatalogSearching = true);
    try {
      final res = await pemakaianService.getListItems(search: query);
      final list = (res.data['data'] as List?) ?? [];
      if (mounted && index < _items.length) {
        setState(() {
          _items[index].filteredCatalog = list
              .map(
                (e) => _CatalogItem(
                  id: (e['id'] as num).toInt(),
                  code: (e['code'] ?? '').toString(),
                  name: (e['name'] ?? '').toString(),
                ),
              )
              .toList();
          _items[index].isCatalogSearching = false;
        });
      }
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pemakaian_detail.searchItems');
      if (mounted && index < _items.length) {
        setState(() => _items[index].isCatalogSearching = false);
      }
    }
  }

  Future<void> _onItemSelected(int index, _CatalogItem item) async {
    // Cegah item dobel dalam satu dokumen.
    final duplicate = _items.asMap().entries.any(
      (e) => e.key != index && e.value.itemId == item.id,
    );
    if (duplicate) {
      SnackbarUtil.show(
        context,
        title: 'Item sudah ada',
        message:
            'Item ini sudah ada di daftar. Ubah jumlahnya pada baris tersebut.',
        status: SnackBarStatus.warning,
      );
      setState(() {
        _items[index].itemNameController.clear();
        _items[index].itemId = null;
        _items[index].itemName = null;
      });
      return;
    }

    setState(() {
      _items[index].itemId = item.id;
      _items[index].itemCode = item.code;
      _items[index].itemName = item.name;
      _items[index].itemNameController.text = item.name;
    });
    await _fetchItemDetail(index);
  }

  Future<void> _fetchItemDetail(int index) async {
    if (index >= _items.length) return;
    final entry = _items[index];
    if (entry.itemId == null) return;
    setState(() => entry.isLoadingDetail = true);
    try {
      final res = await pemakaianService.getDetailItem(
        entry.itemId!,
        customersId: _customerId,
      );
      final data = res.data['data'] as Map<String, dynamic>;
      final opts = (data['uom_options'] as List?) ?? [];
      final uomOptions = opts
          .map(
            (e) => _UomOption(
              id: (e['id'] as num).toInt(),
              code: (e['code'] ?? '').toString(),
              type: (e['type'] ?? '').toString(),
              volume: (e['volume'] as num?) ?? 1,
            ),
          )
          .toList();
      if (!mounted || index >= _items.length) return;
      setState(() {
        entry.uomOptions = uomOptions;
        entry.stock = (data['stock'] as num?) ?? 0;
        entry.avgPrice = (data['avg_price'] as num?) ?? 0;
        final stillValid = uomOptions.any((o) => o.id == entry.selectedUomId);
        if (!stillValid) {
          final base = uomOptions.firstWhere(
            (o) => o.type == 'NISIK',
            orElse: () => uomOptions.isNotEmpty
                ? uomOptions.first
                : _UomOption(id: 0, code: '-', type: 'NISIK', volume: 1),
          );
          entry.selectedUomId = base.id == 0 ? null : base.id;
        }
        entry.isLoadingDetail = false;
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pemakaian_detail.itemDetail');
      if (mounted && index < _items.length) {
        setState(() => entry.isLoadingDetail = false);
      }
    }
  }

  // ─── Volume ─────────────────────────────────────────────────────────────────

  _UomOption? _findUom(_PemakaianItemEntry e, int? id) {
    for (final o in e.uomOptions) {
      if (o.id == id) return o;
    }
    return null;
  }

  _UomOption? _firstUomOfType(_PemakaianItemEntry e, String type) {
    for (final o in e.uomOptions) {
      if (o.type == type) return o;
    }
    return null;
  }

  num _qtyVolume(_PemakaianItemEntry e) {
    final qty = num.tryParse(e.quantityController.text.trim()) ?? 0;
    if (qty <= 0) return 0;
    final sel = _findUom(e, e.selectedUomId);
    if (sel != null && sel.type == 'NISIB') {
      final nisik = _firstUomOfType(e, 'NISIK');
      final nisib = _firstUomOfType(e, 'NISIB');
      if (nisik != null && nisib != null && nisib.volume != 0) {
        return qty * (nisik.volume / nisib.volume);
      }
    }
    return qty;
  }

  // ─── Baris ─────────────────────────────────────────────────────────────────

  void _addItem() {
    if (_isLocked) return;
    final last = _items.isNotEmpty ? _items.last : null;
    if (last != null && last.itemId == null) {
      SnackbarUtil.show(
        context,
        title: 'Lengkapi baris terakhir',
        message: 'Pilih item pada baris terakhir sebelum menambah baris baru.',
        status: SnackBarStatus.warning,
      );
      return;
    }
    setState(() => _items.add(_createItem()));
  }

  Future<void> _removeItem(int index) async {
    if (index >= _items.length || _isLocked) return;
    final item = _items[index];
    if (item.isDeleting) return;

    final confirmed = await _confirmDeleteItem(index + 1);
    if (confirmed != true || !mounted) return;
    if (index >= _items.length) return;

    // Hapus lampiran (kalau ada) — best effort.
    if (item.lampiranId != null) {
      setState(() => item.isDeleting = true);
      await _bestEffortDeleteLampiran(item.lampiranId!);
    }

    if (!mounted) return;
    setState(() {
      item.dispose();
      _items.removeAt(index);
    });
  }

  Future<bool?> _confirmDeleteItem(int displayIndex) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: const Icon(
          Icons.delete_outline_rounded,
          size: 48,
          color: Colors.red,
        ),
        title: const Text(
          'Hapus Item?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: Text(
          'Item ke-$displayIndex akan dihapus beserta fotonya. Lanjutkan?',
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
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Hapus',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Foto / lampiran (1 foto per item) ──────────────────────────────────────

  Future<void> _bestEffortDeleteLampiran(int lampiranId) async {
    try {
      await pemakaianService.deleteLampiran(widget.id, lampiranId);
    } catch (e, s) {
      CrashReporter.report(
        e,
        s,
        reason: 'pemakaian_detail.deleteLampiranBestEffort',
      );
    }
  }

  Future<void> _captureImage(int index) async {
    if (index >= _items.length || _isLocked) return;
    final item = _items[index];

    if (item.itemId == null) {
      SnackbarUtil.show(
        context,
        title: 'Pilih item dulu',
        message: 'Pilih nama item terlebih dahulu sebelum mengambil foto.',
        status: SnackBarStatus.warning,
      );
      return;
    }
    final qty = int.tryParse(item.quantityController.text.trim()) ?? 0;
    if (qty <= 0) {
      SnackbarUtil.show(
        context,
        title: 'Quantity tidak valid',
        message: 'Isi quantity (lebih dari 0) terlebih dahulu.',
        status: SnackBarStatus.warning,
      );
      return;
    }

    final hasPhoto = item.imageFile != null || item.lampiranId != null;
    if (hasPhoto) {
      final confirmed = await _confirmReplacePhoto(item);
      if (confirmed != true || !mounted) return;
    }

    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      SnackbarUtil.show(
        context,
        title: 'Izin kamera diperlukan',
        message: 'Mohon berikan izin kamera untuk mengambil foto.',
        status: SnackBarStatus.warning,
      );
      return;
    }

    final file = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => _CameraCapturePage(outletName: widget.outletName),
      ),
    );
    if (file == null || !mounted) return;

    setState(() => item.imageFile = file);
    await _uploadLampiran(item, file);
  }

  Future<void> _uploadLampiran(_PemakaianItemEntry item, File file) async {
    if (item.itemId == null) return;
    setState(() => item.isUploadingLampiran = true);
    try {
      final name = _lampiranName(item.itemId!);
      final formData = FormData.fromMap({
        'name': name,
        'mime_type': 'image/jpeg',
        'file': await MultipartFile.fromFile(file.path, filename: name),
      });
      final res = await pemakaianService.postLampiran(widget.id, formData);
      final data = res.data['data'];
      if (!mounted) return;
      setState(() {
        item.lampiranId = (data is Map) ? (data['id'] as num?)?.toInt() : null;
        item.lampiranUrl = (data is Map) ? data['file_url']?.toString() : null;
        item.imageBytes = null; // pakai imageFile untuk preview
        item.isUploadingLampiran = false;
      });
      SnackbarUtil.show(
        context,
        title: 'Foto tersimpan',
        message: 'Foto berhasil diunggah.',
        status: SnackBarStatus.success,
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pemakaian_detail.uploadLampiran');
      if (mounted) {
        setState(() {
          item.imageFile = null;
          item.isUploadingLampiran = false;
        });
        SnackbarUtil.show(
          context,
          title: 'Gagal upload foto',
          message: PemakaianService.humanizeError(e),
          status: SnackBarStatus.error,
        );
      }
    }
  }

  Future<void> _fetchLampiran(int index) async {
    if (index >= _items.length) return;
    final item = _items[index];
    final url = item.lampiranUrl;
    if (url == null || url.isEmpty) return;
    if (mounted) setState(() => item.isLoadingLampiran = true);
    try {
      final res = await pemakaianService.getLampiranFile(url);
      final raw = res.data;
      Uint8List? bytes;
      if (raw is Uint8List) {
        bytes = raw;
      } else if (raw is List<int>) {
        bytes = Uint8List.fromList(raw);
      }
      if (!mounted) return;
      setState(() {
        item.imageBytes = bytes;
        item.isLoadingLampiran = false;
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pemakaian_detail.fetchLampiran');
      if (mounted) setState(() => item.isLoadingLampiran = false);
    }
  }

  Future<bool?> _confirmReplacePhoto(_PemakaianItemEntry item) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: const Icon(
          Icons.swap_horiz_rounded,
          size: 48,
          color: AppColors.primary,
        ),
        title: const Text(
          'Ganti Foto?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: const Text(
          'Foto yang sudah ada akan diganti dengan foto baru. Lanjutkan?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
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
                  onPressed: () async {
                    final oldId = item.lampiranId;
                    if (oldId != null) {
                      await _bestEffortDeleteLampiran(oldId);
                      if (mounted) {
                        setState(() {
                          item.lampiranId = null;
                          item.lampiranUrl = null;
                          item.imageBytes = null;
                        });
                      }
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  child: const Text(
                    'Ganti',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _viewPhoto(ImageProvider provider) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image(image: provider, fit: BoxFit.contain),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => Navigator.pop(dialogCtx),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Simpan / Submit ─────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _collectItemsPayload() {
    return _items
        .where(
          (e) =>
              e.itemId != null &&
              (int.tryParse(e.quantityController.text.trim()) ?? 0) > 0,
        )
        .map(
          (e) => <String, dynamic>{
            'item_id': e.itemId,
            'uom_id': e.selectedUomId ?? 0,
            'qty': int.tryParse(e.quantityController.text.trim()) ?? 0,
            'remarks': e.remarksController.text.trim(),
          },
        )
        .toList();
  }

  String? _validate() {
    final withItem = _items.where((e) => e.itemId != null).toList();
    if (withItem.isEmpty) return 'Tambahkan minimal satu item.';
    final ids = <int>{};
    for (final e in withItem) {
      if (!ids.add(e.itemId!)) {
        return 'Ada item yang sama lebih dari sekali. Gabungkan menjadi satu baris.';
      }
      final qty = int.tryParse(e.quantityController.text.trim()) ?? 0;
      if (qty <= 0) {
        return 'Isi quantity (lebih dari 0) untuk item "${e.itemName ?? '-'}".';
      }
    }
    return null;
  }

  Future<void> _saveDraft() async {
    if (isSubmitting || isSavingDraft || _isLocked) return;
    final err = _validate();
    if (err != null) {
      SnackbarUtil.show(
        context,
        title: 'Belum lengkap',
        message: err,
        status: SnackBarStatus.warning,
      );
      return;
    }
    setState(() => isSavingDraft = true);
    try {
      await pemakaianService.patchLines(widget.id, _collectItemsPayload());
      _baselineSignature = _currentSignature();
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Draft tersimpan',
        message: 'Data pemakaian berhasil disimpan sebagai draft.',
        status: SnackBarStatus.success,
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pemakaian_detail.saveDraft');
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Gagal simpan draft',
        message: PemakaianService.humanizeError(e),
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => isSavingDraft = false);
    }
  }

  Future<void> _submit() async {
    if (isSubmitting || isSavingDraft || _isLocked) return;
    final err = _validate();
    if (err != null) {
      SnackbarUtil.show(
        context,
        title: 'Belum lengkap',
        message: err,
        status: SnackBarStatus.warning,
      );
      return;
    }

    // Foto wajib untuk setiap item sebelum diajukan.
    final noPhoto = _items.firstWhere(
      (e) =>
          e.itemId != null &&
          e.imageFile == null &&
          e.imageBytes == null &&
          e.lampiranId == null,
      orElse: _PemakaianItemEntry.new,
    );
    if (noPhoto.itemId != null) {
      SnackbarUtil.show(
        context,
        title: 'Foto belum ada',
        message:
            'Ambil foto terlebih dahulu untuk item "${noPhoto.itemName ?? '-'}".',
        status: SnackBarStatus.warning,
      );
      return;
    }

    // Dua modal konfirmasi berurutan (pola sama dengan reject).
    final first = await _confirmDialog(
      title: 'Ajukan Pemakaian?',
      message:
          'Setelah diajukan, dokumen dikunci dan menunggu approval. Lanjutkan?',
      confirmText: 'Lanjut',
    );
    if (first != true || !mounted) return;

    final second = await _confirmDialog(
      title: 'Konfirmasi Pengajuan',
      message:
          'Pastikan seluruh data dan foto sudah benar. Ajukan sekarang? Aksi ini tidak dapat dibatalkan.',
      confirmText: 'Ya, Ajukan',
    );
    if (second != true || !mounted) return;

    setState(() => isSubmitting = true);
    try {
      // 1) Simpan draft dulu (data terbaru) — supaya tidak ada perubahan hilang.
      await pemakaianService.patchLines(widget.id, _collectItemsPayload());
      _baselineSignature = _currentSignature();
      // 2) Baru ajukan/submit.
      await pemakaianService.submitPemakaian(widget.id);
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Pemakaian diajukan',
        message: 'Dokumen berhasil diajukan untuk approval.',
        status: SnackBarStatus.success,
      );
      _navigateToInventory();
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pemakaian_detail.submit');
      if (!mounted) return;
      final code = PemakaianService.errorCode(e);
      String message = PemakaianService.humanizeError(e);
      if (code.startsWith('insufficient_stock')) {
        final idx = code.indexOf(':');
        final list = idx >= 0 ? code.substring(idx + 1).trim() : '';
        message = list.isNotEmpty
            ? 'Stok tidak cukup untuk:\n$list'
            : 'Stok tidak cukup untuk sebagian item.';
      }
      SnackbarUtil.show(
        context,
        title: 'Gagal mengajukan',
        message: message,
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

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
          size: 48,
          color: Colors.orange,
        ),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
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

  // ─── Deteksi perubahan & tombol kembali ─────────────────────────────────────

  /// Tanda tangan data baris saat ini (item, satuan, qty, keterangan).
  /// Foto tidak dihitung karena upload foto langsung tersimpan ke server.
  String _currentSignature() {
    return _items
        .where((e) => e.itemId != null)
        .map(
          (e) =>
              '${e.itemId}|${e.selectedUomId ?? 0}|'
              '${e.quantityController.text.trim()}|${e.remarksController.text.trim()}',
        )
        .join(';');
  }

  bool _hasUnsavedChanges() {
    if (_isLocked) return false;
    return _currentSignature() != _baselineSignature;
  }

  Future<void> _handleBack() async {
    if (!_hasUnsavedChanges()) {
      _navigateToInventory();
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        icon: const Icon(
          Icons.warning_amber_rounded,
          size: 48,
          color: Colors.orange,
        ),
        title: const Text(
          'Perubahan Belum Disimpan',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: const Text(
          'Ada perubahan yang belum disimpan sebagai draft. Simpan draft dulu, '
          'atau keluar tanpa menyimpan?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
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
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onPressed: () => Navigator.pop(ctx, 'discard'),
                  child: const Text(
                    'Keluar',
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
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  child: const Text(
                    'Simpan Draft',
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
    if (action == 'discard') {
      _navigateToInventory();
    } else if (action == 'save') {
      await _saveDraft();
      if (!mounted) return;
      // Keluar hanya jika draft benar-benar tersimpan (tidak ada sisa perubahan).
      if (!_hasUnsavedChanges()) _navigateToInventory();
    }
    // null (tap di luar) → tetap di halaman.
  }

  void _navigateToInventory() {
    selectedPageInventoryNotifier.value = 4;
    selectedPageNotifier.value = 4;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WidgetTree()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tglDate = _tglPemakaian != null
        ? (DateTime.tryParse(_tglPemakaian!) ?? DateTime.now())
        : DateTime.now();
    final today = _localeReady
        ? DateFormat('dd MMM yyyy', 'id_ID').format(tglDate)
        : DateFormat('dd MMM yyyy').format(tglDate);

    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textDark,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
            tooltip: 'Kembali',
          ),
          title: const Text(
            'Pemakaian Barang',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: Colors.grey.shade200),
          ),
        ),
        body: Column(
          children: [
            _buildInfoBar(today),
            Expanded(
              child: _isLoadingDetail
                  ? Center(
                      child: ModernLoading(
                        timeout: const Duration(seconds: 15),
                        onRetry: () {
                          setState(() => _isLoadingDetail = true);
                          _loadDetail();
                        },
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        isKeyboardVisible ? keyboardHeight + 16 : 8,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) => _buildItemCard(index),
                    ),
            ),
            if (!_isLoadingDetail && !isKeyboardVisible) _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBar(String today) {
    final isDraft = !_isLocked;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _documentNumber ?? 'Input Pemakaian Barang',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDraft
                            ? Colors.grey.shade100
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDraft
                              ? Colors.grey.shade700
                              : Colors.orange.shade800,
                        ),
                      ),
                    ),
                    if (widget.outletName.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.outletName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  today,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
    final qtyVolume = _qtyVolume(item);
    final overStock =
        item.itemId != null && qtyVolume > 0 && qtyVolume > item.stock;
    final estimate = (qtyVolume * item.avgPrice).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
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
          // Badge + hapus
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Item ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (_items.length > 1 && !_isLocked)
                IconButton(
                  onPressed: item.isDeleting ? null : () => _removeItem(index),
                  icon: item.isDeleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red,
                          ),
                        )
                      : const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                        ),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Hapus item',
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Foto (kiri) + field (kanan)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPhotoBox(index, item),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Nama Item'),
                    _buildItemDropdown(index, item),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Quantity'),
                              TextField(
                                controller: item.quantityController,
                                enabled: !_isLocked,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: const TextStyle(fontSize: 13),
                                decoration: _fieldDecoration('0'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Satuan'),
                              _buildUomDropdown(item),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (item.itemId != null) ...[
                      const SizedBox(height: 10),
                      _buildStockInfo(item, qtyVolume, estimate, overStock),
                    ],
                    const SizedBox(height: 10),
                    _buildLabel('Keterangan'),
                    TextField(
                      controller: item.remarksController,
                      enabled: !_isLocked,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13),
                      decoration: _fieldDecoration(
                        'Tambahkan keterangan (opsional)',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoBox(int index, _PemakaianItemEntry item) {
    final hasPhoto = item.imageFile != null || item.imageBytes != null;
    Widget content;
    if (item.imageFile != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.file(item.imageFile!, fit: BoxFit.cover),
      );
    } else if (item.isLoadingLampiran) {
      content = const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      );
    } else if (item.imageBytes != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.memory(item.imageBytes!, fit: BoxFit.cover),
      );
    } else {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt_outlined, color: Colors.grey[400], size: 28),
          const SizedBox(height: 4),
          Text('Foto', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ],
      );
    }

    return Stack(
      children: [
        AbsorbPointer(
          absorbing: _isLocked,
          child: GestureDetector(
            onTap: () => _captureImage(index),
            child: Container(
              width: 290,
              height: 290,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasPhoto ? AppColors.primary : Colors.grey.shade300,
                  width: hasPhoto ? 2 : 1,
                ),
              ),
              child: content,
            ),
          ),
        ),
        if (hasPhoto)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => _viewPhoto(
                item.imageFile != null
                    ? FileImage(item.imageFile!)
                    : MemoryImage(item.imageBytes!) as ImageProvider,
              ),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.visibility_outlined,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        if (item.isUploadingLampiran)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Mengunggah...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItemDropdown(int index, _PemakaianItemEntry item) {
    return DropdownMenu<int>(
      controller: item.itemNameController,
      enabled: !_isLocked,
      enableFilter: false,
      requestFocusOnTap: true,
      expandedInsets: EdgeInsets.zero,
      menuHeight: 200,
      menuStyle: MenuStyle(
        backgroundColor: WidgetStateProperty.all(Colors.white),
      ),
      hintText: 'Ketik nama item...',
      trailingIcon: item.isCatalogSearching
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          : const Icon(Icons.arrow_drop_down),
      textStyle: const TextStyle(fontSize: 13),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      onSelected: (value) {
        if (value == null) return;
        final catalog = item.filteredCatalog;
        if (catalog == null) return;
        final selected = catalog.firstWhere((c) => c.id == value);
        _onItemSelected(index, selected);
      },
      dropdownMenuEntries: (item.filteredCatalog ?? [])
          .map((c) => DropdownMenuEntry<int>(value: c.id, label: c.name))
          .toList(),
    );
  }

  Widget _buildUomDropdown(_PemakaianItemEntry item) {
    if (item.isLoadingDetail && item.uomOptions.isEmpty) {
      return Container(
        height: 44,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }
    final options = item.uomOptions;
    final value = options.any((o) => o.id == item.selectedUomId)
        ? item.selectedUomId
        : (options.isNotEmpty ? options.first.id : null);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _isLocked ? Colors.grey.shade100 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: value,
          hint: const Text('-', style: TextStyle(fontSize: 13)),
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          items: options
              .map(
                (o) => DropdownMenuItem<int>(
                  value: o.id,
                  child: Text(o.code, style: const TextStyle(fontSize: 13)),
                ),
              )
              .toList(),
          onChanged: _isLocked
              ? null
              : (v) => setState(() => item.selectedUomId = v),
        ),
      ),
    );
  }

  Widget _buildStockInfo(
    _PemakaianItemEntry item,
    num qtyVolume,
    int estimate,
    bool overStock,
  ) {
    final baseUom = _firstUomOfType(item, 'NISIK')?.code ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: overStock ? Colors.red.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: overStock ? Colors.red.shade200 : Colors.blue.shade100,
        ),
      ),
      child: Row(
        children: [
          Icon(
            overStock
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded,
            size: 16,
            color: overStock ? Colors.red.shade600 : Colors.blue.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Stok: ${_numFmt.format(item.stock)} $baseUom'
              '${qtyVolume > 0 ? '  •  Butuh: ${_numFmt.format(qtyVolume)} $baseUom' : ''}'
              '${estimate > 0 ? '  •  Est: ${convertIDR(estimate)}' : ''}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: overStock
                    ? Colors.red.shade700
                    : Colors.blueGrey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        top: false,
        child: _isLocked
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Dokumen sudah diajukan dan dikunci.',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (isSavingDraft || isSubmitting)
                          ? null
                          : _addItem,
                      icon: const Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      label: const Text(
                        'Tambah Item',
                        style: TextStyle(
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
                    child: OutlinedButton.icon(
                      onPressed: (isSavingDraft || isSubmitting)
                          ? null
                          : _saveDraft,
                      icon: isSavingDraft
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : const Icon(
                              Icons.save_outlined,
                              size: 18,
                              color: AppColors.primary,
                            ),
                      label: Text(
                        isSavingDraft ? 'Menyimpan...' : 'Simpan Draft',
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
                    child: FilledButton.icon(
                      onPressed: (isSavingDraft || isSubmitting)
                          ? null
                          : _submit,
                      icon: isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(isSubmitting ? 'Mengirim...' : 'Ajukan'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
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

  Widget _buildLabel(String text) => Padding(
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

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade200),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Camera capture page (dengan watermark GPS/waktu) — pola sama dengan reject.
// ─────────────────────────────────────────────────────────────────────────────

class _CameraCapturePage extends StatefulWidget {
  final String outletName;
  const _CameraCapturePage({this.outletName = ''});

  @override
  State<_CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<_CameraCapturePage> {
  CameraController? _controller;
  bool _isReady = false;
  bool _isTaking = false;
  Position? _position;
  String _address = '-';

  @override
  void initState() {
    super.initState();
    _initCamera();
    _getLocation();
  }

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
      _position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );

      final placemarks = await placemarkFromCoordinates(
        _position!.latitude,
        _position!.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.street,
          p.subLocality,
          p.locality,
        ].where((s) => s != null && s.isNotEmpty).join(', ');
        _address = parts.isNotEmpty ? parts : '-';
      }
    } catch (_) {
      // lokasi/geocoding tidak tersedia, tetap lanjut tanpa alamat
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
      if (mounted) setState(() => _isReady = true);
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pemakaian.camera.init');
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<File> _applyWatermark(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(src, Offset.zero, Paint());

    final now = DateTime.now();
    final latStr = _position != null
        ? _position!.latitude.toStringAsFixed(6)
        : '-';
    final longStr = _position != null
        ? _position!.longitude.toStringAsFixed(6)
        : '-';

    final lines = [
      'Lat    : $latStr',
      'Long   : $longStr',
      'Alamat : $_address',
      'Outlet : ${widget.outletName.isNotEmpty ? widget.outletName : '-'}',
      'Tanggal: ${DateFormat('dd/MM/yyyy').format(now)}',
      'Waktu  : ${DateFormat('HH:mm:ss').format(now)} WITA',
    ];

    final fontSize = src.width * 0.009;
    final lineHeight = fontSize * 1.6;
    final padding = fontSize * 0.9;
    final barHeight = lineHeight * lines.length + padding * 2;
    final barTop = (src.height - barHeight).toDouble();

    canvas.drawRect(
      Rect.fromLTWH(0, barTop, src.width.toDouble(), barHeight),
      Paint()..color = const Color(0xAA000000),
    );

    final textStyle = ui.TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: fontSize,
      fontFamily: 'monospace',
      shadows: const [
        ui.Shadow(
          color: Color(0xCC000000),
          blurRadius: 4,
          offset: Offset(1, 1),
        ),
      ],
    );
    final paraStyle = ui.ParagraphStyle(textDirection: ui.TextDirection.ltr);

    for (int i = 0; i < lines.length; i++) {
      final builder = ui.ParagraphBuilder(paraStyle)
        ..pushStyle(textStyle)
        ..addText(lines[i]);
      final para = builder.build()
        ..layout(
          ui.ParagraphConstraints(width: src.width.toDouble() - padding * 2),
        );
      canvas.drawParagraph(
        para,
        Offset(padding, barTop + padding + i * lineHeight),
      );
    }

    final picture = recorder.endRecording();
    final out = await picture.toImage(src.width, src.height);
    final byteData = await out.toByteData(format: ui.ImageByteFormat.png);

    src.dispose();
    out.dispose();

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final pngFile = File('${dir.path}/pemakaian_raw_$ts.png');
    await pngFile.writeAsBytes(byteData!.buffer.asUint8List());

    const targetBytes = 200 * 1024;
    final attempts = [
      {'quality': 85, 'minWidth': 1920},
      {'quality': 70, 'minWidth': 1280},
      {'quality': 55, 'minWidth': 1024},
      {'quality': 40, 'minWidth': 800},
    ];

    File? compressed;
    for (var i = 0; i < attempts.length; i++) {
      final a = attempts[i];
      final jpgPath = '${dir.path}/pemakaian_${ts}_$i.jpg';
      try {
        final result = await FlutterImageCompress.compressAndGetFile(
          pngFile.absolute.path,
          jpgPath,
          format: CompressFormat.jpeg,
          quality: a['quality']!,
          minWidth: a['minWidth']!,
          minHeight: a['minWidth']!,
        );
        if (result == null) continue;
        if (compressed != null) {
          try {
            await compressed.delete();
          } catch (_) {}
        }
        compressed = File(result.path);
        if (await compressed.length() <= targetBytes) break;
      } catch (e, stack) {
        CrashReporter.report(e, stack, reason: 'pemakaian.camera.compress');
      }
    }

    try {
      await pngFile.delete();
    } catch (_) {}

    return compressed ?? pngFile;
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isTaking) {
      return;
    }
    setState(() => _isTaking = true);
    try {
      final xFile = await _controller!.takePicture();
      final watermarked = await _applyWatermark(File(xFile.path));
      if (mounted) Navigator.pop<File>(context, watermarked);
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pemakaian.camera.capture');
      if (mounted) {
        setState(() => _isTaking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengambil foto. Coba lagi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Ambil Foto Item',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isReady
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller!),
                Center(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _isTaking ? null : _capture,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                            alpha: _isTaking ? 0.5 : 1.0,
                          ),
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: _isTaking
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black54,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 120,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      'Arahkan kamera ke item',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}
