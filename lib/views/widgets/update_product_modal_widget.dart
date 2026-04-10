import 'package:flutter/material.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'dart:async';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';

class UpdateProductModalWidget extends StatefulWidget {
  const UpdateProductModalWidget({
    super.key,
    required this.id,
    required this.posMenusId,
    required this.posMenusName,
    required this.quantity,
    required this.price,
    required this.subtotal,
    required this.tax,
    required this.isPercentage,
    required this.discount,
    required this.discountVal,
    required this.total,
    this.pos_cart_props,
    this.maxQty,
    required this.collection,
    required this.onSaved,
    this.imageUrl,
  });

  final int id;
  final int posMenusId;
  final String posMenusName;
  final int quantity;
  final int price;
  final int subtotal;
  final int tax;
  final int isPercentage;
  final int discount;
  final int discountVal;
  final int total;
  final bool collection;
  final List? pos_cart_props;
  final int? maxQty;
  final dynamic onSaved;
  final String? imageUrl;

  @override
  State<UpdateProductModalWidget> createState() =>
      _UpdateProductModalWidgetState();
}

class _UpdateProductModalWidgetState extends State<UpdateProductModalWidget> {
  final apiClient = ApiClient();
  late final CartService cartService;
  int quantity = 1;
  final TextEditingController diskonController = TextEditingController();
  final TextEditingController catatanController = TextEditingController();
  bool selectedUnit = false;
  bool? hasShift;

  Timer? _timer;
  final Duration _interval = Duration(milliseconds: 100);

  void _decreaseQuantity() {
    if (quantity > 1) {
      setState(() {
        quantity--;
      });
    }
  }

  void _increaseQuantity() {
    setState(() {
      quantity++;
    });
  }

  void _startDecreasing() {
    _timer = Timer.periodic(_interval, (_) {
      _decreaseQuantity();
    });
  }

  void _startIncreasing() {
    _timer = Timer.periodic(_interval, (_) {
      _increaseQuantity();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  Map<int, int> selectedProps = {};

  int get totalSelectedProps {
    int sum = 0;
    selectedProps.forEach((key, val) => sum += val);
    return sum;
  }

  void onTapVariant(Map<String, dynamic> item) {
    final code = item["pos_menus_id"]; // ← fix (bukan item["id"])

    setState(() {
      selectedProps[code] = (selectedProps[code] ?? 0) + 1;
      mergedProps = widget.pos_cart_props!.map((e) {
        final c = e['pos_menus_id']; // ← fix
        return {"pos_menus_id": c, "quantity": selectedProps[c] ?? 0};
      }).toList();
    });
  }

  void resetVariants() {
    setState(() {
      selectedProps.clear();
      mergedProps = widget.pos_cart_props!.map((e) {
        return {"pos_menus_id": e["pos_menus_id"], "quantity": 0}; // ← fix
      }).toList();
    });
  }

  late List<Map<String, dynamic>> mergedProps;

  @override
  void initState() {
    super.initState();
    cartService = CartService(apiClient.dio);
    _loadShiftStatus();
    quantity = widget.quantity;

    // Prefill diskon
    diskonController.text = widget.isPercentage == 0
        ? widget.discount.toString()
        : widget.discountVal.toString();

    // Prefill tipe diskon
    selectedUnit = widget.isPercentage == 1;

    // Prefill props
    selectedProps = {};

    if (widget.pos_cart_props != null) {
      for (var item in widget.pos_cart_props!) {
        selectedProps[item["pos_menus_id"]] = item["quantity"];
      }
    }

    mergedProps = (widget.pos_cart_props ?? []).map((item) {
      final id = item['pos_menus_id'];
      final qty = selectedProps[id] ?? 0;
      return {"pos_menus_id": id, "quantity": qty};
    }).toList();
  }

  void savedToCart(int id) async {
    mergedProps = selectedProps.entries.map((entry) {
      return {"pos_menus_id": entry.key, "quantity": entry.value};
    }).toList();

    // late int discount = diskonController.text.isEmpty
    //     ? 0
    //     : selectedUnit == false
    //     ? int.parse(diskonController.text).toInt()
    //     : ((int.parse(diskonController.text) / 100) * (widget.price * quantity))
    //           .toInt();
    late int discount = diskonController.text.isEmpty
        ? 0
        : int.parse(diskonController.text).toInt();

    final int subtotal = widget.price * quantity;
    final int tax = 0;

    final int totalDiscount = selectedUnit
        ? subtotal * discount ~/ 100
        : discount;

    Map<String, dynamic> payload = {
      "pos_menus_id": widget.posMenusId,
      "quantity": quantity,
      "price": widget.price,
      "subtotal": subtotal,
      "tax": tax,
      "is_percentage": selectedUnit ? 1 : 0,
      "discount": selectedUnit ? 0 : discount,
      "discount_val": selectedUnit ? discount : 0,
      "total": subtotal - totalDiscount + tax,
      "pos_cart_props": mergedProps,
    };

    try {
      final response = await cartService.updateCart(id, payload);
      debugPrint('updateCart response: $response');
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'danger',
            title: 'Update gagal',
            description:
                'Terjadi kesalahan saat memperbarui data. Mohon periksa koneksi atau coba kembali.',
          );
        },
      );
    } finally {
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
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
    showDialog(
      context: context,
      builder: (context) => ModalHandling(
        type: 'warning',
        title: 'Perhatian',
        description:
            'Shift belum dimulai. Mulai shift terlebih dahulu untuk melakukan transaksi.',
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(20.0)),
          ),
          width: 600.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16.0,
                  horizontal: 20.0,
                ), // Padding disesuaikan agar lebih proporsional
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 1.5),
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Sisi Kiri: Info Produk
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
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.posMenusName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          // Text(
                          //   widget.category,
                          //   style: TextStyle(
                          //     color: Colors.grey[600],
                          //     fontSize: 13,
                          //   ),
                          // ),
                        ],
                      ),
                    ),

                    // Sisi Kanan: Harga & Tombol
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
                                color: Colors.orange,
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
              SizedBox(height: 16),
              Padding(
                padding: EdgeInsets.all(20.0),
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
                                  widget.posMenusName,
                                ).withOpacity(0.8),
                                baseColor(widget.posMenusName),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: baseColor(
                                  widget.posMenusName,
                                ).withOpacity(0.3),
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
                                ? Image.network(
                                    widget.imageUrl!,
                                    width: 140,
                                    height: 110,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) => Text(
                                          getInitials(widget.posMenusName),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 48,
                                            color: Colors.white,
                                          ),
                                        ),
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                          if (loadingProgress == null)
                                            return child;
                                          return Center(
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              value:
                                                  loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                            .cumulativeBytesLoaded /
                                                        loadingProgress
                                                            .expectedTotalBytes!
                                                  : null,
                                            ),
                                          );
                                        },
                                  )
                                : Text(
                                    getInitials(widget.posMenusName),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 48,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 20),

                        // Bagian Informasi & Stepper
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
                                  color: Colors.black87,
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
                                  _buildStepButton(
                                    icon: Icons.remove,
                                    color: Colors.grey[200]!,
                                    onTap: () {
                                      if (quantity > 1)
                                        setState(() => quantity--);
                                    },
                                    onLongPress: _startDecreasing,
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
                                  _buildStepButton(
                                    icon: Icons.add,
                                    color: Colors.amber,
                                    onTap: () => setState(() => quantity++),
                                    onLongPress: _startIncreasing,
                                  ),
                                  const SizedBox(width: 12),
                                  // Badge Satuan
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.amber.shade200,
                                      ),
                                    ),
                                    child: const Text(
                                      'PCS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
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
                    if (widget.maxQty != null &&
                        (widget.maxQty ?? 0) > 0 &&
                        widget.pos_cart_props != null)
                      // Column(
                      //   crossAxisAlignment: CrossAxisAlignment.start,
                      //   children: [
                      //     SizedBox(height: 20),
                      //     Row(
                      //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      //       children: [
                      //         Text(
                      //           "Pilih Varian ( $totalSelectedProps / ${(widget.maxQty ?? 0) * quantity} )",
                      //           style: TextStyle(
                      //             fontSize: 18,
                      //             fontWeight: FontWeight.bold,
                      //           ),
                      //         ),
                      //         GestureDetector(
                      //           onTap: resetVariants,
                      //           child: Text(
                      //             "Reset",
                      //             style: TextStyle(
                      //               color: Colors.red,
                      //               fontSize: 16,
                      //             ),
                      //           ),
                      //         ),
                      //       ],
                      //     ),
                      //     SizedBox(height: 12),
                      //     Wrap(
                      //       spacing: 10,
                      //       runSpacing: 10,
                      //       children: widget.pos_cart_props!.map((e) {
                      //         final code = e["pos_menus_id"];
                      //         final propsQuantity = selectedProps[code] ?? 0;
                      //         final bool isDisabled =
                      //             totalSelectedProps >=
                      //             (widget.maxQty ?? 0) * quantity;
                      //         return GestureDetector(
                      //           onTap: isDisabled
                      //               ? null
                      //               : () => onTapVariant(e),
                      //           child: Container(
                      //             padding: EdgeInsets.symmetric(
                      //               horizontal: 22,
                      //               vertical: 12,
                      //             ),
                      //             decoration: BoxDecoration(
                      //               color: propsQuantity > 0
                      //                   ? Colors.amber
                      //                   : Colors.white,
                      //               borderRadius: BorderRadius.circular(30),
                      //               border: Border.all(color: Colors.amber),
                      //             ),
                      //             child: Row(
                      //               mainAxisSize: MainAxisSize.min,
                      //               children: [
                      //                 Text(
                      //                   e["pos_menus_name"],
                      //                   style: TextStyle(
                      //                     color: Colors.black,
                      //                     fontWeight: FontWeight.bold,
                      //                   ),
                      //                 ),
                      //                 if (propsQuantity > 0) ...[
                      //                   SizedBox(width: 10),
                      //                   Container(
                      //                     padding: EdgeInsets.symmetric(
                      //                       horizontal: 8,
                      //                       vertical: 3,
                      //                     ),
                      //                     decoration: BoxDecoration(
                      //                       color: Colors.white,
                      //                       borderRadius: BorderRadius.circular(
                      //                         12,
                      //                       ),
                      //                     ),
                      //                     child: Text(
                      //                       propsQuantity.toString(),
                      //                       style: TextStyle(
                      //                         fontWeight: FontWeight.bold,
                      //                       ),
                      //                     ),
                      //                   ),
                      //                 ],
                      //               ],
                      //             ),
                      //           ),
                      //         );
                      //       }).toList(),
                      //     ),
                      //     SizedBox(height: 20),
                      //   ],
                      // ),
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
                                          "( $totalSelectedProps / ${(widget.maxQty ?? 0) * quantity} )",
                                      style: TextStyle(
                                        color:
                                            totalSelectedProps ==
                                                (widget.maxQty! * quantity)
                                            ? Colors.green.shade700
                                            : Colors.orange.shade700,
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
                            children: widget.pos_cart_props!.map((e) {
                              final id = e["pos_menus_id"];
                              final int propsQuantity = selectedProps[id] ?? 0;
                              final bool isSelected = propsQuantity > 0;

                              // Kondisi disable: sudah mencapai batas MAKSIMAL
                              final bool isDisabled =
                                  totalSelectedProps >=
                                  (widget.maxQty ?? 0) * quantity;

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
                                        ? Colors.amber
                                        : (isDisabled
                                              ? Colors.grey.shade100
                                              : Colors.white),
                                    borderRadius: BorderRadius.circular(
                                      12,
                                    ), // Menggunakan Rounded tipis agar lebih modern
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.amber.shade700
                                          : (isDisabled
                                                ? Colors.grey.shade300
                                                : Colors.amber.shade200),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        e["pos_menus_name"],
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.black
                                              : (isDisabled
                                                    ? Colors.grey.shade400
                                                    : Colors.black87),
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
                                              color: Colors.orange,
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
                    // Column(
                    //   crossAxisAlignment: CrossAxisAlignment.start,
                    //   children: [
                    //     Divider(height: 30),
                    //     // Diskon
                    //     Text(
                    //       'Berikan Diskon',
                    //       style: TextStyle(
                    //         fontWeight: FontWeight.bold,
                    //         fontSize: 16,
                    //       ),
                    //     ),
                    //     SizedBox(height: 8),
                    //     Row(
                    //       children: [
                    //         Expanded(
                    //           child: TextField(
                    //             controller: diskonController,
                    //             keyboardType: TextInputType.number,
                    //             decoration: InputDecoration(
                    //               hintText: 'Masukkan diskon',
                    //               border: OutlineInputBorder(
                    //                 borderRadius: BorderRadius.all(
                    //                   Radius.circular(10),
                    //                 ),
                    //               ),
                    //             ),
                    //           ),
                    //         ),
                    //         SizedBox(width: 8),
                    //         ToggleButtons(
                    //           isSelected: [
                    //             selectedUnit == false,
                    //             selectedUnit == true,
                    //           ],
                    //           onPressed: (int index) {
                    //             setState(() {
                    //               selectedUnit = index == 0 ? false : true;
                    //             });
                    //           },
                    //           borderRadius: BorderRadius.circular(5),
                    //           color: Colors.black,
                    //           selectedColor: Colors.white,
                    //           selectedBorderColor: Colors.amber,
                    //           fillColor: Colors.amber,
                    //           children: [
                    //             Padding(
                    //               padding: EdgeInsets.symmetric(
                    //                 horizontal: 17.0,
                    //                 vertical: 17.0,
                    //               ),
                    //               child: Text(
                    //                 'Rp',
                    //                 style: TextStyle(color: Colors.black),
                    //               ),
                    //             ),
                    //             Padding(
                    //               padding: EdgeInsets.symmetric(
                    //                 horizontal: 17.0,
                    //                 vertical: 17.0,
                    //               ),
                    //               child: Text(
                    //                 '%',
                    //                 style: TextStyle(color: Colors.black),
                    //               ),
                    //             ),
                    //           ],
                    //         ),
                    //       ],
                    //     ),
                    //     SizedBox(height: 16),
                    //   ],
                    // ),
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
                                      color: Colors.amber,
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
                              fillColor: Colors.amber,
                              selectedColor: Colors.black,
                              color: Colors.grey[600],
                              selectedBorderColor: Colors.amber,
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
        widget.maxQty == null ||
        widget.maxQty == 0 ||
        totalSelectedProps == (widget.maxQty! * quantity);

    Color btnColor = isPropsValid ? Colors.amber : Colors.grey.shade300;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: btnColor,
        foregroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () {
        // 1. Cek Shift
        if (hasShift == false) {
          _showWarningShift();
          return;
        }

        // 2. Cek Validasi Produk (Topping/Props)
        if (!isPropsValid) {
          // Opsional: Beri toast/snackbar "Pilihan belum lengkap"
          return;
        }

        // 3. Eksekusi
        savedToCart(widget.id);
      },
      child: const Text(
        'Simpan',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStepButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    return GestureDetector(
      onLongPressStart: (_) => onLongPress(),
      onLongPressEnd: (_) => _stopTimer(),
      child: IconButton(
        style: IconButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          minimumSize: const Size(45, 45),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 22, color: Colors.black87),
      ),
    );
  }
}
