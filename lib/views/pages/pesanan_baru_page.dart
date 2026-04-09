import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
// import 'package:pos_panglima_app/services/auth_service.dart';
// import 'package:pos_panglima_app/services/inventory_service.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/menu_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/loader_utils.dart';
import 'package:pos_panglima_app/utils/modal_handling.dart';
import 'package:pos_panglima_app/utils/modal_insufficient_stock.dart';
import 'package:pos_panglima_app/utils/skeleton_loader.dart';
import 'package:pos_panglima_app/views/components/ui/cart_item_tile.dart';
import 'package:pos_panglima_app/views/components/ui/product_card.dart';
import 'package:pos_panglima_app/views/pages/payment_page.dart';
import 'package:pos_panglima_app/views/widgets/product_modal_widget.dart';
import 'package:pos_panglima_app/views/widgets/update_product_modal_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PesananBaruPage extends StatefulWidget {
  const PesananBaruPage({super.key});

  @override
  State<PesananBaruPage> createState() => _PesananBaruPageState();
}

class _PesananBaruPageState extends State<PesananBaruPage>
    with WidgetsBindingObserver {
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

  // void _startDecreasing(int id) {
  //   _timer = Timer.periodic(_interval, (_) {
  //     _decreaseQuantity(id);
  //   });
  // }

  // void _startIncreasing(int id) {
  //   _timer = Timer.periodic(_interval, (_) {
  //     _increaseQuantity(id);
  //   });
  // }

  // void _stopTimer() {
  //   _timer?.cancel();
  // }

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

    WidgetsBinding.instance.addObserver(this);
    _checkPendingNotif();

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
      debugPrint('getCart: $getCart');
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

  void savedToCart(int id, int price, dynamic onSaved) async {
    Map<String, dynamic> payload = {
      "pos_menus_id": id,
      "quantity": 1,
      "price": price,
      "subtotal": price,
      "tax": 0,
      "is_percentage": 0,
      "discount": 0,
      "discount_val": 0,
      "total": price,
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

  void _showProductModal(BuildContext context, Map<String, dynamic> e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) {
        return ProductModalWidget(
          title: e['title'],
          category: e['category'],
          id: e['id'],
          codeProduct: e['code_produk'],
          maxProduk: e['maxProduk'],
          props: e['props'],
          price: e['price'],
          collection: e['maxProduk'] != 0,
          imageUrl: e['image_url'],
          onSaved: () {
            loadCart();
          },
          dialogContext: dialogContext,
        );
      },
    );
  }

  void _showUpdateModal(BuildContext context, Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return UpdateProductModalWidget(
          // Melemparkan data dari Map 'item' ke properti widget
          id: item['id'],
          posMenusId: item['pos_menus_id'],
          posMenusName: item['pos_menus_name'],
          quantity: item['quantity'],
          price: item['price'],
          subtotal: item['subtotal'],
          tax: item['tax'],
          isPercentage: item['is_percentage'],
          discount: item['discount'],
          discountVal: item['discount_val'],
          total: item['total'],
          maxQty: item['max_qty'],
          imageUrl: item['image_url'],

          pos_cart_props: item['pos_cart_props'] ?? [],

          // Logika pengecekan koleksi (boolean)
          collection:
              (item['pos_cart_props'] != null &&
              (item['pos_cart_props'] as List).isNotEmpty),

          // Callback setelah data berhasil diupdate
          onSaved: () {
            loadCart();
          },
        );
      },
    );
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingNotif();
    }
  }

  Future<void> _checkPendingNotif() async {
    final prefs = await SharedPreferences.getInstance();
    final isVisible = prefs.getBool('notif_visible') ?? false;
    if (isVisible) {
      incomingNotifNotifier.value = {
        'title': prefs.getString('notif_title') ?? '',
        'body': prefs.getString('notif_body') ?? '',
      };
      // Reset agar tidak muncul lagi setelah dibaca
      await prefs.setBool('notif_visible', false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                                  : _buildDropdownField(
                                      mainWidth,
                                      actionWidth,
                                      constraints,
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: isLoadingMenu
                        ? Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: SkeletonLoader.menuSkeleton(
                              const Duration(seconds: 10),
                              () {
                                setState(() => isLoadingMenu = true);
                                getMenu();
                              },
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(
                              16.0,
                            ), // Padding lebih besar untuk kesan lega
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return GridView.builder(
                                  itemCount: produkList.length,
                                  physics: const BouncingScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount:
                                            constraints.maxWidth > 600
                                            ? 5
                                            : 2, // Responsif: 5 kolom di tab/pc, 2 di hp
                                        crossAxisSpacing: 2,
                                        mainAxisSpacing: 5,
                                        childAspectRatio:
                                            0.70, // Rasio tetap agar card tidak gepeng
                                      ),
                                  itemBuilder: (context, index) {
                                    final e = produkList[index];
                                    return ProductCard(
                                      product: e,
                                      onTap: () {
                                        if (e['category'] != 'Packaging' &&
                                            e['category'] !=
                                                'Isian / Topping') {
                                          _showProductModal(context, e);
                                        } else {
                                          savedToCart(
                                            e['id'],
                                            e['price'] ?? 0,
                                            () => loadCart(),
                                          );
                                        }
                                      },
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
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          width: constraints.maxWidth,
                          // Kita hapus border atas-bawah yang kaku, ganti dengan shadow halus atau border rounded
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              // Memperbaiki visual menu pop-up agar konsisten dengan Material 3
                              colorScheme: Theme.of(context).colorScheme
                                  .copyWith(
                                    surface: Colors.white,
                                    onSurface: Colors.black87,
                                  ),
                            ),
                            child: DropdownMenu<String>(
                              width: constraints.maxWidth,
                              hintText: 'Pilih Pelanggan',
                              leadingIcon: const Icon(
                                Icons.person_outline,
                                size: 20,
                              ), // Tambahkan ikon agar lebih user-friendly
                              controller: pelangganController,
                              enableFilter: true,
                              enableSearch: true,
                              menuStyle: MenuStyle(
                                backgroundColor: WidgetStateProperty.all(
                                  Colors.white,
                                ),
                                surfaceTintColor: WidgetStateProperty.all(
                                  Colors.white,
                                ),
                                fixedSize: WidgetStateProperty.all(
                                  Size(
                                    constraints.maxWidth - 18,
                                    constraints.maxHeight,
                                  ),
                                ),
                              ),
                              // Mempercantik Input Style
                              inputDecorationTheme: InputDecorationTheme(
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).primaryColor,
                                    width: 1.5,
                                  ),
                                ),
                              ),

                              dropdownMenuEntries: const [
                                DropdownMenuEntry<String>(
                                  value: 'Semua Pelanggan',
                                  label: 'Semua Pelanggan',
                                  leadingIcon: Icon(Icons.group_outlined),
                                ),
                                // Tambahkan entri lain di sini
                              ],
                              onSelected: (value) {
                                // Logika Anda
                              },
                            ),
                          ),
                        );
                      },
                    ),

                    Expanded(
                      child: cartItems.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              // Lebih efisien daripada SingleChildScrollView + Column
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              itemCount: cartItems.length,
                              itemBuilder: (context, index) {
                                final e = cartItems[index];
                                return CartItemTile(
                                  item: e,
                                  onDelete: () => _deletedCartItem(e['id']),
                                  onIncrease: () => _increaseQuantity(e['id']),
                                  onDecrease: () => _decreaseQuantity(e['id']),
                                  onUpdate: () => _showUpdateModal(context, e),
                                );
                              },
                            ),
                    ),
                    Column(
                      mainAxisSize:
                          MainAxisSize.min, // Agar tidak memakan space berlebih
                      children: [
                        // 1. Section Subtotal (Clean Borderless Style)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                            vertical: 16.0,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              top: BorderSide(
                                color: Colors.grey.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Subtotal',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                convertIDR(totalPayment),
                                style: const TextStyle(
                                  fontSize: 18.0,
                                  fontWeight: FontWeight
                                      .w900, // Lebih tegas untuk angka utama
                                  letterSpacing: -0.5,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 2. Section Tombol Bayar
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          child: SizedBox(
                            width: double.infinity,
                            height: 42,
                            child: ElevatedButton(
                              onPressed: () {
                                if (hasShift == true) {
                                  if (cartItems.isNotEmpty) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const PaymentPage(),
                                      ),
                                    );
                                  }
                                } else {
                                  showDialog(
                                    context: context,
                                    builder: (context) => const ModalHandling(
                                      type: 'warning',
                                      title: 'Perhatian',
                                      description:
                                          'Shift belum dimulai. Mulai shift terlebih dahulu.',
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black87,
                                elevation: 0, // Flat design lebih modern
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    12,
                                  ), // Border radius lebih besar
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shopping_cart_checkout_outlined,
                                    size: 20,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Proses Pembayaran',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
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

  Widget _buildDropdownField(
    double width,
    double actionWidth,
    dynamic constraints,
  ) {
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
            menuHeight: 500,
            menuStyle: MenuStyle(
              backgroundColor: WidgetStateProperty.all(Colors.white),
              surfaceTintColor: WidgetStateProperty.all(Colors.white),
              fixedSize: WidgetStateProperty.all(
                Size(constraints.maxWidth, constraints.maxHeight),
              ),
            ),
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

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.only(top: 80),
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Ikon keranjang kosong dengan background lembut
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_basket_outlined,
                size: 50,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Keranjang Masih Kosong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Silakan pilih menu di sebelah kiri untuk\nmulai menambahkan pesanan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
