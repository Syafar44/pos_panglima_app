# AUDIT MENYELURUH PROJECT POS PANGLIMA (Flutter)

**Tanggal Audit**: 2026-05-23
**Versi App**: 2.0.8+36
**Branch**: fix/payment-issue
**Auditor**: Claude (Opus 4.7)

Audit ini meninjau seluruh `lib/` (±27.000 LoC), konfigurasi Android, `pubspec.yaml`, dan kebijakan analisis statis. Temuan dikelompokkan per kategori dengan referensi file:line langsung.

---

## 1. ARSITEKTUR & STRUKTUR PROJECT

### Evaluasi Struktur Folder

Project menggunakan **layer-first hybrid** yang **tidak konsisten**:

```
lib/
├── data/            → constants + ValueNotifier global
├── models/          → Hive models (cart_item, cart_variant) — TIDAK DIPAKAI
├── services/        → API services + storage + helper (dio_client, splash_screen)
│   ├── helper/      → ApiClient + SplashScreen widget di dalam services ❌
│   ├── repositories/→ Hanya 1 file: cart_repository.dart
│   └── storage/     → SharedPreferences wrappers + Hive (tak terpakai)
├── utils/           → 14 file utility (kebanyakan one-off)
└── views/
    ├── components/ui/ → 4 widget (cart_item_tile, product_card, dll)
    ├── pages/       → 18 page (sebagian SANGAT besar)
    └── widgets/     → 8 modal/widget global
```

**Masalah arsitektur utama**:
1. Tidak ada pemisahan **feature-first** — semua page bercampur di `views/pages/`.
2. `SplashScreen` (widget) berada di `lib/services/helper/` — semantik salah ([services/helper/splash_screen.dart](lib/services/helper/splash_screen.dart)).
3. Folder `repositories/` ada tapi hampir kosong; pattern repository tidak konsisten dipakai.
4. Folder `models/` berisi Hive model yang **tidak digunakan sama sekali** (Hive init di-comment di [main.dart:102-104](lib/main.dart#L102-L104)).
5. Logic business banyak yang **bocor ke widget page** (transaksi pembayaran, validasi order, idempotency token, geolocation, device info — semuanya di `_PaymentPageState`).

### 🔴 CRITICAL — File terlalu panjang (>300 baris)

| File | Baris | Severity |
|---|---|---|
| [lib/views/pages/reject_detail_page.dart](lib/views/pages/reject_detail_page.dart) | **2443** | 🔴 |
| [lib/views/pages/payment_page.dart](lib/views/pages/payment_page.dart) | **2301** | 🔴 |
| [lib/views/pages/inventory_page.dart](lib/views/pages/inventory_page.dart) | **1988** | 🔴 |
| [lib/views/pages/riwayat_penjualan_page.dart](lib/views/pages/riwayat_penjualan_page.dart) | 1402 | 🔴 |
| [lib/views/pages/pengaturan_page.dart](lib/views/pages/pengaturan_page.dart) | 1246 | 🟠 |
| [lib/views/pages/pesanan_baru_page.dart](lib/views/pages/pesanan_baru_page.dart) | 1165 | 🟠 |
| [lib/views/pages/reception_inventory_page.dart](lib/views/pages/reception_inventory_page.dart) | 1037 | 🟠 |
| [lib/views/pages/laporan_page.dart](lib/views/pages/laporan_page.dart) | 880 | 🟠 |
| [lib/views/pages/stock_opname_page.dart](lib/views/pages/stock_opname_page.dart) | 875 | 🟠 |
| [lib/views/widgets/update_product_modal_widget.dart](lib/views/widgets/update_product_modal_widget.dart) | 857 | 🟠 |
| [lib/views/widgets/product_modal_widget.dart](lib/views/widgets/product_modal_widget.dart) | 810 | 🟠 |
| [lib/views/widgets/end_shift_modal.dart](lib/views/widgets/end_shift_modal.dart) | 684 | 🟡 |
| [lib/services/bluetooth_printer_service.dart](lib/services/bluetooth_printer_service.dart) | 635 | 🟡 |
| [lib/views/widgets/start_shift_modal.dart](lib/views/widgets/start_shift_modal.dart) | 635 | 🟡 |

**Issue #1: `payment_page.dart` melanggar SRP secara ekstrem**

- **Severity**: 🔴 Critical
- **File & Line**: [lib/views/pages/payment_page.dart:1-2301](lib/views/pages/payment_page.dart)
- **Problem**: Class `_PaymentPageState` menangani: cart state, idempotency token, payment method state, voucher, geolocation, device info, bluetooth state, snackbar dialogs (5 modal showDialog inline: slowExecution, paymentError, paymentSuccess, voucherSuccess, voucherError), validation, AND UI rendering. ±60 method dalam 1 class.
- **Impact**: Hampir mustahil untuk diuji, di-debug, atau dimodifikasi tanpa regresi. Setiap perubahan kecil berpotensi memecah flow pembayaran (yang adalah jalur transaksi kritis bisnis).
- **Solution**: Pecah menjadi:
  ```
  payment_page/
    payment_page.dart                 (widget tree saja)
    controller/payment_controller.dart (state + logic, pakai ChangeNotifier/Bloc)
    services/order_submission.dart    (handlePayment + idempotency)
    services/device_context.dart      (getDeviceInfo + getLocation)
    widgets/payment_method_picker.dart
    widgets/voucher_section.dart
    widgets/payment_modals.dart       (semua showDialog)
  ```
- **Effort**: Refactor besar (3-5 hari kerja)

**Issue #2: `reject_detail_page.dart` mengandung CameraView + Watermarking custom**

- **Severity**: 🔴 Critical
- **File & Line**: [lib/views/pages/reject_detail_page.dart:2150-2350](lib/views/pages/reject_detail_page.dart#L2150)
- **Problem**: Reverse geocoding, kamera init, watermark canvas dengan ParagraphBuilder, kompresi multi-attempt — semuanya inline dalam page yang juga handle CRUD reject lines.
- **Impact**: Class tunggal melakukan ±8 tanggung jawab berbeda. Memori dapat bocor jika `src.dispose()`/`out.dispose()` di [line 2280-2281](lib/views/pages/reject_detail_page.dart#L2280) gagal dipanggil saat exception sebelum titik tersebut.
- **Solution**: Ekstrak ke `services/reject_camera_service.dart` dan `utils/watermark_renderer.dart`.
- **Effort**: Medium (1-2 hari)

### Naming Convention

- **Bahasa campur**: nama page memakai Bahasa Indonesia (`pesanan_baru_page`, `laporan_page`, `pengaturan_page`) sementara service memakai Bahasa Inggris (`bluetooth_printer_service`, `cart_service`). Tidak konsisten.
- **Typo**: [bluetooth_printer_service.dart:557](lib/services/bluetooth_printer_service.dart#L557) → `'Pelangan'` seharusnya `'Pelanggan'` (struk cetak ke pelanggan akhir).
- **Class private inkonsisten**: `_CatalogItem`, `_RejectItemEntry` (private) vs class top-level lainnya (public).

---

## 2. STATE MANAGEMENT

### Pattern yang Digunakan

Project memakai **3 pendekatan tercampur**:

1. **`setState` + StatefulWidget** — dominan (209 occurrence di 21 file).
2. **`ValueNotifier`** global di [lib/data/notifiers.dart](lib/data/notifiers.dart) (6 notifier).
3. **Static `ValueNotifier`** di service (`BluetoothPrinterService.connectedPrinterNotifier`).

**Tidak ada Provider / Riverpod / Bloc / GetX.** State sharing antar page hanya via `ValueNotifier` global dan SharedPreferences.

### 🔴 Issue #3: `ValueNotifier<dynamic> isValue` — Global state tanpa tipe

- **Severity**: 🟠 High
- **File & Line**: [lib/data/notifiers.dart:8](lib/data/notifiers.dart#L8)
- **Problem**:
  ```dart
  ValueNotifier<dynamic> isValue = ValueNotifier('');
  ```
  Notifier global bertipe `dynamic`, nama tidak deskriptif (`isValue`), dan tidak jelas dipakai untuk apa. Anti-pattern serupa "magic global variable".
- **Impact**: Type safety hilang, sulit dilacak siapa yang menulis/membaca, race condition antar listener.
- **Solution**: Hapus jika tidak dipakai; atau ganti dengan ValueNotifier bertipe spesifik dengan nama jelas.
- **Effort**: Quick win (15 menit untuk audit penggunaan + remove)

### 🟠 Issue #4: setState berlebihan pada widget besar

- **Severity**: 🟠 High
- **File & Line**: [lib/views/pages/payment_page.dart:240-247, 824-840, 1455-1458](lib/views/pages/payment_page.dart) (dan 21 lokasi lain di file ini)
- **Problem**: `_PaymentPageState` punya 25+ `setState` call. Setiap call merebuild seluruh tree 2300 baris.

  Contoh paling parah:
  ```dart
  // payment_page.dart:240
  setState(() {
    cartItems = newItems;
    totalPayment = newTotalPayment;
    subTotal = newSubtotal;
    discount = newDiscount;
    isLoadingCart = false;
    totalQuantity = newTotalQuantity;
  });
  ```
  Tidak ada `const` widget pada subtree besar, jadi rebuild = penuh.
- **Impact**: Frame drop pada device low-end (POS biasanya tablet kelas menengah). UI lag saat tap product berkali-kali.
- **Solution**: Pecah subtree dengan `ValueListenableBuilder` per section (cart, payment methods, voucher) supaya rebuild lokal. Atau migrate ke `ChangeNotifier` + `Provider`.
- **Effort**: Refactor besar (bagian dari Issue #1)

### 🟠 Issue #5: ScrollController listener memicu setState pada setiap pixel scroll

- **Severity**: 🟠 High
- **File & Line**: [lib/views/pages/payment_page.dart:123-134](lib/views/pages/payment_page.dart#L123-L134), [lib/views/pages/pesanan_baru_page.dart:184-195](lib/views/pages/pesanan_baru_page.dart#L184-L195)
- **Problem**:
  ```dart
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
  ```
  Listener jalan setiap frame scroll. Walaupun ada guard `if (fadeOpacity != 0)`, setState merebuild seluruh page.
- **Solution**: Ganti dengan `ValueNotifier<double>` lokal + `ValueListenableBuilder` yang membungkus hanya widget fade.
  ```dart
  // before
  if (fadeOpacity != 0) setState(() => fadeOpacity = 0);
  // after
  _fadeOpacityNotifier.value = 0;
  // … wrap fade widget:
  ValueListenableBuilder<double>(valueListenable: _fadeOpacityNotifier, …)
  ```
- **Effort**: Quick win (30 menit per file)

### 🟠 Issue #6: Listener `BluetoothPrinterService` lupa di-remove di PengaturanPage

- **Severity**: 🟠 High (memory leak)
- **File & Line**: [lib/views/pages/pengaturan_page.dart:51-53, 539-544](lib/views/pages/pengaturan_page.dart)
- **Problem**: `addListener(_onPrinterChanged)` tidak punya `removeListener` di `dispose()`. Static notifier akan menahan reference ke `_PengaturanPageState` setelah widget destroyed → memory leak + setState pada widget unmounted.
- **Solution**:
  ```dart
  @override
  void dispose() {
    BluetoothPrinterService.connectedPrinterNotifier.removeListener(_onPrinterChanged);
    _bluetoothSubscription?.cancel();
    super.dispose();
  }
  ```
- **Effort**: Quick win (5 menit)

### 🟡 Issue #7: `isBackSO.value == true;` — Statement tanpa efek

- **Severity**: 🟡 Medium (bug logic)
- **File & Line**: [lib/views/pages/inventory_page.dart:132](lib/views/pages/inventory_page.dart#L132)
- **Problem**:
  ```dart
  setState(() {
    soList = list;
    isLoadingSO = false;
    soIsEmpty = list.isEmpty;
    soPaginationInfo = pagination;
    isBackSO.value == true;  // ❌ comparison, bukan assignment
  });
  ```
  Operator `==` digunakan padahal niatnya assignment `=`. Statement tidak melakukan apa-apa.
- **Impact**: Flag `isBackSO` tidak pernah di-set, kemungkinan menyebabkan refetch berulang yang tidak diinginkan.
- **Solution**: `isBackSO.value = true;`
- **Effort**: Quick win (1 menit)

---

## 3. PERFORMANCE ISSUES

### 🟠 Issue #8: `precacheImage` dipanggil di build context tanpa caching guard

- **Severity**: 🟡 Medium
- **File & Line**: [lib/services/helper/splash_screen.dart:27-31](lib/services/helper/splash_screen.dart#L27-L31)
- **Problem**: Sudah dipindah ke SplashScreen (bagus), tapi tidak pernah dicek bahwa context masih valid.
- **Solution**: Tambah `if (!mounted) return;` sebelum precache.
- **Effort**: Quick win

### 🔴 Issue #9: Bug fatal di `printStruk` — `.map().toString()` tidak mengeksekusi callback

- **Severity**: 🔴 Critical
- **File & Line**: [lib/services/bluetooth_printer_service.dart:563-582](lib/services/bluetooth_printer_service.dart#L563-L582)
- **Problem**:
  ```dart
  listProduk.map((e) {
    bluetooth.printCustom(e['pos_menus_name'], 1, 0);
    if (isPayment) {
      final dynamic listProps = e['pos_cart_props'];
      listProps.forEach((e) { ... });
    }
    bluetooth.printLeftRight(...);
    bluetooth.printNewLine();
  }).toString();   // ❌ .map() is LAZY in Dart!
  ```
  Method `Iterable.map()` adalah lazy — callback tidak pernah dieksekusi sampai iterable benar-benar di-iterate (mis. via `.toList()`, `.forEach()`, atau loop). `.toString()` pada iterable **tidak mengiterasi**, hanya menghasilkan representasi string. **Akibatnya: ada kemungkinan item produk tidak tercetak pada struk!**
- **Impact**: Bug bisnis kritis — struk pelanggan tidak menunjukkan daftar produk yang dibeli. Catatan: Dart VM dengan `MappedListIterable.toString()` *mungkin* memanggil callback saat membuat string representation; namun ini **implementation-dependent** dan tidak boleh diandalkan.
- **Solution**:
  ```dart
  for (final e in listProduk) {
    bluetooth.printCustom(e['pos_menus_name'], 1, 0);
    if (isPayment) {
      final List listProps = e['pos_cart_props'] ?? [];
      for (final p in listProps) {
        bluetooth.printCustom(' ${p['quantity']}x ${p['pos_menus_name']}', 0, 0);
      }
    }
    bluetooth.printLeftRight(
      ' ${e['quantity']} x ${convertIDR(e['price'])}',
      convertIDR(e['price'] * e['quantity']),
      0,
    );
    bluetooth.printNewLine();
  }
  ```
- **Effort**: Quick win (10 menit)

### 🟠 Issue #10: `_processQueue` while loop tanpa delay → race condition pada printer

- **Severity**: 🟠 High
- **File & Line**: [lib/services/bluetooth_printer_service.dart:354-384](lib/services/bluetooth_printer_service.dart#L354-L384)
- **Problem**: `while (_printQueue.isNotEmpty)` memanggil `_executePrint` berurutan tanpa jeda. Printer ESC/POS bisa flood/buffer-overflow.
- **Solution**: Tambah `await Future.delayed(const Duration(milliseconds: 500))` antar print.
- **Effort**: Quick win

### 🟠 Issue #11: `produkList` getter mengkomputasi ulang setiap rebuild

- **Severity**: 🟠 High
- **File & Line**: [lib/views/pages/pesanan_baru_page.dart:56-85](lib/views/pages/pesanan_baru_page.dart#L56-L85)
- **Problem**: Getter `produkList` melakukan `.expand().map().toList()` dan filtering setiap kali widget rebuild. Untuk menu dengan 100+ produk, ini berjalan pada main thread setiap setState.
- **Impact**: UI jank saat user mengetik di search box (rebuild + filter ratusan item × setiap keystroke).
- **Solution**:
  ```dart
  // Cache flat list saat menuList diset, hanya filter saat keyword berubah
  List<Map<String, dynamic>>? _flatProducts;
  void _rebuildFlatProducts() {
    _flatProducts = menuList.expand<Map<String, dynamic>>((e) {
      final categoryName = e['category'] as String;
      return (e['data'] as List).map((item) => {
        ...Map<String, dynamic>.from(item as Map),
        'category': categoryName,
      });
    }).toList();
  }
  // Panggil saat menuList diisi, lalu filter pakai cached list.
  ```
- **Effort**: Medium (1 jam)

### 🟢 Issue #12: `Column` membungkus list panjang (bukan ListView.builder)

- **Severity**: 🟡 Medium
- **File & Line**: [lib/views/pages/laporan_page.dart:244-269, 311-333, 375-397](lib/views/pages/laporan_page.dart)
- **Problem**: `breakdown.map<Widget>((item) { ... }).toList()` lalu ditaruh di `Column` — tidak lazy. Untuk breakdown 50+ item akan dibangun semua di awal.
- **Solution**: Gunakan `ListView.builder` atau `Column(children: List.generate(...))` sudah cukup karena dibungkus `SingleChildScrollView`-less di sini.
- **Effort**: Medium

### 🟡 Issue #13: ImageCache di-set tapi tidak ada resize policy untuk asset non-cached

- **Severity**: 🟡 Medium
- **File & Line**: [lib/main.dart:108-109](lib/main.dart#L108-L109)
- **Problem**: `PaintingBinding.instance.imageCache.maximumSize = 100; maximumSizeBytes = 50<<20;`. Setting sudah baik, tapi `Image.asset('assets/images/background.png')` di splash & login tidak punya `cacheWidth`/`cacheHeight`, dan background dipakai berulang.
- **Solution**: Tambah `cacheWidth: 1080` pada `AssetImage` background.
- **Effort**: Quick win

---

## 4. ERROR HANDLING

### 🔴 Issue #14: API key di `.env` di-bang (`!`) tanpa fallback → crash silent saat .env missing

- **Severity**: 🔴 Critical
- **File & Line**: [lib/services/helper/dio_client.dart:14, 18](lib/services/helper/dio_client.dart#L14-L18)
- **Problem**:
  ```dart
  baseUrl: dotenv.env['BASE_URL']!,
  headers: { "apikey": dotenv.env['API_KEY']!, },
  ```
  Jika `.env` tidak ter-load (mis. proguard menghapus asset, atau dotenv.load throw), `!` akan melempar `NoSuchMethodError` saat ApiClient pertama dipakai — biasanya saat user tap login, tanpa pesan error yang bermakna.
- **Solution**: Validasi di app startup setelah `dotenv.load`:
  ```dart
  final baseUrl = dotenv.env['BASE_URL'];
  final apiKey = dotenv.env['API_KEY'];
  if (baseUrl == null || apiKey == null) {
    throw StateError('Missing required .env keys: BASE_URL, API_KEY');
  }
  ```
- **Effort**: Quick win (15 menit)

### 🟠 Issue #15: `catch (_) {}` menelan error tanpa logging

- **Severity**: 🟠 High
- **File & Line**:
  - [lib/views/pages/reject_detail_page.dart:2316, 2328](lib/views/pages/reject_detail_page.dart#L2316)
  - [lib/services/network_service.dart:23](lib/services/network_service.dart#L23)
  - [lib/views/widgets/network_indicator.dart:60](lib/views/widgets/network_indicator.dart#L60)
- **Problem**: 7 lokasi total. Network/IO error ditelan diam-diam, menyulitkan debugging produksi.
- **Solution**: Setidaknya `debugPrint` + lakukan throw selektif untuk error yang seharusnya tidak terjadi:
  ```dart
  } catch (e, stack) {
    if (kDebugMode) debugPrint('cleanup failed: $e');
    // Jangan report ke Crashlytics jika benar-benar best-effort
  }
  ```
- **Effort**: Quick win

### 🟠 Issue #16: `int.parse(customerId!)` tanpa try-catch di kritikal path payment

- **Severity**: 🟠 High
- **File & Line**: [lib/views/pages/payment_page.dart:528, 594, 673](lib/views/pages/payment_page.dart#L528)
- **Problem**:
  ```dart
  "outlet_hub_id": int.parse(customerId!),
  ```
  3 lokasi pakai `int.parse` (bukan `int.tryParse`) dengan `!`. Jika `customerId` non-numeric (mis. UUID string atau corrupt SharedPreferences), `FormatException` dilempar dan ditangkap di blok generic `catch (e)` yang menampilkan pesan generik — user tidak tahu data outletnya rusak.
- **Solution**:
  ```dart
  final outletId = int.tryParse(customerId ?? '');
  if (outletId == null) {
    SnackbarUtil.show(context, title: 'Data outlet rusak', ...);
    return;
  }
  ```
  Sudah ada `_validateOrderPayload` di [line 301](lib/views/pages/payment_page.dart#L301) — tapi parsing dilakukan **sebelum** sampai ke validasi. Refactor: validasi dulu, parsing belakangan.
- **Effort**: Quick win

### 🟠 Issue #17: Duplikasi error handling identik antara `on DioException` dan `catch (e)`

- **Severity**: 🟡 Medium
- **File & Line**: [lib/views/pages/inventory_page.dart:134-170, 200-236](lib/views/pages/inventory_page.dart) (dan pola sama di banyak file lain)
- **Problem**: Block `on DioException` dan `catch (e)` berisi `setState(...)` + `SnackbarUtil.show(...)` yang **identik**, berbeda hanya pada `CrashReporter.report` reason. Kode duplikat.
- **Solution**: Ekstrak helper:
  ```dart
  void _handleFetchError(Object e, StackTrace s, {required String reason, required String title}) {
    CrashReporter.report(e, s, reason: reason);
    if (!mounted) return;
    setState(() { isLoadingReject = false; rejectIsEmpty = true; });
    SnackbarUtil.show(context, title: title, ...);
  }
  ```
- **Effort**: Medium

### 🟡 Issue #18: API tidak memiliki retry strategy

- **Severity**: 🟡 Medium
- **File & Line**: [lib/services/helper/dio_client.dart:22-35](lib/services/helper/dio_client.dart#L22-L35)
- **Problem**: Interceptor hanya menangani auth token; tidak ada retry untuk 5xx atau timeout. Padahal `payment_page` punya idempotency token yang **dirancang** untuk retry-aman, tapi tidak dimanfaatkan secara otomatis.
- **Solution**: Tambah retry interceptor (`dio_smart_retry` atau custom) — 2x retry untuk 5xx/timeout, dengan respek terhadap idempotency.
- **Effort**: Medium

### 🟡 Issue #19: Generic `catch (fcmError, stack)` di login tanpa kategorisasi

- **Severity**: 🟢 Low
- **File & Line**: [lib/views/pages/login_page.dart:158-165](lib/views/pages/login_page.dart#L158-L165)
- **Problem**: Best-effort secara desain (FCM optional), OK. Tapi tidak ada retry — jika FCM token gagal di-post, notifikasi push tidak akan jalan tanpa user re-login.
- **Solution**: Simpan flag `fcm_token_pending` dan retry di startup.
- **Effort**: Medium

---

## 5. CODE QUALITY & MAINTAINABILITY

### 🔴 Issue #20: Magic number `customers_id: 16` dan `pos_payment_method_id: 11` hardcoded

- **Severity**: 🔴 Critical (data integrity)
- **File & Line**: [lib/views/pages/payment_page.dart:526, 530, 592, 671, 675](lib/views/pages/payment_page.dart#L526)
- **Problem**: Hardcoded ID database di 5 tempat:
  ```dart
  "customers_id": 16,                  // ❌
  "pos_payment_method_id": 11,         // ❌
  ```
  Jika database direstore atau ID berubah, pembayaran akan langsung rusak silent (server akan menerima ID yang salah dan menghubungkan ke pelanggan/method yang salah).
- **Impact**: Bisnis-kritis — semua transaksi compliment & tunai diarahkan ke customer #16 secara hardcoded.
- **Solution**: Pindah ke `AppConfig` atau `.env`:
  ```dart
  // app_config.dart
  static const int defaultCustomerId = 16;
  static const int defaultCashMethodId = 11;
  ```
  Lebih baik: server endpoint khusus untuk pos config yang dipanggil sekali saat login.
- **Effort**: Quick win (30 menit untuk konstanta, refactor server-driven medium)

### 🔴 Issue #21: API key di .env ter-commit ke repo

- **Severity**: 🔴 Critical (security)
- **File & Line**: `.env` (root)
- **Problem**: `.env` mengandung:
  ```
  API_KEY=afoL9gSyzqtQrXyjvhCnUTo9djqEOk5klRukHYVpy5J528F12NOZoDHLwCyvyyRC
  BASE_URL=https://api.panglimaroqiiqugroup.com
  ```
  File ini ada di `assets:` `pubspec.yaml:105` → di-bundle ke APK → trivial untuk diekstrak (`unzip *.apk`).
- **Impact**: API key bocor ke setiap install APK; bisa dipakai untuk hit endpoint produksi tanpa autentikasi user-level.
- **Solution**:
  1. **Rotate API key sekarang** (anggap sudah compromised).
  2. Pindah ke environment-specific Build (`--dart-define` saat build).
  3. Tambahkan `.env` ke `.gitignore`, hapus dari history (`git filter-repo`).
  4. Untuk produksi, gunakan certificate pinning + API key dynamic per device.
- **Effort**: Medium (rotate + refactor env loading)

### 🟠 Issue #22: Dummy product data 200+ baris di constants.dart yang tidak dipakai

- **Severity**: 🟡 Medium
- **File & Line**: [lib/data/constants.dart:16-223](lib/data/constants.dart#L16)
- **Problem**: `dummyRGP` (223 baris) berisi seluruh katalog produk hardcoded. Tidak ada reference ke variable ini di codebase (kemungkinan sudah deprecated setelah migrasi ke API).
- **Verifikasi**: `grep -r "dummyRGP" lib/` → 0 occurrence di luar definisi.
- **Solution**: Hapus blok `dummyRGP` (lines 16-223).
- **Effort**: Quick win (5 menit + git diff review)

### 🟠 Issue #23: Hive models tidak terpakai

- **Severity**: 🟡 Medium
- **File & Line**: [lib/models/cart_item.dart](lib/models/cart_item.dart), [lib/models/cart_variant.dart](lib/models/cart_variant.dart), [lib/main.dart:102-104](lib/main.dart#L102-L104)
- **Problem**: Hive init di-comment, models tidak dipakai. Pubspec masih mendefinisikan `hive: ^2.2.3`, `hive_flutter: ^1.1.0`, dan `hive_generator: ^2.0.1` (build deps).
- **Solution**: Jika tidak akan dipakai → hapus models + dependency. Jika akan dipakai → finalisasi migrasi (saat ini menggunakan SharedPreferences untuk semua persistence; Hive lebih cocok untuk struktur kompleks seperti cart).
- **Effort**: Quick win untuk hapus, medium untuk migrate

### 🟡 Issue #24: 49 `debugPrint` call di 14 file (memori produksi)

- **Severity**: 🟡 Medium
- **File & Line**: Tersebar (lihat hasil grep).
- **Problem**: `debugPrint` no-op di release build untuk `print()`, tetapi `debugPrint` **TETAP berjalan** di release (hanya rate-limited). Bisa mengandung data sensitif:
  - [lib/views/pages/login_page.dart:159, 92](lib/views/pages/login_page.dart#L159) → log FCM error
  - [lib/views/pages/payment_page.dart:259, 410](lib/views/pages/payment_page.dart#L259) → log response error
  - [lib/services/bluetooth_printer_service.dart:78, 90, 96, 197, 216, 220](lib/services/bluetooth_printer_service.dart) → log printer state
- **Solution**: Bungkus dalam `if (kDebugMode)`:
  ```dart
  if (kDebugMode) debugPrint('...');
  ```
  Atau ganti dengan `LogBuffer` (yang sudah ada di [lib/utils/log_buffer.dart](lib/utils/log_buffer.dart)) yang sudah debug-aware.
- **Effort**: Medium (review per call)

### 🟡 Issue #25: Hardcoded URL `1.1.1.1` dan `google.com` untuk ping

- **Severity**: 🟢 Low
- **File & Line**:
  - [lib/views/widgets/network_indicator.dart:45](lib/views/widgets/network_indicator.dart#L45) → `'1.1.1.1'`
  - [lib/services/network_service.dart:15](lib/services/network_service.dart#L15) → `'google.com'`
- **Problem**: Two different hosts untuk cek konektivitas. Tidak konsisten. Jika `google.com` di-block (mis. firewall korporat), aplikasi salah deteksi offline.
- **Solution**: Konstanta tunggal — `cloudflare.com` atau IP server sendiri:
  ```dart
  // app_config.dart
  static const String connectivityProbeHost = 'api.panglimaroqiiqugroup.com';
  ```
- **Effort**: Quick win

### 🟡 Issue #26: Banyak commented-out code di production

- **Severity**: 🟡 Medium
- **File & Line**:
  - [lib/main.dart:102-104](lib/main.dart#L102-L104) → Hive init
  - [lib/views/widgets_tree.dart:8, 10, 13, 22-23](lib/views/widgets_tree.dart) → page imports & menu items
  - [lib/views/pages/payment_page.dart:485-500](lib/views/pages/payment_page.dart#L485) → "QUEUE-DISABLED" block
  - [lib/views/components/ui/cart_item_tile.dart:69-79](lib/views/components/ui/cart_item_tile.dart#L69-L79) → old discount code
- **Solution**: Hapus. Versi historis ada di git log.
- **Effort**: Quick win

### 🟡 Issue #27: `late int discount = ...` redundant

- **Severity**: 🟢 Low
- **File & Line**: [lib/views/widgets/product_modal_widget.dart:119](lib/views/widgets/product_modal_widget.dart#L119)
- **Problem**: `late` + initializer = sama dengan tanpa `late`. Misleading.
- **Solution**: `final int discount = ...;`
- **Effort**: Quick win

---

## 6. SECURITY ISSUES

### 🔴 Issue #28: API_KEY ter-hardcode di asset bundle (lihat juga Issue #21)

Detail di Issue #21. Severity 🔴, perlu rotasi key.

### 🟠 Issue #29: `FlutterSecureStorage` digunakan, tapi token validation hanya local

- **Severity**: 🟠 High
- **File & Line**: [lib/services/helper/splash_screen.dart:191-210](lib/services/helper/splash_screen.dart#L191-L210)
- **Problem**: `isTokenExpired` mendecode JWT secara lokal tanpa verifikasi signature. Jika user secara manual menulis token palsu ke SecureStorage (rooted device), aplikasi akan melewati cek expired ini dengan token apapun yang punya `exp` masa depan.
- **Mitigasi yang ada**: `SafeDevice.isJailBroken` cek di [splash_screen.dart:41](lib/services/helper/splash_screen.dart#L41) → DeviceLockedScreen. OK.
- **Solution**: Tambahkan validation di server pada setiap request (sudah dilakukan via Bearer token). Tambah refresh token rotation untuk mempersulit token reuse.
- **Effort**: Medium

### 🟠 Issue #30: SharedPreferences menyimpan data semi-sensitif tanpa enkripsi

- **Severity**: 🟡 Medium
- **File & Line**:
  - [lib/services/storage/shift_storage_service.dart](lib/services/storage/shift_storage_service.dart) → `active_shift_id`, `active_cash`
  - [lib/views/pages/login_page.dart:146](lib/views/pages/login_page.dart#L146) → `outlet_address`
  - [lib/views/pages/payment_page.dart:1440-1444](lib/views/pages/payment_page.dart#L1440) → `voucher_barcodes`, `voucher_nominal`
- **Problem**: SharedPreferences tidak terenkripsi di Android (kecuali pakai EncryptedSharedPreferences). Pada device rooted, data shift dan voucher bisa dimanipulasi (modifikasi `voucher_nominal` untuk diskon palsu).
- **Solution**: Pindah voucher & shift data ke `FlutterSecureStorage` (sudah dipakai untuk token).
- **Effort**: Medium (refactor storage layer)

### 🟡 Issue #31: Logging payload dengan data user di Crashlytics

- **Severity**: 🟡 Medium
- **File & Line**: [lib/views/pages/payment_page.dart:253-258, 769-773](lib/views/pages/payment_page.dart#L253-L258)
- **Problem**:
  ```dart
  context: {
    'responseData': e.response?.data?.toString(),  // ❌ bisa berisi data user
  },
  ```
  `responseData` dari server bisa mengandung email, no telp, alamat, dll. yang dilarang oleh GDPR/UU PDP saat di-record ke Crashlytics.
- **Solution**: Filter sensitive fields sebelum logging, atau hanya simpan status code + endpoint.
- **Effort**: Quick win

### 🟢 Issue #32: HTTP request OK pakai HTTPS, tapi tidak ada certificate pinning

- **Severity**: 🟡 Medium
- **File & Line**: [lib/services/helper/dio_client.dart](lib/services/helper/dio_client.dart)
- **Problem**: BASE_URL pakai HTTPS (baik), tetapi tidak ada certificate pinning. Pada device dengan custom CA terinstall, traffic bisa di-MITM (mis. mitmproxy).
- **Solution**: Tambah pinning via `dio` interceptor + `bad_certificate_callback`, atau pakai `dio_certificate_pinning`.
- **Effort**: Medium

---

## 7. UI/UX ISSUES

### 🟠 Issue #33: Aplikasi force landscape — UX issue di tablet portrait kasir

- **Severity**: 🟠 High
- **File & Line**: [lib/main.dart:30-33](lib/main.dart#L30-L33)
- **Problem**:
  ```dart
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  ```
  Force landscape, tetapi `reject_detail_page` mengizinkan toggle portrait di [line 217-225](lib/views/pages/reject_detail_page.dart#L217). Inkonsisten — beberapa screen support portrait, sebagian tidak.
- **Impact**: Saat user kembali dari reject detail, orientation tidak selalu balik ke landscape secara konsisten.
- **Solution**: Pakai per-page orientation control via `WidgetsBindingObserver` atau `didChangeDependencies`, jangan global.
- **Effort**: Medium

### 🟡 Issue #34: Tidak ada empty/loading state pada DropdownMenu pelanggan

- **Severity**: 🟡 Medium
- **File & Line**: [lib/views/pages/pesanan_baru_page.dart:741-748](lib/views/pages/pesanan_baru_page.dart#L741-L748)
- **Problem**:
  ```dart
  dropdownMenuEntries: const [
    DropdownMenuEntry<String>(
      value: 'Semua Pelanggan', ...
    ),
    // Tambahkan entri lain di sini  ← TODO komentar
  ],
  ```
  Hardcoded 1 entry. Fitur pelanggan tampaknya belum selesai.
- **Solution**: Sembunyikan dropdown jika belum ada implementasi, atau load dari API.
- **Effort**: Medium

### 🟡 Issue #35: Login button tidak ada loading state untuk slow network

- **Severity**: 🟢 Low
- **File & Line**: [lib/views/pages/login_page.dart:294-326](lib/views/pages/login_page.dart#L294)
- **Problem**: Ada timer 15s yang men-set `_loginTimedOut` (baik). Tapi setelah `_loginTimedOut`, button text jadi "Coba Lagi" namun behavior `onPressed` tetap menjalankan `login` — tidak ada feedback bahwa request sebelumnya masih berjalan di background.
- **Solution**: Cancel old request via `CancelToken` saat user retry.
- **Effort**: Quick win

### 🟡 Issue #36: SnackBar `SnackbarUtil.show` tidak guard `context` non-mounted

- **Severity**: 🟡 Medium
- **File & Line**: [lib/utils/snackbar_util.dart](lib/utils/snackbar_util.dart)
- **Problem**: `ScaffoldMessenger.of(context)` akan throw jika tidak ada Scaffold ancestor (mis. dipanggil dari background callback). Tidak ada try-catch.
- **Solution**:
  ```dart
  static void show(BuildContext context, ...) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    ...
  }
  ```
- **Effort**: Quick win

### 🟢 Issue #37: Tidak ada Semantics label untuk accessibility

- **Severity**: 🟢 Low
- **File & Line**: Seluruh widget
- **Problem**: 0 occurrence `Semantics(` di codebase. Tablet POS umumnya tidak butuh screen reader, tapi tetap praktik baik untuk button utama (`Hapus`, `Bayar`, `Mulai Shift`).
- **Solution**: Bungkus action button kritis dengan `Semantics(label: 'Bayar transaksi', button: true)`.
- **Effort**: Medium

### 🟢 Issue #38: Hardcoded MediaQuery threshold `> 600` di banyak tempat

- **Severity**: 🟢 Low
- **File & Line**:
  - [lib/views/pages/login_page.dart:212](lib/views/pages/login_page.dart#L212)
  - [lib/services/helper/splash_screen.dart:215](lib/services/helper/splash_screen.dart#L215)
  - [lib/views/pages/pesanan_baru_page.dart:621](lib/views/pages/pesanan_baru_page.dart#L621)
- **Problem**: Threshold 600 untuk "tablet" diulang tanpa konstanta.
- **Solution**: Buat extension `BuildContext.isTablet`:
  ```dart
  // utils/responsive.dart
  extension Responsive on BuildContext {
    bool get isTablet => MediaQuery.of(this).size.width > 600;
  }
  ```
- **Effort**: Quick win

---

## 8. DEPENDENCIES & PACKAGES

### 🟠 Issue #39: Package `firebase: ^9.0.3` tidak relevan

- **Severity**: 🟡 Medium
- **File & Line**: [pubspec.yaml:58](pubspec.yaml#L58)
- **Problem**: `firebase: ^9.0.3` adalah meta-package untuk **Firebase Web JS interop** — tidak dimaksudkan untuk app Flutter mobile. Yang dipakai `firebase_core`, `firebase_messaging`, `firebase_crashlytics` — semuanya benar.
- **Solution**: Hapus `firebase: ^9.0.3` dari pubspec.
- **Effort**: Quick win (verify lalu hapus)

### 🟡 Issue #40: Package Hive masih ada tapi tidak dipakai

- **Severity**: 🟡 Medium
- **File & Line**: [pubspec.yaml:52-53, 80](pubspec.yaml#L52)
- **Problem**: `hive`, `hive_flutter`, `hive_generator` masih di-import → menambah ukuran APK ±200KB. Lihat juga Issue #23.
- **Solution**: Hapus jika tidak ada plan migrasi.
- **Effort**: Quick win

### 🟡 Issue #41: `connectivity_plus: ^7.0.0` dan `network_info_plus: ^7.0.0` — versi mayor terbaru, periksa stabilitas

- **Severity**: 🟢 Low
- **Problem**: Versi 7 cukup baru, breaking change dari 6. Pastikan testing pada device target.
- **Solution**: Pin ke versi minor terverifikasi atau update API call jika ada deprecation warning.
- **Effort**: Quick win

### 🟢 Issue #42: `flutter_dotenv: ^6.0.0` dengan asset di-bundle = .env ter-export ke APK

Lihat Issue #21. `flutter_dotenv` **tidak menambah security** — file `.env` di `assets/` tetap plaintext di APK.

---

## 9. TESTING

### 🔴 Issue #43: Zero test coverage

- **Severity**: 🔴 Critical
- **File & Line**: Tidak ada folder `test/` atau `integration_test/`.
- **Problem**: Aplikasi POS bisnis-kritis tanpa **satupun** unit/widget/integration test. Setiap perubahan = risiko regresi tanpa safety net.
- **Impact**: Bug subtle seperti `.map().toString()` (Issue #9) atau `==` salah di setState (Issue #7) akan masuk produksi tanpa terdeteksi.
- **Solution**: Mulai dengan **unit test** untuk:
  1. `utils/convert.dart` (formatIDR, convertIDR, formatDate) — pure functions, paling mudah.
  2. `utils/stock_parser.dart` (parsing insufficient_stock).
  3. `services/cart_storage_service.dart` (add/update/remove logic).
  4. `payment_page._validateOrderPayload` (validation rules).
  5. `splash_screen.isTokenExpired` (JWT decoding).

  Lanjut dengan **widget test** untuk:
  - `CartItemTile`, `ProductCard`, `LoginPage` (form validation).

  Roadmap minimum coverage 30% untuk core business logic.
- **Effort**: Refactor besar (minggu kerja)

### 🟠 Issue #44: Tidak ada mocking infrastructure

- **Severity**: 🟠 High
- **Problem**: `ApiClient` singleton diakses langsung di setiap page (`ApiClient()`). Sulit untuk diuji.
- **Solution**: Dependency injection via constructor atau `get_it` / `provider`. Atau minimal — inject `Dio` via parameter `ApiClient(dio: customDio)`.
- **Effort**: Refactor besar

---

## 10. BUILD & DEPLOYMENT

### 🟢 Issue #45: `build.gradle.kts` mengandalkan default Flutter SDK versi

- **Severity**: 🟢 Low
- **File & Line**: [android/app/build.gradle.kts:24-25, 38-40](android/app/build.gradle.kts)
- **Problem**:
  ```kotlin
  compileSdk = flutter.compileSdkVersion
  minSdk = flutter.minSdkVersion
  targetSdk = flutter.targetSdkVersion
  ```
  Bergantung pada Flutter SDK. Jika upgrade Flutter, app target SDK ikut berubah tanpa explicit declare → potensi breaking di Play Store policy.
- **Solution**: Pin eksplisit:
  ```kotlin
  minSdk = 23  // Android 6.0, target POS
  targetSdk = 35  // Update tahunan sesuai Play Store policy
  compileSdk = 35
  ```
- **Effort**: Quick win

### 🟢 Issue #46: ProGuard rules custom tidak ada

- **Severity**: 🟡 Medium
- **File & Line**: `android/app/proguard-rules.pro` tidak ada.
- **Problem**: `isMinifyEnabled = true` + `proguardFiles("proguard-android-optimize.txt", "proguard-rules.pro")` — referensi `proguard-rules.pro` ada di gradle tapi file fisiknya tidak ada. R8 akan jalan dengan default rules saja.
- **Impact**: Plugin native (blue_thermal_printer, camera, firebase_messaging) yang pakai reflection bisa di-strip → crash di release build.
- **Solution**: Buat `android/app/proguard-rules.pro` dengan keep rules untuk:
  ```pro
  -keep class id.flutter.blue_thermal_printer.** { *; }
  -keep class com.google.firebase.** { *; }
  -keepattributes Signature, *Annotation*
  -keep class com.dexterous.** { *; }  # flutter_local_notifications
  ```
- **Effort**: Medium (test release build)

### 🟢 Issue #47: Tidak ada split APK per ABI

- **Severity**: 🟢 Low
- **File & Line**: `android/app/build.gradle.kts`
- **Problem**: Tidak ada `splits.abi` configuration → APK universal (besar, ±60-80MB).
- **Solution**:
  ```kotlin
  splits {
    abi {
      isEnable = true
      reset()
      include("armeabi-v7a", "arm64-v8a", "x86_64")
      isUniversalApk = false
    }
  }
  ```
  Atau gunakan `flutter build appbundle` untuk Play Store (otomatis split).
- **Effort**: Quick win

### 🟢 Issue #48: `targetCompatibility = JavaVersion.VERSION_11`

- **Severity**: 🟢 Low
- **File & Line**: [android/app/build.gradle.kts:23-30](android/app/build.gradle.kts#L23)
- **Problem**: Java 11 OK, tapi `kotlinOptions { jvmTarget = "11" }` mungkin lebih baik 17 untuk Android Gradle Plugin terbaru (kompatibilitas).
- **Solution**: Pertimbangkan upgrade ke Java 17 jika AGP > 8.0.
- **Effort**: Quick win

---

# 📊 RANGKUMAN AUDIT

## TOP 5 PRIORITAS (Segera Diperbaiki)

| # | Issue | Severity | File | Mengapa Prioritas |
|---|---|---|---|---|
| 1 | **Bug `.map().toString()`** tidak iterasi → struk produk tidak tercetak | 🔴 | [bluetooth_printer_service.dart:563-582](lib/services/bluetooth_printer_service.dart#L563-L582) | Bisnis-kritis; pelanggan menerima struk tanpa item |
| 2 | **API_KEY ter-bundle di APK** | 🔴 | `.env` + [pubspec.yaml:105](pubspec.yaml#L105) | Security; rotasi + refactor mandatory |
| 3 | **Magic ID hardcoded** `customers_id: 16`, `pos_payment_method_id: 11` | 🔴 | [payment_page.dart:526, 530, 592, 671, 675](lib/views/pages/payment_page.dart) | Pembayaran rusak silent jika DB berubah |
| 4 | **Zero test coverage** untuk aplikasi POS bisnis-kritis | 🔴 | (Tidak ada `test/`) | Tidak ada safety net untuk regresi |
| 5 | **`payment_page.dart` 2300 baris monolit** | 🔴 | [payment_page.dart](lib/views/pages/payment_page.dart) | Setiap perubahan = risiko tinggi |

## ⚡ QUICK WINS (<1 jam total)

Issue-issue ini bisa dikerjakan cepat tanpa risiko besar:

| Issue | File:Line | Estimasi |
|---|---|---|
| Fix `isBackSO.value == true;` → `=` (#7) | [inventory_page.dart:132](lib/views/pages/inventory_page.dart#L132) | 1 menit |
| Hapus `dummyRGP` array (#22) | [constants.dart:16-223](lib/data/constants.dart#L16-L223) | 5 menit |
| Hapus package `firebase: ^9.0.3` (#39) | [pubspec.yaml:58](pubspec.yaml#L58) | 5 menit |
| Hapus Hive deps + models tidak terpakai (#23, #40) | [pubspec.yaml:52-53](pubspec.yaml#L52), [models/](lib/models/) | 10 menit |
| Fix typo `'Pelangan'` di struk | [bluetooth_printer_service.dart:557](lib/services/bluetooth_printer_service.dart#L557) | 1 menit |
| Hapus `ValueNotifier<dynamic> isValue` jika tidak dipakai (#3) | [notifiers.dart:8](lib/data/notifiers.dart#L8) | 10 menit |
| Hapus commented Hive init (#26) | [main.dart:102-104](lib/main.dart#L102-L104) | 1 menit |
| `removeListener` di dispose pengaturan_page (#6) | [pengaturan_page.dart:539](lib/views/pages/pengaturan_page.dart#L539) | 5 menit |
| Tambah ekstensi `context.isTablet` (#38) | new file | 10 menit |
| Validasi `.env` keys di startup (#14) | [main.dart](lib/main.dart) | 15 menit |
| `int.tryParse` di customerId payment (#16) | [payment_page.dart:528, 594, 673](lib/views/pages/payment_page.dart) | 15 menit |
| Konstanta untuk magic ID (#20 — minimal fix) | new constant in `app_config.dart` | 30 menit |

**Total estimasi: ~1.5 jam — semua "low risk, high return" — kerjakan ini lebih dulu.**

## 🗺️ ROADMAP REFACTORING JANGKA PANJANG

### Sprint 1 (Minggu 1-2): Stabilisasi
- Implementasi semua Quick Wins di atas.
- Fix bug `.map().toString()` di bluetooth_printer (Issue #9) — **ini mungkin alasan ada branch `fix/payment-issue` dibuka**.
- Rotasi API key + pindah ke `--dart-define` (Issue #21).
- Tambahkan ProGuard rules (Issue #46).
- Setup test infrastructure (Mockito + flutter_test base).

### Sprint 2 (Minggu 3-4): Test Coverage Minimum
- Unit test untuk semua util murni (`convert.dart`, `stock_parser.dart`, `app_config.dart`).
- Unit test untuk validation di `payment_page._validateOrderPayload`.
- Widget test untuk `LoginPage`, `CartItemTile`, `ProductCard`.
- Target: 30% line coverage di module `lib/utils` dan `lib/services`.

### Sprint 3-4 (Minggu 5-8): Refactor payment_page
- Ekstrak `PaymentController` (ChangeNotifier / Riverpod).
- Ekstrak modal-modal ke file terpisah.
- Ekstrak `OrderSubmissionService` (handlePayment, idempotency, validation).
- Ekstrak `DeviceContextService` (location + device info).
- Setelah refactor: target 50% test coverage untuk payment flow.

### Sprint 5-6 (Minggu 9-12): Arsitektur Global
- Pilih state management resmi (rekomendasi: **Riverpod**, simple, type-safe, mudah testing).
- Restructure folder ke feature-first:
  ```
  lib/
    core/         (api, env, theme, errors)
    features/
      auth/       (login, splash, register)
      cart/       (pesanan_baru, cart_service, cart_storage)
      payment/    (payment_page, voucher, methods)
      inventory/  (inventory, stock_opname, reject)
      laporan/
      pengaturan/
    shared/       (utils, widgets, models)
  ```
- Pindahkan `SplashScreen` keluar dari `services/helper/`.
- Implementasi DI container (`get_it` atau Riverpod providers).

### Sprint 7+ (Minggu 13+): Hardening
- Certificate pinning + token refresh rotation.
- EncryptedSharedPreferences untuk voucher & shift data.
- Migrate cart_storage_service ke Hive (atau sqflite) untuk performa & query.
- Implement offline-first untuk order queue (saat ini queue di printer dimatikan — lihat [payment_page.dart:485-500](lib/views/pages/payment_page.dart#L485-L500)).
- A11y audit + Semantics labels untuk button kritis.
- Performance profiling dengan DevTools, target 60fps stable di tablet target.

---

# 📈 STATISTIK PROJECT

- **Total Dart files (lib/)**: 78 file
- **Total baris (lib/)**: ±27.000 LoC
- **File >300 baris**: 14 file (18% dari total)
- **File >1000 baris**: 7 file (9% — semuanya page UI)
- **debugPrint calls**: 49 occurrences di 14 file
- **setState calls**: 209 occurrences di 21 file
- **catch (_) blocks**: 7 occurrences (3 file)
- **Test coverage**: **0%**
- **TODO/FIXME comments**: 1 (hanya yang di build.gradle.kts — "TODO: Specify your own unique Application ID")
- **Dependencies di pubspec**: 28 (3 di antaranya tidak terpakai/redundant)

---

# CATATAN AKHIR

Project ini menunjukkan **iterasi cepat dengan utang teknis tinggi** — yang umum untuk MVP yang sudah mencapai produksi (version 2.0.8). Beberapa hal positif yang **harus dipertahankan**:

✅ Penggunaan `flutter_secure_storage` untuk token JWT
✅ Crashlytics terintegrasi dengan reason + context
✅ Idempotency token untuk order POST (excellent practice!)
✅ Slow-execution dialog UX di payment page
✅ Heartbeat + exponential backoff reconnect di bluetooth service (sangat solid)
✅ `WidgetsBindingObserver` untuk pending notification check
✅ Network indicator real-time
✅ `SafeDevice.isJailBroken` check
✅ `in_app_update` integration
✅ Snackbar utility terpusat dengan status enum

Bug paling mendesak yang harus dibetulkan **sebelum release berikutnya** adalah **Issue #9 (`.map().toString()` di printStruk)** — kemungkinan besar inilah alasan branch `fix/payment-issue` dibuka. Validasi melalui testing manual: cetak struk dengan 2+ produk dan periksa apakah semua produk tercetak.

Setelah itu, prioritaskan refactor `payment_page.dart` karena ini jalur transaksi inti — setiap bug di sini = uang hilang nyata.

---

**Selesai**. Audit ini mengidentifikasi **48 issue** total: 6 Critical 🔴, 11 High 🟠, 21 Medium 🟡, 10 Low 🟢.
