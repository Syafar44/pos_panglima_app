import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:flutter_barcode_listener/flutter_barcode_listener.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
// import 'package:pos_panglima_app/services/auth_service.dart';
// import 'package:pos_panglima_app/services/inventory_service.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/menu_service.dart';
import 'package:pos_panglima_app/services/network_service.dart';
import 'package:pos_panglima_app/services/offline_cart_sync.dart';
import 'package:pos_panglima_app/services/storage/offline_stock_service.dart';
import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:pos_panglima_app/utils/modal_insufficient_stock.dart';
import 'package:pos_panglima_app/utils/skeleton_loader.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';
import 'package:pos_panglima_app/utils/stock_parser.dart';
import 'package:pos_panglima_app/views/components/ui/cart_item_tile.dart';
import 'package:pos_panglima_app/views/components/ui/product_card.dart';
import 'package:pos_panglima_app/views/pages/payment_page.dart';
import 'package:pos_panglima_app/views/pages/pending_payment_page.dart';
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
  bool isProcessingPayment = false;
  final TextEditingController searchController = TextEditingController();
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController pelangganController = TextEditingController();

  List<Map<String, dynamic>> cartItems = [];
  int totalPayment = 0;
  final Set<int> _busyCartIds = {};
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

  void _decreaseQuantity(int id) async {
    if (_busyCartIds.contains(id)) return;
    setState(() => _busyCartIds.add(id));
    try {
      if (!await NetworkService.isOnline()) {
        await OfflineStockService.decreaseCartItem(id);
        await loadCart();
        return;
      }
      await cartService.minusCart(id);
      await loadCart();
    } catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'pesanan_baru_page._decreaseQuantity',
      );
      await loadCart();
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: "Gagal memuat keranjang",
        message:
            "Terjadi kesalahan saat mengambil data keranjang. Mohon periksa koneksi atau coba kembali.",
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => _busyCartIds.remove(id));
    }
  }

  void _increaseQuantity(int id) async {
    if (_busyCartIds.contains(id)) return;
    setState(() => _busyCartIds.add(id));
    try {
      if (!await NetworkService.isOnline()) {
        // Validasi stok terhadap cart prospektif (baris ini +1).
        final cart = await OfflineStockService.getCartSnapshot();
        final prospective = cart
            .map(
              (c) => c['id'] == id
                  ? {...c, 'quantity': (c['quantity'] as num).toInt() + 1}
                  : c,
            )
            .toList()
            .cast<Map<String, dynamic>>();
        final lacking = await OfflineStockService.validateDetailed(prospective);
        if (lacking.isNotEmpty) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (_) => ModalInsufficientStock(items: lacking),
          );
          return;
        }
        await OfflineStockService.increaseCartItem(id);
        await loadCart();
        return;
      }
      await cartService.plusCart(id);
      await loadCart();
    } on DioException catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'pesanan_baru_page._increaseQuantity',
        context: {
          'endpoint': e.requestOptions.path,
          'statusCode': e.response?.statusCode,
          'responseData': e.response?.data?.toString(),
        },
      );
      await loadCart();
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
      if (mounted) setState(() => _busyCartIds.remove(id));
    }
  }

  Future<void> _deletedCartItem(int id) async {
    if (_busyCartIds.contains(id)) return;
    setState(() {
      _busyCartIds.add(id);
      cartItems.removeWhere((item) => item['id'] == id);
    });

    try {
      if (!await NetworkService.isOnline()) {
        await OfflineStockService.removeCartItem(id);
        return;
      }
      await cartService.deleteCart(id);
    } catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'pesanan_baru_page._deletedCartItem',
      );
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: "Gagal menghapus item",
        message: "Terjadi kendala saat menghapus item. Silakan coba kembali.",
        status: SnackBarStatus.error,
      );
    } finally {
      if (mounted) setState(() => _busyCartIds.remove(id));
      await loadCart();
    }
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

    _initMenu();

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
      }),
    ];
  }

  /// Tambahkan field `category` ke tiap produk supaya filter & pencarian jalan.
  List _enrichMenu(List rawList) {
    return rawList.map((categoryGroup) {
      final categoryName = categoryGroup['category'];
      final enrichedData = (categoryGroup['data'] as List).map((product) {
        return {...product, 'category': categoryName};
      }).toList();
      return {...categoryGroup, 'data': enrichedData};
    }).toList();
  }

  /// Cache-first: tampilkan menu dari local storage dulu (instan, tahan offline
  /// & saat pindah halaman), baru refresh dari server di belakang layar.
  Future<void> _initMenu() async {
    final cachedMenu = await OfflineStockService.getMenu();
    if (cachedMenu.isNotEmpty && mounted) {
      setState(() {
        menuList = _enrichMenu(cachedMenu);
        isLoadingMenu = false;
      });
    }
    await getMenu();
  }

  Future<void> getMenu() async {
    try {
      final response = await menuService.getList();
      final List rawList = response.data['data'];

      // Simpan menu mentah ke local storage untuk fallback offline.
      await OfflineStockService.saveMenu(rawList);

      if (!mounted) return;
      setState(() {
        menuList = _enrichMenu(rawList);
        isLoadingMenu = false;
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pesanan_baru_page.getMenu');

      // Kalau menu sudah tampil (dari cache), jangan ganggu UI — diam saja.
      if (menuList.isNotEmpty) return;

      // Belum ada menu di layar → coba ambil dari cache.
      final cachedMenu = await OfflineStockService.getMenu();
      if (!mounted) return;

      if (cachedMenu.isNotEmpty) {
        setState(() {
          menuList = _enrichMenu(cachedMenu);
          isLoadingMenu = false;
        });
        SnackbarUtil.show(
          context,
          title: "Mode Offline",
          message:
              "Menampilkan menu tersimpan. Stok mengikuti data terakhir saat online.",
          status: SnackBarStatus.warning,
        );
        return;
      }

      // Tidak ada cache sama sekali → biarkan UI retry tampil.
      setState(() => isLoadingMenu = true);
      SnackbarUtil.show(
        context,
        title: "Gagal memuat Menu",
        message:
            "Terjadi kesalahan saat mengambil data Menu. Mohon periksa koneksi atau coba kembali.",
        status: SnackBarStatus.error,
      );
    }
  }

  Future<void> loadCart() async {
    try {
      final online = await NetworkService.isOnline();
      List<Map<String, dynamic>> newItems;

      if (!online) {
        // Offline: ambil cart dari local storage.
        newItems = await OfflineStockService.getCartSnapshot();
      } else {
        // Hapus dulu item yang sudah dibayar offline dari cart server agar
        // tidak muncul lagi di keranjang.
        await OfflineCartSync.flushServerCartDeletions();
        // Dorong dulu item yang dibuat saat offline ke cart server agar tidak
        // hilang saat cart ditarik dari server.
        final failed = await OfflineCartSync.migrateToServer();
        if (failed > 0 && mounted) {
          SnackbarUtil.show(
            context,
            title: "Sebagian item gagal disinkronkan",
            message:
                "$failed item dari mode offline tidak bisa ditambahkan (cek stok server).",
            status: SnackBarStatus.warning,
          );
        }

        final getCart = await cartService.getCart();
        newItems = List<Map<String, dynamic>>.from(getCart.data['data'] ?? []);
        // Sinkronkan snapshot lokal supaya siap saat tiba-tiba offline.
        await OfflineStockService.saveCartSnapshot(newItems);
      }

      final newTotalPayment = newItems.fold<int>(0, (sum, item) {
        final int price = (item['total'] as int?) ?? 0;
        return sum + price;
      });

      if (!mounted) return;

      setState(() {
        cartItems = newItems;
        totalPayment = newTotalPayment;
      });
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'pesanan_baru_page.loadCart');
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

  /// Dipanggil saat menekan "Proses Pembayaran". Menyamakan sumber data cart
  /// lebih dulu supaya quantity di halaman ini dan di halaman pembayaran identik.
  Future<void> _goToPayment() async {
    if (isProcessingPayment) return;
    if (hasShift != true) {
      SnackbarUtil.show(
        context,
        title: "Mulai Shift terlebih dahulu",
        message: "Shift belum dimulai. Mulai shift terlebih dahulu.",
        status: SnackBarStatus.warning,
      );
      return;
    }
    if (cartItems.isEmpty) return;

    setState(() => isProcessingPayment = true);
    try {
      if (await NetworkService.isOnline()) {
        // Online: dorong item offline ke server lalu tarik ulang. Setelah ini
        // server, snapshot, dan tampilan seragam.
        await OfflineCartSync.migrateToServer();
        await loadCart();
      } else {
        // Offline: snapshot jadi sumber kebenaran — samakan dengan yang tampil
        // (mencakup semua perubahan qty +/- yang baru dilakukan).
        await OfflineStockService.saveCartSnapshot(cartItems);
      }
    } finally {
      if (mounted) setState(() => isProcessingPayment = false);
    }

    if (!mounted) return;
    if (cartItems.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PaymentPage()),
    );
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

    // ── MODE OFFLINE ──────────────────────────────────────────────────────
    if (!await NetworkService.isOnline()) {
      await _savedToCartOffline(id, price);
      onSaved();
      return;
    }

    try {
      await cartService.postCart(payload);
    } on DioException catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'pesanan_baru_page.savedToCart',
        context: {
          'endpoint': e.requestOptions.path,
          'statusCode': e.response?.statusCode,
          'responseData': e.response?.data?.toString(),
        },
      );
      final message = e.response?.data['message'] ?? 'Terjadi kesalahan';
      if (!mounted) return;
      if (message.contains('insufficient_stock')) {
        final parsedItems = parseInsufficientStock(message);
        showDialog(
          context: context,
          builder: (_) => ModalInsufficientStock(items: parsedItems),
        );
      } else {
        SnackbarUtil.show(
          context,
          title: "Gagal menambahkan item",
          message:
              "Terjadi kendala saat menambahkan item. Silakan coba kembali.",
          status: SnackBarStatus.error,
        );
      }
    } finally {
      onSaved();
    }
  }

  /// Tambah item sederhana (Packaging/Topping/barcode) ke cart lokal offline.
  Future<void> _savedToCartOffline(int id, int price) async {
    try {
      final product = produkList.firstWhere(
        (p) => p['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      final item = <String, dynamic>{
        'id': DateTime.now().microsecondsSinceEpoch,
        'pos_menus_id': id,
        'pos_menus_name': product['title'] ?? 'Item',
        'quantity': 1,
        'price': price,
        'subtotal': price,
        'tax': 0,
        'is_percentage': 0,
        'discount': 0,
        'discount_val': 0,
        'total': price,
        'max_qty': 0,
        'image_url': product['image_url'],
        'pos_cart_props': const [],
        // Penanda item dibuat offline → didorong ke server saat online lagi.
        '_offline': true,
      };

      final currentCart = await OfflineStockService.getCartSnapshot();
      final lacking = await OfflineStockService.validateDetailed([
        ...currentCart,
        item,
      ]);
      if (lacking.isNotEmpty) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => ModalInsufficientStock(items: lacking),
        );
        return;
      }
      await OfflineStockService.addCartItem(item);
    } catch (e, stack) {
      CrashReporter.report(
        e,
        stack,
        reason: 'pesanan_baru_page.savedToCartOffline',
      );
    }
  }

  void _handleBarcodeScan(String barcode) {
    final cleanBarcode = barcode.trim().toLowerCase();
    if (cleanBarcode.isEmpty) return;

    Map<String, dynamic>? foundProduct;

    for (final categoryGroup in menuList) {
      final products = categoryGroup['data'] as List? ?? [];
      for (final product in products) {
        final productBarcode =
            product['barcode']?.toString().toLowerCase() ?? '';
        final codeProduk =
            product['code_produk']?.toString().toLowerCase() ?? '';

        if ((productBarcode.isNotEmpty && productBarcode == cleanBarcode) ||
            (codeProduk.isNotEmpty && codeProduk == cleanBarcode)) {
          foundProduct = Map<String, dynamic>.from(product);
          break;
        }
      }
      if (foundProduct != null) break;
    }

    if (foundProduct == null) {
      if (mounted) {
        SnackbarUtil.show(
          context,
          title: "Tidak ditemukan",
          message: "Barcode [$cleanBarcode] tidak ditemukan",
          status: SnackBarStatus.error,
        );
      }
      return;
    }

    final productCategory = foundProduct['category'] ?? '';
    final hasProps = (foundProduct['props'] as List?)?.isNotEmpty ?? false;

    // Validasi stok dilakukan server (sama dengan flow tap manual):
    // - kalau item sudah di keranjang → increment via API
    // - kalau tidak, savedToCart hit server. Bila stok kurang, response
    //   `insufficient_stock` akan memunculkan ModalInsufficientStock.
    final existingCartItem = cartItems.firstWhere(
      (item) => item['pos_menus_id'] == foundProduct!['id'],
      orElse: () => {},
    );

    if (existingCartItem.isNotEmpty) {
      _increaseQuantity(existingCartItem['id']);
      return;
    }

    // Produk dengan variant (props) selain Packaging/Topping → buka modal pilihan.
    if (productCategory != 'Packaging' &&
        productCategory != 'Isian / Topping' &&
        hasProps) {
      _showProductModal(context, foundProduct);
      return;
    }

    savedToCart(foundProduct['id'], foundProduct['price'] ?? 0, loadCart);
  }

  void _showProductModal(BuildContext context, Map<String, dynamic> e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,

      isDismissible: false,
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
    final allProducts = menuList.expand<Map>(
      (cat) => (cat['data'] as List).cast<Map>(),
    );
    final menuItem = allProducts.firstWhere(
      (p) => p['id'] == item['pos_menus_id'],
      orElse: () => {},
    );
    final List? availableProps = menuItem['props'] as List?;

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

          posCartProps: item['pos_cart_props'] ?? [],
          availableProps: availableProps,

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

  @override
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
    categoryController.dispose();
    pelangganController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BarcodeKeyboardListener(
      bufferDuration: const Duration(milliseconds: 200),
      onBarcodeScanned: _handleBarcodeScan,
      child: Stack(
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
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
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
                                timeout: const Duration(seconds: 10),
                                onRetry: () {
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
                                              loadCart,
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
                  decoration: const BoxDecoration(
                    border: Border(left: BorderSide(color: Colors.black26)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                itemCount: cartItems.length,
                                itemBuilder: (context, index) {
                                  final e = cartItems[index];
                                  return CartItemTile(
                                    item: e,
                                    isBusy: _busyCartIds.contains(e['id']),
                                    onDelete: () => _deletedCartItem(e['id']),
                                    onIncrease: () =>
                                        _increaseQuantity(e['id']),
                                    onDecrease: () =>
                                        _decreaseQuantity(e['id']),
                                    onUpdate: () =>
                                        _showUpdateModal(context, e),
                                  );
                                },
                              ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize
                            .min, // Agar tidak memakan space berlebih
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
                                  color: Colors.grey.withValues(alpha: 0.2),
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

                          // 2. Section Tombol Bayar + Hamburger Menu
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 42,
                                    child: ElevatedButton(
                                      onPressed: isProcessingPayment
                                          ? null
                                          : _goToPayment,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.black87,
                                        disabledBackgroundColor:
                                            AppColors.white,
                                        elevation: 0,
                                        side: isProcessingPayment
                                            ? const BorderSide(
                                                color: AppColors.primary,
                                              )
                                            : null,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: isProcessingPayment
                                          ? const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            AppColors.primary,
                                                      ),
                                                ),
                                              ],
                                            )
                                          : const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons
                                                      .shopping_cart_checkout_outlined,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(width: 12),
                                                Text(
                                                  'Proses Pembayaran',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: PopupMenuButton<String>(
                                    tooltip: 'Menu lainnya',
                                    icon: const Icon(
                                      Icons.menu,
                                      color: AppColors.primary,
                                    ),
                                    // Muncul di atas tombol, sedikit naik & lebar.
                                    position: PopupMenuPosition.over,
                                    offset: const Offset(0, -64),
                                    color: Colors.white,
                                    elevation: 4,
                                    constraints: const BoxConstraints(
                                      minWidth: 200,
                                      maxWidth: 220,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    style: ButtonStyle(
                                      backgroundColor: WidgetStateProperty.all(
                                        AppColors.white,
                                      ),
                                      side: WidgetStateProperty.all(
                                        const BorderSide(
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      shape: WidgetStateProperty.all(
                                        RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    onSelected: (value) {
                                      if (value == 'riwayat') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const PendingPaymentPage(),
                                          ),
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'riwayat',
                                        height: 40,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.history,
                                              size: 18,
                                              color: AppColors.primary,
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                              'Riwayat',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                bottom: MediaQuery.of(context).padding.top + 15,
                left: 20,
                child: Align(
                  alignment: Alignment.topRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 720,
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
                                // Inventory reminder tidak boleh dihapus manual —
                                // hanya hilang setelah semua surat jalan dikonfirmasi
                                if (incomingNotifNotifier.value?['type'] !=
                                    'inventory') {
                                  incomingNotifNotifier.value = null;
                                }
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
      ),
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
            onPressed: searchController.clear,
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
        icon: Icon(icon, color: AppColors.primaryDarkest, size: 22),
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
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_basket_outlined,
                size: 50,
                color: AppColors.primary,
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
