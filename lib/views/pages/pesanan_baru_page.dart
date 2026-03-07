import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/menu_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_error.dart';
import 'package:pos_panglima_app/views/pages/payment_page.dart';
import 'package:pos_panglima_app/views/widgets/error_modal.dart';
import 'package:pos_panglima_app/views/widgets/product_modal_widget.dart';
import 'package:pos_panglima_app/views/widgets/update_product_modal_widget.dart';

class PesananBaruPage extends StatefulWidget {
  const PesananBaruPage({super.key});

  @override
  State<PesananBaruPage> createState() => _PesananBaruPageState();
}

class _PesananBaruPageState extends State<PesananBaruPage> {
  String category = 'all';
  bool showSearch = false;
  bool? hasShift;
  bool isLoadingMenu = true;
  final TextEditingController searchController = TextEditingController();
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController pelangganController = TextEditingController();

  Timer? _timer;
  final Duration _interval = Duration(milliseconds: 100);

  void _decreaseQuantity(int id) async {
    try {
      await cartService.minusCart(id);
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
        },
      );
    } finally {
      loadCart();
    }
  }

  void _increaseQuantity(int id) async {
    try {
      await cartService.plusCart(id);
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
        },
      );
    } finally {
      loadCart();
    }
  }

  Future<void> _deletedCartItem(int id) async {
    setState(() {
      cartItems.removeWhere((item) => item['id'] == id);
    });

    try {
      await cartService.deleteCart(id);
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) {
          return ModalError();
        },
      );
    } finally {
      loadCart();
    }
  }

  void _startDecreasing(int id) {
    _timer = Timer.periodic(_interval, (_) {
      _decreaseQuantity(id);
    });
  }

  void _startIncreasing(int id) {
    _timer = Timer.periodic(_interval, (_) {
      _increaseQuantity(id);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  List<Map<String, dynamic>> cartItems = [];
  int totalPayment = 0;
  final ScrollController _scrollController = ScrollController();
  double fadeOpacity = 0.2;
  final apiClient = ApiClient();
  late final CartService cartService;
  late final MenuService menuService;
  List menuList = [];

  Map<String, dynamic> get selectedCategory => menuList.firstWhere(
    (cat) => cat['category'] == category,
    orElse: () => {"data": []},
  );

  List<Map<String, dynamic>> get produkList {
    final keyword = searchController.text.toLowerCase();

    final allProducts = menuList.expand<Map<String, dynamic>>((e) {
      final categoryName = e['category'] as String;
      return (e['data'] as List).map<Map<String, dynamic>>((item) {
        final mapped = Map<String, dynamic>.from(item as Map); // ← fix di sini
        return {...mapped, 'category': categoryName};
      });
    }).toList();

    if (keyword.isNotEmpty) {
      return allProducts.where((e) {
        final title = e['title']?.toString().toLowerCase() ?? '';
        return title.contains(keyword);
      }).toList();
    }

    if (category == 'all') return allProducts;

    final selected = menuList.firstWhere(
      (e) => e['category'] == category,
      orElse: () => {'data': []},
    );

    return (selected['data'] as List? ?? []).map<Map<String, dynamic>>((item) {
      final mapped = Map<String, dynamic>.from(item as Map);
      return {...mapped, 'category': category};
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    menuService = MenuService(apiClient.dio);
    cartService = CartService(apiClient.dio);

    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;

      double maxScroll = _scrollController.position.maxScrollExtent;
      double current = _scrollController.position.pixels;

      if (current >= maxScroll - 5) {
        if (fadeOpacity != 0) setState(() => fadeOpacity = 0);
      } else {
        if (fadeOpacity != 1) setState(() => fadeOpacity = 1);
      }
    });

    loadCart();

    _loadShiftStatus();

    getMenu();

    searchController.addListener(() {
      if (searchController.text.isNotEmpty) {
        category = 'all';
      }
      setState(() {});
    });
  }

  List<DropdownMenuEntry<String>> get categoryDropdownItems {
    return [
      const DropdownMenuEntry(value: 'all', label: 'Semua kategori'),
      ...menuList.map((e) {
        return DropdownMenuEntry<String>(
          value: e['category'],
          label: e['category'],
        );
      }).toList(),
    ];
  }

  Future<void> getMenu() async {
    try {
      final response = await menuService.getList();
      final List rawList = response.data['data'];
      final enrichedList = rawList.map((categoryGroup) {
        final categoryName = categoryGroup['category'];
        final enrichedData = (categoryGroup['data'] as List).map((product) {
          return {...product, 'category': categoryName};
        }).toList();
        return {...categoryGroup, 'data': enrichedData};
      }).toList();

      setState(() {
        menuList = enrichedList;
        isLoadingMenu = false;
      });
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

  Future<void> loadCart() async {
    try {
      final getCart = await cartService.getCart();
      print(getCart);
      final newItems = List<Map<String, dynamic>>.from(
        getCart.data['data'] ?? [],
      );

      final newTotalPayment = newItems.fold<int>(0, (sum, item) {
        final int price = (item['total'] as int?) ?? 0;
        return sum + price;
      });

      if (!mounted) return;

      setState(() {
        cartItems = newItems;
        totalPayment = newTotalPayment;
      });
    } catch (e) {
      print('cart kosong');
    }
  }

  Future<void> _loadShiftStatus() async {
    final result = await ShiftStorageService.hasActiveShift();
    setState(() {
      hasShift = result;
    });
  }

  void savedToCart(int id, dynamic onSaved) async {
    print(
      '========================= Kamu menambahkan cart packaging ===========================',
    );
    Map<String, dynamic> payload = {
      "pos_menus_id": id,
      "quantity": 1,
      "price": 0,
      "subtotal": 0,
      "tax": 0,
      "is_percentage": 0,
      "discount": 0,
      "discount_val": 0,
      "total": 0,
      "max_qty": 0,
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
      onSaved();
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: constraints.maxWidth - 70,
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: Colors.black26),
                                    top: BorderSide(color: Colors.black26),
                                  ),
                                ),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: Theme.of(context).colorScheme
                                        .copyWith(
                                          surface: Colors.white,
                                          surfaceContainer: Colors.white,
                                          onSurface: Colors.black,
                                        ),
                                  ),
                                  child: DropdownMenu<String>(
                                    width: constraints.maxWidth - 70,
                                    hintText: 'Semua kategori',
                                    controller: categoryController,
                                    enableFilter: true,
                                    enableSearch: true,
                                    inputDecorationTheme:
                                        const InputDecorationTheme(
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.zero,
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: Colors.white,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10.0,
                                          ),
                                        ),
                                    dropdownMenuEntries: categoryDropdownItems,
                                    onSelected: (value) {
                                      setState(() {
                                        category = value ?? 'all';
                                      });
                                    },
                                  ),
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                    bottom: BorderSide(color: Colors.black26),
                                    top: BorderSide(color: Colors.black26),
                                    left: BorderSide(color: Colors.black26),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10.5,
                                  vertical: 4.0,
                                ),
                                child: IconButton(
                                  iconSize: 30.0,
                                  splashRadius: 20,
                                  onPressed: () {
                                    setState(() {
                                      showSearch = !showSearch;
                                      if (showSearch) {
                                        category = 'all';
                                      } else {
                                        searchController.clear();
                                      }
                                    });
                                  },
                                  icon: Icon(
                                    showSearch ? Icons.close : Icons.search,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (showSearch)
                            Positioned.fill(
                              child: Row(
                                children: [
                                  Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10.8,
                                      vertical: 3.5,
                                    ),
                                    child: IconButton(
                                      iconSize: 30.0,
                                      splashRadius: 20,
                                      onPressed: () {
                                        setState(() {
                                          showSearch = false;
                                          searchController.clear();
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.arrow_back,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: constraints.maxWidth - 70,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color:
                                            Theme.of(
                                              context,
                                            ).inputDecorationTheme.fillColor ??
                                            Colors.white,
                                        borderRadius: BorderRadius.zero,
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4.0,
                                          vertical: 3.0,
                                        ),
                                        child: TextField(
                                          controller: searchController,
                                          autofocus: true,
                                          decoration: const InputDecoration(
                                            hintText: 'Cari Produk...',
                                            border: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  vertical: 10,
                                                  horizontal: 6,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  Expanded(
                    child: isLoadingMenu
                        ? Center(child: CircularProgressIndicator())
                        : Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return GridView.builder(
                                  cacheExtent: 800,
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: produkList.length,
                                  addAutomaticKeepAlives: false,
                                  addRepaintBoundaries: true,
                                  addSemanticIndexes: false,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 5,
                                        crossAxisSpacing: 7,
                                        mainAxisSpacing: 10,
                                        childAspectRatio:
                                            constraints.maxWidth / (5 * 190),
                                      ),
                                  itemBuilder: (context, index) {
                                    final e = produkList[index];

                                    return RepaintBoundary(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(13),
                                        onTap: () {
                                          if (e['category'] != 'Packaging') {
                                            showDialog(
                                              context: context,
                                              builder: (context) {
                                                return ProductModalWidget(
                                                  title: e['title'],
                                                  id: e['id'],
                                                  codeProduct: e['code_produk'],
                                                  maxProduk: e['maxProduk'],
                                                  props: e['props'],
                                                  price: e['price'],
                                                  collection:
                                                      e['maxProduk'] != 0,
                                                  onSaved: () {
                                                    loadCart();
                                                  },
                                                );
                                              },
                                            );
                                          } else {
                                            savedToCart(e['id'], () {
                                              loadCart();
                                            });
                                          }
                                        },
                                        child: Card(
                                          color: Colors.white,
                                          elevation: 1,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Container(
                                                width: double.infinity,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      secondColor(e['title']),
                                                      baseColor(e['title']),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                        top: Radius.circular(
                                                          12,
                                                        ),
                                                      ),
                                                ),
                                                padding: const EdgeInsets.all(
                                                  15.0,
                                                ),
                                                child: Text(
                                                  getInitials(e['title']),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 40.0,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    8.0,
                                                  ),
                                                  child: Align(
                                                    alignment:
                                                        Alignment.topLeft,
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Text(
                                                          e['title'],
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 13,
                                                              ),
                                                        ),
                                                        Text(
                                                          convertIDR(
                                                            e['price'],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.black26)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Container(
                          width: constraints.maxWidth,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.black26),
                              top: BorderSide(color: Colors.black26),
                            ),
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: Theme.of(context).colorScheme
                                  .copyWith(
                                    surface:
                                        Colors.white, // background dropdown
                                    surfaceContainer: Colors.white,
                                    onSurface: Colors.black, // warna teks
                                  ),
                            ),
                            child: DropdownMenu<String>(
                              width: constraints.maxWidth,
                              hintText: 'Pelanggan',
                              controller: pelangganController,
                              enableFilter: true,
                              enableSearch: true,
                              inputDecorationTheme: const InputDecorationTheme(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.zero,
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10.0,
                                ),
                              ),
                              dropdownMenuEntries: [
                                DropdownMenuEntry<String>(
                                  value: 'Semua Pelanggan',
                                  label: 'Semua Pelanggan',
                                ),
                              ],
                              onSelected: (value) {
                                // setState(() {
                                //   category = value ?? 'all';
                                // });
                              },
                            ),
                          ),
                        );
                      },
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: cartItems.isEmpty
                              ? [
                                  SizedBox(
                                    height: 500.0,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Center(
                                          child: Text(
                                            'Keranjang kosong',
                                            style: TextStyle(
                                              fontSize: 18.0,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ]
                              : cartItems.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final e = cartItems[i];

                                  return InkWell(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        barrierDismissible: true,
                                        builder: (BuildContext context) {
                                          return UpdateProductModalWidget(
                                            id: e['id'],
                                            posMenusId: e['pos_menus_id'],
                                            posMenusName: e['pos_menus_name'],
                                            quantity: e['quantity'],
                                            price: e['price'],
                                            subtotal: e['subtotal'],
                                            tax: e['tax'],
                                            isPercentage: e['is_percentage'],
                                            discount: e['discount'],
                                            discountVal: e['discount_val'],
                                            total: e['total'],
                                            maxQty: e['max_qty'],
                                            pos_cart_props:
                                                e['pos_cart_props'] ?? [],
                                            collection:
                                                (e['pos_cart_props'] != null &&
                                                (e['pos_cart_props'] as List)
                                                    .isNotEmpty),
                                            onSaved: () {
                                              loadCart();
                                            },
                                          );
                                        },
                                      );
                                    },
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 20.0,
                                        vertical: 10.0,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Colors.black26,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      cartItems[i]['pos_menus_name'],
                                                      softWrap: true,
                                                      overflow:
                                                          TextOverflow.visible,
                                                      style: TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    Row(
                                                      children: [
                                                        Text(
                                                          convertIDR(
                                                            cartItems[i]['total'],
                                                          ),
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        (cartItems[i]['discount'] ??
                                                                        0) +
                                                                    (cartItems[i]['discount_val'] ??
                                                                        0) !=
                                                                0
                                                            ? Text(
                                                                ' ( - ${convertIDR(cartItems[i]['subtotal'] - cartItems[i]['total'])} )',
                                                                style:
                                                                    TextStyle(
                                                                      fontSize:
                                                                          16,
                                                                    ),
                                                              )
                                                            : SizedBox(),
                                                      ],
                                                    ),
                                                    if (e['max_qty'] != 0 &&
                                                        e['pos_cart_props'] !=
                                                            null)
                                                      Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children:
                                                            (e['pos_cart_props']
                                                                    as List)
                                                                .where(
                                                                  (item) =>
                                                                      item['quantity'] !=
                                                                      0,
                                                                )
                                                                .map<Widget>((
                                                                  item,
                                                                ) {
                                                                  return Text(
                                                                    '${item['quantity']}x ${item['pos_menus_name']}',
                                                                  );
                                                                })
                                                                .toList(),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () async {
                                                  _deletedCartItem(
                                                    cartItems[i]['id'],
                                                  );
                                                },
                                                icon: Icon(
                                                  Icons.delete,
                                                  color: Colors.redAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 20.0),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 20.0,
                                                  vertical: 10.0,
                                                ),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Colors.amber,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        50.0,
                                                      ),
                                                ),
                                                child: Text('PCS'),
                                              ),
                                              SizedBox(width: 20.0),
                                              GestureDetector(
                                                onLongPressStart: (_) {
                                                  _startDecreasing(
                                                    cartItems[i]['id'],
                                                  );
                                                },
                                                onLongPressEnd: (_) {
                                                  _stopTimer();
                                                },
                                                child: IconButton(
                                                  style: IconButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.grey[300],
                                                    shadowColor: Colors.black,
                                                    padding: EdgeInsets.all(5),
                                                    shape: CircleBorder(),
                                                  ),
                                                  onPressed: () {
                                                    _decreaseQuantity(
                                                      cartItems[i]['id'],
                                                    );
                                                  },
                                                  icon: Icon(
                                                    Icons.remove,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                alignment: Alignment.center,
                                                width: 40.0,
                                                child: Text(
                                                  // '$quantity',
                                                  '${cartItems[i]['quantity']}',
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                  ),
                                                ),
                                              ),
                                              GestureDetector(
                                                onLongPressStart: (_) {
                                                  _startIncreasing(
                                                    cartItems[i]['id'],
                                                  );
                                                },
                                                onLongPressEnd: (_) {
                                                  _stopTimer();
                                                },
                                                child: IconButton(
                                                  style: IconButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.amber,
                                                    padding: EdgeInsets.all(5),
                                                    shape: CircleBorder(),
                                                  ),
                                                  onPressed: () {
                                                    _increaseQuantity(
                                                      cartItems[i]['id'],
                                                    );
                                                  },
                                                  icon: Icon(
                                                    Icons.add,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.black26),
                              bottom: BorderSide(color: Colors.black26),
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Subtotal',
                                  style: TextStyle(fontSize: 16.0),
                                ),
                                Text(
                                  convertIDR(totalPayment),
                                  style: TextStyle(
                                    fontSize: 17.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    if (hasShift == true) {
                                      // if (hasShift == false) {
                                      if (cartItems.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) {
                                              return PaymentPage();
                                            },
                                          ),
                                        );
                                      }
                                    } else {
                                      showDialog(
                                        context: context,
                                        builder: (context) {
                                          return ErrorModal(
                                            title: 'Perhatian',
                                            description:
                                                'Shift belum dimulai. Mulai shift terlebih dahulu untuk melakukan transaksi.',
                                          );
                                        },
                                      );
                                    }
                                  },
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.amber,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  child: Text(
                                    'Bayar',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              // SizedBox(width: 10.0),
                              // IconButton(
                              //   onPressed: () {},
                              //   icon: Icon(Icons.menu),
                              //   style: IconButton.styleFrom(
                              //     backgroundColor: Colors.grey[300],
                              //     shadowColor: Colors.black,
                              //     padding: EdgeInsets.all(5),
                              //     shape: RoundedRectangleBorder(
                              //       borderRadius: BorderRadius.circular(6),
                              //     ),
                              //   ),
                              // ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Positioned(
        //   top: 5,
        //   right: 5,
        //   child: Card(
        //     color: Colors.red.shade50,
        //     child: InkWell(
        //       onTap: () {
        //         selectedPageNotifier.value = 6;
        //       },
        //       child: Container(
        //         padding: EdgeInsets.all(30.0),
        //         child: Row(
        //           spacing: 20.0,
        //           children: [
        //             Icon(Icons.notifications, color: Colors.red, size: 50.0),
        //             Column(
        //               crossAxisAlignment: CrossAxisAlignment.start,
        //               children: [
        //                 Text(
        //                   'Target Hari ini',
        //                   style: TextStyle(
        //                     fontWeight: FontWeight.bold,
        //                     fontSize: 24.0,
        //                   ),
        //                 ),
        //                 LinearProgressIndicator(value: 0.6),
        //               ],
        //             ),
        //           ],
        //         ),
        //       ),
        //     ),
        //   ),
        // ),
        // Positioned(
        //   top: 5,
        //   right: 5,
        //   child: Card(
        //     color: Colors.red.shade50,
        //     child: InkWell(
        //       onTap: () {
        //         selectedPageNotifier.value = 6;
        //       },
        //       child: Container(
        //         padding: EdgeInsets.all(30.0),
        //         child: Row(
        //           spacing: 20.0,
        //           children: [
        //             Icon(
        //               Icons.notifications,
        //               color: Colors.red.shade300,
        //               size: 50.0,
        //             ),
        //             Column(
        //               crossAxisAlignment: CrossAxisAlignment.start,
        //               children: [
        //                 Text(
        //                   'Ini Notifikasi',
        //                   style: TextStyle(
        //                     fontWeight: FontWeight.bold,
        //                     fontSize: 24.0,
        //                   ),
        //                 ),
        //                 Text(
        //                   'Segera selesiakan penerimaan Surat Jalan',
        //                   style: TextStyle(fontSize: 16.0),
        //                 ),
        //               ],
        //             ),
        //           ],
        //         ),
        //       ),
        //     ),
        //   ),
        // ),
      ],
    );
  }
}
