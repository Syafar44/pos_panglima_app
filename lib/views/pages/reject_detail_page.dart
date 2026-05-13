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
import 'package:pos_panglima_app/services/reject_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

class _CatalogItem {
  final int id;
  final String code;
  final String name;
  _CatalogItem({required this.id, required this.code, required this.name});
}

class _RejectItemEntry {
  File? imageFile;
  Uint8List? imageBytes;
  bool isLoadingLampiran = false;
  int? lineId;
  int? lampiranId;
  String? lampiranUrl;
  int? itemId;
  String? itemCode;
  String? itemName;
  String uom = '-';
  bool isLoadingUom = false;
  bool isDeleting = false;
  bool isSaving = false;
  bool isUploadingLampiran = false;
  List<_CatalogItem>? filteredCatalog;
  bool isCatalogSearching = false;
  Timer? _searchTimer;

  bool get isSaved => lineId != null;

  final TextEditingController itemNameController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController remarksController = TextEditingController();

  void scheduleSearch(String query, VoidCallback onFire) {
    _searchTimer?.cancel();
    if (query.isEmpty) {
      filteredCatalog = null;
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 1000), onFire);
  }

  void dispose() {
    _searchTimer?.cancel();
    itemNameController.dispose();
    quantityController.dispose();
    remarksController.dispose();
  }
}

class RejectDetailPage extends StatefulWidget {
  final String outletName;
  final int id;
  const RejectDetailPage({super.key, this.outletName = '', required this.id});

  @override
  State<RejectDetailPage> createState() => _RejectDetailPageState();
}

class _RejectDetailPageState extends State<RejectDetailPage> {
  bool _localeReady = false;
  bool isSubmitting = false;
  bool isSavingDraft = false;
  Timer? _submitTimeoutTimer;
  bool _isPortrait = false;
  final ApiClient apiClient = ApiClient();
  late final RejectService rejectService;

  final List<_RejectItemEntry> _items = [];
  List<_CatalogItem> _catalog = [];
  bool _catalogLoading = false;
  bool _isLoadingDetail = true;
  bool _isAddingLine = false;
  String? _hashtagType;
  String? _tglReject;
  int? _customerId;
  String? _rawText;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    rejectService = RejectService(apiClient.dio);
    _loadCatalog();
    _loadRejectDetail();
    initializeDateFormatting('id_ID', null).then((_) {
      if (mounted) setState(() => _localeReady = true);
    });
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _loadRejectDetail() async {
    try {
      final res = await rejectService.getDetailReject(widget.id);
      final data = res.data['data'] as Map<String, dynamic>;
      final lines = (data['lines'] as List?) ?? [];
      final lampirans = (data['lampirans'] as List?) ?? [];
      debugPrint('[REJECT-DETAIL] loaded id=${widget.id}, '
          'lines=${lines.length}, lampirans=${lampirans.length}');

      // Buat map: reject_lines_id → lampiran_id
      // (file_url sekarang diambil dari masing-masing line, bukan dari lampirans)
      final lampiranIdMap = <int, int>{};
      for (final l in lampirans) {
        final lm = l as Map;
        final lampiranId = (lm['id'] as num?)?.toInt();
        final rejectLinesId = (lm['reject_lines_id'] as num?)?.toInt();
        debugPrint('[REJECT-DETAIL] lampiran raw → id=$lampiranId, '
            'reject_lines_id=$rejectLinesId');
        if (lampiranId != null && rejectLinesId != null) {
          lampiranIdMap[rejectLinesId] = lampiranId;
        }
      }
      debugPrint('[REJECT-DETAIL] lampiranIdMap built: $lampiranIdMap');

      _hashtagType = data['hashtag_type']?.toString();
      final rawDate = data['tgl_reject']?.toString();
      if (rawDate != null && rawDate.isNotEmpty) {
        final parsed = DateTime.tryParse(rawDate);
        _tglReject = parsed != null
            ? DateFormat('yyyy-MM-dd').format(parsed)
            : rawDate;
      }
      _customerId = (data['customer_id'] as num?)?.toInt();
      _rawText = data['raw_text']?.toString();
      _isLocked = data['approve'] != null;

      if (!mounted) return;

      setState(() {
        for (final line in lines) {
          final m = line as Map;
          final entry = _createItem();
          entry.lineId = (m['id'] as num?)?.toInt();
          final lineFileUrl = m['file_url']?.toString() ?? '';
          if (lineFileUrl.isNotEmpty) {
            entry.lampiranUrl = lineFileUrl;
          }
          if (entry.lineId != null) {
            final lampiranId = lampiranIdMap[entry.lineId!] ??
                _extractLampiranIdFromUrl(lineFileUrl);
            if (lampiranId != null) {
              entry.lampiranId = lampiranId;
            }
            debugPrint('[REJECT-DETAIL] line ${entry.lineId} → '
                'lampiranId=$lampiranId, file_url="$lineFileUrl"');
          }
          entry.itemId = (m['item_id'] as num?)?.toInt();
          entry.itemCode = (m['code'] ?? m['item_code'])?.toString();
          entry.itemName = (m['nama_produk'] ?? m['name'] ?? m['item_name'])
              ?.toString();
          if (entry.itemName != null) {
            entry.itemNameController.text = entry.itemName!;
          }
          final uomName = m['satuan'] ?? m['uom']?['name'] ?? m['uom_name'];
          if (uomName != null) entry.uom = uomName.toString();
          final qty = m['qty'] ?? m['quantity'];
          if (qty != null) entry.quantityController.text = qty.toString();
          final remarks = m['alasan'] ?? m['remarks'] ?? m['note'];
          if (remarks != null) {
            entry.remarksController.text = remarks.toString();
          }

          // Buang baris kosong (tanpa item terpilih) dari response API
          if (entry.itemId == null) {
            entry.dispose();
            continue;
          }

          _items.add(entry);
        }
        // Sediakan baris draft kosong hanya jika belum di-approve
        if (!_isLocked) {
          _items.add(_createItem());
        }
      });

      // Fetch lampiran untuk setiap baris yang memiliki lampiran
      // (cek seluruh items, bukan length-1, karena draft kosong sudah otomatis
      // di-skip oleh kondisi url null/empty)
      debugPrint('[REJECT-DETAIL] _items.length=${_items.length}, '
          'isLocked=$_isLocked');
      for (int i = 0; i < _items.length; i++) {
        final url = _items[i].lampiranUrl;
        debugPrint('[REJECT-DETAIL] check item[$i] '
            'lineId=${_items[i].lineId}, url="$url"');
        if (url != null && url.isNotEmpty) _fetchLampiran(i);
      }
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'reject_detail.loadDetail');
      if (mounted) {
        SnackbarUtil.show(
          context,
          title: 'Gagal memuat data',
          message: 'Terjadi kendala saat memuat data reject.',
          status: SnackBarStatus.error,
        );
        // Tetap kasih 1 draft kosong supaya user bisa mulai input
        setState(() => _items.add(_createItem()));
      }
    } finally {
      if (mounted) setState(() => _isLoadingDetail = false);
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

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _submitTimeoutTimer?.cancel();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  _RejectItemEntry _createItem() {
    final entry = _RejectItemEntry();
    entry.itemNameController.addListener(() {
      if (!mounted) return;
      final idx = _items.indexOf(entry);
      if (idx == -1) return;
      final text = entry.itemNameController.text.trim();
      // Skip jika text sama dengan item yang sudah dipilih (set otomatis oleh DropdownMenu)
      if (entry.itemName != null && text == entry.itemName) return;
      // User ubah text → clear pilihan sebelumnya
      if (entry.itemId != null) {
        entry.itemId = null;
        entry.itemCode = null;
        entry.itemName = null;
        entry.uom = '-';
        entry.filteredCatalog = null;
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
      final res = await rejectService.getListItems(search: query);
      final list = (res.data['data'] as List?) ?? [];
      if (mounted && index < _items.length) {
        setState(() {
          _items[index].filteredCatalog = list
              .map(
                (e) => _CatalogItem(
                  id: e['id'] as int,
                  code: e['code'] as String,
                  name: e['name'] as String,
                ),
              )
              .toList();
          _items[index].isCatalogSearching = false;
        });
      }
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'reject_detail.searchItems');
      if (mounted && index < _items.length) {
        setState(() => _items[index].isCatalogSearching = false);
      }
    }
  }

  Future<void> _loadCatalog() async {
    setState(() => _catalogLoading = true);
    try {
      final res = await rejectService.getListItems();
      final list = (res.data['data'] as List?) ?? [];
      if (mounted) {
        setState(() {
          _catalog = list
              .map(
                (e) => _CatalogItem(
                  id: e['id'] as int,
                  code: e['code'] as String,
                  name: e['name'] as String,
                ),
              )
              .toList();
        });
      }
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'reject_detail.loadCatalog');
    } finally {
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  Future<void> _onItemSelected(int index, _CatalogItem item) async {
    setState(() {
      _items[index].itemId = item.id;
      _items[index].itemCode = item.code;
      _items[index].itemName = item.name;
      _items[index].uom = '-';
      _items[index].isLoadingUom = true;
    });
    try {
      final res = await rejectService.getDetailItems(item.id);
      final data = res.data['data'];
      final uomName = (data['uom']?['name'] as String?) ?? '-';
      if (mounted) {
        setState(() {
          _items[index].uom = uomName;
          _items[index].isLoadingUom = false;
        });
      }
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'reject_detail.loadItemDetail');
      if (mounted) setState(() => _items[index].isLoadingUom = false);
    }
  }

  void _viewPhoto(File file) {
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
              child: Image.file(file, fit: BoxFit.contain),
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

  Future<void> _fetchLampiran(int index) async {
    if (index >= _items.length) return;
    final item = _items[index];
    final url = item.lampiranUrl;
    if (url == null || url.isEmpty) {
      debugPrint('[REJECT-FETCH] skip index=$index, url is null/empty');
      return;
    }
    debugPrint('[REJECT-FETCH] START index=$index, url="$url"');
    if (mounted) setState(() => item.isLoadingLampiran = true);
    try {
      final res = await rejectService.getLampiran(url);
      debugPrint('[REJECT-FETCH] response index=$index, '
          'status=${res.statusCode}, '
          'content-type=${res.headers.value('content-type')}, '
          'runtimeType=${res.data.runtimeType}');

      final raw = res.data;
      Uint8List? bytes;
      if (raw is Uint8List) {
        bytes = raw;
      } else if (raw is List<int>) {
        bytes = Uint8List.fromList(raw);
      } else {
        debugPrint('[REJECT-FETCH] WARNING: data bukan Uint8List/List<int>. '
            'Sample: ${raw.toString().substring(0, raw.toString().length.clamp(0, 200))}');
      }
      debugPrint('[REJECT-FETCH] bytes.length=${bytes?.length ?? 0}');

      if (!mounted) return;
      setState(() {
        item.imageBytes = bytes;
        item.isLoadingLampiran = false;
      });
    } catch (e, stack) {
      debugPrint('[REJECT-FETCH] ERROR index=$index, url="$url" → $e');
      debugPrint(stack.toString());
      if (mounted) setState(() => item.isLoadingLampiran = false);
    }
  }

  void _viewPhotoBytes(Uint8List bytes) {
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
              child: Image.memory(bytes, fit: BoxFit.contain),
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

  Future<void> _addItem() async {
    if (_isAddingLine || _items.isEmpty) return;

    final lastIndex = _items.length - 1;
    final last = _items[lastIndex];

    // Kalau baris terakhir sudah tersimpan (rare case), langsung tambah draft baru
    if (last.isSaved) {
      setState(() => _items.add(_createItem()));
      return;
    }

    // Validasi baris terakhir sebelum simpan
    final qty = int.tryParse(last.quantityController.text.trim()) ?? 0;
    final alasan = last.remarksController.text.trim();

    if (last.itemId == null) {
      SnackbarUtil.show(
        context,
        title: 'Item belum dipilih',
        message: 'Pilih item pada baris terakhir terlebih dahulu.',
        status: SnackBarStatus.warning,
      );
      return;
    }
    if (qty <= 0) {
      SnackbarUtil.show(
        context,
        title: 'Quantity tidak valid',
        message: 'Quantity baris terakhir harus lebih dari 0.',
        status: SnackBarStatus.warning,
      );
      return;
    }
    if (alasan.isEmpty) {
      SnackbarUtil.show(
        context,
        title: 'Alasan kosong',
        message: 'Isi alasan reject pada baris terakhir.',
        status: SnackBarStatus.warning,
      );
      return;
    }

    setState(() {
      _isAddingLine = true;
      last.isSaving = true;
    });

    try {
      final payload = {'item_id': last.itemId, 'qty': qty, 'alasan': alasan};
      final res = await rejectService.addLinesReject(widget.id, payload);
      final data = res.data['data'];

      if (!mounted) return;
      setState(() {
        last.lineId = (data is Map) ? data['id'] as int? : null;
        last.isSaving = false;
        _isAddingLine = false;
        _items.add(_createItem());
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'reject_detail.addLine');
      if (mounted) {
        setState(() {
          last.isSaving = false;
          _isAddingLine = false;
        });
        SnackbarUtil.show(
          context,
          title: 'Gagal menyimpan baris',
          message: 'Terjadi kendala saat menyimpan baris item.',
          status: SnackBarStatus.error,
        );
      }
    }
  }

  /// Extract lampiran id dari URL berformat: /pos/reject/{rejectId}/lampirans/{lampiranId}/file
  int? _extractLampiranIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final match = RegExp(r'/lampirans/(\d+)').firstMatch(url);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
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
          'Item ke-$displayIndex akan dihapus beserta foto lampirannya. Lanjutkan?',
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
                    style: TextStyle(
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

  Future<void> _removeItem(int index) async {
    if (index >= _items.length) return;
    final item = _items[index];
    if (item.isDeleting) return;

    final confirmed = await _confirmDeleteItem(index + 1);
    if (confirmed != true || !mounted) return;

    if (index >= _items.length) return;

    if (item.lineId != null) {
      setState(() => item.isDeleting = true);

      // Pastikan lampiranId tersedia (fallback: extract dari file_url)
      final lampiranId =
          item.lampiranId ?? _extractLampiranIdFromUrl(item.lampiranUrl);

      // Best-effort: hapus lampiran dulu kalau ada (cegah FK constraint saat delete line)
      if (lampiranId != null) {
        try {
          await rejectService.deleteLampiran(widget.id, lampiranId);
          if (mounted) {
            setState(() {
              item.lampiranId = null;
              item.lampiranUrl = null;
              item.imageBytes = null;
              item.imageFile = null;
            });
          }
        } catch (e, stack) {
          CrashReporter.report(
            e,
            stack,
            reason: 'reject_detail.deleteLampiranOnRemove',
          );
        }
      }

      try {
        await rejectService.deleteLinesReject(widget.id, item.lineId!);
      } catch (e, stack) {
        CrashReporter.report(e, stack, reason: 'reject_detail.deleteLine');
        if (mounted) {
          setState(() => item.isDeleting = false);
          SnackbarUtil.show(
            context,
            title: 'Gagal hapus item',
            message: 'Terjadi kendala saat menghapus item.',
            status: SnackBarStatus.error,
          );
        }
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      item.dispose();
      _items.removeAt(index);
    });
    SnackbarUtil.show(
      context,
      title: 'Item dihapus',
      message: 'Item berhasil dihapus.',
      status: SnackBarStatus.success,
    );
  }

  Future<void> _captureImage(int index) async {
    if (index >= _items.length) return;
    final item = _items[index];

    // 1. Validasi item dipilih
    if (item.itemId == null) {
      SnackbarUtil.show(
        context,
        title: 'Pilih item dulu',
        message: 'Pilih nama item terlebih dahulu sebelum mengambil foto.',
        status: SnackBarStatus.warning,
      );
      return;
    }

    // 2. Validasi quantity
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

    // 3. Validasi alasan
    final alasan = item.remarksController.text.trim();
    if (alasan.isEmpty) {
      SnackbarUtil.show(
        context,
        title: 'Alasan kosong',
        message: 'Isi alasan reject terlebih dahulu.',
        status: SnackBarStatus.warning,
      );
      return;
    }

    final hasExistingPhoto = item.imageFile != null || item.lampiranId != null;
    if (hasExistingPhoto) {
      final confirmed = await _confirmReplacePhoto(item);
      if (confirmed != true || !mounted) return;
    }

    // 5. Save line ke server kalau belum tersimpan
    if (item.lineId == null) {
      setState(() => item.isSaving = true);
      try {
        final res = await rejectService.addLinesReject(widget.id, {
          'item_id': item.itemId,
          'qty': qty,
          'alasan': alasan,
        });
        final data = res.data['data'];
        if (!mounted) return;
        setState(() {
          item.lineId = (data is Map) ? (data['id'] as num?)?.toInt() : null;
          item.isSaving = false;
        });
      } catch (e, stack) {
        CrashReporter.report(
          e,
          stack,
          reason: 'reject_detail.captureImage.saveLine',
        );
        if (mounted) {
          setState(() => item.isSaving = false);
          SnackbarUtil.show(
            context,
            title: 'Gagal menyimpan baris',
            message: 'Tidak dapat menyimpan baris item. Coba kembali.',
            status: SnackBarStatus.error,
          );
        }
        return;
      }
    }

    // 6. Permission kamera
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

    // 7. Buka kamera
    final file = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => _CameraCapturePage(outletName: widget.outletName),
      ),
    );
    if (file == null || !mounted) return;

    // 8. Tampilkan preview lokal lalu upload
    setState(() => item.imageFile = file);
    await _uploadLampiran(item, file);
  }

  Future<bool?> _confirmReplacePhoto(_RejectItemEntry item) {
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
                    final oldLampiranId = item.lampiranId;
                    if (oldLampiranId != null) {
                      try {
                        await rejectService.deleteLampiran(
                          widget.id,
                          oldLampiranId,
                        );
                        if (mounted) {
                          setState(() {
                            item.lampiranId = null;
                            item.lampiranUrl = null;
                            item.imageBytes = null;
                          });
                        }
                      } catch (e, stack) {
                        CrashReporter.report(
                          e,
                          stack,
                          reason: 'reject_detail.deleteLampiranOnReplace',
                        );
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

  Future<void> _uploadLampiran(_RejectItemEntry item, File file) async {
    if (item.lineId == null) return;

    setState(() => item.isUploadingLampiran = true);

    try {
      final fileName = 'reject-${item.itemName ?? ''}-${widget.id}.jpg';
      final formData = FormData.fromMap({
        'reject_lines_id': item.lineId,
        'name': fileName,
        'mime_type': 'image/jpeg',
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final res = await rejectService.postLampiran(widget.id, formData);
      final data = res.data['data'];
      if (!mounted) return;
      setState(() {
        item.lampiranId = (data is Map) ? (data['id'] as num?)?.toInt() : null;
        item.lampiranUrl = (data is Map)
            ? data['file_url']?.toString()
            : null;
        item.isUploadingLampiran = false;
      });
      SnackbarUtil.show(
        context,
        title: 'Foto tersimpan',
        message: 'Foto berhasil diunggah.',
        status: SnackBarStatus.success,
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'reject_detail.uploadLampiran');
      if (mounted) {
        setState(() => item.isUploadingLampiran = false);
        SnackbarUtil.show(
          context,
          title: 'Gagal upload foto',
          message: 'Foto belum tersimpan ke server. Coba ambil ulang.',
          status: SnackBarStatus.error,
        );
      }
    }
  }

  /// Kumpulkan lines payload sesuai kontrak API:
  /// - punya lineId (>0) → sertakan "id" untuk update
  /// - tanpa lineId       → tanpa "id" untuk insert baru
  /// - line lama yang tidak ada di array → dihapus oleh backend (cascade)
  List<Map<String, dynamic>> _collectLinesPayload() {
    return _items.where((e) => e.itemId != null).map((e) {
      final map = <String, dynamic>{
        'item_id': e.itemId,
        'qty': int.tryParse(e.quantityController.text.trim()) ?? 0,
        'alasan': e.remarksController.text.trim(),
      };
      if (e.lineId != null && e.lineId! > 0) {
        map['id'] = e.lineId;
      }
      return map;
    }).toList();
  }

  Future<void> _saveDraft() async {
    if (isSubmitting) return;

    final lines = _collectLinesPayload();

    if (lines.isEmpty) {
      SnackbarUtil.show(
        context,
        title: 'Tidak ada item',
        message: 'Minimal isi 1 item terlebih dahulu.',
        status: SnackBarStatus.warning,
      );
      return;
    }

    // Validasi setiap line: item_id & qty wajib (qty > 0)
    for (int i = 0; i < lines.length; i++) {
      if ((lines[i]['qty'] as int) <= 0) {
        SnackbarUtil.show(
          context,
          title: 'Quantity tidak valid',
          message: 'Quantity baris ke-${i + 1} harus lebih dari 0.',
          status: SnackBarStatus.warning,
        );
        return;
      }
      if ((lines[i]['alasan'] as String).isEmpty) {
        SnackbarUtil.show(
          context,
          title: 'Alasan kosong',
          message: 'Isi alasan reject pada baris ke-${i + 1}.',
          status: SnackBarStatus.warning,
        );
        return;
      }
    }

    setState(() => isSavingDraft = true);
    try {
      final payload = <String, dynamic>{
        'tgl_reject':
            _tglReject ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'hashtag_type': _hashtagType ?? '#REJECT',
        'customer_id': _customerId,
        'raw_text': _rawText ?? '',
        'lines': lines,
      };
      await rejectService.postRejectDraft(widget.id, payload);
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Draft tersimpan',
        message: 'Data reject berhasil disimpan sebagai draft.',
        status: SnackBarStatus.success,
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'reject_detail.saveDraft');
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Gagal simpan draft',
        message: 'Terjadi kendala saat menyimpan draft. Coba kembali.',
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => isSavingDraft = false);
    }
  }

  Future<void> _submit() async {
    if (isSubmitting || isSavingDraft) return;

    // Hanya validasi baris yang sudah tersimpan (punya lineId)
    final savedItems = _items.where((e) => e.lineId != null).toList();

    if (savedItems.isEmpty) {
      SnackbarUtil.show(
        context,
        title: 'Item kosong',
        message: 'Tambahkan minimal 1 item reject.',
        status: SnackBarStatus.warning,
      );
      return;
    }

    for (int i = 0; i < savedItems.length; i++) {
      final item = savedItems[i];
      final hasPhoto = item.imageFile != null || item.imageBytes != null;
      if (!hasPhoto) {
        SnackbarUtil.show(
          context,
          title: 'Foto belum ada',
          message: 'Item ke-${i + 1} belum memiliki foto.',
          status: SnackBarStatus.warning,
        );
        return;
      }
      if (item.itemName == null) {
        SnackbarUtil.show(
          context,
          title: 'Item belum dipilih',
          message: 'Item ke-${i + 1} belum memilih nama barang.',
          status: SnackBarStatus.warning,
        );
        return;
      }
      if ((int.tryParse(item.quantityController.text.trim()) ?? 0) <= 0) {
        SnackbarUtil.show(
          context,
          title: 'Quantity tidak valid',
          message: 'Item ke-${i + 1} harus memiliki quantity lebih dari 0.',
          status: SnackBarStatus.warning,
        );
        return;
      }
    }

    final confirmed = await showDialog<bool>(
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
          'Submit Reject?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: const Text(
          'Setelah disubmit, data reject akan dikunci dan tidak dapat diubah kembali. Lanjutkan?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
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

    final finalConfirmed = await showDialog<bool>(
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
          'Konfirmasi Reject?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        content: const Text(
          'Pastikan seluruh data sudah benar. Anda yakin ingin submit stock opname sekarang? Aksi ini tidak dapat dibatalkan.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
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
    if (finalConfirmed != true || !mounted) return;

    setState(() => isSubmitting = true);

    // Start timeout timer
    _submitTimeoutTimer?.cancel();
    _submitTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && isSubmitting) {
        _showSubmissionTimeoutDialog();
      }
    });

    try {
      await rejectService.postRejectSubmit(widget.id);
      _submitTimeoutTimer?.cancel();

      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Reject disubmit',
        message: 'Data reject berhasil disubmit.',
        status: SnackBarStatus.success,
      );
      _navigateToInventory();
    } catch (e, stack) {
      _submitTimeoutTimer?.cancel();
      CrashReporter.report(e, stack, reason: 'reject_detail_page.submit');
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Gagal submit',
        message: 'Terjadi kendala saat submit reject. Coba kembali.',
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void _navigateToInventory() {
    selectedPageInventoryNotifier.value = 3;
    selectedPageNotifier.value = 3;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WidgetTree()),
      (route) => false,
    );
  }

  void _showSubmissionTimeoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.hourglass_bottom_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Text('Proses Sedang Berjalan'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Proses submit memakan waktu lebih lama dari biasanya. Ini mungkin karena kendala jaringan.',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 16),
            Text(
              'Mohon jangan tutup aplikasi agar data tetap sinkron. Anda boleh kembali ke halaman riwayat sementara proses berlanjut.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToInventory();
            },
            child: const Text('Kembali ke Riwayat'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Tunggu Saja'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _localeReady
        ? DateFormat('dd MMM yyyy', 'id_ID').format(DateTime.now())
        : DateFormat('dd MMM yyyy').format(DateTime.now());

    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            selectedPageInventoryNotifier.value = 3;
            selectedPageNotifier.value = 3;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const WidgetTree()),
              (route) => false,
            );
          },
          tooltip: 'Kembali',
        ),
        title: const Text(
          'Buat Reject',
          style: TextStyle(fontWeight: FontWeight.bold),
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
      body: Column(
        children: [
          // Header info bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Buat Reject Baru',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Input item yang akan di-reject',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
          ),

          // Item list
          Expanded(
            child: _isLoadingDetail
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
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
    );
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
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
          // Badge + remove
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Item ${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ),
                  if (item.isSaved) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: Colors.green.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Tersimpan',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (item.isSaving) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Menyimpan...',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
              if (_items.length > 1)
                if (!_isLocked)
                  IconButton(
                    onPressed: (item.isDeleting || _isLocked)
                        ? null
                        : () => _removeItem(index),
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

          // Photo + fields
          IgnorePointer(
            ignoring: item.isSaving,
            child: Opacity(
              opacity: item.isSaving ? 0.6 : 1.0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Camera tap area
                  Stack(
                    children: [
                      AbsorbPointer(
                        absorbing: _isLocked,
                        child: GestureDetector(
                          onTap: () => _captureImage(index),
                          child: Container(
                            width: 255,
                            height: 255,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    (item.imageFile != null ||
                                        item.imageBytes != null)
                                    ? AppColors.primary
                                    : Colors.grey.shade300,
                                width:
                                    (item.imageFile != null ||
                                        item.imageBytes != null)
                                    ? 2
                                    : 1,
                              ),
                            ),
                            child: item.imageFile != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: Image.file(
                                      item.imageFile!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : item.isLoadingLampiran
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : item.imageBytes != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: Image.memory(
                                      item.imageBytes!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.camera_alt_outlined,
                                        color: Colors.grey[400],
                                        size: 28,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Foto',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      if (item.imageFile != null || item.imageBytes != null)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: () => item.imageFile != null
                                ? _viewPhoto(item.imageFile!)
                                : _viewPhotoBytes(item.imageBytes!),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.visibility_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      if (item.isUploadingLampiran)
                        Positioned(
                          left: 0,
                          top: 0,
                          right: 0,
                          bottom: 0,
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
                                    width: 32,
                                    height: 32,
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
                  ),
                  const SizedBox(width: 14),

                  // Form fields
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Item dropdown
                        _buildLabel('Nama Item'),
                        DropdownMenu<int>(
                          controller: item.itemNameController,
                          enabled: !_isLocked,
                          enableFilter: false,
                          requestFocusOnTap: true,
                          expandedInsets: EdgeInsets.zero,
                          menuHeight: 200,
                          menuStyle: MenuStyle(
                            backgroundColor: WidgetStateProperty.all(
                              Colors.white,
                            ),
                          ),
                          hintText: _catalogLoading
                              ? 'Memuat...'
                              : 'Ketik nama item...',
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
                              vertical: 11,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                          onSelected: (id) {
                            if (id != null) {
                              final entries = item.filteredCatalog ?? _catalog;
                              final found = entries.firstWhere(
                                (e) => e.id == id,
                              );
                              _onItemSelected(index, found);
                            }
                          },
                          dropdownMenuEntries:
                              (item.filteredCatalog ?? _catalog)
                                  .map(
                                    (e) => DropdownMenuEntry<int>(
                                      value: e.id,
                                      label: e.name,
                                      leadingIcon: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryLight,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          e.code,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primaryDark,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                        const SizedBox(height: 10),

                        // Quantity + UOM
                        Row(
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
                                    onChanged: (_) => setState(() {}),
                                    decoration: _fieldDecoration(hint: '0'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel('Satuan'),
                                  Container(
                                    height: 40,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: item.isLoadingUom
                                        ? const Center(
                                            child: SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          )
                                        : Text(
                                            item.uom,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black54,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Remarks
                        _buildLabel('Keterangan'),
                        TextField(
                          controller: item.remarksController,
                          enabled: !_isLocked,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 13),
                          decoration: _fieldDecoration(hint: 'Alasan reject'),
                        ),
                      ],
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

  InputDecoration _fieldDecoration({required String hint}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
  );

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        top: false,
        child: _isLocked
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: Colors.grey,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Data sudah diproses dan tidak dapat diubah',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            : Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: (isSubmitting || isSavingDraft || _isAddingLine)
                        ? null
                        : _addItem,
                    icon: _isAddingLine
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(
                            Icons.add_rounded,
                            color: AppColors.primary,
                          ),
                    label: Text(
                      _isAddingLine ? 'Menambah...' : 'Tambah Item',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      side: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (isSubmitting || isSavingDraft) ? null : _saveDraft,
                      icon: isSavingDraft
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.save_outlined,
                              color: Colors.white,
                            ),
                      label: Text(
                        isSavingDraft ? 'Menyimpan...' : 'Simpan Draft',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.textDark,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (isSubmitting || isSavingDraft) ? null : _submit,
                      icon: isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                            ),
                      label: Text(
                        isSubmitting ? 'Mengirim...' : 'Submit Reject',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Camera capture page
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

      // Reverse geocoding
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
      CrashReporter.report(e, stack, reason: 'reject.camera.init');
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
    final pngFile = File('${dir.path}/reject_raw_$ts.png');
    await pngFile.writeAsBytes(byteData!.buffer.asUint8List());

    // Kompres PNG → JPEG ~50KB. Coba beberapa kali dengan parameter makin agresif
    // sampai ukuran ≤ 50KB atau quality minimum tercapai.
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
      final jpgPath = '${dir.path}/reject_${ts}_$i.jpg';
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
        // Hapus hasil sebelumnya
        if (compressed != null) {
          try {
            await compressed.delete();
          } catch (_) {}
        }
        compressed = File(result.path);
        if (await compressed.length() <= targetBytes) break;
      } catch (e, stack) {
        CrashReporter.report(e, stack, reason: 'reject.camera.compress');
      }
    }

    // Cleanup PNG mentah
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
      CrashReporter.report(e, stack, reason: 'reject.camera.capture');
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
                // Guide overlay
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
                // Capture button
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
                // Hint text
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
