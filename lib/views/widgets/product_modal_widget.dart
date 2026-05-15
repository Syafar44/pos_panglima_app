import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/modal_insufficient_stock.dart';
import 'package:pos_panglima_app/utils/quantity_timer_mixin.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/utils/stock_parser.dart';
import 'package:pos_panglima_app/views/components/ui/step_button.dart';

class ProductModalWidget extends StatefulWidget {
  const ProductModalWidget({
    super.key,
    required this.title,
    required this.category,
    required this.price,
    required this.codeProduct,
    required this.id,
    required this.collection,
    this.props,
    this.maxProduk,
    required this.onSaved,
    required this.dialogContext,
    this.imageUrl,
  });

  final String title;
  final String category;
  final String codeProduct;
  final int id;
  final int price;
  final bool collection;
  final List? props;
  final int? maxProduk;
  final dynamic onSaved;
  final dynamic dialogContext;
  final String? imageUrl;

  @override
  State<ProductModalWidget> createState() => _ProductModalWidgetState();
}

class _ProductModalWidgetState extends State<ProductModalWidget>
    with QuantityTimerMixin {
  final apiClient = ApiClient();
  late final CartService cartService;
  int quantity = 1;
  final TextEditingController diskonController = TextEditingController();
  bool selectedUnit = false;
  bool? hasShift;
  bool isSubmitting = false;

  void _decreaseQuantity() {
    if (quantity > 1) {
      setState(() {
        quantity--;
        final newMax = (widget.maxProduk ?? 0) * quantity;
        if (totalSelectedProps > newMax) selectedProps.clear();
      });
    }
  }

  void _increaseQuantity() {
    setState(() => quantity++);
  }

  Map<int, int> selectedProps = {};

  int get totalSelectedProps {
    int sum = 0;
    selectedProps.forEach((key, val) => sum += val);
    return sum;
  }

  void onTapVariant(Map<String, dynamic> item) {
    final maxTotal = (widget.maxProduk ?? 0) * quantity;
    final id = (item["id"]);

    if (totalSelectedProps >= maxTotal) return;

    setState(() {
      selectedProps[id] = (selectedProps[id] ?? 0) + 1;
    });
  }

  void resetVariants() {
    setState(() {
      selectedProps.clear();
    });
  }

  late List<Map<String, dynamic>> mergedProps;

  @override
  void initState() {
    super.initState();
    cartService = CartService(apiClient.dio);
    _loadShiftStatus();
  }

  void savedToCart() async {
    if (isSubmitting) return;
    setState(() => isSubmitting = true);

    final props = widget.props ?? [];

    final mergedProps = props.map<Map<String, dynamic>>((item) {
      final id = item['id'];
      final qty = selectedProps[id] ?? 0;

      return {"pos_menus_id": id, "quantity": qty};
    }).toList();

    late int discount = diskonController.text.isEmpty
        ? 0
        : int.parse(diskonController.text).toInt();

    final int subtotal = widget.price * quantity;
    final int tax = 0;

    final int totalDiscount = selectedUnit
        ? subtotal * discount ~/ 100
        : discount;

    Map<String, dynamic> payload = {
      "pos_menus_id": widget.id,
      "quantity": quantity,
      "price": widget.price,
      "subtotal": subtotal,
      "tax": tax,
      "is_percentage": selectedUnit ? 1 : 0,
      "discount": selectedUnit ? 0 : discount,
      "discount_val": selectedUnit ? discount : 0,
      "total": subtotal - totalDiscount + tax,
      "max_qty": widget.maxProduk,
      "pos_cart_props": mergedProps,
    };

    try {
      await cartService.postCart(payload);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
    } on DioException catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'product_modal_widget.addToCart',
        context: {
          'endpoint': e.requestOptions.path,
          'statusCode': e.response?.statusCode,
          'responseData': e.response?.data?.toString(),
        },
      );
      if (!mounted) return;
      final String message = e.response?.data['message'] ?? 'Terjadi kesalahan';

      if (message.contains('insufficient_stock')) {
        final parsedItems = parseInsufficientStock(message);
        showDialog(
          context: context,
          builder: (_) => ModalInsufficientStock(items: parsedItems),
        );
      }
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> _loadShiftStatus() async {
    final result = await ShiftStorageService.hasActiveShift();
    if (!mounted) return;
    setState(() {
      hasShift = result;
    });
  }

  void _showWarningShift() {
    SnackbarUtil.show(
      context,
      title: "Mulai Shift terlebih dahulu",
      message:
          "Shift belum dimulai. Mulai shift terlebih dahulu untuk melakukan transaksi.",
      status: SnackBarStatus.warning,
    );
  }

  @override
  void dispose() {
    disposeTimer();
    diskonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(20.0)),
          ),
          width: 800.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16.0,
                  horizontal: 20.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 1.5),
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: 0.3,
                      ), // Diperhalus dari 0.5 ke 0.05 agar lebih modern
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Sisi Kiri: Tombol Close + Info Produk
                    Expanded(
                      child: Row(
                        children: [
                          // TOMBOL X MODERN
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Info Produk
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  widget.category,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Sisi Kanan: Harga & Tombol Simpan
                    Row(
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Subtotal',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              convertIDR(widget.price * quantity),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        _buildSaveButton(),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Bagian Visual/Thumbnail Produk
                        Container(
                          width: 140,
                          height: 110,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                secondColor(
                                  widget.title,
                                ).withValues(alpha: 0.8),
                                baseColor(widget.title),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: baseColor(
                                  widget.title,
                                ).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child:
                                (widget.imageUrl != null &&
                                    widget.imageUrl!.isNotEmpty)
                                ? CachedNetworkImage(
                                    imageUrl: widget.imageUrl!,
                                    width: 240,
                                    height: 210,
                                    fit: BoxFit.cover,
                                    maxWidthDiskCache: 280,
                                    maxHeightDiskCache: 220,
                                    memCacheWidth: 240,
                                    memCacheHeight: 210,
                                    errorWidget: (context, url, error) => Text(
                                      getInitials(widget.title),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 48,
                                        color: Colors.white,
                                      ),
                                    ),
                                    placeholder: (context, url) => const Center(
                                      child: SizedBox.square(
                                        dimension: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  )
                                : Text(
                                    getInitials(widget.title),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 48,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                convertIDR(widget.price),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 26,
                                  letterSpacing: -0.5,
                                  color: AppColors.black87,
                                ),
                              ),
                              Text(
                                'Atur Kuantitas',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 15),

                              // Custom Stepper Row
                              Row(
                                children: [
                                  StepButton(
                                    icon: Icons.remove,
                                    color: Colors.grey[200]!,
                                    onTap: () {
                                      if (quantity > 1) {
                                        setState(() => quantity--);
                                      }
                                    },
                                    onLongPressStart: () =>
                                        startTimer(_decreaseQuantity),
                                    onLongPressEnd: stopTimer,
                                  ),
                                  Container(
                                    width: 60,
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$quantity',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  StepButton(
                                    icon: Icons.add,
                                    iconColor: AppColors.white,
                                    color: AppColors.primary,
                                    onTap: () => setState(() => quantity++),
                                    onLongPressStart: () =>
                                        startTimer(_increaseQuantity),
                                    onLongPressEnd: stopTimer,
                                  ),
                                  const SizedBox(width: 12),
                                  // Badge Satuan
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppColors.primaryAccent,
                                      ),
                                    ),
                                    child: const Text(
                                      'PCS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (widget.maxProduk != null &&
                        widget.maxProduk! > 0 &&
                        widget.props != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),
                          // Header Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              RichText(
                                text: TextSpan(
                                  text: "Pilih Varian ",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                  children: [
                                    TextSpan(
                                      text:
                                          "( $totalSelectedProps / ${(widget.maxProduk ?? 0) * quantity} )",
                                      style: TextStyle(
                                        color:
                                            totalSelectedProps ==
                                                (widget.maxProduk! * quantity)
                                            ? Colors.green.shade700
                                            : Colors.red,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: resetVariants,
                                icon: const Icon(
                                  Icons.refresh,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                label: const Text(
                                  "Reset",
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Chips Wrap
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: widget.props!.map((e) {
                              final id = e["id"];
                              final int propsQuantity = selectedProps[id] ?? 0;
                              final bool isSelected = propsQuantity > 0;

                              // Kondisi disable: sudah mencapai batas MAKSIMAL
                              final bool isDisabled =
                                  totalSelectedProps >=
                                  (widget.maxProduk ?? 0) * quantity;

                              return GestureDetector(
                                onTap: isDisabled
                                    ? null
                                    : () => onTapVariant(e),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    // Warna background berubah berdasarkan status
                                    color: isSelected
                                        ? AppColors.primary
                                        : (isDisabled
                                              ? Colors.grey.shade100
                                              : Colors.white),
                                    borderRadius: BorderRadius.circular(
                                      12,
                                    ), // Menggunakan Rounded tipis agar lebih modern
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primaryDark
                                          : (isDisabled
                                                ? Colors.grey.shade300
                                                : AppColors.primaryAccent),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        e["title"],
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : (isDisabled
                                                    ? Colors.grey.shade400
                                                    : AppColors.black87),
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                        ),
                                      ),
                                      if (isSelected) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            propsQuantity.toString(),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primaryDark,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 40, thickness: 1),
                        const Text(
                          'Berikan Diskon',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Input Field
                            Expanded(
                              child: TextField(
                                controller: diskonController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  prefixText: selectedUnit ? null : 'Rp ',
                                  suffixText: selectedUnit ? '%' : null,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: AppColors.primary,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                onChanged: (value) {
                                  // Tambahkan logika validasi di sini jika perlu
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Unit Selector (Rp / %)
                            ToggleButtons(
                              isSelected: [!selectedUnit, selectedUnit],
                              onPressed: (int index) {
                                setState(() {
                                  selectedUnit = index == 1;
                                  // Opsional: Clear controller saat ganti tipe agar tidak membingungkan
                                  // diskonController.clear();
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              constraints: const BoxConstraints(
                                minHeight: 54,
                                minWidth: 60,
                              ),
                              fillColor: AppColors.primary,
                              selectedColor: Colors.white,
                              color: Colors.grey[600],
                              selectedBorderColor: AppColors.primary,
                              borderColor: Colors.grey[300],
                              children: const [
                                Text(
                                  'Rp',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Preview Potongan Harga (Visual Feedback)
                        if (diskonController.text.isNotEmpty &&
                            diskonController.text != '0')
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 4),
                            child: Text(
                              selectedUnit
                                  ? "Hemat ${convertIDR((widget.price * quantity) * (double.tryParse(diskonController.text) ?? 0) / 100)}"
                                  : "Potongan harga diterapkan",
                              style: TextStyle(
                                color: Colors.green[700],
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    // Hitung status validasi
    bool isPropsValid =
        widget.maxProduk == null ||
        widget.maxProduk == 0 ||
        totalSelectedProps == (widget.maxProduk! * quantity);

    Color btnColor = isPropsValid && !isSubmitting
        ? AppColors.primary
        : Colors.grey.shade300;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: btnColor,
        foregroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: (isSubmitting || !isPropsValid)
          ? null
          : () {
              if (hasShift == false) {
                _showWarningShift();
                return;
              }
              savedToCart();
            },
      child: isSubmitting
          ? const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 2.0,
              ),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black54,
                ),
              ),
            )
          : const Text(
              'Simpan',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.white,
              ),
            ),
    );
  }
}
