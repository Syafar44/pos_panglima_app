import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/inventory_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/notif_utils.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/widgets/confirm_modal.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

class ReceptionInventoryPage extends StatefulWidget {
  const ReceptionInventoryPage({super.key, required this.id});

  final int id;

  @override
  State<ReceptionInventoryPage> createState() => _ReceptionInventoryPageState();
}

class _ReceptionInventoryPageState extends State<ReceptionInventoryPage> {
  bool headerChecked = false;
  final apiClient = ApiClient();
  late final AuthService authService;
  late final InventoryService inventoryService;
  Map<String, dynamic>? inventoryDetail;
  Map<String, dynamic>? profile;
  late bool isLoading = true;
  late bool isLoadingProfile = true;
  final Map<int, TextEditingController> realisasiControllers = {};
  final Map<int, TextEditingController> remarksControllers = {};
  dynamic focusedItemId;
  bool _isPortrait = false;

  /// True jika username (nama profil) mengandung "Gerai Panglima".
  /// Menentukan tampilan tombol Realisasi Partial/Close & kolom Final Realisasi.
  bool get isGeraiPanglima =>
      (profile?['name'] ?? '').toString().contains('Gerai Panglima');

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
  void initState() {
    super.initState();
    inventoryService = InventoryService(apiClient.dio);
    authService = AuthService(apiClient.dio);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    getInventoryTransferDetail();
    getProfile();
  }

  Future<void> getInventoryTransferDetail() async {
    try {
      final response = await inventoryService.getDetail(widget.id);

      setState(() {
        inventoryDetail = response.data['data'];
      });

      final lines = response.data['data']['inventory_transfer_lines'];

      // ── DEBUG: dump lengkap inventory detail (inspeksi final realisasi) ──
      // Hanya logging; tidak mengubah alur. debugPrint memotong ~1020 char,
      // jadi JSON dicetak per potongan agar utuh.
      final detail = response.data['data'];
      debugPrint(
        '[InventoryDetail] header keys: ${(detail as Map).keys.toList()}',
      );
      final encoded = const JsonEncoder.withIndent('  ').convert(detail);
      const chunk = 800;
      for (var i = 0; i < encoded.length; i += chunk) {
        debugPrint(
          '[InventoryDetail] ${encoded.substring(i, i + chunk > encoded.length ? encoded.length : i + chunk)}',
        );
      }
      if (lines is List) {
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i] as Map;
          debugPrint(
            '[InventoryDetail] line[$i] item=${l['item_name']} '
            'qty=${l['quantity']} realisasi=${l['realisasi']} '
            'reject=${l['reject']} remarks="${l['remarks']}"',
          );
        }
      }
      // ── AKHIR DEBUG ─────────────────────────────────────────────────────

      for (final line in lines) {
        final lineId = line['id'];
        realisasiControllers[lineId] ??= TextEditingController();
        remarksControllers[lineId] ??= TextEditingController();
      }
      _applyRealisasiDefaults();

      setState(() => isLoading = false);
    } catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'reception_inventory_page.getInventoryTransferDetail',
      );
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: "Gagal memuat data inventory",
        message:
            "Terjadi kendala saat mengambil data inventory. Mohon periksa koneksi atau coba kembali.",
        status: SnackBarStatus.error,
      );
    }
  }

  /// Set nilai default kolom input realisasi.
  /// - Sudah approve: tampilkan realisasi tersimpan.
  /// - Gerai Panglima (belum approve): default 0 (tidak dari qty).
  /// - Lainnya (belum approve): default sisa = quantity - realisasi.
  ///
  /// Dipanggil dari [getInventoryTransferDetail] (saat lines siap) dan
  /// [getProfile] (saat profil siap), supaya hasilnya benar di urutan apa pun.
  void _applyRealisasiDefaults() {
    final lines = inventoryDetail?['inventory_transfer_lines'];
    if (lines is! List) return;
    final approved = inventoryDetail?['approve'] == 1;
    for (final line in lines) {
      final controller = realisasiControllers[line['id']];
      if (controller == null) continue;
      if (approved) {
        controller.text = (line['realisasi'] ?? 0).toString();
      } else if (isGeraiPanglima) {
        controller.text = '0';
      } else {
        final num qty = line['quantity'] ?? 0;
        final num realized = line['realisasi'] ?? 0;
        final num remaining = (qty - realized) < 0 ? 0 : (qty - realized);
        controller.text = remaining.toString();
      }
    }
  }

  Future<void> getProfile() async {
    try {
      final response = await authService.getProfile();

      if (!mounted) return;

      setState(() {
        profile = response.data['data'];
        isLoadingProfile = false;
      });

      // Profil baru termuat → terapkan default (mis. Gerai Panglima → 0).
      _applyRealisasiDefaults();
    } catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'reception_inventory_page.getProfile',
      );
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: "Gagal memuat data pengguna",
        message:
            "Terjadi kendala saat mengambil data pengguna. Mohon periksa koneksi atau coba kembali.",
        status: SnackBarStatus.error,
      );
    }
  }

  Map<String, dynamic> buildPayload() {
    final lines = inventoryDetail?['inventory_transfer_lines'] ?? [];

    for (final line in lines) {
      final qty = line['quantity'];
      final realisasi =
          int.tryParse(realisasiControllers[line['id']]?.text ?? '0') ?? 0;

      if (realisasi > qty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Realisasi item ${line['item_name']} melebihi quantity",
            ),
          ),
        );
        throw Exception(
          "Realisasi item ${line['item_name']} melebihi quantity",
        );
      }
    }

    return {
      "id": inventoryDetail?['id'],
      "approve": 1,
      "approve_users_id": profile?['userid'],
      "approve_date": DateTime.now().toString(),
      "inventory_transfer_lines": lines.map((line) {
        final double qty = (line['quantity'] ?? 0).toDouble();
        final double realisasi =
            double.tryParse(realisasiControllers[line['id']]?.text ?? '0') ??
            0.0;

        return {
          "id": line['id'],
          "inventory_transfer_id": line['inventory_transfer_id'],
          "item_id": line['item_id'],
          "quantity": qty,
          "realisasi": realisasi,
          "reject": qty - realisasi,
          "remarks": remarksControllers[line['id']]?.text ?? "-",
        };
      }).toList(),
    };
  }

  Future<void> submitRealisasi() async {
    try {
      if (!validateRealisasi()) return;

      final mismatchItems = getMismatchItems();

      if (mismatchItems.isNotEmpty) {
        final proceed = await showRemarksModal(mismatchItems);
        if (!proceed) return;
      }

      final confirm = await showConfirmModal(
        'Konfirmasi Penerimaan',
        'Apakah Anda yakin ingin menyimpan penerimaan ini?',
      );

      if (!confirm) return;

      final payload = buildPayload();

      await inventoryService.patchRealisasi(inventoryDetail?['id'], payload);

      if (!mounted) return;

      SnackbarUtil.show(
        context,
        title: "Berhasil Disimpan",
        message: "Penerimaan berhasil disimpan",
        status: SnackBarStatus.success,
      );

      resetNotif();

      selectedPageInventoryNotifier.value = 1;
      selectedPageNotifier.value = 3;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WidgetTree()),
        (route) => false,
      );
    } on DioException catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'reception_inventory_page.submitRealisasi',
        context: {
          'endpoint': e.requestOptions.path,
          'statusCode': e.response?.statusCode,
          'responseData': e.response?.data?.toString(),
        },
      );
      if (!mounted) return;
      debugPrint("DioException: ${e.response?.data ?? e.message}");
      SnackbarUtil.show(
        context,
        title: "Gagal menyimpan penerimaan",
        message:
            "Terjadi kendala saat menyimpan penerimaan. Mohon periksa koneksi atau coba kembali.",
        status: SnackBarStatus.error,
      );
    }
  }

  /// Realisasi Partial (Gerai Panglima) — kirim realisasi per baris tanpa
  /// menutup surat jalan. Tetap di halaman & reload detail agar kolom
  /// "Final Realisasi" memperlihatkan akumulasi terbaru.
  Future<void> submitRealisasiPartial() async {
    try {
      final List<dynamic> lines =
          inventoryDetail?['inventory_transfer_lines'] ?? [];

      // Validasi: input (sisa yang diterima ronde ini) + realisasi (yang sudah
      // terealisasi) tidak boleh melebihi quantity.
      for (final line in lines) {
        final double qty = (line['quantity'] ?? 0).toDouble();
        final double realized = (line['realisasi'] ?? 0).toDouble();
        final double input =
            double.tryParse(realisasiControllers[line['id']]?.text ?? '0') ??
            0.0;
        if (input + realized > qty) {
          if (!mounted) return;
          SnackbarUtil.show(
            context,
            title: "Realisasi melebihi quantity",
            message:
                "${line['item_name']}: total realisasi (${input + realized}) melebihi quantity ($qty).",
            status: SnackBarStatus.error,
          );
          return;
        }
      }

      // Konfirmasi dobel untuk mengurangi salah klik.
      final confirm1 = await showConfirmModal(
        'Konfirmasi Realisasi Partial',
        'Simpan realisasi sebagian untuk surat jalan ini?',
      );
      if (!confirm1) return;

      final confirm2 = await showConfirmModal(
        'Konfirmasi Sekali Lagi',
        'Pastikan jumlah realisasi sudah benar. Lanjut simpan?',
      );
      if (!confirm2) return;

      // Nilai yang dikirim = input + realisasi yang sudah ada (nilai absolut baru).
      final payloadLines = lines.map<Map<String, dynamic>>((line) {
        final double realized = (line['realisasi'] ?? 0).toDouble();
        final double input =
            double.tryParse(realisasiControllers[line['id']]?.text ?? '0') ??
            0.0;
        return {"id": line['id'], "realisasi": input + realized};
      }).toList();

      await inventoryService.realisasiPartial(
        inventoryDetail?['id'],
        payloadLines,
      );

      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: "Berhasil Disimpan",
        message: "Realisasi partial berhasil disimpan",
        status: SnackBarStatus.success,
      );

      // Reload detail (tetap di halaman) untuk menampilkan Final Realisasi baru.
      setState(() => isLoading = true);
      await getInventoryTransferDetail();
    } on DioException catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'reception_inventory_page.submitRealisasiPartial',
        context: {
          'endpoint': e.requestOptions.path,
          'statusCode': e.response?.statusCode,
          'responseData': e.response?.data?.toString(),
        },
      );
      if (!mounted) return;
      debugPrint("DioException: ${e.response?.data ?? e.message}");

      // Server menolak realisasi partial yang berulang untuk item yang sama
      // (unique constraint). Beri pesan yang lebih jelas ke kasir.
      final String serverMsg =
          (e.response?.data is Map ? e.response?.data['message'] : '')
              ?.toString() ??
          '';
      final bool isDuplicate = serverMsg.contains('duplicate key');

      SnackbarUtil.show(
        context,
        title: isDuplicate
            ? "Realisasi sudah tercatat"
            : "Gagal menyimpan realisasi partial",
        message: isDuplicate
            ? "Item pada surat jalan ini sudah pernah direalisasi. Gunakan \"Realisasi Close\" untuk menyelesaikan."
            : "Terjadi kendala saat menyimpan realisasi partial. Mohon periksa koneksi atau coba kembali.",
        status: SnackBarStatus.error,
      );
    }
  }

  /// Realisasi Close (Gerai Panglima) — tutup/selesaikan surat jalan.
  /// `approve_users_id` diambil dari detail surat jalan (approver yang sudah
  /// ditetapkan saat dibuat); fallback ke user yang sedang login bila kosong.
  Future<void> submitRealisasiClose() async {
    try {
      // Konfirmasi dobel untuk mengurangi salah klik.
      final confirm1 = await showConfirmModal(
        'Konfirmasi Tutup Realisasi',
        'Tutup (close) surat jalan ini? Penerimaan akan diselesaikan.',
      );
      if (!confirm1) return;

      final confirm2 = await showConfirmModal(
        'Konfirmasi Sekali Lagi',
        'Setelah ditutup, surat jalan tidak bisa diubah lagi. Yakin menutup?',
      );
      if (!confirm2) return;

      final int detailApprover =
          (inventoryDetail?['approve_users_id'] as num?)?.toInt() ?? 0;
      final int approveUsersId = detailApprover > 0
          ? detailApprover
          : ((profile?['userid'] as num?)?.toInt() ?? 0);

      await inventoryService.realisasiClose(
        inventoryDetail?['id'],
        approveUsersId,
      );

      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: "Berhasil Ditutup",
        message: "Surat jalan berhasil ditutup",
        status: SnackBarStatus.success,
      );

      resetNotif();
      selectedPageInventoryNotifier.value = 1;
      selectedPageNotifier.value = 3;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WidgetTree()),
        (route) => false,
      );
    } on DioException catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'reception_inventory_page.submitRealisasiClose',
        context: {
          'endpoint': e.requestOptions.path,
          'statusCode': e.response?.statusCode,
          'responseData': e.response?.data?.toString(),
        },
      );
      if (!mounted) return;
      debugPrint("DioException: ${e.response?.data ?? e.message}");
      SnackbarUtil.show(
        context,
        title: "Gagal menutup surat jalan",
        message:
            "Terjadi kendala saat menutup surat jalan. Mohon periksa koneksi atau coba kembali.",
        status: SnackBarStatus.error,
      );
    }
  }

  List<Map<String, dynamic>> getMismatchItems() {
    final List<dynamic> lines =
        inventoryDetail?['inventory_transfer_lines'] ?? [];

    return lines
        .where((line) {
          final double qty = (line['quantity'] ?? 0).toDouble();
          final double realisasi =
              double.tryParse(realisasiControllers[line['id']]?.text ?? '0') ??
              0;
          return realisasi < qty;
        })
        .map((line) => line as Map<String, dynamic>)
        .toList();
  }

  Future<bool> showConfirmModal(String title, String description) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) {
            return ConfirmModal(title: title, description: description);
          },
        ) ??
        false;
  }

  Future<bool> showRemarksModal(
    List<Map<String, dynamic>> items,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              titlePadding: EdgeInsets.zero,
              title: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "Selisih Barang Ditemukan",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Beberapa barang memiliki jumlah kirim dan terima yang berbeda. Mohon berikan alasan.",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    // Selisih dihitung PER ITEM dari realisasi masing-masing,
                    // bukan dari satu nilai global (penyebab bug 2872 vs 2000).
                    final int qtyItem = (item['quantity'] as num? ?? 0).toInt();
                    final int realisasiItem = int.tryParse(
                          realisasiControllers[item['id']]?.text ?? '0',
                        ) ??
                        0;
                    final int selisihItem = qtyItem - realisasiItem;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['item_name'] ?? '-',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Selisih: $selisihItem ${item['uoms_code']}",
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: remarksControllers[item['id']],
                            maxLines: 2,
                            decoration: InputDecoration(
                              hintText: "Contoh: Barang rusak di perjalanan...",
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade400,
                              ),
                              fillColor: Colors.white,
                              filled: true,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    "Batal",
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      bool allValid = true;
                      for (final item in items) {
                        final controller = remarksControllers[item['id']];
                        if (controller == null ||
                            controller.text.trim().isEmpty) {
                          allValid = false;
                          break;
                        }
                      }

                      if (!allValid) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Mohon isi semua alasan selisih"),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else {
                        Navigator.pop(context, true);
                      }
                    },
                    child: const Text(
                      "Simpan & Lanjutkan",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  bool validateRealisasi() {
    final lines = inventoryDetail?['inventory_transfer_lines'] ?? [];

    for (final line in lines) {
      final String itemName = line['item_name'] ?? 'Barang';
      final double qtyKirim = (line['quantity'] ?? 0).toDouble();

      // Ambil nilai dari controller, default ke 0 jika kosong atau tidak valid
      final controller = realisasiControllers[line['id']];
      final double realisasi = double.tryParse(controller?.text ?? '0') ?? 0;

      if (realisasi > qtyKirim) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            elevation: 3,
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade800,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Jumlah $itemName melebihi kiriman ($realisasi > $qtyKirim)",
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    for (final c in realisasiControllers.values) {
      c.dispose();
    }
    for (final c in remarksControllers.values) {
      c.dispose();
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildScaffold(context);
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'Penerimaan Surat Jalan',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5, // Memberikan kesan modern pada teks
          ),
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(16), // Sedikit melengkung di sudut bawah
          ),
        ),
      ),
      body: isLoading || isLoadingProfile
          ? Center(
              child: ModernLoading(
                timeout: const Duration(seconds: 10),
                onRetry: () {
                  setState(() {
                    isLoading = true;
                    isLoadingProfile = true;
                  });
                  getInventoryTransferDetail();
                  getProfile();
                },
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 10.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sisi Kiri
                      Expanded(
                        flex: 5,
                        child: Column(
                          children: [
                            _buildInfoRow(
                              'No. PO/SJ',
                              inventoryDetail?['document_number'],
                            ),
                            const SizedBox(height: 5),
                            _buildInfoRow(
                              'Supplier',
                              inventoryDetail?['from_outlet_hub_name'],
                            ),
                            const SizedBox(height: 5),
                            _buildInfoRow(
                              'Ke Gudang',
                              inventoryDetail?['to_outlet_hub_name'],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Sisi Kanan
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            _buildInfoRow(
                              'Tanggal',
                              formatDateTime(inventoryDetail?['date']),
                            ),
                            const SizedBox(height: 5),
                            _buildInfoRow('Penerima', profile?['name']),
                            const SizedBox(height: 5),
                            _buildInfoRow(
                              'Status',
                              inventoryDetail?['approve'] == 1
                                  ? 'Telah Diterima'
                                  : 'Menunggu',
                              isStatus: true,
                              isApproved: inventoryDetail?['approve'] == 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: Card(
                      color: Colors.white,
                      elevation: 2,
                      margin: const EdgeInsets.only(top: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          // Header Tabel yang lebih clean
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  flex: 4,
                                  child: Text(
                                    "DETAIL BARANG",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  flex: 2,
                                  child: Center(
                                    child: Text(
                                      "QTY",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  flex: 2,
                                  child: Center(
                                    child: Text(
                                      "REALISASI",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                ),
                                // Kolom Final Realisasi (hanya Gerai Panglima,
                                // disembunyikan saat sudah "Telah Diterima").
                                if (isGeraiPanglima &&
                                    inventoryDetail?['approve'] != 1)
                                  const Expanded(
                                    flex: 2,
                                    child: Center(
                                      child: Text(
                                        "Final Realisasi",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                  ),
                                // Kolom Keterangan tidak dipakai untuk Gerai.
                                if (inventoryDetail?['approve'] == 1 &&
                                    !isGeraiPanglima)
                                  const Expanded(
                                    flex: 3,
                                    child: Center(
                                      child: Text(
                                        "KETERANGAN",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          Expanded(
                            child: ListView.separated(
                              itemCount:
                                  inventoryDetail?['inventory_transfer_lines']
                                      ?.length ??
                                  0,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: Colors.grey.shade200,
                              ),
                              itemBuilder: (context, index) {
                                final item =
                                    inventoryDetail?['inventory_transfer_lines'][index];

                                if (focusedItemId != null &&
                                    focusedItemId != item['id']) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      // Kolom Nama & Kode (Dibuat bertumpuk agar hemat ruang horizontal)
                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item["item_name"] ?? '-',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              item["item_code"] ?? '-',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Kolom Qty Kirim & Satuan
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          children: [
                                            Text(
                                              "${item['quantity']}",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            Text(
                                              "${item['uoms_code']}",
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: ValueListenableBuilder<TextEditingValue>(
                                          valueListenable:
                                              realisasiControllers[item['id']]!,
                                          builder: (context, value, _) {
                                            // Baseline pembanding warna:
                                            // - Gerai Panglima: sisa (quantity - realisasi)
                                            //   karena input = jumlah ronde ini.
                                            // - Lainnya: quantity penuh.
                                            final double qtyFull =
                                                (item['quantity'] ?? 0)
                                                    .toDouble();
                                            final double realized =
                                                (item['realisasi'] ?? 0)
                                                    .toDouble();
                                            // Baseline = sisa (qty - realisasi)
                                            // HANYA saat mode input partial Gerai
                                            // (belum approve). Saat sudah approve,
                                            // input = realisasi absolut → baseline
                                            // = quantity penuh (20 == 20 → biru).
                                            final bool isPartialInput =
                                                isGeraiPanglima &&
                                                inventoryDetail?['approve'] !=
                                                    1;
                                            final qty = isPartialInput
                                                ? (qtyFull - realized)
                                                : qtyFull;
                                            final realisasi =
                                                double.tryParse(value.text) ??
                                                0;

                                            Color inputColor;
                                            Color inputBgColor;

                                            if (realisasi == 0) {
                                              inputColor = Colors
                                                  .blue; // default belum diisi
                                              inputBgColor =
                                                  Colors.blue.shade50;
                                            } else if (realisasi < qty) {
                                              inputColor =
                                                  Colors.orange; // kurang
                                              inputBgColor =
                                                  Colors.orange.shade50;
                                            } else if (realisasi == qty) {
                                              inputColor = Colors.blue; // pas
                                              inputBgColor =
                                                  Colors.blue.shade50;
                                            } else {
                                              inputColor =
                                                  Colors.red; // kelebihan
                                              inputBgColor = Colors.red.shade50;
                                            }

                                            return SizedBox(
                                              height: 45,
                                              child: TextField(
                                                controller:
                                                    realisasiControllers[item['id']],
                                                keyboardType:
                                                    TextInputType.number,
                                                textAlign: TextAlign.center,
                                                enabled:
                                                    inventoryDetail?['approve'] !=
                                                    1,
                                                onTap: () {
                                                  setState(() {
                                                    focusedItemId = item['id'];
                                                  });
                                                },
                                                onEditingComplete: () {
                                                  setState(() {
                                                    focusedItemId = null;
                                                  });
                                                  FocusScope.of(
                                                    context,
                                                  ).unfocus();
                                                },
                                                onTapOutside: (_) {
                                                  setState(() {
                                                    focusedItemId = null;
                                                  });
                                                },
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: inputColor,
                                                ),
                                                decoration: InputDecoration(
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 0,
                                                      ),
                                                  hintText: '0',
                                                  filled: true,
                                                  fillColor: inputBgColor,
                                                  enabledBorder:
                                                      OutlineInputBorder(
                                                        borderSide: BorderSide(
                                                          color: inputColor
                                                              .withValues(
                                                                alpha: 0.3,
                                                              ),
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                  focusedBorder:
                                                      OutlineInputBorder(
                                                        borderSide: BorderSide(
                                                          color: inputColor,
                                                          width: 2,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                      ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      // Kolom Final Realisasi (hanya Gerai Panglima;
                                      // disembunyikan saat sudah "Telah Diterima").
                                      // Field "realisasi" = jumlah yang sudah
                                      // terealisasi (akumulatif) dari server.
                                      if (isGeraiPanglima &&
                                          inventoryDetail?['approve'] != 1)
                                        Expanded(
                                          flex: 2,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8.0,
                                            ),
                                            child: SizedBox(
                                              height: 45,
                                              child: Container(
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: Colors.green
                                                        .withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: Text(
                                                  "${item['realisasi'] ?? '-'}",
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.green,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      // Kolom Keterangan tidak dipakai untuk Gerai.
                                      if (inventoryDetail?['approve'] == 1 &&
                                          !isGeraiPanglima)
                                        Expanded(
                                          flex: 3,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8.0,
                                            ),
                                            child: Text(
                                              item['remarks'] != null &&
                                                      item['remarks']
                                                          .toString()
                                                          .isNotEmpty
                                                  ? item['remarks']
                                                  : "-",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (inventoryDetail?['approve'] != 1)
                    Column(
                      mainAxisSize: MainAxisSize
                          .min, // Agar kontainer mengikuti tinggi konten
                      children: [
                        // Box Peringatan / Alert
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.red.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Harap perhatikan kembali barang yang diterima sebelum menekan tombol "Konfirmasi". Pastikan jumlah dan kualitas barang sudah sesuai.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),

                        // Tombol Aksi
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: isGeraiPanglima
                              ? Row(
                                  children: [
                                    // Tombol kiri: Realisasi Partial
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: submitRealisasiPartial,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.save_outlined),
                                            SizedBox(width: 8),
                                            Text(
                                              'Realisasi Partial',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Tombol kanan: Realisasi Close
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: submitRealisasiClose,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.check_circle_outline),
                                            SizedBox(width: 8),
                                            Text(
                                              'Realisasi Close',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ElevatedButton(
                                  onPressed: submitRealisasi,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline),
                                      SizedBox(width: 8),
                                      Text(
                                        'Konfirmasi Terima Barang',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
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
            ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String? value, {
    bool isStatus = false,
    bool isApproved = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 85, // Lebar label tetap
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          ": ",
          style: TextStyle(
            color: Colors.grey[700],
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(
            value ?? '-',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isApproved
                  ? Colors.green.shade700
                  : isStatus
                  ? Colors.orange.shade900
                  : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
