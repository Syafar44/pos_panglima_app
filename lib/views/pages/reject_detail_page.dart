import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int? itemId;
  String? itemCode;
  String? itemName;
  String uom = '-';
  bool isLoadingUom = false;
  List<_CatalogItem>? filteredCatalog;
  bool isCatalogSearching = false;
  Timer? _searchTimer;

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

// ─────────────────────────────────────────────────────────────────────────────

class RejectDetailPage extends StatefulWidget {
  final String outletName;
  const RejectDetailPage({super.key, this.outletName = ''});

  @override
  State<RejectDetailPage> createState() => _RejectDetailPageState();
}

class _RejectDetailPageState extends State<RejectDetailPage> {
  bool _localeReady = false;
  bool isSubmitting = false;
  bool _isPortrait = false;
  final ApiClient apiClient = ApiClient();
  late final RejectService rejectService;

  final List<_RejectItemEntry> _items = [];
  List<_CatalogItem> _catalog = [];
  bool _catalogLoading = false;

  @override
  void initState() {
    super.initState();
    rejectService = RejectService(apiClient.dio);
    _items.add(_createItem());
    _loadCatalog();
    initializeDateFormatting('id_ID', null).then((_) {
      if (mounted) setState(() => _localeReady = true);
    });
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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

  void _addItem() => setState(() => _items.add(_createItem()));

  void _removeItem(int index) {
    _items[index].dispose();
    setState(() => _items.removeAt(index));
  }

  Future<void> _captureImage(int index) async {
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
    if (file != null && mounted) {
      setState(() => _items[index].imageFile = file);
    }
  }

  Future<void> _submit() async {
    if (isSubmitting) return;

    if (_items.isEmpty) {
      SnackbarUtil.show(
        context,
        title: 'Item kosong',
        message: 'Tambahkan minimal 1 item reject.',
        status: SnackBarStatus.warning,
      );
      return;
    }

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.imageFile == null) {
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
          'Setelah disubmit, data reject tidak dapat diubah kembali. Lanjutkan?',
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
                    backgroundColor: Colors.red,
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

    setState(() => isSubmitting = true);
    try {
      // TODO: ganti dengan API call yang sebenarnya
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Reject disubmit',
        message: 'Data reject berhasil disubmit.',
        status: SnackBarStatus.success,
      );
      selectedPageInventoryNotifier.value = 3;
      selectedPageNotifier.value = 3;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WidgetTree()),
        (route) => false,
      );
    } catch (e, stack) {
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

  @override
  Widget build(BuildContext context) {
    final today = _localeReady
        ? DateFormat('dd MMM yyyy', 'id_ID').format(DateTime.now())
        : DateFormat('dd MMM yyyy').format(DateTime.now());

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _items.length,
              itemBuilder: (context, index) => _buildItemCard(index),
            ),
          ),

          // Bottom bar
          _buildBottomBar(),
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
              if (_items.length > 1)
                IconButton(
                  onPressed: () => _removeItem(index),
                  icon: const Icon(
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Camera tap area
              Stack(
                children: [
                  GestureDetector(
                    onTap: () => _captureImage(index),
                    child: Container(
                      width: 255,
                      height: 255,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: item.imageFile != null
                              ? AppColors.primary
                              : Colors.grey.shade300,
                          width: item.imageFile != null ? 2 : 1,
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
                  if (item.imageFile != null)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: () => _viewPhoto(item.imageFile!),
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
                      enableFilter: false,
                      requestFocusOnTap: true,
                      expandedInsets: EdgeInsets.zero,
                      menuHeight: 200,
                      menuStyle: MenuStyle(
                        backgroundColor: WidgetStateProperty.all(Colors.white),
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
                      onSelected: (id) {
                        if (id != null) {
                          final entries = item.filteredCatalog ?? _catalog;
                          final found = entries.firstWhere((e) => e.id == id);
                          _onItemSelected(index, found);
                        }
                      },
                      dropdownMenuEntries: (item.filteredCatalog ?? _catalog)
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
                                  borderRadius: BorderRadius.circular(4),
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
                      maxLines: 2,
                      style: const TextStyle(fontSize: 13),
                      decoration: _fieldDecoration(
                        hint: 'Alasan reject (opsional)',
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
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: isSubmitting ? null : _addItem,
              icon: const Icon(Icons.add_rounded, color: AppColors.primary),
              label: const Text(
                'Tambah Item',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isSubmitting ? null : _submit,
                icon: isSubmitting
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
    final outFile = File(
      '${dir.path}/reject_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await outFile.writeAsBytes(byteData!.buffer.asUint8List());
    return outFile;
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
