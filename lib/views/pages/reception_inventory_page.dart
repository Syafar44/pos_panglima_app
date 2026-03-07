import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/inventory_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_error.dart';
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

      final lines = response.data['data']['inventory_transfer_lines'];

      for (final line in lines) {
        final lineId = line['id'];

        realisasiControllers[lineId] = TextEditingController(
          text: line['quantity'].toString(),
        );
        remarksControllers[lineId] =
            remarksControllers[lineId] ?? TextEditingController();
      }

      setState(() => isLoading = false);
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
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
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
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
        final qty = line['quantity'];
        final realisasi =
            int.tryParse(realisasiControllers[line['id']]?.text ?? '0') ?? 0;

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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Penerimaan berhasil disimpan")),
      );

      selectedPageNotifier.value = 5;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => WidgetTree()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
        },
      );
    }
  }

  List<Map<String, dynamic>> getMismatchItems() {
    final List<dynamic> lines =
        inventoryDetail?['inventory_transfer_lines'] ?? [];

    return lines
        .where((line) {
          final int qty = line['quantity'];
          final int realisasi =
              int.tryParse(realisasiControllers[line['id']]?.text ?? '0') ?? 0;
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

  Future<bool> showRemarksModal(List<Map<String, dynamic>> items) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Column(
                spacing: 10.0,
                children: [
                  Text(
                    "Keterangan Selisih Barang",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Berikan penjelasan atau catatan terkait selisih barang yang terjadi (contoh: kerusakan, hilang, pencatatan salah, dll).",
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 600.0,
                  child: Column(
                    children: items.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: remarksControllers[item['id']],
                          onChanged: (value) {
                            setState(() {}); // Memastikan state diperbarui
                          },
                          decoration: InputDecoration(
                            labelText:
                                "${item['item_name']} (Qty ${item['quantity']})",
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text("Batal", style: TextStyle(color: Colors.black)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.0),
                    ),
                  ),
                  onPressed: () {
                    bool allValid = true;

                    for (final item in items) {
                      final controller = remarksControllers[item['id']];
                      if (controller == null ||
                          controller.text.trim().isEmpty) {
                        allValid = false;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Semua remarks wajib diisi")),
                        );
                        break;
                      }
                    }

                    if (allValid) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: Text(
                    "Lanjutkan",
                    style: TextStyle(color: Colors.black),
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
      final qty = line['quantity'];
      final realisasi =
          int.tryParse(realisasiControllers[line['id']]?.text ?? '0') ?? 0;
      if (realisasi > qty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Realisasi ${line['item_name']} melebihi quantity"),
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
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'Penerimaan Surat Jalan',
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: isLoading || isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            spacing: 10.0,
                            children: [
                              const Text(
                                'No. Po / No. SJ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                ':  ${inventoryDetail?['document_number'] ?? '-'}',
                              ),
                            ],
                          ),
                          Row(
                            spacing: 55.5,
                            children: [
                              Text(
                                'Supplier',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                ':  ${inventoryDetail?['from_outlet_hub_name'] ?? '-'}',
                              ),
                            ],
                          ),
                          Row(
                            spacing: 39.4,
                            children: [
                              Text(
                                'Ke Gudang',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                ':  ${inventoryDetail?['to_outlet_hub_name'] ?? '-'}',
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            spacing: 63.0,
                            children: [
                              Text(
                                'Tanggal',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                ':  ${formatDateTime(inventoryDetail?['date'] ?? '-')}',
                              ),
                            ],
                          ),
                          Row(
                            spacing: 26.0,
                            children: [
                              Text(
                                'Diterima Oleh',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(':  ${profile?['name'] ?? '-'}'),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Card(
                      color: Colors.white,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: const BoxDecoration(
                              color: Colors.black12,
                              border: Border(
                                bottom: BorderSide(color: Colors.black26),
                              ),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  flex: 2,
                                  child: Center(
                                    child: Text(
                                      "KODE BARANG",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  flex: 3,
                                  child: Center(
                                    child: Text(
                                      "NAMA BARANG",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      "QTY",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Text(
                                      "SATUAN",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
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
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount:
                                  inventoryDetail?['inventory_transfer_lines']
                                      .length,
                              itemBuilder: (context, index) {
                                final item =
                                    inventoryDetail?['inventory_transfer_lines'][index];
                                return Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Center(
                                          child: Text(item["item_code"]),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 8,
                                          ),
                                          child: Text(item["item_name"]),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Text("${item['quantity']}"),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: Text(item["uoms_code"]),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller:
                                              realisasiControllers[item['id']],
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          decoration: const InputDecoration(
                                            hintText: '0',
                                            isDense: true,
                                            border: OutlineInputBorder(),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '* Perhatian',
                                style: TextStyle(
                                  fontSize: 16.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                              Text(
                                'Harap perhatikan kembali barang yang diterima sebelum menekan tombol “Terima”.Pastikan jumlah, satuan, dan kualitas barang telah sesuai dengan pesanan serta dalam kondisi baik.',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: submitRealisasi,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.amber,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            fixedSize: Size(150, 50),
                          ),
                          child: Text(
                            'Terima',
                            style: TextStyle(
                              fontSize: 18.0,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
