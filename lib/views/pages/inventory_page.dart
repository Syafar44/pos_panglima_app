import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:number_pagination/number_pagination.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/services/inventory_service.dart';
import 'package:pos_panglima_app/services/stock_opname_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/notif_utils.dart';
import 'package:pos_panglima_app/utils/skeleton_loader.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pos_panglima_app/views/pages/reception_inventory_page.dart';
import 'package:pos_panglima_app/views/pages/stock_opname_page.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final apiClient = ApiClient();
  late final AuthService authService;
  late final InventoryService inventoryService;
  late final StockOpnameService stockOpnameService;
  String? customerId;
  String outletName = '';
  bool isLoadingCustomerId = true;
  bool isLoadingInventory = true;
  bool inventoryIsEmpty = false;
  List inventoryList = [];
  int unapprovedCount = 0;
  int selectedPageNumber = 1;
  Map<String, dynamic>? paginationInfo;

  List soList = [];
  bool isLoadingSO = false;
  bool soIsEmpty = false;
  int soPageNumber = 1;
  Map<String, dynamic>? soPaginationInfo;

  @override
  void initState() {
    super.initState();
    authService = AuthService(apiClient.dio);
    inventoryService = InventoryService(apiClient.dio);
    stockOpnameService = StockOpnameService(apiClient.dio);
    initializeDateFormatting('id_ID', null);
    getCustomerId();
  }

  Future<void> getCustomerId() async {
    try {
      final response = await authService.getProfile();
      final data = response.data['data'];
      final newCustomer =
          (data['customer'] is List && data['customer'].isNotEmpty)
          ? data['customer'][0]
          : null;
      await getInventoryTransfer(newCustomer);
      setState(() {
        customerId = newCustomer;
        outletName =
            data['outlet_hub_name']?.toString() ??
            data['outlet_name']?.toString() ??
            data['name']?.toString() ??
            '';
        isLoadingCustomerId = false;
      });
      if (isBackSO.value == false) {
        fetchListSO();
      }
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'inventory_page.getCustomerId');
      if (!mounted) return;
      setState(() {
        isLoadingCustomerId = false;
        isLoadingInventory = false;
        inventoryIsEmpty = true;
      });
      SnackbarUtil.show(
        context,
        title: "Gagal memuat data pengguna",
        message:
            "Terjadi kendala saat mengambil data pengguna. Mohon periksa koneksi atau coba kembali.",
        status: SnackBarStatus.error,
      );
    }
  }

  Future<void> fetchListSO() async {
    setState(() => isLoadingSO = true);
    try {
      final response = await stockOpnameService.getListSO(
        soPageNumber,
        10,
        int.tryParse(customerId?.toString() ?? '') ?? 0,
      );
      List list = [];
      Map<String, dynamic>? pagination;
      if (response.data['data'] is List) {
        list = response.data['data'];
        pagination = response.data['pagination'] ?? response.data['metadata'];
      } else if (response.data['data'] is Map) {
        list = response.data['data']['data'] ?? [];
        pagination =
            response.data['data']['pagination'] ??
            response.data['data']['metadata'];
      }
      setState(() {
        soList = list;
        isLoadingSO = false;
        soIsEmpty = list.isEmpty;
        soPaginationInfo = pagination;
        isBackSO.value == true;
      });
    } on DioException catch (e, stack) {
      if (e.response?.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          soList = [];
          isLoadingSO = false;
          soIsEmpty = true;
          soPaginationInfo = null;
        });
        return;
      }
      CrashReporter.report(e, stack, reason: 'inventory_page.fetchListSO');
      if (!mounted) return;
      setState(() {
        isLoadingSO = false;
        soIsEmpty = true;
      });
      SnackbarUtil.show(
        context,
        title: 'Gagal memuat Stock Opname',
        message: 'Terjadi kendala saat mengambil data stock opname.',
        status: SnackBarStatus.error,
      );
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'inventory_page.fetchListSO');
      if (!mounted) return;
      setState(() {
        isLoadingSO = false;
        soIsEmpty = true;
      });
      SnackbarUtil.show(
        context,
        title: 'Gagal memuat Stock Opname',
        message: 'Terjadi kendala saat mengambil data stock opname.',
        status: SnackBarStatus.error,
      );
    }
  }

  Future<void> getInventoryTransfer(customerId) async {
    try {
      final response = await inventoryService.getList(
        page: selectedPageNumber,
        limit: 10,
        outletHubId: customerId?.toString() ?? '',
      );

      List list = [];
      Map<String, dynamic>? pagination;

      if (response.data['data'] is List) {
        list = response.data['data'];
        pagination =
            response.data['pagination'] ??
            response.data['metadata'] ??
            response.data;
      } else if (response.data['data'] is Map) {
        list = response.data['data']['data'] ?? [];
        pagination =
            response.data['data']['pagination'] ??
            response.data['data']['metadata'] ??
            response.data['data'];
      } else {
        list = [];
      }

      final count = list.where((item) => (item['approve'] ?? 0) == 0).length;

      setState(() {
        inventoryList = list;
        isLoadingInventory = false;
        unapprovedCount = count;
        paginationInfo = pagination;
      });

      if (count > 0) {
        await saveInventoryReminder(count);
      } else {
        await clearInventoryReminder();
      }
    } on DioException catch (e, stack) {
      if (e.response?.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          inventoryList = [];
          isLoadingInventory = false;
          inventoryIsEmpty = true;
          unapprovedCount = 0;
          paginationInfo = null;
        });
        await clearInventoryReminder();
        return;
      }
      CrashReporter.report(
        e,
        stack,
        reason: 'inventory_page.getInventoryTransfer',
      );
      if (!mounted) return;
      setState(() {
        isLoadingInventory = false;
        inventoryIsEmpty = true;
      });
      SnackbarUtil.show(
        context,
        title: "Gagal memuat surat jalan",
        message: "Terjadi kendala saat mengambil data surat jalan.",
        status: SnackBarStatus.error,
      );
    } catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'inventory_page.getInventoryTransfer',
      );
      if (!mounted) return;
      setState(() {
        isLoadingInventory = false;
        inventoryIsEmpty = true;
      });
      SnackbarUtil.show(
        context,
        title: "Gagal memuat surat jalan",
        message: "Terjadi kendala saat mengambil data surat jalan.",
        status: SnackBarStatus.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                right: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // BAGIAN ATAS: DAFTAR MENU
                Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    spacing: 10.0,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMenuItem(
                        index: 1,
                        icon: Icons.all_inbox_rounded,
                        label: 'Surat Jalan',
                      ),
                      _buildMenuItem(
                        index: 2,
                        icon: Icons.drive_file_rename_outline_rounded,
                        label: 'Stock Opname',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 2,
          // child: numberPage == 1 ? suratJalan() : stockOpname(),
          child: ValueListenableBuilder<int>(
            valueListenable: selectedPageInventoryNotifier,
            builder: (context, value, child) {
              if (value == 1) {
                return suratJalan();
              } else if (value == 2) {
                return stockOpname();
              } else {
                return const SizedBox.shrink();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget suratJalan() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white, // Menggunakan putih agar lebih clean
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              left: const BorderSide(
                color: AppColors.primary,
                width: 5,
              ), // Aksen warna identitas POS
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Surat Jalan',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Inventory Transfer',
                    style: TextStyle(fontSize: 12.0, color: Colors.grey[500]),
                  ),
                ],
              ),
              if (unapprovedCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.pending_actions,
                        size: 16,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$unapprovedCount Menunggu',
                        style: const TextStyle(
                          fontSize: 13.0,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        inventoryIsEmpty
            ? Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 80,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Belum Ada Surat Jalan',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ],
                ),
              )
            : Expanded(
                child: isLoadingInventory || isLoadingCustomerId
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: SkeletonLoader.detailInventorySkeleton(
                          timeout: const Duration(seconds: 10),
                          onRetry: () {
                            setState(() => isLoadingInventory = true);
                            getInventoryTransfer(customerId);
                          },
                        ),
                      )
                    : ListView.builder(
                        // Menggunakan ListView.builder lebih efisien memori
                        padding: const EdgeInsets.all(16),
                        itemCount: inventoryList.length,
                        itemBuilder: (context, index) {
                          final inventory = inventoryList[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
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
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(15),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ReceptionInventoryPage(
                                            id: inventory['id'],
                                          ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Header Card: No. Dokumen & Status
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              inventory['document_number'] ??
                                                  '-',
                                              style: const TextStyle(
                                                fontSize: 18.0,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: inventory['approve'] == 1
                                                  ? Colors.green.shade50
                                                  : Colors.red.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              inventory['approve'] == 1
                                                  ? 'DITERIMA'
                                                  : 'BELUM DITERIMA',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: inventory['approve'] == 1
                                                    ? Colors.green
                                                    : Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 24),

                                      // Detail Section menggunakan Row yang lebih rapi
                                      _buildDetailRow(
                                        'Asal',
                                        inventory['from_outlet_hub_name'],
                                      ),
                                      const SizedBox(height: 8),
                                      _buildDetailRow(
                                        'Ke',
                                        inventory['to_outlet_hub_name'],
                                      ),
                                      const SizedBox(height: 8),
                                      _buildDetailRow(
                                        'Tanggal',
                                        formatDateTime(inventory['date']),
                                      ),

                                      const SizedBox(height: 16),
                                      const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Detail Transaksi',
                                            style: TextStyle(
                                              color: AppColors.primaryDarkest,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 16,
                                            color: AppColors.primaryDarkest,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
        Builder(
          builder: (context) {
            int totalPages = 1;
            if (paginationInfo != null) {
              if (paginationInfo!['total_page'] != null) {
                totalPages = (paginationInfo!['total_page'] as num).toInt();
              } else if (paginationInfo!['total_pages'] != null) {
                totalPages = (paginationInfo!['total_pages'] as num).toInt();
              } else if (paginationInfo!['last_page'] != null) {
                totalPages = (paginationInfo!['last_page'] as num).toInt();
              } else if (paginationInfo!['total'] != null) {
                int total = (paginationInfo!['total'] as num).toInt();
                int limit = (paginationInfo!['limit'] as num?)?.toInt() ?? 10;
                totalPages = (total / limit).ceil();
              }
            }

            if (totalPages <= 1) return const SizedBox.shrink();

            return Container(
              padding: const EdgeInsets.symmetric(
                vertical: 2.0,
                horizontal: 16.0,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: NumberPagination(
                onPageChanged: (int pageNumber) {
                  setState(() {
                    selectedPageNumber = pageNumber;
                    isLoadingInventory = true;
                  });
                  getInventoryTransfer(customerId);
                },
                visiblePagesCount: totalPages < 3 ? totalPages : 3,
                totalPages: totalPages,
                currentPage: selectedPageNumber.clamp(1, totalPages),
                buttonRadius: 12,
                selectedButtonColor: AppColors.primarySelected,
                selectedNumberColor: Colors.black,
                unSelectedButtonColor: Colors.grey[100]!,
                unSelectedNumberColor: Colors.grey[700]!,
                numberButtonSize: const Size(35, 35),
                controlButtonSize: const Size(35, 35),
                fontSize: 14,
                sectionSpacing: 5,
                navigationButtonSpacing: 0,
              ),
            );
          },
        ),
      ],
    );
  }

  void _showStockOpnameModal() {
    DateTime selectedDate = DateTime.now();
    final prefix =
        'Daily Stok Opname${outletName.isNotEmpty ? ' $outletName' : ''}';
    final keteranganCtrl = TextEditingController(text: prefix);
    final pageContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              setModalState(() => isSubmitting = true);
              try {
                final payload = {
                  'outlet_hub_id': int.tryParse(customerId?.toString() ?? ''),
                  'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                  'remarks': keteranganCtrl.text.trim(),
                };
                final response = await stockOpnameService.generateSO(payload);
                final newId = (response.data['data']['id'] as num).toInt();
                if (!dialogContext.mounted) return;
                SnackbarUtil.show(
                  pageContext,
                  title: 'Stock Opname Dibuat',
                  message: 'Draft stock opname berhasil disimpan.',
                  status: SnackBarStatus.success,
                );
                await Navigator.push(
                  pageContext,
                  MaterialPageRoute(builder: (_) => StockOpnamePage(id: newId)),
                );
              } catch (e, stack) {
                CrashReporter.report(
                  e,
                  stack,
                  reason: 'inventory_page.generateSO',
                );
                if (!context.mounted) return;
                SnackbarUtil.show(
                  context,
                  title: 'Gagal Membuat SO',
                  message:
                      'Terjadi kendala saat membuat stock opname. Coba kembali.',
                  status: SnackBarStatus.error,
                );
              } finally {
                if (context.mounted) setModalState(() => isSubmitting = false);
              }
            }

            final today = DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
            );
            final dateLabel = DateFormat(
              'dd MMM yyyy',
              'id_ID',
            ).format(selectedDate);

            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate.isBefore(today)
                    ? today
                    : selectedDate,
                firstDate: today,
                lastDate: today.add(const Duration(days: 365)),
                helpText: 'Pilih Tanggal Stock Opname',
                builder: (context, child) => Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: AppColors.primary,
                      onPrimary: Colors.white,
                      onSurface: Color(0xFF2D3436),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) setModalState(() => selectedDate = picked);
            }

            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.drive_file_rename_outline_rounded,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Buat Stock Opname',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                            visualDensity: VisualDensity.compact,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pencatatan fisik stock barang harian',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const Divider(height: 28),
                      const Text(
                        'Tanggal Stock Opname',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: pickDate,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
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
                              const Spacer(),
                              Icon(
                                Icons.arrow_drop_down_rounded,
                                color: Colors.grey[600],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tidak dapat memilih tanggal sebelum hari ini.',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Keterangan',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: keteranganCtrl,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Tambahkan keterangan (opsional)',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
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
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: isSubmitting ? null : submit,
                              icon: isSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.save_outlined,
                                      color: AppColors.primary,
                                      size: 18,
                                    ),
                              label: Text(
                                isSubmitting ? 'Membuat...' : 'Buat Draft',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
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
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(keteranganCtrl.dispose);
  }

  Widget stockOpname() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white, // Menggunakan putih agar lebih clean
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              left: const BorderSide(
                color: AppColors.primary,
                width: 5,
              ), // Aksen warna identitas POS
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Stcok Opname',
                    style: TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Daftar Stock Opname',
                    style: TextStyle(fontSize: 12.0, color: Colors.grey[500]),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: _showStockOpnameModal,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: AppColors.primary,
                  side: const BorderSide(
                    color: AppColors.primaryDark,
                    width: 1.5,
                  ), // Garis pinggir lebih tegas
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      12,
                    ), // Sudut yang lebih lembut
                  ),
                ),
                child: const Text('Post Stock Opname +'),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoadingSO || isLoadingCustomerId
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: SkeletonLoader.detailInventorySkeleton(
                    timeout: const Duration(seconds: 10),
                    onRetry: fetchListSO,
                  ),
                )
              : soIsEmpty || soList.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.drive_file_rename_outline_rounded,
                      size: 80,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Belum Ada Stock Opname',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: soList.length,
                  itemBuilder: (context, index) {
                    final so = soList[index];
                    final rawStatus = (so['status'] ?? 'draft').toString();
                    final status = rawStatus.toUpperCase();
                    final isDraft = status == 'DRAFT';
                    final dateStr = so['date']?.toString() ?? '';
                    final dateFormatted = dateStr.isNotEmpty
                        ? DateFormat(
                            'dd MMM yyyy',
                            'id_ID',
                          ).format(DateTime.tryParse(dateStr) ?? DateTime.now())
                        : '-';
                    final totalItems = so['total_items'] ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
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
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StockOpnamePage(
                                  id: (so['id'] as num).toInt(),
                                ),
                              ),
                            );
                            if (mounted) fetchListSO();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        so['document_number']?.toString() ??
                                            '-',
                                        style: const TextStyle(
                                          fontSize: 16.0,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
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
                                        rawStatus,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: isDraft
                                              ? Colors.blueGrey
                                              : Colors.green,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                Row(
                                  // Menambahkan alignment agar konten rata tengah secara vertikal
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // --- BUNGKUS COLUMN DENGAN EXPANDED ---
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment
                                            .start, // Pastikan teks rata kiri
                                        children: [
                                          _buildDetailRow(
                                            'Tanggal',
                                            dateFormatted,
                                          ),
                                          const SizedBox(height: 6),
                                          _buildDetailRow(
                                            'Outlet',
                                            so['outlet_hub_name']?.toString() ??
                                                '-',
                                          ),
                                        ],
                                      ),
                                    ),
                                    // --------------------------------------

                                    // Memberikan jarak antara Column detail dan Stat Chip
                                    const SizedBox(width: 12),

                                    _buildStatChip(
                                      'Items',
                                      totalItems.toString(),
                                      Colors.blue,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Lihat Detail',
                                      style: TextStyle(
                                        color: AppColors.primaryDarkest,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 16,
                                      color: AppColors.primaryDarkest,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Builder(
          builder: (context) {
            int totalPages = 1;
            if (soPaginationInfo != null) {
              if (soPaginationInfo!['total_page'] != null) {
                totalPages = (soPaginationInfo!['total_page'] as num).toInt();
              } else if (soPaginationInfo!['total_pages'] != null) {
                totalPages = (soPaginationInfo!['total_pages'] as num).toInt();
              } else if (soPaginationInfo!['last_page'] != null) {
                totalPages = (soPaginationInfo!['last_page'] as num).toInt();
              } else if (soPaginationInfo!['total'] != null) {
                int total = (soPaginationInfo!['total'] as num).toInt();
                int limit = (soPaginationInfo!['limit'] as num?)?.toInt() ?? 10;
                totalPages = (total / limit).ceil();
              }
            }
            if (totalPages <= 1) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(
                vertical: 2.0,
                horizontal: 16.0,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: NumberPagination(
                onPageChanged: (int pageNumber) {
                  setState(() {
                    soPageNumber = pageNumber;
                    isLoadingSO = true;
                  });
                  fetchListSO();
                },
                visiblePagesCount: totalPages < 3 ? totalPages : 3,
                totalPages: totalPages,
                currentPage: soPageNumber.clamp(1, totalPages),
                buttonRadius: 12,
                selectedButtonColor: AppColors.primarySelected,
                selectedNumberColor: Colors.black,
                unSelectedButtonColor: Colors.grey[100]!,
                unSelectedNumberColor: Colors.grey[700]!,
                numberButtonSize: const Size(35, 35),
                controlButtonSize: const Size(35, 35),
                fontSize: 14,
                sectionSpacing: 5,
                navigationButtonSpacing: 0,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    bool isActive = selectedPageInventoryNotifier.value == index;

    return Material(
      color: isActive ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          setState(() => selectedPageInventoryNotifier.value = index);
          if (index == 2 &&
              soList.isEmpty &&
              !isLoadingSO &&
              !isLoadingCustomerId) {
            fetchListSO();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              width: 2,
              color: isActive ? AppColors.primaryDark : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24.0,
                color: isActive ? Colors.white : Colors.grey[500],
              ),
              const SizedBox(width: 16.0),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15.0,
                  color: isActive ? AppColors.white : Colors.grey[700],
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              if (isActive) const Spacer(),
              if (isActive)
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.primaryDarker,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ),
        const Text(': ', style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
