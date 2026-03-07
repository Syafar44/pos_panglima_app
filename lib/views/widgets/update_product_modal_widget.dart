import 'package:flutter/material.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'dart:async';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_error.dart';
import 'package:pos_panglima_app/views/widgets/error_modal.dart';

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

    late int discount = diskonController.text.isEmpty
        ? 0
        : selectedUnit == false
        ? int.parse(diskonController.text).toInt()
        : ((int.parse(diskonController.text) / 100) * (widget.price * quantity))
              .toInt();

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
      print(response);
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
        },
      );
    } finally {
      widget.onSaved();
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadShiftStatus() async {
    final result = await ShiftStorageService.hasActiveShift();
    setState(() {
      hasShift = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: SizedBox(
          width: 800.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(vertical: 20.0, horizontal: 30.0),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.posMenusName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Subtotal',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              convertIDR(widget.price * quantity),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.maxQty == 0
                                ? Colors.amber
                                : totalSelectedProps ==
                                      (widget.maxQty ?? 0) * quantity
                                ? Colors.amber
                                : Colors.grey[300],
                            padding: EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => {
                            if (hasShift == true)
                              {
                                if (widget.maxQty != null)
                                  {
                                    if (totalSelectedProps ==
                                        (widget.maxQty ?? 0) * quantity)
                                      {savedToCart(widget.id)},
                                  }
                                else
                                  {savedToCart(widget.id)},
                              }
                            else
                              {
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    return ErrorModal(
                                      title: 'Perhatian',
                                      description:
                                          'Shift belum dimulai. Mulai shift terlebih dahulu untuk melakukan transaksi.',
                                    );
                                  },
                                ),
                              },
                          },
                          child: Text(
                            'Simpan',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
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
                      children: [
                        Container(
                          width: 200,
                          height: 130,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                secondColor(widget.posMenusName),
                                baseColor(widget.posMenusName),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            getInitials(widget.posMenusName),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 70,
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Harga ${convertIDR(widget.price)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 25,
                                ),
                              ),
                              Text('Kuantitas'),
                              SizedBox(height: 10),
                              Row(
                                children: [
                                  GestureDetector(
                                    onLongPressStart: (_) {
                                      _startDecreasing();
                                    },
                                    onLongPressEnd: (_) {
                                      _stopTimer();
                                    },
                                    child: IconButton(
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.grey[300],
                                        shadowColor: Colors.black,
                                        padding: EdgeInsets.all(5),
                                        shape: CircleBorder(),
                                      ),
                                      onPressed: () {
                                        if (quantity > 1) {
                                          setState(() => quantity--);
                                        }
                                      },
                                      icon: Icon(Icons.remove, size: 20),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Container(
                                    alignment: Alignment.center,
                                    width: 100.0,
                                    decoration: BoxDecoration(
                                      border: Border(bottom: BorderSide()),
                                    ),
                                    child: Text(
                                      '$quantity',
                                      style: TextStyle(fontSize: 20),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  GestureDetector(
                                    onLongPressStart: (_) {
                                      _startIncreasing();
                                    },
                                    onLongPressEnd: (_) {
                                      _stopTimer();
                                    },
                                    child: IconButton(
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.amber,
                                        padding: EdgeInsets.all(5),
                                        shape: CircleBorder(),
                                      ),
                                      onPressed: () {
                                        setState(() => quantity++);
                                      },
                                      icon: Icon(Icons.add, size: 20),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.amber),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'PCS',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Pilih Varian ( $totalSelectedProps / ${(widget.maxQty ?? 0) * quantity} )",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              GestureDetector(
                                onTap: resetVariants,
                                child: Text(
                                  "Reset",
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: widget.pos_cart_props!.map((e) {
                              final code = e["pos_menus_id"];
                              final propsQuantity = selectedProps[code] ?? 0;
                              final bool isDisabled =
                                  totalSelectedProps >=
                                  (widget.maxQty ?? 0) * quantity;
                              return GestureDetector(
                                onTap: isDisabled
                                    ? null
                                    : () => onTapVariant(e),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 22,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: propsQuantity > 0
                                        ? Colors.amber
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(color: Colors.amber),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        e["pos_menus_name"],
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (propsQuantity > 0) ...[
                                        SizedBox(width: 10),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            propsQuantity.toString(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
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
                          SizedBox(height: 20),
                        ],
                      ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(height: 30),
                        // Diskon
                        Text(
                          'Berikan Diskon',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: diskonController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'Masukkan diskon',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            ToggleButtons(
                              isSelected: [
                                selectedUnit == false,
                                selectedUnit == true,
                              ],
                              onPressed: (int index) {
                                setState(() {
                                  selectedUnit = index == 0 ? false : true;
                                });
                              },
                              borderRadius: BorderRadius.circular(5),
                              color: Colors.black,
                              selectedColor: Colors.white,
                              selectedBorderColor: Colors.amber,
                              fillColor: Colors.amber,
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 17.0,
                                    vertical: 17.0,
                                  ),
                                  child: Text(
                                    'Rp',
                                    style: TextStyle(color: Colors.black),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 17.0,
                                    vertical: 17.0,
                                  ),
                                  child: Text(
                                    '%',
                                    style: TextStyle(color: Colors.black),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
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
}
