import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'dart:async';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_error.dart';
import 'package:pos_panglima_app/views/widgets/error_modal.dart';

class ProductModalWidget extends StatefulWidget {
  const ProductModalWidget({
    super.key,
    required this.title,
    required this.price,
    required this.codeProduct,
    required this.id,
    required this.collection,
    this.props,
    this.maxProduk,
    required this.onSaved,
  });

  final String title;
  final String codeProduct;
  final int id;
  final int price;
  final bool collection;
  final List? props;
  final int? maxProduk;
  final dynamic onSaved;

  @override
  State<ProductModalWidget> createState() => _ProductModalWidgetState();
}

class _ProductModalWidgetState extends State<ProductModalWidget> {
  final apiClient = ApiClient();
  late final CartService cartService;
  int quantity = 1;
  final TextEditingController diskonController = TextEditingController();
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
    final max = widget.maxProduk ?? 0;
    final id = (item["id"]);

    if (totalSelectedProps >= max && !selectedProps.containsKey(id)) return;

    setState(() {
      selectedProps[id] = (selectedProps[id] ?? 0) + 1;
    });

    print(selectedProps);
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
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(20.0)),
          ),
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
                          widget.title,
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
                            backgroundColor: widget.maxProduk == 0
                                ? Colors.amber
                                : totalSelectedProps ==
                                      (widget.maxProduk ?? 0) * quantity
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
                              // if (hasShift == false)
                              {
                                if (widget.maxProduk != null)
                                  {
                                    if (totalSelectedProps ==
                                        (widget.maxProduk ?? 0) * quantity)
                                      {savedToCart()},
                                  }
                                else
                                  {savedToCart()},
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
                                secondColor(widget.title),
                                baseColor(widget.title),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            getInitials(widget.title),
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
                    if (widget.maxProduk != null &&
                        widget.maxProduk! > 0 &&
                        widget.props != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Pilih Varian ( $totalSelectedProps / ${(widget.maxProduk ?? 0) * quantity} )",
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
                            children: widget.props!.map((e) {
                              final id = e["id"];
                              final propsQuantity = selectedProps[id] ?? 0;

                              // kondisi disable jika batas penuh
                              final bool isDisabled =
                                  totalSelectedProps >=
                                  (widget.maxProduk ?? 0) * quantity;

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
                                        e["title"],
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
