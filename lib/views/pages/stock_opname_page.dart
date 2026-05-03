import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/stock_opname_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

class StockOpnamePage extends StatefulWidget {
  final int id;
  const StockOpnamePage({super.key, required this.id});

  @override
  State<StockOpnamePage> createState() => _StockOpnamePageState();
}

class _StockOpnameItem {
  final int id;
  final String itemCode;
  final String itemName;
  final String uomCode;
  final int systemQty;
  final TextEditingController qtyController;
  final TextEditingController remarksController;

  _StockOpnameItem({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.uomCode,
    this.systemQty = 0,
    int actualQty = 0,
    String remarks = '',
  }) : qtyController = TextEditingController(
         text: actualQty > 0 ? '$actualQty' : '',
       ),
       remarksController = TextEditingController(text: remarks);

  void dispose() {
    qtyController.dispose();
    remarksController.dispose();
  }

  Map<String, dynamic> toUpdatePayload() => {
    'id': id,
    'actual_qty': int.tryParse(qtyController.text.trim()) ?? 0,
    'remarks': remarksController.text.trim(),
  };
}

class _StockOpnamePageState extends State<StockOpnamePage> {
  final ApiClient apiClient = ApiClient();
  late final StockOpnameService stockOpnameService;

  bool _localeReady = false;
  bool isLoading = true;
  bool isSaving = false;
  bool isSubmitting = false;
  bool _isPortrait = false;

  Map<String, dynamic>? detail;
  List<_StockOpnameItem> items = [];

  @override
  void initState() {
    super.initState();
    stockOpnameService = StockOpnameService(apiClient.dio);
    initializeDateFormatting('id_ID', null).then((_) {
      if (mounted) setState(() => _localeReady = true);
    });
    fetchDetail();
  }

  void _toggleOrientation() {
    setState(() => _isPortrait = !_isPortrait);
  }

  @override
  void dispose() {
    for (final item in items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> fetchDetail() async {
    setState(() => isLoading = true);
    try {
      final response = await stockOpnameService.getDetailSO(widget.id);
      final data = response.data['data'] as Map<String, dynamic>;
      final lines = (data['lines'] ?? []) as List;

      for (final item in items) {
        item.dispose();
      }

      final newItems = lines
          .map<_StockOpnameItem>(
            (line) => _StockOpnameItem(
              id: (line['id'] as num).toInt(),
              itemCode: line['item_code']?.toString() ?? '',
              itemName: line['item_name']?.toString() ?? '',
              uomCode: line['uom_code']?.toString() ?? '',
              systemQty: (line['system_qty'] as num?)?.toInt() ?? 0,
              actualQty: (line['actual_qty'] as num?)?.toInt() ?? 0,
              remarks: line['remarks']?.toString() ?? '',
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        detail = data;
        items = newItems;
        isLoading = false;
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'stock_opname_page.fetchDetail');
      if (!mounted) return;
      setState(() => isLoading = false);
      SnackbarUtil.show(
        context,
        title: 'Gagal memuat detail',
        message: 'Terjadi kendala saat mengambil detail stock opname.',
        status: SnackBarStatus.error,
      );
    }
  }

  Future<void> _pickDate() async {
    SnackbarUtil.show(
      context,
      title: 'Tidak dapat diubah',
      message: 'Tanggal stock opname mengikuti tanggal pembuatan draft.',
      status: SnackBarStatus.warning,
    );
  }

  bool _isReadOnly() {
    final status = (detail?['status'] ?? '').toString().toLowerCase();
    return status != 'draft';
  }

  Future<void> _saveDraft() async {
    if (_isReadOnly()) return;
    if (isSaving || isSubmitting) return;
    setState(() => isSaving = true);
    try {
      final payload = {
        'lines': items.map((item) => item.toUpdatePayload()).toList(),
      };
      await stockOpnameService.updateDraftSO(widget.id, payload);
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Draft tersimpan',
        message: 'Stock opname disimpan sebagai draft.',
        status: SnackBarStatus.success,
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'stock_opname_page.saveDraft');
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Gagal menyimpan draft',
        message: 'Terjadi kendala saat menyimpan draft. Coba kembali.',
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> _submit() async {
    if (_isReadOnly()) return;
    if (isSubmitting || isSaving) return;
    setState(() => isSubmitting = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Memperhalus sudut agar terlihat lebih modern
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        // Mencegah Material 3 memberikan warna tint pada background putih
        surfaceTintColor: Colors.transparent,

        // 1. Menambahkan Ikon Indikator
        icon: const Icon(
          Icons
              .info_outline_rounded, // Gunakan warning_rounded jika ini aksi destruktif
          size: 48,
          color: AppColors.primary,
        ),

        // 2. Tipografi Judul yang Terpusat
        title: const Text(
          'Submit Stock Opname?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),

        // 3. Tipografi Konten yang Lebih Lembut
        content: const Text(
          'Setelah disubmit, data stock opname akan dikunci dan tidak dapat diubah kembali. Lanjutkan?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.black54,
            height: 1.5, // Memberikan ruang bernapas antar baris teks
          ),
        ),

        // 4. Penataan Tombol Modern (Sejajar dan Proporsional)
        actionsPadding: const EdgeInsets.only(
          bottom: 24,
          left: 20,
          right: 20,
          top: 10,
        ),
        actions: [
          Row(
            children: [
              // Tombol Secondary (Batal)
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
              // Tombol Primary (Submit)
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
                    'Submit',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => isSubmitting = false);
      return;
    }
    if (!mounted) return;

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
          'Konfirmasi Akhir',
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
    if (finalConfirmed != true) {
      if (mounted) setState(() => isSubmitting = false);
      return;
    }
    if (!mounted) return;

    try {
      await stockOpnameService.updateDraftSO(widget.id, {
        'lines': items.map((item) => item.toUpdatePayload()).toList(),
      });
      await stockOpnameService.submitSO(widget.id);
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Stock opname dikirim',
        message: 'Data stock opname berhasil disubmit.',
        status: SnackBarStatus.success,
      );
      isBackSO.value = false;
      selectedPageInventoryNotifier.value = 2;
      selectedPageNotifier.value = 3;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WidgetTree()),
        (route) => false,
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'stock_opname_page.submit');
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Gagal submit',
        message: 'Terjadi kendala saat submit stock opname. Coba kembali.',
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: _isPortrait ? 3 : 0,
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            isBackSO.value = false;
            selectedPageInventoryNotifier.value = 2;
            selectedPageNotifier.value = 3;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const WidgetTree()),
              (route) => false,
            );
          },
          tooltip: 'Kembali ke Menu Utama',
        ),
        title: Text(
          detail?['document_number']?.toString() ?? 'Stock Opname',
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
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildItemList()),
                if (!_isReadOnly()) _buildBottomBar(),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    final dateStr = detail?['date']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(dateStr);
    final dateLabel = parsedDate != null
        ? (_localeReady
              ? DateFormat('dd MMM yyyy', 'id_ID').format(parsedDate)
              : DateFormat('dd MMM yyyy').format(parsedDate))
        : '-';
    final status = (detail?['status'] ?? '').toString();
    final isDraft = status.toLowerCase() == 'draft';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Daily Stock Opname',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDraft
                            ? Colors.blueGrey.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDraft ? Colors.blueGrey : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  detail?['outlet_hub_name']?.toString() ?? '-',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if ((detail?['remarks']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail!['remarks'].toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tanggal',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
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
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemList() {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Belum ada item',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildItemCard(index),
    );
  }

  Widget _buildItemCard(int index) {
    final item = items[index];
    final readOnly = _isReadOnly();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                        item.itemCode,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.itemName,
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
                  controller: item.qtyController,
                  hint: '0',
                  uomCode: item.uomCode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  readOnly: readOnly,
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
                  controller: item.remarksController,
                  hint: 'Keterangan (opsional)',
                  readOnly: readOnly,
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
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      readOnly: readOnly,
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
                padding: const EdgeInsets.only(
                  right: 12.0,
                ), // Jarak teks dengan batas kanan
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
            ? const BoxConstraints(
                minWidth: 0,
                minHeight:
                    0, // Memastikan suffix tidak memakan ruang ekstra secara vertikal
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        filled: true,
        fillColor: readOnly ? Colors.grey.shade100 : Colors.grey.shade50,
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
    );
  }

  Widget _buildBottomBar() {
    final busy = isSaving || isSubmitting;
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
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : _saveDraft,
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(Icons.save_outlined, color: AppColors.primary),
                label: Text(
                  isSaving ? 'Menyimpan...' : 'Simpan Draft',
                  style: const TextStyle(
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
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: busy ? null : _submit,
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
                  isSubmitting ? 'Mengirim...' : 'Submit',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
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
