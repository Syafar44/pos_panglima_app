import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/sift_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';
import 'package:intl/date_symbol_data_local.dart'; // tambahkan ini

class StartsiftModal extends StatefulWidget {
  const StartsiftModal({super.key});

  @override
  State<StartsiftModal> createState() => _StartsiftModalState();
}

class _StartsiftModalState extends State<StartsiftModal> {
  final apiClient = ApiClient();
  late final SiftService siftService;
  late final AuthService authService;
  Map<String, dynamic>? profile;
  int? customerId;
  bool isLoadingProfile = true;
  TextEditingController controllerSalesStart = TextEditingController();
  String date = DateTime.now().toString();
  String? selectedShift;
  final TextEditingController selectedShiftController = TextEditingController();

  int parseRupiah(String text) {
    return int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID', null);
    authService = AuthService(apiClient.dio);
    siftService = SiftService(apiClient.dio);
    getProfile();
  }

  Future<void> getProfile() async {
    try {
      final response = await authService.getProfile();

      debugPrint("PROFILE RESPONSE: ${response.data}");
      final data = response.data['data'];

      if (!mounted) return;
      setState(() {
        profile = data;
        customerId = (data['customer'] is List && data['customer'].isNotEmpty)
            ? int.parse(data['customer'][0].toString())
            : 0;
        isLoadingProfile = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      isLoadingProfile = false;
      debugPrint('error shift: ${e.response}');
    }
  }

  Map<String, dynamic> buildPayload() {
    return {
      "name": '$selectedShift - ${profile?['name']}',
      "shifts_label": selectedShift == "Shift Pagi"
          ? 1
          : selectedShift == "Shift Siang"
          ? 2
          : null,
      "outlet_hub_id": customerId,
      "users_id": profile?['userid'],
      "shift_start": DateTime.now().toString(),
      "sales_start": parseRupiah(controllerSalesStart.text),
    };
  }

  Future<void> submitShift() async {
    try {
      final salesStart = parseRupiah(controllerSalesStart.text);

      if (salesStart <= 0) {
        SnackbarUtil.show(
          context,
          title: "Input Tidak Valid",
          message: "Modal awal wajib diisi",
          status: SnackBarStatus.warning,
        );
        return;
      }

      final confirm = await showConfirmModal();

      if (!confirm) {
        return;
      }

      final payload = buildPayload();

      final response = await siftService.startShift(payload);
      final shiftId = response.data['data']['id'];

      await ShiftStorageService.saveShiftId(shiftId, salesStart);

      if (!mounted) return;

      SnackbarUtil.show(
        context,
        title: "Shift Dimulai",
        message: "Shift telah berhasil dimulai",
        status: SnackBarStatus.success,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => WidgetTree()),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'warning',
            title: 'Jadwal Shift Sudah diambil',
            description:
                'Jadwal shift yang Anda pilih sudah pernah diambil hari ini. Pilih shift lain atau hubungi supervisor.',
          );
        },
      );
    }
  }

  Color getShiftColor(String? shift) {
    if (shift == null) return Colors.grey;
    final s = shift.toLowerCase();
    if (s.contains('pagi'))
      return const Color.fromARGB(255, 96, 220, 255); // Maron untuk Pagi
    if (s.contains('siang') || s.contains('sore'))
      return const Color.fromARGB(
        255,
        255,
        132,
        0,
      ); // Orange/Amber gelap untuk Siang
    return Colors.blueGrey; // Warna default jika ada shift lain
  }

  Future<bool> showConfirmModal() async {
    final Color themeColor = getShiftColor(selectedShift);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) {
            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor:
                  Colors.white, // Menjaga dialog tetap putih bersih
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ikon Header dengan aksen Maron & Amber
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFF800000,
                        ).withOpacity(0.1), // Maron transparan
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons
                            .access_time_filled_rounded, // Ikon jam lebih cocok untuk shift
                        color: Color(0xFF800000), // Maron Utama
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Teks Judul
                    const Text(
                      "Konfirmasi Buka Shift",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF800000), // Judul menggunakan Maron
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Deskripsi dalam Container terpisah agar informasinya terfokus
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(
                          0.05,
                        ), // Background tipis sesuai warna shift
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: themeColor.withOpacity(0.3),
                          width: 2,
                        ), // Border lebih tebal agar terlihat
                      ),
                      child: Column(
                        children: [
                          Text(
                            "ANDA MEMILIH:",
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.bold,
                              color: themeColor.withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            selectedShift?.toUpperCase() ?? '-',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24, // Lebih besar agar sangat mencolok
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Divider(color: themeColor.withOpacity(0.2)),
                          const SizedBox(height: 12),

                          // Detail Waktu
                          _buildInfoRow(
                            Icons.calendar_today_rounded,
                            DateFormat(
                              'EEEE, dd MMM yyyy',
                              'id_ID',
                            ).format(DateTime.now()),
                          ),
                          const SizedBox(height: 8),
                          _buildInfoRow(
                            Icons.schedule_rounded,
                            'Pukul ${DateFormat('HH:mm').format(DateTime.now())} WIB',
                            20,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Footer Alert kecil
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.amber.shade900,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Pastikan shift sudah sesuai sebelum memulai.",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Baris Tombol
                    Row(
                      children: [
                        // Tombol Batal
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              'Batal',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Tombol Konfirmasi (Warna Amber khas POS Panglima)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black87,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Mulai Shift',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
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
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 450,
        ), // Ukuran ideal untuk modal input
        color: Colors.white,
        child: isLoadingProfile
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
                    // Header dengan Ikon Selamat Datang
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.wb_sunny_rounded,
                        color: Colors.blue.shade700,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Mulai Shift',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Silakan lengkapi data awal untuk memulai transaksi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Card Info Kasir
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          _buildSmallInfoRow(
                            'Nama Kasir',
                            profile?['name'] ?? '-',
                          ),
                          const SizedBox(height: 12),
                          _buildSmallInfoRow('Tanggal', formatDateTime(date)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Dropdown Pilih Shift
                    DropdownButtonFormField<String>(
                      value: selectedShift,
                      borderRadius: BorderRadius.circular(16),
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Pilih Shift',
                        prefixIcon: const Icon(Icons.access_time_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Shift Pagi',
                          child: Text('Shift Pagi'),
                        ),
                        DropdownMenuItem(
                          value: 'Shift Siang',
                          child: Text('Shift Siang'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => selectedShift = value),
                    ),
                    const SizedBox(height: 16),

                    // Input Modal Awal
                    TextField(
                      keyboardType: TextInputType.number,
                      controller: controllerSalesStart,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        RupiahFormatter(),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Modal Awal (Cash)',
                        prefixIcon: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        suffixIcon: const Icon(Icons.edit, size: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Colors.amber,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 32),

                    // Tombol Submit
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              (controllerSalesStart.text.isEmpty ||
                                  selectedShift == null)
                              ? Colors.grey.shade300
                              : Colors.amber,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed:
                            (controllerSalesStart.text.isEmpty ||
                                selectedShift == null)
                            ? null
                            : submitShift,
                        child: const Text(
                          'Buka Kasir Sekarang',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
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

  Widget _buildSmallInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, [double size = 14]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: size, color: Colors.black54),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: size - 1,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class RupiahFormatter extends TextInputFormatter {
  final formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  TextEditingValue formatEditUpdate(oldValue, newValue) {
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.isEmpty) return const TextEditingValue(text: '');

    final result = formatter.format(int.parse(text));
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
