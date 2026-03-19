import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/menu_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';
import 'package:pos_panglima_app/utils/modal_insufficient_stock.dart';
import 'package:pos_panglima_app/views/pages/payment_page.dart';
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
      loadCart();
    } catch (e) {
      loadCart();
      showDialog(
        context: context,
        builder: (context) {
          return ModalHandling(
            type: 'danger',
            title: 'Gagal memuat keranjang',
            description:
                'Terjadi kesalahan saat mengambil data keranjang. Mohon periksa koneksi atau coba kembali.',
          );
        },
      );
    }
  }

  void _increaseQuantity(int id) async {
    try {
      await cartService.plusCart(id);
      loadCart();
    } on DioException catch (e) {
      final String message = e.response?.data['message'] ?? 'Terjadi kesalahan';

      if (message.contains('insufficient_stock')) {
        final String stockPart = message.replaceFirst(
          'insufficient_stock: ',
          '',
        );
        final List<String> stockItems = stockPart.split('; ');

        final List<Map<String, String>> parsedItems = stockItems.map((item) {
          final RegExp regex = RegExp(
            r'^(.*?): required ([\d.]+), stock ([\d.]+)$',
          );
          final match = regex.firstMatch(item.trim());
          final String cleanName = (match?.group(1) ?? item).replaceAll(
            RegExp(r'\s*\(ITM\d+\)'),
            '',
          );
          return {
            'name': cleanName,
            'required': match?.group(2) ?? '-',
            'stock': match?.group(3) ?? '-',
          };
        }).toList();

        showDialog(
          context: context,
          builder: (context) {
            return ModalInsufficientStock(items: parsedItems);
          },
        );
      }
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
          return ModalHandling(
            type: 'warning',
            title: 'Gagal menghapus item',
            description:
                'Terjadi kendala saat menghapus item. Silakan coba kembali.',
          );
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
          return ModalHandling(
            type: 'danger',
            title: 'Gagal memuat Menu',
            description:
                'Terjadi kesalahan saat mengambil data Menu. Mohon periksa koneksi atau coba kembali.',
          );
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
      if (!mounted) return;
      setState(() {
        cartItems = [];
        totalPayment = 0;
      });
    }
  }

  Future<void> _loadShiftStatus() async {
    final result = await ShiftStorageService.hasActiveShift();
    setState(() {
      hasShift = result;
    });
  }

  void savedToCart(int id, dynamic onSaved) async {
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
          return ModalHandling(
            type: 'warning',
            title: 'Gagal menambahkan item',
            description:
                'Terjadi kendala saat menambahkan item. Silakan coba kembali.',
          );
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
                  // LayoutBuilder(
                  //   builder: (context, constraints) {
                  //     return Stack(
                  //       children: [
                  //         Row(
                  //           children: [
                  //             Container(
                  //               width: constraints.maxWidth - 70,
                  //               decoration: BoxDecoration(
                  //                 border: Border(
                  //                   bottom: BorderSide(color: Colors.black26),
                  //                   top: BorderSide(color: Colors.black26),
                  //                 ),
                  //               ),
                  //               child: Theme(
                  //                 data: Theme.of(context).copyWith(
                  //                   colorScheme: Theme.of(context).colorScheme
                  //                       .copyWith(
                  //                         surface: Colors.white,
                  //                         surfaceContainer: Colors.white,
                  //                         onSurface: Colors.black,
                  //                       ),
                  //                 ),
                  //                 child: DropdownMenu<String>(
                  //                   width: constraints.maxWidth - 70,
                  //                   hintText: 'Semua kategori',
                  //                   controller: categoryController,
                  //                   enableFilter: true,
                  //                   enableSearch: true,
                  //                   menuHeight: 500,
                  //                   inputDecorationTheme:
                  //                       const InputDecorationTheme(
                  //                         border: OutlineInputBorder(
                  //                           borderRadius: BorderRadius.zero,
                  //                           borderSide: BorderSide.none,
                  //                         ),
                  //                         filled: true,
                  //                         fillColor: Colors.white,
                  //                         contentPadding: EdgeInsets.symmetric(
                  //                           horizontal: 10.0,
                  //                         ),
                  //                       ),
                  //                   dropdownMenuEntries: categoryDropdownItems,
                  //                   onSelected: (value) {
                  //                     setState(() {
                  //                       category = value ?? 'all';
                  //                     });
                  //                   },
                  //                 ),
                  //               ),
                  //             ),
                  //             Container(
                  //               decoration: BoxDecoration(
                  //                 color: Colors.white,
                  //                 border: Border(
                  //                   bottom: BorderSide(color: Colors.black26),
                  //                   top: BorderSide(color: Colors.black26),
                  //                   left: BorderSide(color: Colors.black26),
                  //                 ),
                  //               ),
                  //               padding: const EdgeInsets.symmetric(
                  //                 horizontal: 10.5,
                  //                 vertical: 4.0,
                  //               ),
                  //               child: IconButton(
                  //                 iconSize: 30.0,
                  //                 splashRadius: 20,
                  //                 onPressed: () {
                  //                   setState(() {
                  //                     showSearch = !showSearch;
                  //                     if (showSearch) {
                  //                       category = 'all';
                  //                     } else {
                  //                       searchController.clear();
                  //                     }
                  //                   });
                  //                 },
                  //                 icon: Icon(
                  //                   showSearch ? Icons.close : Icons.search,
                  //                 ),
                  //               ),
                  //             ),
                  //           ],
                  //         ),
                  //         if (showSearch)
                  //           Positioned.fill(
                  //             child: Row(
                  //               children: [
                  //                 Container(
                  //                   decoration: const BoxDecoration(
                  //                     color: Colors.white,
                  //                   ),
                  //                   padding: const EdgeInsets.symmetric(
                  //                     horizontal: 10.8,
                  //                     vertical: 3.5,
                  //                   ),
                  //                   child: IconButton(
                  //                     iconSize: 30.0,
                  //                     splashRadius: 20,
                  //                     onPressed: () {
                  //                       setState(() {
                  //                         showSearch = false;
                  //                         searchController.clear();
                  //                       });
                  //                     },
                  //                     icon: const Icon(
                  //                       Icons.arrow_back,
                  //                       color: Colors.black,
                  //                     ),
                  //                   ),
                  //                 ),
                  //                 SizedBox(
                  //                   width: constraints.maxWidth - 70,
                  //                   child: Container(
                  //                     decoration: BoxDecoration(
                  //                       color:
                  //                           Theme.of(
                  //                             context,
                  //                           ).inputDecorationTheme.fillColor ??
                  //                           Colors.white,
                  //                       borderRadius: BorderRadius.zero,
                  //                       border: Border.all(
                  //                         color: Colors.grey.shade300,
                  //                       ),
                  //                     ),
                  //                     child: Padding(
                  //                       padding: const EdgeInsets.symmetric(
                  //                         horizontal: 4.0,
                  //                         vertical: 3.0,
                  //                       ),
                  //                       child: TextField(
                  //                         controller: searchController,
                  //                         autofocus: true,
                  //                         decoration: const InputDecoration(
                  //                           hintText: 'Cari Produk...',
                  //                           border: InputBorder.none,
                  //                           contentPadding:
                  //                               EdgeInsets.symmetric(
                  //                                 vertical: 10,
                  //                                 horizontal: 6,
                  //                               ),
                  //                         ),
                  //                       ),
                  //                     ),
                  //                   ),
                  //                 ),
                  //               ],
                  //             ),
                  //           ),
                  //       ],
                  //     );
                  //   },
                  // ),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 12.0,
                      right: 12.0,
                      top: 12.0,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const double actionWidth = 70.0;
                        final double mainWidth =
                            constraints.maxWidth - actionWidth;

                        return Container(
                          height: 56, // Tinggi standar yang nyaman
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: showSearch
                                  ? _buildSearchField(mainWidth, actionWidth)
                                  : _buildDropdownField(mainWidth, actionWidth),
                            ),
                          ),
                        );
                      },
                    ),
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
                                              builder: (dialogContext) {
                                                return ProductModalWidget(
                                                  title: e['title'],
                                                  category: e['category'],
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
                                                  dialogContext: dialogContext,
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
                                    height: 450.0,
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
                                      if (e['price'] != 0) {
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
                                                  (e['pos_cart_props'] !=
                                                      null &&
                                                  (e['pos_cart_props'] as List)
                                                      .isNotEmpty),
                                              onSaved: () {
                                                loadCart();
                                              },
                                            );
                                          },
                                        );
                                      }
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
                                                    if (e['max_qty'] != 0 &&
                                                        e['pos_cart_materials'] !=
                                                            null)
                                                      Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children:
                                                            (e['pos_cart_materials']
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
                                                                    '${item['quantity']}x ${item['items_name']}',
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
                                          return ModalHandling(
                                            type: 'warning',
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
        ValueListenableBuilder<Map<String, String>?>(
          valueListenable: incomingNotifNotifier,
          builder: (context, notif, child) {
            if (notif == null) return const SizedBox.shrink();

            return Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 0,
              right: 16,
              child: Align(
                alignment: Alignment.topRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 440,
                    maxHeight: 200,
                  ),
                  child: Material(
                    elevation: 6.0,
                    borderRadius: BorderRadius.circular(16.0),
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.0),
                        border: Border.all(
                          color: Colors.red.shade200,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16.0),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              selectedPageNotifier.value = 3;
                              incomingNotifNotifier.value = null;
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(
                                12.0,
                              ), // Padding sedikit dikecilkan agar lebih compact
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // --- Icon Indicator ---
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.notifications_active_rounded,
                                      color: Colors.red.shade400,
                                      size: 20.0, // Ukuran icon disesuaikan
                                    ),
                                  ),
                                  const SizedBox(width: 12.0),

                                  // --- Text Content (Title & Body) ---
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          notif['title'] ?? 'Notifikasi',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize:
                                                14.0, // Font sedikit disesuaikan
                                            color: Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4.0),
                                        Text(
                                          notif['body'] ?? '',
                                          style: TextStyle(
                                            fontSize:
                                                12.0, // Font sedikit disesuaikan
                                            color: Colors.grey.shade600,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),

                                  // --- Close Button ---
                                  const SizedBox(width: 4.0),
                                  GestureDetector(
                                    onTap: () {
                                      // incomingNotifNotifier.value = null;
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 2.0),
                                      child: Icon(
                                        Icons.close_rounded,
                                        color: Colors.grey.shade400,
                                        size: 18.0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDropdownField(double width, double actionWidth) {
    return Row(
      key: const ValueKey('dropdown'),
      children: [
        SizedBox(
          width: width,
          child: DropdownMenu<String>(
            width: width,
            hintText: 'Semua kategori',
            controller: categoryController,
            enableFilter: true,
            menuHeight: 300,
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16),
            ),
            dropdownMenuEntries: categoryDropdownItems,
            onSelected: (value) => setState(() => category = value ?? 'all'),
          ),
        ),
        _buildActionButton(
          icon: Icons.search,
          onPressed: () => setState(() => showSearch = true),
        ),
      ],
    );
  }

  Widget _buildSearchField(double width, double actionWidth) {
    return Row(
      key: const ValueKey('search'),
      children: [
        _buildActionButton(
          icon: Icons.arrow_back,
          onPressed: () {
            setState(() {
              showSearch = false;
              searchController.clear();
            });
          },
        ),
        Expanded(
          child: TextField(
            controller: searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Cari Produk...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
        if (searchController.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => searchController.clear(),
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 60,
      height: double.infinity,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey.shade100)),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.amber[900], size: 22),
        onPressed: onPressed,
      ),
    );
  }
}
