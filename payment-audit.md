# Audit `payment_page.dart`

Audit menyeluruh terhadap [lib/views/pages/payment_page.dart](lib/views/pages/payment_page.dart). Setiap issue diberi kategori severity, lokasi, dampak nyata, dan langkah perbaikan konkret.

**Legenda Severity:**
- **Critical** — Bisa menyebabkan duplikasi order, kehilangan uang, atau data finansial salah.
- **High** — Crash, state inkonsisten, atau order tersubmit tanpa konfirmasi yang benar.
- **Medium** — UX buruk, edge case yang sering muncul, integritas data minor.
- **Low** — Code smell, defensive programming, perbaikan kecil.

---

## CRITICAL

### CR-1. Order ter-submit tapi print/upload gagal → user retry → DUPLICATE ORDER

**Lokasi:** [payment_page.dart:510](lib/views/pages/payment_page.dart#L510) — `await Future.wait([printFuture, uploadFuture])`

**Severity:** Critical

**Deskripsi:**
Setelah `orderService.postOrder(payloadOrder)` berhasil di baris 346/406/472 (order sudah tersimpan di server), kode lanjut ke print struk dan upload foto via `Future.wait`. Jika SALAH SATU gagal:
- `printFuture` lempar exception (printer mati, bluetooth disconnect) — **bukan `DioException`**, jadi tidak ditangkap oleh `on DioException catch (e, stack)` di baris 539.
- Exception propagate keluar, `paymentSuccessModal` dan `clearVouchers` tidak dipanggil, tapi `finally` jalan dan `isLoading = false`.
- User melihat error / aplikasi crash. Kasir berasumsi order gagal dan menekan tombol bayar lagi → **order kedua tercipta di server** padahal pembayaran fisik hanya sekali.

**Dampak:**
- Duplikasi transaksi di database.
- Stok ter-decrement dua kali.
- Laporan penjualan tidak sesuai uang fisik di kasir.

**Rekomendasi:**
1. Bungkus `printFuture` dan `uploadFuture` masing-masing dengan try/catch independen — jangan biarkan gagalnya printer/kamera membatalkan flow setelah order tersimpan.
2. Tampilkan modal sukses **segera setelah `postOrder` berhasil**, sebelum print/upload. Print/upload dijalankan fire-and-forget di background.
3. Tambahkan idempotency key di payload (`client_order_id` = UUID dibuat sekali per attempt) supaya server menolak duplikat.

**Contoh kode:**
```dart
final response = await orderService.postOrder(payloadOrder);
orderId = response.data['data']['id'];

// Order sudah aman tersimpan — clear cart & tampilkan sukses dulu.
paymentSuccessModal(kembalian);
isTargetNotifier.value = true;
await clearVouchers();

// Print & upload sebagai best-effort, error tidak boleh membatalkan flow.
_runBestEffort(() => BluetoothPrinterService.printStruk(...));
_runBestEffort(() => _uploadLampiran(orderId));
```

---

### CR-2. Race condition: tombol bayar bisa di-tap dua kali sebelum `isLoading` ter-render

**Lokasi:** [payment_page.dart:270-271](lib/views/pages/payment_page.dart#L270-L271) — awal `handlePayment`

**Severity:** Critical

**Deskripsi:**
`onPressed` di-disable lewat `isLoading`, tapi `setState(() => isLoading = true)` dipanggil **di dalam** `handlePayment`. Antara saat user menekan tombol dan saat frame berikutnya digambar (yang men-disable tombol), user bisa men-tap berkali-kali pada layar lambat. Setiap tap menjalankan `handlePayment` paralel → multiple `postOrder` request → duplikasi order.

Selain itu, `await NetworkService.isOnline()` di baris 272 adalah titik async pertama — semua tap yang masuk sebelum titik ini akan jalan paralel.

**Dampak:**
- Pada perangkat lambat atau saat backend lambat respon, sangat mungkin terjadi 2-3 order duplikat dari satu transaksi.

**Rekomendasi:**
Tambahkan guard sinkron di awal fungsi:
```dart
void handlePayment() async {
  if (isLoading) return;            // guard sinkron, tidak menunggu setState
  setState(() => isLoading = true);
  // ...
}
```

---

### CR-3. `selectedMethodId` dan `selectedPaymentNonTunaiId` tidak diverifikasi terhadap data server

**Lokasi:** [payment_page.dart:86-88](lib/views/pages/payment_page.dart#L86-L88), validasi di [payment_page.dart:248-256](lib/views/pages/payment_page.dart#L248-L256)

**Severity:** Critical

**Deskripsi:**
`selectedMethodId = "1"` dan `selectedPaymentNonTunaiId = "1"` adalah **default hardcoded** sebelum `_methods()` selesai. Validator hanya mengecek `>0`, tidak memverifikasi bahwa ID itu ada di `orderMethods` / `paymentMethods` yang sudah di-fetch.

Skenario:
1. User membuka halaman, `_methods()` masih loading.
2. Halaman menampilkan loading screen (`isLoadingMethod`). OK aman selama loading.
3. **Tapi:** jika `_methods()` gagal (lihat CR-4 / HI-2), `isLoadingMethod = false` tetap di-set di catch, UI lanjut, dan user bisa submit dengan `selectedMethodId = "1"` yang mungkin tidak valid di server.

**Dampak:**
- Server menerima `pos_order_method_id` atau `pos_payment_method_id` yang merujuk ke data yang tidak ada → order tersimpan dengan FK rusak atau ditolak server. Lihat juga CR-1: jika ditolak server, user retry → duplikasi.

**Rekomendasi:**
1. Jika `_methods()` gagal, jangan tampilkan UI pembayaran — blok user dengan error & tombol "Coba Lagi".
2. Validasi `selectedMethodId` dengan `orderMethods.any((m) => m['id'].toString() == selectedMethodId)`.
3. Jangan default ke `"1"` — biarkan null/empty dan paksa user memilih.

---

### CR-4. Hardcoded `pos_payment_method_id: 11` di payload Tunai & Compliment

**Lokasi:** [payment_page.dart:335](lib/views/pages/payment_page.dart#L335), [payment_page.dart:460](lib/views/pages/payment_page.dart#L460)

**Severity:** Critical

**Deskripsi:**
Untuk transaksi tunai dan compliment, payload mengirim `"pos_payment_method_id": 11` — angka magic yang tidak berasal dari konfigurasi maupun response server. Jika di server data ID 11 dihapus, di-rename, atau berbeda antar environment (dev/staging/prod), semua transaksi tunai gagal atau menyimpan FK yang salah.

**Dampak:**
- Salah satu environment bisa silently menyimpan pembayaran ke metode yang salah (mis. "Cash" jadi "Bank Transfer") tanpa error.
- Migrasi/refactor data master tidak aman.

**Rekomendasi:**
1. Endpoint `/pos/payment-method` (atau serupa) harus memiliki flag `is_cash: true` pada record cash. Filter `paymentMethods.firstWhere((p) => p['is_cash'] == true)` saat init.
2. Atau pindahkan konstanta ke `app_config.dart` dan dokumentasikan asumsinya.
3. Tambahkan assertion di startup: jika `cashPaymentMethodId` tidak ditemukan di response server, blok aplikasi dengan pesan error.

---

## HIGH

### HI-1. Print/upload exception tidak ditangkap (hanya `DioException`)

**Lokasi:** [payment_page.dart:539](lib/views/pages/payment_page.dart#L539) — `on DioException catch (e, stack)`

**Severity:** High

**Deskripsi:**
Catch block hanya `on DioException`. Exception dari:
- `BluetoothPrinterService.printStruk` (printer disconnect, BT error)
- `cameraService.initialize()` / `capture()` (permission denied, kamera busy)
- `MultipartFile.fromFile` (file dihapus, IO error)
- `int.parse(customerId!)` (jika lewat dari guard, walaupun seharusnya tidak)

...akan propagate keluar fungsi, tidak menampilkan modal error, dan user hanya melihat tombol kembali enable tanpa feedback apapun.

**Dampak:** Lihat CR-1 — user retry → duplikasi.

**Rekomendasi:**
Tambah catch generic setelah `on DioException`:
```dart
} on DioException catch (e, stack) {
  // existing
} catch (e, stack) {
  CrashReporter.report(e, stack, reason: 'payment_page.handlePayment.unknown');
  if (!mounted) return;
  SnackbarUtil.show(context,
    title: "Terjadi Kesalahan",
    message: 'Terjadi kesalahan tak terduga: $e',
    status: SnackBarStatus.error,
  );
  // Jangan tampilkan paymentErrorModal jika orderId sudah terisi — order sudah tersimpan.
  if (orderId == null) paymentErrorModal();
}
```

---

### HI-2. `_methods()` sequential — kegagalan call kedua membiarkan state setengah-jalan

**Lokasi:** [payment_page.dart:595-617](lib/views/pages/payment_page.dart#L595-L617)

**Severity:** High

**Deskripsi:**
```dart
paymentMethods = ...; // call 1
orderMethods = ...;   // call 2
setState(() => isLoadingMethod = false);
```
Jika call kedua gagal, `paymentMethods` sudah ter-isi tapi `orderMethods` masih `[]`. Catch block men-set `isLoadingMethod = false` → UI ditampilkan, tapi `methodPaymnet()` me-render Row kosong. Validasi `selectedMethodId == "1"` lolos (default) → order tetap bisa di-submit dengan method ID yang mungkin salah.

**Rekomendasi:**
1. Jalankan paralel dengan `Future.wait`.
2. Jika salah satu gagal, **jangan set `isLoadingMethod = false`** — tampilkan error state dengan tombol retry.

```dart
try {
  final results = await Future.wait([
    methodService.getPaymentMethods(),
    methodService.getOrderMethods(),
  ]);
  paymentMethods = List<Map<String, dynamic>>.from(results[0].data['data']);
  orderMethods = List<Map<String, dynamic>>.from(results[1].data['data']);
  if (mounted) setState(() => isLoadingMethod = false);
} catch (e, stack) {
  // log + tampilkan error state, jangan biarkan UI pembayaran muncul
}
```

---

### HI-3. `getProfile` assign null ke field non-nullable `userName`

**Lokasi:** [payment_page.dart:574](lib/views/pages/payment_page.dart#L574)

**Severity:** High

**Deskripsi:**
```dart
userName = data?['name'];   // userName adalah String non-nullable
userId = data?['userid'];
```
Jika `data` null atau `data['name']` null, ini melempar runtime error (assign null ke non-nullable). Tidak ada try/catch lokal selain catch umum di luar. State `isLoadingUserId = false` di catch — UI lanjut, tapi data tidak valid.

Selain itu, `customerId = data['customer'][0]` **tanpa** null-safety operator pada `data` — inkonsisten dengan baris di atas.

**Rekomendasi:**
```dart
final name = data?['name'];
final uid = data?['userid'];
if (name == null || uid == null) {
  // data tidak valid → tampilkan error, jangan biarkan halaman lanjut
  throw StateError('Profile data invalid');
}
userName = name as String;
userId = uid as int;
```

---

### HI-4. `_loadShiftId` tidak cek `mounted` sebelum `setState`

**Lokasi:** [payment_page.dart:619-624](lib/views/pages/payment_page.dart#L619-L624)

**Severity:** High

**Deskripsi:**
```dart
Future<void> _loadShiftId() async {
  final result = await ShiftStorageService.getShiftId();
  setState(() { shiftId = result; });
}
```
Jika user keluar dari halaman selama prefs load (di Android lambat ini bisa puluhan ms), `setState` dipanggil setelah dispose → exception "setState called after dispose".

**Rekomendasi:**
```dart
final result = await ShiftStorageService.getShiftId();
if (!mounted) return;
setState(() => shiftId = result);
```
Audit semua `setState` lain di file ini untuk pola yang sama.

---

### HI-5. Tidak ada `PopScope` / `WillPopScope` — user bisa back saat loading

**Lokasi:** Build method, line [payment_page.dart:1210-1764](lib/views/pages/payment_page.dart#L1210-L1764)

**Severity:** High

**Deskripsi:**
Saat `isLoading = true` (order sedang di-submit, print/upload sedang jalan), user bisa menekan tombol back Android. Halaman pop → state dispose → `setState` di middle-of-flight gagal → response order yang sudah berhasil hilang ditangkap. User berasumsi gagal & coba lagi.

**Rekomendasi:**
Bungkus `Scaffold` dengan `PopScope`:
```dart
return PopScope(
  canPop: !isLoading,
  onPopInvoked: (didPop) {
    if (!didPop) {
      SnackbarUtil.show(context,
        title: "Sedang Memproses",
        message: "Tunggu sampai pembayaran selesai",
        status: SnackBarStatus.warning,
      );
    }
  },
  child: Scaffold(...),
);
```

---

### HI-6. `slowTimer` mulai sebelum `showRemarksModal` untuk Compliment → false-positive

**Lokasi:** [payment_page.dart:289-291](lib/views/pages/payment_page.dart#L289-L291) vs [payment_page.dart:425](lib/views/pages/payment_page.dart#L425)

**Severity:** High

**Deskripsi:**
`slowTimer` 15 detik dimulai SEBELUM `await showRemarksModal()`. Modal menunggu user mengetik keterangan. Jika user butuh 16 detik mengetik, dialog "Proses Lambat" muncul padahal belum ada request apa-apa ke server. Membingungkan kasir.

**Rekomendasi:**
Pindahkan `slowTimer` ke setelah validasi & modal — start hanya sebelum `postOrder` actual.

---

### HI-7. `paymentErrorModal` tidak `barrierDismissible: false`

**Lokasi:** [payment_page.dart:752-831](lib/views/pages/payment_page.dart#L752-L831)

**Severity:** High

**Deskripsi:**
Modal error pakai default `barrierDismissible: true`. User bisa tap di luar modal → modal hilang → user kembali ke halaman pembayaran tanpa tahu order benar-benar gagal atau berhasil (bisa saja request timeout tapi backend terima). User klik bayar lagi → potensi duplikasi.

**Rekomendasi:**
Set `barrierDismissible: false` + paksa user menekan tombol "Selesai" yang reset cart.

---

## MEDIUM

### MD-1. Validasi dijalankan SETELAH `setState(isLoading = true)`

**Lokasi:** [payment_page.dart:271 → 306](lib/views/pages/payment_page.dart#L271-L306)

**Severity:** Medium

**Deskripsi:**
`isLoading = true` di-set sebelum cek network, sebelum validasi. Jika validasi gagal, tombol "berkedip" spinner selama satu frame untuk lalu kembali. Minor UX issue.

**Rekomendasi:**
1. Jalankan validasi sinkron PERTAMA (sebelum cek network).
2. Baru `setState(isLoading = true)` dan await `NetworkService.isOnline()`.

---

### MD-2. Cart tidak di-clear setelah sukses

**Lokasi:** [payment_page.dart:512-526](lib/views/pages/payment_page.dart#L512-L526)

**Severity:** Medium

**Deskripsi:**
`clearVouchers()` dipanggil, tapi `cartItems` di state lokal masih ada. Jika navigation ke `WidgetTree` ada delay/gagal, user bisa "balik" ke halaman ini dengan cart yang sama. Risiko submit ulang.

**Rekomendasi:**
Tambah `await cartService.clearCart()` (atau equivalent) setelah `postOrder` sukses dan sebelum nav.

---

### MD-3. `selectedTab == 1 && id == 4` menyembunyikan order method tanpa reset state

**Lokasi:** [payment_page.dart:1874-1876](lib/views/pages/payment_page.dart#L1874-L1876)

**Severity:** Medium

**Deskripsi:**
Jika user memilih order method id 4 (mungkin "Compliment") saat tab Tunai, lalu pindah ke tab Non-Tunai, chip ID 4 disembunyikan tapi `selectedMethodId` masih `"4"`. Order tetap di-submit dengan ID 4 di tab Non-Tunai padahal UI tidak menampilkannya.

**Rekomendasi:**
Saat `selectedTab` berubah ke 1, reset `selectedMethodName/selectedMethodId` ke default valid yang tampil di tab itu.

---

### MD-4. `paymentSuccessModal` auto-nav delay 5 detik tidak bisa dibatalkan

**Lokasi:** [payment_page.dart:531-538](lib/views/pages/payment_page.dart#L531-L538)

**Severity:** Medium

**Deskripsi:**
`await Future.delayed(const Duration(seconds: 5))` lalu pushAndRemoveUntil. Jika user men-tap tombol "Selesai" sebelum 5 detik, navigasi terjadi DUA kali (sekali dari onPressed, sekali dari delayed). Mounted check menangkap kasus ke-2, tapi ada potensi race jika first nav belum selesai update state.

**Rekomendasi:**
Simpan flag `_navigated` atau cancel delayed timer saat tombol Selesai ditekan.

---

### MD-5. `data['nominal']` di-cast langsung tanpa parsing

**Lokasi:** [payment_page.dart:1123](lib/views/pages/payment_page.dart#L1123)

**Severity:** Medium

**Deskripsi:**
```dart
final int nominal = data['nominal'];
```
Jika server mengirim `"50000"` (string) atau `50000.0` (double), cast langsung throw `TypeError`. Ditangkap oleh `on DioException`? Tidak — ini bukan DioException, jadi uncaught.

**Rekomendasi:**
```dart
final nominal = int.tryParse(data['nominal'].toString()) ?? 0;
if (nominal <= 0) {
  // tampilkan error voucher invalid
  return;
}
```

---

### MD-6. `saveVoucherToLocal` menampilkan modal SEBELUM save selesai

**Lokasi:** [payment_page.dart:1159-1173](lib/views/pages/payment_page.dart#L1159-L1173)

**Severity:** Medium

**Deskripsi:**
`voucherSuccessModal()` di-show, baru `prefs.setString` dipanggil. Jika `setString` gagal (sangat jarang tapi mungkin di low storage), modal menampilkan sukses padahal data tidak tersimpan. Voucher tidak akan terkirim di payload.

**Rekomendasi:**
Pindahkan modal show ke setelah `await prefs.setString` & `setInt` sukses.

---

### MD-7. `_showSlowExecutionDialog` `barrierDismissible: true`

**Lokasi:** [payment_page.dart:202](lib/views/pages/payment_page.dart#L202)

**Severity:** Medium

**Deskripsi:**
User bisa dismiss dialog ini. Tidak masalah secara fungsional, tapi pesan-nya penting ("jangan tutup aplikasi") — dismiss aksidental membuat kasir berasumsi proses selesai padahal masih jalan.

**Rekomendasi:**
Set `barrierDismissible: false`, dengan tombol "Tutup" yang eksplisit.

---

## LOW

### LO-1. `late int finalPayment = 0` redundant

**Lokasi:** [payment_page.dart:90](lib/views/pages/payment_page.dart#L90)

**Severity:** Low

**Deskripsi:** Kata kunci `late` tidak dibutuhkan karena ada inisialisasi langsung. Ganti dengan `int finalPayment = 0`.

---

### LO-2. `cameraService.dispose()` di finally dipanggil meskipun `initialize()` belum jalan

**Lokasi:** [payment_page.dart:562](lib/views/pages/payment_page.dart#L562)

**Severity:** Low

**Deskripsi:**
Jika validasi gagal di awal, `uploadFuture` (yang berisi `initialize`) tidak pernah jalan, tapi `dispose` tetap dipanggil. Jika `CameraService.dispose` tidak idempotent, error.

**Rekomendasi:** Pastikan `CameraService.dispose` aman dipanggil sebelum init, atau pakai flag.

---

### LO-3. `tax_amount: 0.00` hardcoded

**Lokasi:** [payment_page.dart:339, 399, 464](lib/views/pages/payment_page.dart#L339)

**Severity:** Low

**Deskripsi:** Jika di masa depan pajak diaktifkan per outlet, harus diubah di 3 tempat. Sekarang OK, tapi pindahkan ke fungsi `_buildPayload()` shared.

---

### LO-4. Tiga payload block hampir identik — duplikasi kode

**Lokasi:** [payment_page.dart:330-344, 390-404, 455-470](lib/views/pages/payment_page.dart#L330-L344)

**Severity:** Low

**Deskripsi:** Tiga payload (Tunai, Non-Tunai, Compliment) berbagi 90% field. Extract ke helper `_buildOrderPayload({required bool isCash, required int paymentMethodId, ...})` untuk mengurangi risiko drift saat menambah field baru.

---

### LO-5. `setState` di Bluetooth listener tanpa cek `mounted`

**Lokasi:** [payment_page.dart:100-106](lib/views/pages/payment_page.dart#L100-L106)

**Severity:** Low

**Deskripsi:**
```dart
.onStateChanged().listen((state) {
  setState(() { connectedPrinter = ...; });
});
```
Subscription di-cancel di `dispose`, tapi ada window race kecil di antara dispose dan cancel. Tambahkan `if (!mounted) return;`.

---

## Ringkasan Action Item (urut prioritas)

1. **Tambah idempotency key + pisahkan print/upload dari order flow** — fix CR-1, HI-1 sekaligus.
2. **`if (isLoading) return;` di awal handlePayment** — fix CR-2 (1 baris kode, dampak besar).
3. **Validasi `selectedMethodId` & `selectedPaymentNonTunaiId` terhadap fetched methods** — fix CR-3.
4. **Hapus hardcode `pos_payment_method_id: 11`** — fix CR-4 (gunakan flag dari server).
5. **`Future.wait` untuk `_methods()` + error state UI** — fix HI-2.
6. **`PopScope` saat loading** — fix HI-5.
7. **Catch generic untuk non-Dio exception** — fix HI-1 sekunder.
8. **Reset `selectedMethodId` saat switch tab** — fix MD-3.

Item 1 dan 2 adalah yang paling cost-effective: dampak duplikasi finansial dengan effort kecil.
