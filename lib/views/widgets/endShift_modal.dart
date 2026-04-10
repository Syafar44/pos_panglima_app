import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/report_service.dart';
import 'package:pos_panglima_app/services/shift_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';
import 'package:pos_panglima_app/utils/rupiah_formatter.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/pages/login_page.dart';
import 'package:pos_panglima_app/views/widgets/confirm_modal.dart';

class EndShiftModal extends StatefulWidget {
  const EndShiftModal({super.key});

  @override
  State<EndShiftModal> createState() => _EndShiftModalState();
}

class _EndShiftModalState extends State<EndShiftModal> {
  final apiClient = ApiClient();
  late final ShiftService shiftService;
  late final AuthService authService;
  late final ReportService reportService;
  Map<String, dynamic>? profile;
  bool isLoadingProfile = true;
  TextEditingController controllerSalesEnd = TextEditingController();
  TextEditingController remarksControllers = TextEditingController();
  String date = DateTime.now().toString();
  int? shiftId;
  int? cashActive;
  late bool isLoading = true;
  Map<String, dynamic> reportData = {};
  int totalPenerimaan = 0;

  @override
  void initState() {
    super.initState();
    authService = AuthService(apiClient.dio);
    shiftService = ShiftService(apiClient.dio);
    reportService = ReportService(apiClient.dio);

    getProfile();
    _loadShiftId();
  }

  Future<void> getProfile() async {
    try {
      final response = await authService.getProfile();

      final data = response.data['data'];

      if (!mounted) return;
      setState(() {
        profile = data;
        isLoadingProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      isLoadingProfile = false;
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

  Future<void> _loadShiftId() async {
    final result = await ShiftStorageService.getShiftId();
    final cash = await ShiftStorageService.getCash();
    await _getPenerimaan(result);
    _autoFillSalesEnd(cash);
    setState(() {
      shiftId = result;
      cashActive = cash;
      isLoading = false;
    });
  }

  Future<void> _deleteIdShift() async {
    await ShiftStorageService.clearShift();
  }

  Map<String, dynamic> buildPayload() {
    return {
      "id": shiftId,
      "shift_end": DateTime.now().toString(),
      "sales_end": parseRupiah(controllerSalesEnd.text),
      if (remarksControllers.text.isNotEmpty) "excuse": remarksControllers.text,
    };
  }

  Future<void> _getPenerimaan(shiftId) async {
    try {
      final response = await reportService.getPenerimaan(shiftId);
      final result = response.data['data'] ?? {};
      debugPrint('penerimaan result: $result');
      setState(() {
        reportData = response.data['data'] ?? {};
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error fetching report data: $e');
    }
  }

  void _autoFillSalesEnd(cash) {
    if (reportData == null) return;

    final totalPenerimaanNew = (reportData?['total_penerimaan'] ?? 0) as int;
    final cashActive = cash ?? 0;
    final total = totalPenerimaanNew + cashActive;

    setState(() {
      totalPenerimaan = total.toInt();
    });

    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    controllerSalesEnd.text = formatter.format(total);
  }

  Future<bool> showRemarksModal(
    List<Map<String, dynamic>> items,
    int realisasiQty,
  ) async {
    remarksControllers.clear(); // Reset dulu setiap kali modal dibuka

    final selisih = realisasiQty - totalPenerimaan;
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

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
                          "Selisih Pendapatan Ditemukan",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Terdapat perbedaan antara total pendapatan sistem dan input Anda.",
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
                child: SingleChildScrollView(
                  child: Container(
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
                        // Info selisih
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Column(
                            children: [
                              _buildSelisihRow(
                                'Input Anda',
                                formatter.format(realisasiQty),
                              ),
                              const SizedBox(height: 4),
                              _buildSelisihRow(
                                'Total Sistem',
                                formatter.format(totalPenerimaan),
                              ),
                              const Divider(),
                              _buildSelisihRow(
                                'Selisih',
                                formatter.format(selisih.abs()),
                                isBold: true,
                                color: Colors.red.shade700,
                              ),
                            ],
                          ),
                        ),
                        const Text(
                          'Berikan Keterangan',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Kenapa terjadi perbedaan pendapatan antara sistem dan pendapatan manual",
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: remarksControllers,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Tulis alasan selisih di sini...',
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
                  ),
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
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black87,
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
                    // Validasi: pastikan alasan tidak kosong
                    if (remarksControllers.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Mohon isi alasan selisih"),
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
              ],
            );
          },
        ) ??
        false;
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

  Future<void> submitEndShift() async {
    try {
      final salesInput = parseRupiah(controllerSalesEnd.text);

      if (salesInput <= 0) {
        SnackbarUtil.show(
          context,
          title: "Input Tidak Valid",
          message: "Total pendapatan wajib diisi",
          status: SnackBarStatus.warning,
        );
        return;
      }

      if (shiftId == null) {
        SnackbarUtil.show(
          context,
          title: "Data Tidak Ditemukan",
          message: "Shift tidak ditemukan",
          status: SnackBarStatus.error,
        );
        return;
      }

      if (salesInput != totalPenerimaan) {
        final confirmed = await showRemarksModal([], salesInput);
        if (!confirmed) return;
      }

      final confirm = await showConfirmModal(
        'Konfirmasi Akhiri Shift',
        'Apakah Anda yakin ingin mengakhiri shift ini?',
      );

      if (!confirm) return;

      final payload = buildPayload();

      await shiftService.endShift(shiftId!, payload);

      if (!mounted) return;

      SnackbarUtil.show(
        context,
        title: "Berhasil",
        message: "Shift berhasil diakhiri",
        status: SnackBarStatus.success,
      );

      _deleteIdShift();
      ApiClient().clearToken();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage(title: 'Login')),
        (route) => false,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      debugPrint('DioException: $e');
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'warning',
            title: 'Gagal mengakhiri shift',
            description:
                'Terjadi kendala saat mengakhiri shift. Silakan coba kembali.',
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 600.0,
        constraints: const BoxConstraints(maxWidth: 500),
        color: Colors.white,
        child: isLoading || isLoadingProfile
            ? SizedBox(
                height: 300,
                child: Center(
                  child: ModernLoading(
                    timeout: const Duration(seconds: 10),
                    onRetry: () {},
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Colors.amber,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Akhiri Shift',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pastikan semua transaksi hari ini sudah tercatat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Informasi dengan gaya yang lebih rapi
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          _buildInfoRow('Kasir', profile?['name'] ?? '-'),
                          const Divider(height: 24),
                          _buildInfoRow('Waktu', formatDateTime(date)),
                          const Divider(height: 24),
                          _buildInfoRow(
                            'Total Pendapatan System',
                            reportData != null
                                ? NumberFormat.currency(
                                    locale: 'id_ID',
                                    symbol: 'Rp ',
                                    decimalDigits: 0,
                                  ).format(totalPenerimaan)
                                : '-',
                            isBold: true,
                            valueColor: Colors.black87,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Input Pendapatan Aktual
                    TextField(
                      keyboardType: TextInputType.number,
                      controller: controllerSalesEnd,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        RupiahFormatter(),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Total Pendapatan (Rp)',
                        labelStyle: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade700,
                        ),
                        hintText: '0',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        filled: true,
                        fillColor: Colors.amber.shade50.withOpacity(0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16.0),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16.0),
                          borderSide: const BorderSide(
                            color: Colors.amber,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 32),

                    // Tombol Aksi
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Batal',
                              style: TextStyle(color: Colors.black87),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: controllerSalesEnd.text.isEmpty
                                ? null
                                : submitEndShift,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black87,
                              disabledBackgroundColor: Colors.grey.shade200,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Konfirmasi',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: 14,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildSelisihRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }
}
