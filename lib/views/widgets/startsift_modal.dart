import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/sift_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

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
      isLoadingProfile = false;
      print('error shift ini ================= ${e.response}');
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Modal awal wajib diisi")));
        return;
      }

      final payload = buildPayload();

      final response = await siftService.startShift(payload);
      final shiftId = response.data['data']['id'];
      await ShiftStorageService.saveShiftId(shiftId);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Shift berhasil dimulai")));

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => WidgetTree()),
      );
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.all(16),
      child: Container(
        padding: EdgeInsets.all(32),
        width: 800.0,
        height: 400,
        child: SingleChildScrollView(
          child: isLoadingProfile
              ? Center(child: CircularProgressIndicator())
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Mulai Shift',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 30,
                      ),
                    ),
                    SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Kasir :',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(' ${profile?['name']}'),
                              ],
                            ),
                            // Row(
                            //   children: [
                            //     Text(
                            //       'Outlet :',
                            //       style: TextStyle(fontWeight: FontWeight.bold),
                            //     ),
                            //     Text(' Jaunda 1'),
                            //   ],
                            // ),
                            Row(
                              children: [
                                Text(
                                  'Tanggal :',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(' ${formatDateTime(date)}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    SizedBox(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedShift,
                        borderRadius: BorderRadius.circular(12),
                        decoration: InputDecoration(
                          hintText: 'Pilih Shift',
                          filled: true,
                          fillColor: Colors.transparent,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
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
                        onChanged: (value) {
                          setState(() {
                            selectedShift = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      keyboardType: TextInputType.number,
                      controller: controllerSalesStart,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        RupiahFormatter(),
                      ],
                      decoration: InputDecoration(
                        label: Text(
                          'Modal Awal (Rp)',
                          style: TextStyle(fontSize: 20, color: Colors.black),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15.0),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: controllerSalesStart.text.isEmpty
                              ? Colors.grey
                              : Colors.amber,
                          padding: EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: controllerSalesStart.text.isEmpty
                            ? null
                            : submitShift,
                        // onPressed: () {
                        //   Navigator.pushReplacement(
                        //     context,
                        //     MaterialPageRoute(builder: (_) => WidgetTree()),
                        //   );
                        // },
                        child: Text(
                          'Mulai Shift',
                          style: TextStyle(color: Colors.black),
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
