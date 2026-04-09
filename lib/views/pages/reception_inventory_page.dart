import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/inventory_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';
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

  @override
  void initState() {
    super.initState();
    inventoryService = InventoryService(apiClient.dio);
    authService = AuthService(apiClient.dio);
    getInventoryTransferDetail();
    getProfile();
  }

  Future<void> getInventoryTransferDetail() async {
    try {
      final response = await inventoryService.getDetail(widget.id);

      setState(() {
        inventoryDetail = response.data['data'];
      });

      debugPrint(inventoryDetail.toString());

      final lines = response.data['data']['inventory_transfer_lines'];

      for (final line in lines) {
        final lineId = line['id'];

        if (inventoryDetail?['approve'] == 1) {
          realisasiControllers[lineId] = TextEditingController(
            text: line['realisasi'].toString(),
          );
        } else {
          realisasiControllers[lineId] = TextEditingController(
            text: line['quantity'].toString(),
          );
        }

        remarksControllers[lineId] =
            remarksControllers[lineId] ?? TextEditingController();
      }

      setState(() => isLoading = false);
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'warning',
            title: 'Gagal memuat data inventory',
            description:
                'Terjadi kendala saat mengambil data inventory. Mohon periksa koneksi atau coba kembali.',
          );
        },
      );
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
    } catch (e) {
      if (!mounted) return;
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
        final double realisasi = double.tryParse(realisasiControllers[line['id']]?.text ?? '0') ?? 0.0;

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
        final proceed = await showRemarksModal(
          mismatchItems,
          int.tryParse(
                realisasiControllers[mismatchItems.first['id']]?.text ?? '0',
              ) ??
              0,
        );
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

      selectedPageNotifier.value = 3;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => WidgetTree()),
        (route) => false,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      debugPrint("DioException: ${e.response?.data ?? e.message}");
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'danger',
            title: 'Gagal melakukan Realisasi',
            description:
                'Terjadi kendala saat melakukan Realisasi. Silakan coba kembali.',
          );
        },
      );
    }
  }

  List<Map<String, dynamic>> getMismatchItems() {
    final List<dynamic> lines =
        inventoryDetail?['inventory_transfer_lines'] ?? [];

    return lines
        .where((line) {
          final double qty = (line['quantity'] ?? 0).toDouble();
          final double realisasi = double.tryParse(realisasiControllers[line['id']]?.text ?? '0') ?? 0;
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
    int realisasiQty,
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
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: items.map((item) {
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
                              "Selisih: ${item['quantity'] - realisasiQty} ${item['uoms_code']}",
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
                                hintText:
                                    "Contoh: Barang rusak di perjalanan...",
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
                    }).toList(),
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
                SizedBox(
                  child: ElevatedButton(
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

      debugPrint("Validasi $itemName: realisasi=$realisasi, qtyKirim=$qtyKirim");

      if (realisasi > qtyKirim) {
        // 1. Berikan feedback getaran atau warna jika memungkinkan (Opsional)

        // 2. Tampilkan SnackBar dengan gaya yang lebih "Alert"
        ScaffoldMessenger.of(
          context,
        ).hideCurrentSnackBar(); // Hapus snackbar sebelumnya agar tidak antre
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
  Widget build(BuildContext context) {
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(16), // Sedikit melengkung di sudut bawah
          ),
        ),
      ),
      body: isLoading || isLoadingProfile
          ? Center(child: ModernLoading(
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
                  // Row(
                  //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  //   children: [
                  //     Column(
                  //       crossAxisAlignment: CrossAxisAlignment.start,
                  //       children: [
                  //         Row(
                  //           spacing: 10.0,
                  //           children: [
                  //             const Text(
                  //               'No. Po / No. SJ',
                  //               style: TextStyle(fontWeight: FontWeight.bold),
                  //             ),
                  //             Text(
                  //               ':  ${inventoryDetail?['document_number'] ?? '-'}',
                  //             ),
                  //           ],
                  //         ),
                  //         Row(
                  //           spacing: 55.5,
                  //           children: [
                  //             Text(
                  //               'Supplier',
                  //               style: TextStyle(fontWeight: FontWeight.bold),
                  //             ),
                  //             Text(
                  //               ':  ${inventoryDetail?['from_outlet_hub_name'] ?? '-'}',
                  //             ),
                  //           ],
                  //         ),
                  //         Row(
                  //           spacing: 39.4,
                  //           children: [
                  //             Text(
                  //               'Ke Gudang',
                  //               style: TextStyle(fontWeight: FontWeight.bold),
                  //             ),
                  //             Text(
                  //               ':  ${inventoryDetail?['to_outlet_hub_name'] ?? '-'}',
                  //             ),
                  //           ],
                  //         ),
                  //       ],
                  //     ),
                  //     Column(
                  //       crossAxisAlignment: CrossAxisAlignment.start,
                  //       children: [
                  //         Row(
                  //           spacing: 63.0,
                  //           children: [
                  //             Text(
                  //               'Tanggal',
                  //               style: TextStyle(fontWeight: FontWeight.bold),
                  //             ),
                  //             Text(
                  //               ':  ${formatDateTime(inventoryDetail?['date'] ?? '-')}',
                  //             ),
                  //           ],
                  //         ),
                  //         Row(
                  //           spacing: 26.0,
                  //           children: [
                  //             Text(
                  //               'Diterima Oleh',
                  //               style: TextStyle(fontWeight: FontWeight.bold),
                  //             ),
                  //             Text(':  ${profile?['name'] ?? '-'}'),
                  //           ],
                  //         ),
                  //       ],
                  //     ),
                  //   ],
                  // ),
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
                                if (inventoryDetail?['approve'] == 1)
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

                                      // Kolom Input Realisasi
                                      // Expanded(
                                      //   flex: 2,
                                      //   child: SizedBox(
                                      //     height: 45,
                                      //     child: TextField(
                                      //       controller:
                                      //           realisasiControllers[item['id']],
                                      //       keyboardType: TextInputType.number,
                                      //       textAlign: TextAlign.center,
                                      //       enabled:
                                      //           inventoryDetail?['approve'] !=
                                      //           1,
                                      //       onTap: () {
                                      //         setState(() {
                                      //           focusedItemId = item['id'];
                                      //         });
                                      //       },
                                      //       onEditingComplete: () {
                                      //         setState(() {
                                      //           focusedItemId = null;
                                      //         });
                                      //         FocusScope.of(context).unfocus();
                                      //       },
                                      //       onTapOutside: (_) {
                                      //         setState(() {
                                      //           focusedItemId = null;
                                      //         });
                                      //       },
                                      //       style: TextStyle(
                                      //         fontWeight: FontWeight.bold,
                                      //         color: item['reject'] > 0
                                      //             ? Colors.orange
                                      //             : Colors.blue,
                                      //       ),
                                      //       decoration: InputDecoration(
                                      //         contentPadding:
                                      //             const EdgeInsets.symmetric(
                                      //               vertical: 0,
                                      //             ),
                                      //         hintText: '0',
                                      //         filled: true,
                                      //         fillColor: item['reject'] > 0
                                      //             ? Colors.orange.shade50
                                      //             : Colors.blue.shade50,
                                      //         enabledBorder: OutlineInputBorder(
                                      //           borderSide: BorderSide(
                                      //             color: item['reject'] > 0
                                      //                 ? Colors.orange.shade100
                                      //                 : Colors.blue.shade100,
                                      //           ),
                                      //           borderRadius:
                                      //               BorderRadius.circular(8),
                                      //         ),
                                      //         focusedBorder: OutlineInputBorder(
                                      //           borderSide: BorderSide(
                                      //             color: item['reject'] > 0
                                      //                 ? Colors.orange
                                      //                 : Colors.blue,
                                      //             width: 2,
                                      //           ),
                                      //           borderRadius:
                                      //               BorderRadius.circular(8),
                                      //         ),
                                      //       ),
                                      //     ),
                                      //   ),
                                      // ),
                                      Expanded(
                                        flex: 2,
                                        child: ValueListenableBuilder<TextEditingValue>(
                                          valueListenable:
                                              realisasiControllers[item['id']]!,
                                          builder: (context, value, _) {
                                            final qty = (item['quantity'] ?? 0)
                                                .toDouble();
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

                                            return Container(
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
                                                              .withOpacity(0.3),
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
                                      if (inventoryDetail?['approve'] == 1)
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
                  SizedBox(height: 10),
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
                          width: double
                              .infinity, // Tombol full width agar lebih mudah ditekan jari
                          height: 48,
                          child: ElevatedButton(
                            onPressed: submitRealisasi,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black87,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
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
