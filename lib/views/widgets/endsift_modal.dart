import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/sift_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_error.dart';
import 'package:pos_panglima_app/views/widgets_tree.dart';

class EndsiftModal extends StatefulWidget {
  const EndsiftModal({super.key});

  @override
  State<EndsiftModal> createState() => _EndsiftModalState();
}

class _EndsiftModalState extends State<EndsiftModal> {
  final apiClient = ApiClient();
  late final SiftService siftService;
  late final AuthService authService;
  Map<String, dynamic>? profile;
  bool isLoadingProfile = true;
  TextEditingController controllerSalesEnd = TextEditingController();
  String date = DateTime.now().toString();
  int? shiftId;
  late bool isLoading = true;

  @override
  void initState() {
    super.initState();
    authService = AuthService(apiClient.dio);
    siftService = SiftService(apiClient.dio);

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
      isLoadingProfile = false;
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
        },
      );
    }
  }

  Future<void> _loadShiftId() async {
    final result = await ShiftStorageService.getShiftId();
    setState(() {
      shiftId = result;
      isLoading = false;
    });
  }

  Future<void> _deleteIdShift() async {
    await ShiftStorageService.clearShift();
  }

  int parseRupiah(String text) {
    return int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  Map<String, dynamic> buildPayload() {
    return {
      "id": shiftId,
      "shift_end": DateTime.now().toString(),
      "sales_end": parseRupiah(controllerSalesEnd.text),
    };
  }

  Future<void> submitShift() async {
    try {
      final salesStart = parseRupiah(controllerSalesEnd.text);

      if (salesStart <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Total Pendapatan wajib diisi")),
        );
        return;
      }

      if (shiftId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Shift ID tidak ditemukan")),
        );
        return;
      }

      final payload = buildPayload();

      await siftService.endShift(shiftId!, payload);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Shift berhasil di akhiri")));

      _deleteIdShift();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => WidgetTree()),
      );
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.all(32),
          width: 800.0,
          height: 450,
          child: isLoading || isLoadingProfile
              ? Center(child: CircularProgressIndicator())
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Akhiri Shift',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 30,
                      ),
                    ),
                    SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Informasi :',
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
                            Row(
                              children: [
                                Text(
                                  'Total Penjualan :',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(' Rp 1.500.000'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      keyboardType: TextInputType.number,
                      controller: controllerSalesEnd,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        RupiahFormatter(),
                      ],
                      decoration: InputDecoration(
                        label: Text(
                          'Total Pendapatan (Rp)',
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
                          backgroundColor: controllerSalesEnd.text.isEmpty
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
                        onPressed: controllerSalesEnd.text.isEmpty
                            ? null
                            : submitShift,
                        child: Text(
                          'Akhiri Shift',
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
