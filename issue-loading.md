# Issue: Audit State Loading

> Daftar lengkap state loading di project, status implementasi, dan panduan perbaikan per item. Standar acuan: [network.md](network.md).
>
> Setiap item yang **Belum Implementasi** disertai langkah teknis yang bisa langsung dikerjakan junior programmer atau AI model murah tanpa perlu memahami konteks bisnis.

---

## Ringkasan Standar Wajib (acuan dari `network.md`)

Setiap state loading yang berinteraksi dengan jaringan **wajib** memenuhi 6 syarat berikut:

1. **Indikator visual** (spinner / shimmer / skeleton) saat loading aktif.
2. **Pengecekan `mounted`** sebelum setiap `setState()` pasca-await.
3. **Reset loading di `finally`** — bukan hanya di blok sukses.
4. **Timeout eksplisit** (gunakan `ModernLoading.timeout` / `SkeletonLoader timeout`, atau `.timeout(Duration(seconds: 15))` di service).
5. **Pesan error informatif** + tombol **Retry**.
6. **Disable tombol** saat aksi sedang berjalan (cegah race condition).

Komponen reusable yang sudah tersedia di project:
- [lib/utils/loader_utils.dart](lib/utils/loader_utils.dart) — `ModernLoading` (spinner + timeout + retry).
- [lib/utils/skeleton_loader.dart](lib/utils/skeleton_loader.dart) — kumpulan skeleton dengan timeout & retry.
- [lib/services/network_service.dart](lib/services/network_service.dart) — `NetworkService.isOnline()`.
- [lib/views/widgets/network_indicator.dart](lib/views/widgets/network_indicator.dart) — indikator status jaringan global.

---

## 1. Splash Screen — `checkLogin()`

**Lokasi:** [lib/services/helper/splash_screen.dart:36](lib/services/helper/splash_screen.dart#L36)

**Status:** Belum Implementasi

**Kondisi saat ini:**
- Spinner berputar dengan label "Memuat Data..." (tampilan oke).
- Tidak ada timeout — jika `UpdateService.check()`, `getToken()`, atau `getShiftId()` macet, splash bisa stuck selamanya.
- Tidak ada tombol retry saat gagal.
- Tidak ada error feedback ke user (semua error masuk Crashlytics tapi user tidak tahu).

**Langkah Implementasi:**

1. Tambahkan timer 15 detik di `initState()` setelah memanggil `checkLogin()`:
   ```dart
   Timer? _splashTimeout;

   @override
   void initState() {
     super.initState();
     WidgetsBinding.instance.addPostFrameCallback((_) {
       precacheImage(...);
       checkLogin();
       _splashTimeout = Timer(const Duration(seconds: 15), () {
         if (mounted) setState(() => _isTimedOut = true);
       });
     });
   }

   @override
   void dispose() {
     _splashTimeout?.cancel();
     super.dispose();
   }
   ```
2. Tambahkan field state: `bool _isTimedOut = false;`.
3. Pada `build()`, ganti widget spinner + label dengan kondisi:
   ```dart
   _isTimedOut
       ? _buildRetryBlock()  // pesan error + tombol "Coba Lagi"
       : _buildLoadingBlock(); // spinner existing
   ```
4. `_buildRetryBlock()` berisi `OutlinedButton.icon` yang `onPressed`-nya:
   ```dart
   setState(() => _isTimedOut = false);
   _splashTimeout?.cancel();
   checkLogin();
   _splashTimeout = Timer(const Duration(seconds: 15), ...);
   ```
5. Pada `checkLogin()`, hapus `Future.delayed(const Duration(seconds: 1))` di baris 37 — itu hanya menunda tanpa manfaat.
6. Pada `_maybePromptUpdate()`, bungkus `UpdateService.check()` dengan `.timeout(const Duration(seconds: 8), onTimeout: () => null)` agar tidak menyandera splash.

---

## 2. Login — Tombol Masuk

**Lokasi:** [lib/views/pages/login_page.dart:83](lib/views/pages/login_page.dart#L83)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- Pakai `ModernLoading` dengan `timeout: const Duration(seconds: 10)` di dalam tombol.
- `try/catch/finally` lengkap dengan reset `loading = false` di `finally`.
- `if (!mounted) return` sebelum setiap `setState` / `SnackbarUtil.show` / `Navigator`.
- Tombol di-`null`-kan saat loading (`onPressed: loading ? null : login`).

**Catatan minor:** Callback `onRetry: () {}` di [login_page.dart:272](lib/views/pages/login_page.dart#L272) masih kosong. Belum kritikal karena tombol login tetap bisa ditekan setelah loading reset.

---

## 3. Pesanan Baru — Loading Menu Produk

**Lokasi:** [lib/views/pages/pesanan_baru_page.dart:211](lib/views/pages/pesanan_baru_page.dart#L211)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- Pakai `SkeletonLoader.menuSkeleton(timeout: 10s, onRetry: ...)`.
- Reset `isLoadingMenu = false` saat sukses; saat error, snackbar tampil tapi `isLoadingMenu` tetap `true` → user akan melihat skeleton + timeout retry. Behavior ini disengaja dan benar.

---

## 4. Pesanan Baru — Aksi Cart (plus / minus / delete / add)

**Lokasi:** [lib/views/pages/pesanan_baru_page.dart:86-322](lib/views/pages/pesanan_baru_page.dart#L86-L322)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- Tidak ada per-tombol loading. User bisa tap berkali-kali → kirim banyak request paralel (race condition).
- `loadCart()` dipanggil silent (tanpa indikator).
- Tidak ada timeout / disable tombol.

**Langkah Implementasi:**

1. Tambahkan map state untuk track item yang sedang loading:
   ```dart
   final Set<int> _busyCartIds = {};
   ```
2. Bungkus tiap aksi (`_increaseQuantity`, `_decreaseQuantity`, `_deletedCartItem`) dengan guard:
   ```dart
   void _increaseQuantity(int id) async {
     if (_busyCartIds.contains(id)) return;
     setState(() => _busyCartIds.add(id));
     try {
       await cartService.plusCart(id);
       await loadCart();
     } on DioException catch (e, stack) {
       // ... handler existing
     } finally {
       if (mounted) setState(() => _busyCartIds.remove(id));
     }
   }
   ```
3. Di `CartItemTile`, terima prop `bool isBusy` lalu disable tombol & tampilkan mini-spinner saat `isBusy == true`. Edit pemanggilan di [pesanan_baru_page.dart:757-766](lib/views/pages/pesanan_baru_page.dart#L757-L766):
   ```dart
   CartItemTile(
     item: e,
     isBusy: _busyCartIds.contains(e['id']),
     onDelete: () => _deletedCartItem(e['id']),
     ...
   )
   ```
4. Untuk `savedToCart`, lakukan hal yang sama dengan `bool _isAddingToCart = false;` lalu disable `ProductCard.onTap` saat `true`.

---

## 5. Payment Page — Loading Awal (`isLoadingCart`, `isLoadingMethod`, `isLoadingUserId`)

**Lokasi:** [lib/views/pages/payment_page.dart:59-62](lib/views/pages/payment_page.dart#L59-L62)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- 3 flag loading terpisah, semuanya default `true`.
- Di [payment_page.dart:175](lib/views/pages/payment_page.dart#L175) (catch `loadCart`), `isLoadingCart` **tidak pernah** diset `false` → spinner bisa stuck saat error.
- Tidak ada timeout/retry pada loading awal.
- Tidak ada pengecekan `mounted` sebelum `setState` di beberapa cabang.

**Langkah Implementasi:**

1. Pada `loadCart()`, tambahkan reset di blok catch:
   ```dart
   } on DioException catch (e, stack) {
     // ... existing
     if (!mounted) return;
     setState(() => isLoadingCart = false);
     SnackbarUtil.show(...);
   }
   ```
2. Lakukan hal yang sama untuk `_methods()` dan `getProfile()` di file ini — pastikan `isLoadingMethod` dan `isLoadingUserId` selalu di-`false`-kan di catch.
3. Ganti placeholder `CircularProgressIndicator` (jika ada) dengan `ModernLoading` yang punya `onRetry`:
   ```dart
   ModernLoading(
     timeout: const Duration(seconds: 10),
     onRetry: () {
       setState(() {
         isLoadingCart = true;
         isLoadingMethod = true;
         isLoadingUserId = true;
       });
       loadCart();
       _methods();
       getProfile();
     },
   )
   ```
4. Bungkus tiap fungsi fetch dengan `try/finally` agar reset terjamin.

---

## 6. Payment Page — `handlePayment()` (Submit Transaksi)

**Lokasi:** [lib/views/pages/payment_page.dart:227](lib/views/pages/payment_page.dart#L227)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- Cek `NetworkService.isOnline()` sebelum kirim request.
- `Timer(const Duration(seconds: 15))` untuk dialog "Proses Lambat".
- Disable tombol via `isLoading`.
- Reset `isLoading = false` di `finally`.

**Catatan minor:** Pesan error 4xx/5xx belum dibedakan — saat ini semua error masuk ke handler generic. Bisa ditingkatkan dengan menambah switch `e.response?.statusCode`.

---

## 7. Riwayat Penjualan — List & Detail

**Lokasi:** [lib/views/pages/riwayat_penjualan_page.dart:75-164](lib/views/pages/riwayat_penjualan_page.dart#L75-L164)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- Skeleton sudah dipakai untuk list & detail.
- **Bug:** Di [riwayat_penjualan_page.dart:152](lib/views/pages/riwayat_penjualan_page.dart#L152), `isLoadingUserId = false` di-assign **tanpa `setState`** → widget tidak rebuild → spinner stuck saat error fetch profile.
- `_fetchOrderDetail` di catch tidak reset `isLoadingOrdersDetail` → spinner detail stuck.

**Langkah Implementasi:**

1. Edit baris 152 jadi:
   ```dart
   if (!mounted) return;
   setState(() => isLoadingUserId = false);
   ```
2. Di catch `_fetchOrderDetail()` baris 123-133, tambahkan reset:
   ```dart
   } catch (e, stack) {
     CrashReporter.report(...);
     if (!mounted) return;
     setState(() => isLoadingOrdersDetail = false);
     SnackbarUtil.show(...);
   }
   ```
3. Tambahkan `finally { if (mounted) setState(() => isLoadingOrdersList = false); }` di `_fetchOrders` untuk menjamin reset.

---

## 8. Laporan — Loading Data per Tab

**Lokasi:** [lib/views/pages/laporan_page.dart:93](lib/views/pages/laporan_page.dart#L93)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- Pakai `SkeletonLoader.detailLaporanSkeleton`.
- Reset `isLoadingData = false` di blok catch dengan `setState`.
- `mounted` di-check.

**Catatan minor:** Tidak ada `finally` — kalau ada throw di luar `Dio`, `isLoadingData` bisa tetap `true`. Tambahkan `finally { if (mounted) setState(() => isLoadingData = false); }` untuk safety.

---

## 9. Inventory Page — List Surat Jalan / SO / Reject

**Lokasi:** [lib/views/pages/inventory_page.dart:68-327](lib/views/pages/inventory_page.dart#L68-L327)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- 3 list (inventory transfer, stock opname, reject) masing-masing punya `isLoading*` + skeleton + reset di catch.
- `mounted` check ada di semua cabang.
- 404 ditangani khusus (set list kosong + empty state, bukan error).

**Catatan minor:** Tidak ada timeout/retry visual — saat ini hanya snackbar error. Pertimbangkan ganti `SkeletonLoader.detailInventorySkeleton` dengan param `onRetry` agar setelah timeout user bisa retry langsung dari UI (sudah didukung skeleton, tinggal kirim callback).

---

## 10. Stock Opname Detail — `fetchDetail`, `_saveDraft`, `_submit`

**Lokasi:** [lib/views/pages/stock_opname_page.dart:104](lib/views/pages/stock_opname_page.dart#L104)

**Status:** Belum Implementasi

**Kondisi saat ini:**
- `fetchDetail` punya `isLoading` dengan reset di catch — bagus.
- Tidak ada timeout/retry pada `isLoading` (cuma `CircularProgressIndicator` polos di build).
- `_saveDraft` dan `_submit` sudah pakai `try/catch/finally` + disable tombol — bagus.

**Langkah Implementasi:**

1. Ganti `CircularProgressIndicator` di build (saat `isLoading == true`) dengan:
   ```dart
   ModernLoading(
     timeout: const Duration(seconds: 10),
     onRetry: () {
       setState(() => isLoading = true);
       fetchDetail();
     },
   )
   ```
2. Tambahkan `finally` di `fetchDetail` agar reset terjamin saat exception tak terduga.

---

## 11. Reject Detail — `_loadRejectDetail`, `_fetchLampiran`, Submit

**Lokasi:** [lib/views/pages/reject_detail_page.dart:116](lib/views/pages/reject_detail_page.dart#L116)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- `_isLoadingDetail` dipakai dengan `CircularProgressIndicator` polos — tanpa timeout/retry.
- `_fetchLampiran` per item: ada spinner thumbnail (`isLoadingLampiran`), reset di catch — bagus.
- Submit punya `_submitTimeoutTimer` 15s + dialog timeout — bagus.
- Save draft & add line per item sudah `try/catch/finally`.

**Langkah Implementasi:**

1. Ganti spinner halaman di [reject_detail_page.dart:1344](lib/views/pages/reject_detail_page.dart#L1344) dengan:
   ```dart
   ModernLoading(
     timeout: const Duration(seconds: 10),
     onRetry: () {
       setState(() => _isLoadingDetail = true);
       _loadRejectDetail();
     },
   )
   ```
2. Pada `_fetchLampiran`, tambahkan timeout `.timeout(const Duration(seconds: 10))` pada call Dio agar tidak menggantung selamanya.
3. Tambahkan `if (!mounted) return;` setelah setiap `await` di `_loadRejectDetail` (sebagian sudah ada, audit ulang).

---

## 12. Pengaturan — `getProfile()`

**Lokasi:** [lib/views/pages/pengaturan_page.dart:514](lib/views/pages/pengaturan_page.dart#L514)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- **Bug:** di [pengaturan_page.dart:526](lib/views/pages/pengaturan_page.dart#L526), saat catch error, `isLoadingProfile = false` di-assign **tanpa `setState`** → widget tidak rebuild → spinner stuck.
- Tidak ada timeout/retry.

**Langkah Implementasi:**

1. Ganti baris 526:
   ```dart
   if (!mounted) return;
   setState(() => isLoadingProfile = false);
   ```
2. Bungkus dengan `try/finally`:
   ```dart
   Future<void> getProfile() async {
     try {
       final response = await authService.getProfile();
       if (!mounted) return;
       setState(() => profile = response.data['data']);
     } catch (e, stack) {
       CrashReporter.report(...);
       if (!mounted) return;
       SnackbarUtil.show(...);
     } finally {
       if (mounted) setState(() => isLoadingProfile = false);
     }
   }
   ```
3. Pada widget profile (saat `isLoadingProfile`), pakai `ModernLoading(onRetry: getProfile)`.

---

## 13. Start Shift Modal — `getProfile()`

**Lokasi:** [lib/views/widgets/start_shift_modal.dart:47](lib/views/widgets/start_shift_modal.dart#L47)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- Bug serupa item 12: [start_shift_modal.dart:72](lib/views/widgets/start_shift_modal.dart#L72) — `isLoadingProfile = false` tanpa `setState`.

**Langkah Implementasi:**

1. Ganti baris 72-73:
   ```dart
   if (!mounted) return;
   setState(() => isLoadingProfile = false);
   ```
2. Tambahkan `finally`:
   ```dart
   } finally {
     if (mounted) setState(() => isLoadingProfile = false);
   }
   ```
3. Tambahkan snackbar error agar user tahu (saat ini hanya `debugPrint`).

---

## 14. End Shift Modal — `getProfile()` + `_loadShiftId()`

**Lokasi:** [lib/views/widgets/end_shift_modal.dart:53](lib/views/widgets/end_shift_modal.dart#L53)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- Bug serupa: [end_shift_modal.dart:67](lib/views/widgets/end_shift_modal.dart#L67) — `isLoadingProfile = false` tanpa `setState`.
- `_loadShiftId()` ([end_shift_modal.dart:78](lib/views/widgets/end_shift_modal.dart#L78)) tidak ada `try/catch` — jika `_getPenerimaan(result)` throw, `isLoading` tetap `true` selamanya.

**Langkah Implementasi:**

1. Fix `getProfile()` seperti item 13.
2. Bungkus `_loadShiftId()` dengan `try/finally`:
   ```dart
   Future<void> _loadShiftId() async {
     try {
       final result = await ShiftStorageService.getShiftId();
       final cash = await ShiftStorageService.getCash();
       await _getPenerimaan(result);
       _autoFillSalesEnd(cash);
       if (!mounted) return;
       setState(() {
         shiftId = result;
         cashActive = cash;
       });
     } catch (e, stack) {
       CrashReporter.report(e, stack, reason: 'endShift_modal._loadShiftId');
     } finally {
       if (mounted) setState(() => isLoading = false);
     }
   }
   ```

---

## 15. Product Modal Widget & Update Product Modal — Submit

**Lokasi:** [lib/views/widgets/product_modal_widget.dart](lib/views/widgets/product_modal_widget.dart), [lib/views/widgets/update_product_modal_widget.dart](lib/views/widgets/update_product_modal_widget.dart)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- `isSubmitting` dengan `setState(() => isSubmitting = true)` di awal.
- `try/finally` lengkap dengan `if (mounted) setState(() => isSubmitting = false)`.
- Tombol disable saat submitting.

---

## 16. Reception Inventory Page — Loading Awal

**Lokasi:** [lib/views/pages/reception_inventory_page.dart:33](lib/views/pages/reception_inventory_page.dart#L33)

**Status:** Belum Implementasi

**Kondisi saat ini:**
- Punya `isLoading` + `isLoadingProfile` keduanya `late true`.
- Pakai `setState(() => isLoading = false)` di akhir fetch.
- Belum diaudit detail apakah ada path catch yang tidak reset; risiko sama dengan pola lain → cek manual.

**Langkah Implementasi:**

1. Buka file, cari semua `isLoading = false` dan `isLoadingProfile = false`.
2. Pastikan setiap-nya:
   - Dibungkus `setState(() => ...)`.
   - Selalu dipanggil di `finally`, bukan hanya di blok sukses/catch tertentu.
   - Didahului `if (!mounted) return;`.
3. Pasang `ModernLoading(onRetry: ...)` di build untuk loading awal.

---

## 17. Network Indicator Global (Status Bar)

**Lokasi:** [lib/views/widgets/network_indicator.dart](lib/views/widgets/network_indicator.dart)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- Indikator pasif yang memeriksa Connectivity + ping `1.1.1.1` tiap 15 detik.
- 4 status: fast / medium / slow / offline.
- Dispose timer & subscription dengan benar.

---

## 18. Dio Client — Timeout Global

**Lokasi:** [lib/services/helper/dio_client.dart:13](lib/services/helper/dio_client.dart#L13)

**Status:** Sudah Implementasi

**Kondisi saat ini:**
- `connectTimeout: 30s`, `receiveTimeout: 30s`.
- Interceptor untuk inject token.

**Catatan minor:** 30 detik cukup lama. Untuk operasi yang user-facing (mis. load menu), `15s` lebih sesuai dengan rekomendasi `network.md` (15–30s, lebih pendek untuk UX yang gesit). Pertimbangkan turunkan ke 20s.

---

## 19. Loading di Atas Layar Tanpa Cancel Token

**Lokasi:** Semua service ([lib/services/*.dart](lib/services))

**Status:** Belum Implementasi

**Kondisi saat ini:**
- Tidak ada `CancelToken` di mana pun.
- Jika user spam tombol search / refresh / pindah halaman, request lama tetap berjalan dan respons bisa datang setelah widget dispose.
- Mitigasi yang ada: cek `mounted` sebelum `setState` (sudah konsisten di sebagian besar tempat). Cukup mencegah crash, tapi tidak mencegah race condition data lama menimpa data baru.

**Langkah Implementasi (per file yang punya search/refresh):**

1. Tambah field di state class:
   ```dart
   CancelToken? _cancelToken;
   ```
2. Sebelum kirim request baru, batalkan request lama:
   ```dart
   Future<void> getMenu() async {
     _cancelToken?.cancel('new request');
     _cancelToken = CancelToken();
     try {
       final response = await menuService.getList(cancelToken: _cancelToken);
       // ...
     } on DioException catch (e) {
       if (CancelToken.isCancel(e)) return; // diam-diam abaikan
       // ... error handler existing
     }
   }
   ```
3. Tambahkan parameter `CancelToken?` di method service terkait, mis. [lib/services/menu_service.dart](lib/services/menu_service.dart):
   ```dart
   Future<Response> getList({CancelToken? cancelToken}) {
     return dio.get('/pos/menu', cancelToken: cancelToken);
   }
   ```
4. `dispose()` widget:
   ```dart
   @override
   void dispose() {
     _cancelToken?.cancel('widget disposed');
     super.dispose();
   }
   ```

Prioritaskan untuk: `pesanan_baru_page` (search produk), `riwayat_penjualan_page` (search order), `reject_detail_page._searchItems` (sudah punya debounce, tinggal tambah CancelToken).

---

## 20. Pre-flight Connectivity Check Sebelum Mutasi Data

**Lokasi:** Semua aksi submit (kecuali `payment_page.handlePayment`)

**Status:** Sebagian Sudah Implementasi (start_shift, end_shift sudah; reject/SO/login belum)

**Kondisi saat ini:**
- Hanya `payment_page.handlePayment` yang panggil `NetworkService.isOnline()` sebelum kirim.
- Submit reject, submit SO, save draft, end shift, start shift, dll. langsung tembak ke server. Jika offline, user baru tahu setelah timeout 30 detik.

**Langkah Implementasi (template universal):**

Pada setiap fungsi submit yang menulis data, tambahkan blok berikut di paling awal (setelah validasi input lokal):

```dart
final online = await NetworkService.isOnline();
if (!online) {
  if (!mounted) return;
  SnackbarUtil.show(
    context,
    title: 'Tidak Ada Koneksi',
    message: 'Perangkat sedang offline. Periksa koneksi internet Anda.',
    status: SnackBarStatus.warning,
  );
  return;
}
```

Daftar fungsi yang perlu update:
- `reject_detail_page._submit`, `_saveDraft`, `_addItem`, `_uploadLampiran`
- `stock_opname_page._submit`, `_saveDraft`
- `start_shift_modal.submitShift`
- `end_shift_modal` (submit end shift)
- `login_page.login` (opsional — bisa beri pesan lebih jelas dibanding error generic)

---

## 21. Minimum Loading Duration (Anti-Flicker)

**Lokasi:** Seluruh aplikasi

**Status:** Belum Implementasi

**Kondisi saat ini:** Skeleton bisa muncul dan hilang dalam <100ms saat koneksi cepat → kedipan UI.

**Langkah Implementasi (opsional / nice-to-have):**

Buat helper di [lib/utils/loader_utils.dart](lib/utils/loader_utils.dart):

```dart
Future<T> withMinDuration<T>(
  Future<T> future, {
  Duration minDuration = const Duration(milliseconds: 300),
}) async {
  final results = await Future.wait([
    future,
    Future.delayed(minDuration),
  ]);
  return results[0] as T;
}
```

Lalu pakai di tempat loading awal cepat:
```dart
final response = await withMinDuration(menuService.getList());
```

Terapkan di list yang relatif kecil (kategori, profile, method pembayaran). Tidak perlu di submit transaksi.

---

## 22. Lifecycle: App ke Background Saat Loading

**Lokasi:** Halaman dengan submit lama (payment, submit reject, submit SO)

**Status:** Belum Implementasi

**Kondisi saat ini:** Tidak ada `WidgetsBindingObserver.didChangeAppLifecycleState` di payment / reject / SO. Jika user switch app saat submit, callback tetap berjalan tapi tanpa pemulihan jika request gagal di background.

**Langkah Implementasi (untuk halaman submit kritis):**

1. Tambahkan `with WidgetsBindingObserver` di state class.
2. `initState()`: `WidgetsBinding.instance.addObserver(this);`.
3. `dispose()`: `WidgetsBinding.instance.removeObserver(this);`.
4. Override:
   ```dart
   @override
   void didChangeAppLifecycleState(AppLifecycleState state) {
     if (state == AppLifecycleState.resumed && isSubmitting) {
       // Tampilkan dialog konfirmasi: "Apakah submit masih berjalan?"
       // Atau cek ulang status order di backend
     }
   }
   ```

Prioritas: `payment_page` saja (transaksi paling kritis). Pada reject/SO sudah ada timeout dialog (`_showSubmissionTimeoutDialog`), jadi UX-nya cukup.

---

## 23. Disable Tombol Saat Aksi Berjalan (Global Audit)

**Status:** Sebagian Sudah Implementasi (review case-by-case)

Sudah benar di:
- `login_page.login` (tombol Masuk).
- `payment_page.handlePayment` (tombol Bayar).
- `stock_opname_page._saveDraft` / `_submit`.
- `reject_detail_page._submit` / `_saveDraft` / `_addItem`.
- `product_modal_widget` / `update_product_modal_widget`.

Belum benar di:
- Tombol +/- /delete pada `CartItemTile` (lihat item 4).
- `ProductCard.onTap` saat add to cart (lihat item 4).
- Search produk di `pesanan_baru_page` — tidak ada disable / debounce.

---

## Prioritas Pengerjaan (Disarankan)

| Prioritas | Item | Alasan |
|---|---|---|
| **P0 (bug nyata)** | 7, 12, 13, 14 | Spinner stuck karena `setState` lupa dipanggil di catch → user perlu tutup-buka manual. |
| **P0** | 5 | Payment page loadCart catch tidak reset `isLoadingCart` → blocker transaksi. |
| **P0** | 4 | Race condition tombol cart memicu insufficient stock error palsu. |
| **P1 (UX kritis)** | 1, 11 | Splash & detail reject tidak ada timeout — user bisa stuck di splash. |
| **P1** | 20 | Pre-flight connectivity check di submit untuk feedback offline yang cepat. |
| **P2 (improvement)** | 10, 16, 19 | Timeout/retry visual + CancelToken untuk konsistensi. |
| **P3 (polish)** | 8, 21, 22 | Hardening kecil dan anti-flicker. |

---

## Checklist Wajib Setiap Kali Menambah State Loading Baru

Saat membuat fitur baru yang memerlukan loading, pastikan dev/AI mengikuti checklist ini:

- [ ] Deklarasikan `bool isLoading{Something} = true|false;` di state class.
- [ ] Bungkus call jaringan dengan `try { } catch (e, stack) { CrashReporter.report(...); } finally { }`.
- [ ] Reset loading di blok `finally`, didahului `if (mounted) setState(...)`.
- [ ] Cek `if (!mounted) return;` sebelum `setState` / `Navigator` / `SnackbarUtil` setelah setiap `await`.
- [ ] Tampilkan UI loading: `ModernLoading(timeout: ..., onRetry: ...)` atau `SkeletonLoader.*(timeout: ..., onRetry: ...)`.
- [ ] Disable tombol/aksi yang relevan saat `isLoading == true`.
- [ ] Untuk aksi mutasi (POST/PUT/DELETE): cek `NetworkService.isOnline()` di awal.
- [ ] Untuk halaman dengan search/refresh: pakai `CancelToken`.
- [ ] Tampilkan snackbar error yang informatif (bukan hanya `debugPrint`).
