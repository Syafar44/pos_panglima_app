# Update: Mode Offline POS Panglima

Dokumentasi implementasi fitur **Mode Offline** untuk `pos_panglima_app`.

**Sumber kebenaran kontrak API:** *Guide Tim FE — Transaksi POS Offline & Sync* (backend, disepakati
2026-06-05). Dokumen ini menerjemahkan kontrak itu menjadi langkah implementasi konkret di Flutter.
Prinsip umum: [README-offline-mode-pos.md](README-offline-mode-pos.md).

---

## 0. Keputusan Final (sudah disepakati)

| # | Keputusan | Jawaban | Dampak implementasi |
|---|---|---|---|
| 1 | Topologi outlet | **Wajib 1 outlet = 1 tablet** | Konflik stok antar-device **nihil**. Tidak perlu conflict resolution rumit. Decrement lokal aman karena hanya 1 device menyentuh stok outlet. |
| 2 | Resep (BOM) di payload sync | **Ya** (sudah ada di `getOfflineSync.data.bom`) | Decrement stok lokal **akurat** — expand BOM per `items_id`. |
| 3 | Voucher saat offline | **Skip dulu** | Voucher **& Compliment** diblokir di UI saat offline (server juga menolak). |
| 4 | Batas durasi offline maksimal | **Minimal 1 jam** | Setelah 1 jam tanpa sync, tampilkan peringatan ke kasir untuk menyambungkan internet. |

---

## 1. Konsep Dasar

- Saat **offline**, kasir tetap bisa transaksi tunai/normal. Order disimpan **lokal**.
- Saat **online**, semua order lokal dikirim **batch** ke server (`POST /pos/order/sync`), server
  simpan apa adanya (tanpa transformasi di FE).
- Stok lokal di-**decrement** saat transaksi offline (pakai BOM), lalu **direset** dari snapshot
  server tiap sync (5 menit / saat online lagi).
- **Idempotensi:** tiap order punya `client_ref` (UUID dari device). Kirim ulang aman — server
  balas `duplicate`, tidak dobel.

---

## 2. Kontrak Backend (AUTHORITATIVE — dari guide resmi)

### 2.1. `GET /pos/offline-sync` — tarik snapshot (panggil berkala saat online)

```json
{
  "message": "Success",
  "data": {
    "synced_at": "2026-06-10T13:00:00+08:00",
    "outlet": { "customers_id": 12, "warehouse_code": "WH-OUTLET-01", "outlet_hub_type": "gerai" },
    "stocks": [
      { "items_id": 3, "item_code": "ITM26010001", "name": "Tepung Terigu", "uom": "Gr",  "qty": 25000, "skip_validation": false },
      { "items_id": 9, "item_code": "ITM26020149", "name": "Kertas Doorslag", "uom": "Pcs", "qty": 100,  "skip_validation": true }
    ],
    "bom": [
      { "pos_menus_id": 101, "items_id": 3, "item_code": "ITM26010001", "quantity": 200, "uom": "Gr" }
    ]
  }
}
```

Aturan penting (dari guide):
- Semua kuantitas dalam **satuan NISIK** (Gr/Ml/Pcs). `stocks[].qty` dan `bom[].quantity` **sudah
  satu satuan** → bisa langsung dibandingkan.
- `skip_validation == true` → **jangan** jadikan item ini pembatas stok (mis. Kertas Doorslag).
  **Pakai flag ini, JANGAN menebak dari `uom`.**
- `synced_at` → tampilkan ke kasir: "stok per … (terakhir sync)".
- `bom` memuat **semua menu** termasuk variant/extra/topping (props ikut terhitung).

### 2.2. `POST /pos/order/sync` — kirim batch order offline (saat online kembali)

**Request body** = array order. Tiap order:

```json
[
  {
    "client_ref": "f2b1c3a4-...-uuid-device",
    "created_at": "2026-06-10T13:45:12+08:00",
    "outlet_hub_id": 12,
    "pos_shifts_id": 88,
    "users_id": 5,
    "pos_payment_method_id": 1,
    "pos_order_method_id": 1,
    "is_cash": 1,
    "subtotal_amount": 50000,
    "discount_amount": 0,
    "tax_amount": 0,
    "total_amount": 50000,
    "pay_amount": 50000,
    "keterangan": "",
    "latitude": "-5.14",
    "longitude": "119.43",
    "device_info": "Samsung A52 / appv1.2.3",
    "pos_order_lines": [
      {
        "pos_menus_id": 101,
        "quantity": 2,
        "price": 25000,
        "subtotal": 50000,
        "discount": 0,
        "tax": 0,
        "total": 50000,
        "pos_order_lines_props": [ { "pos_menus_id": 205, "quantity": 2 } ],
        "pos_order_lines_material": [ { "items_id": 3, "qty_nisik": 400 } ]
      }
    ]
  }
]
```

**Field yang diisi FE:** `client_ref`, `created_at`, header (outlet/shift/user/method/amounts),
`pos_order_lines[]` (menu, qty, harga, props), dan `pos_order_lines_material[].qty_nisik` (hasil
expand BOM, §5).
**Jangan dikirim FE** (server yang generate): `document_number`, `entry`, `token`, `source`,
`quantity_volume`.

**Response:**

```json
{
  "message": "Success",
  "data": [
    { "client_ref": "f2b1c3a4-...", "status": "created",   "document_number": "POS1718000712042" },
    { "client_ref": "a9d4e7b0-...", "status": "duplicate", "document_number": "POS1718000698311" },
    { "client_ref": "c1f0b2d9-...", "status": "rejected",  "message": "compliment/voucher not allowed offline" }
  ]
}
```

| status | Arti | Tindakan FE |
|---|---|---|
| `created` | Order baru tersimpan | **Hapus** dari antrian. Simpan `document_number` bila perlu cetak ulang. |
| `duplicate` | `client_ref` sudah pernah masuk | **Hapus** dari antrian (sudah aman). |
| `rejected` | Ditolak (compliment/voucher/method invalid) | **Jangan hapus**; tandai untuk review manual. |

### 2.3. Aturan WAJIB offline (dari guide)

- **Hanya transaksi tunai/normal.** Voucher & Compliment (`pos_order_method_id = 4`) **dilarang
  offline** → blokir di UI.
- `client_ref` **unik & stabil**: generate sekali saat order dibuat, simpan bersama order lokal,
  pakai nilai sama di setiap retry.
- `qty_nisik` = angka NISIK yang **sama** dengan yang dipakai saat decrement stok lokal.
- Hapus order dari antrian **hanya** jika `status = created` atau `duplicate`.

---

## 3. Pemetaan File

### File baru
| File | Tugas |
|---|---|
| `lib/services/storage/offline_stock_service.dart` | Simpan snapshot (stocks + bom + menu), decrement, reset, validasi |
| `lib/services/storage/pending_order_service.dart` | Antrian order offline (outbox) + flush batch |
| `lib/services/offline_sync_manager.dart` | Timer 5 menit: sync snapshot + flush antrian |
| `lib/utils/bom_calculator.dart` | Expand BOM → `qty_nisik` per `items_id` (validasi + payload) |
| `lib/views/pages/pending_payment_page.dart` | Halaman "Pending Payment" (auto + manual submit) |

### File diubah
| File | Perubahan |
|---|---|
| [lib/services/offline_sync_service.dart](lib/services/offline_sync_service.dart) | Tambah `postOrderSync(List orders)` |
| [lib/main.dart](lib/main.dart) | `OfflineSyncManager.start()` |
| [lib/views/pages/pesanan_baru_page.dart](lib/views/pages/pesanan_baru_page.dart) | Tombol hamburger → dropdown "Riwayat"; cart offline |
| [lib/views/pages/payment_page.dart](lib/views/pages/payment_page.dart) | Cabang offline di `handlePayment` (blokir voucher/compliment, enqueue, decrement, cetak) |
| [lib/views/widgets/product_modal_widget.dart](lib/views/widgets/product_modal_widget.dart) | Validasi stok lokal saat offline |

---

## 4. Arsitektur Data Lokal (SharedPreferences)

| Key | Isi | Reset |
|---|---|---|
| `offline_snapshot` | `{synced_at, outlet, stocks[], bom[]}` dari `getOfflineSync` | tiap sync (overwrite) |
| `offline_menu` | seluruh menu `pesanan_baru` | tiap sync |
| `offline_synced_at` | timestamp sync sukses terakhir | tiap sync |
| `cart_items` | keranjang aktif (pakai `CartStorageService` yang sudah ada) | saat clear cart |
| `pending_orders` | antrian order offline (outbox) | hapus per-item setelah ACK |

> **Decrement stok** dilakukan dengan **menimpa `stocks[].qty` di dalam `offline_snapshot`**. Karena
> tiap sync menimpa seluruh snapshot dengan data server terbaru, decrement lokal otomatis **ter-reset**.
> (1 tablet/outlet → tidak ada device lain yang menyentuh stok, jadi cara sederhana ini aman.)

---

## 5. Logika BOM — Validasi & Decrement (INTI, ikuti PERSIS)

Untuk tiap transaksi, ulangi logika server (guide §2.1):

1. Untuk tiap **baris keranjang**: ambil BOM untuk `pos_menus_id` baris **dan** tiap
   `pos_cart_props[].pos_menus_id`.
2. Akumulasi kebutuhan per `items_id`:
   - dari menu utama: `bom.quantity(pos_menus_id baris) × quantity baris`
   - dari tiap prop: `bom.quantity(prop.pos_menus_id) × prop.quantity`
     *(catatan: di cart ini `prop.quantity` sudah absolut — sudah dikali jumlah paket saat dipilih
     di `product_modal_widget`. Jadi JANGAN dikali `quantity baris` lagi.)*
3. Bandingkan dengan `stocks.qty`. **Lewati** item ber-`skip_validation = true`.
4. Bila cukup → boleh. **Decrement** `stocks.qty` lokal sejumlah kebutuhan (banyak menu berbagi
   bahan baku yang sama, jadi sisa stok harus benar untuk transaksi berikutnya).

Angka kebutuhan per `items_id` inilah yang dikirim sebagai `qty_nisik` di `pos_order_lines_material`.

```dart
// lib/utils/bom_calculator.dart
class BomCalculator {
  /// Index BOM: pos_menus_id -> [ {items_id, quantity}, ... ]
  static Map<int, List<Map<String, dynamic>>> indexBom(List bom) {
    final map = <int, List<Map<String, dynamic>>>{};
    for (final row in bom) {
      final menuId = (row['pos_menus_id'] as num).toInt();
      (map[menuId] ??= []).add({
        'items_id': (row['items_id'] as num).toInt(),
        'quantity': (row['quantity'] as num).toInt(),
      });
    }
    return map;
  }

  /// Kebutuhan material untuk SATU baris cart → {items_id: qty_nisik}.
  static Map<int, int> materialsForLine(
    Map<String, dynamic> line,
    Map<int, List<Map<String, dynamic>>> bomIndex,
  ) {
    final need = <int, int>{};
    final menuId = (line['pos_menus_id'] as num).toInt();
    final lineQty = (line['quantity'] as num?)?.toInt() ?? 1;

    // Menu utama × qty baris
    for (final b in (bomIndex[menuId] ?? const [])) {
      need[b['items_id']] = (need[b['items_id']] ?? 0) + (b['quantity'] as int) * lineQty;
    }
    // Props (prop.quantity sudah absolut)
    final props = (line['pos_cart_props'] as List?) ?? const [];
    for (final p in props) {
      final propMenuId = (p['pos_menus_id'] as num).toInt();
      final propQty = (p['quantity'] as num?)?.toInt() ?? 0;
      for (final b in (bomIndex[propMenuId] ?? const [])) {
        need[b['items_id']] = (need[b['items_id']] ?? 0) + (b['quantity'] as int) * propQty;
      }
    }
    return need;
  }

  /// Total kebutuhan seluruh cart → {items_id: qty_nisik} (untuk validasi + decrement).
  static Map<int, int> totalNeed(
    List<Map<String, dynamic>> cart,
    Map<int, List<Map<String, dynamic>>> bomIndex,
  ) {
    final total = <int, int>{};
    for (final line in cart) {
      materialsForLine(line, bomIndex).forEach((id, qty) {
        total[id] = (total[id] ?? 0) + qty;
      });
    }
    return total;
  }
}
```

---

## 6. TAHAPAN IMPLEMENTASI (step-by-step untuk junior / AI)

> Kerjakan **berurutan**. Tiap fase punya "cara test" — jangan lanjut sebelum fase sekarang lolos.
> Jalankan `flutter analyze <file>` tiap selesai edit. Jangan ubah perilaku online yang sudah ada.

### FASE 0 — Tambah method endpoint sync
**File:** [lib/services/offline_sync_service.dart](lib/services/offline_sync_service.dart)

```dart
class OfflineSyncService {
  final Dio dio;
  OfflineSyncService(this.dio);

  Future<Response> getOfflineSync() => dio.get("/pos/offline-sync");

  // TAMBAH:
  Future<Response> postOrderSync(List<Map<String, dynamic>> orders) =>
      dio.post("/pos/order/sync", data: orders);
}
```
**Test:** `flutter analyze` bersih.

---

### FASE 1 — Storage snapshot + decrement + reset
**File baru:** `lib/services/storage/offline_stock_service.dart`

Tanggung jawab:
- `saveSnapshot(Map data)` → simpan `offline_snapshot` (overwrite = reset decrement).
- `saveMenu(List menu)` → simpan `offline_menu`.
- `getSnapshot()` / `getMenu()` / `getSyncedAt()`.
- `validate(List cart)` → `null` kalau cukup, atau nama item kurang stok (pakai `BomCalculator` +
  `skip_validation`).
- `applyDecrement(List cart)` → kurangi `stocks[].qty` di `offline_snapshot` sesuai `totalNeed`.

```dart
class OfflineStockService {
  static const _snapshotKey = 'offline_snapshot';
  static const _menuKey = 'offline_menu';
  static const _syncedAtKey = 'offline_synced_at';

  static Future<void> saveSnapshot(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, jsonEncode(data));
    await prefs.setString(_syncedAtKey, data['synced_at']?.toString() ?? '');
  }

  static Future<void> saveMenu(List menu) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_menuKey, jsonEncode(menu));
  }

  static Future<Map<String, dynamic>?> getSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// null = boleh; selain itu nama item yang kurang.
  static Future<String?> validate(List<Map<String, dynamic>> cart) async {
    final snap = await getSnapshot();
    if (snap == null) return null; // belum pernah sync → jangan blokir (best-effort)
    final bomIndex = BomCalculator.indexBom(snap['bom'] as List? ?? []);
    final need = BomCalculator.totalNeed(cart, bomIndex);
    final stocks = (snap['stocks'] as List? ?? []);
    for (final entry in need.entries) {
      final stock = stocks.cast<Map>().firstWhere(
        (s) => (s['items_id'] as num).toInt() == entry.key,
        orElse: () => {},
      );
      if (stock.isEmpty) continue;
      if (stock['skip_validation'] == true) continue;
      if (entry.value > (stock['qty'] as num? ?? 0)) {
        return stock['name']?.toString() ?? 'Item';
      }
    }
    return null;
  }

  static Future<void> applyDecrement(List<Map<String, dynamic>> cart) async {
    final prefs = await SharedPreferences.getInstance();
    final snap = await getSnapshot();
    if (snap == null) return;
    final bomIndex = BomCalculator.indexBom(snap['bom'] as List? ?? []);
    final need = BomCalculator.totalNeed(cart, bomIndex);
    final stocks = (snap['stocks'] as List? ?? []).cast<Map>();
    for (final s in stocks) {
      final id = (s['items_id'] as num).toInt();
      if (need.containsKey(id)) {
        s['qty'] = (s['qty'] as num).toInt() - need[id]!; // boleh negatif (overselling diterima)
      }
    }
    await prefs.setString(_snapshotKey, jsonEncode(snap));
  }
}
```
**Test:** unit-test kecil — buat snapshot dummy + cart dummy, panggil `validate` & `applyDecrement`,
cek `getSnapshot().stocks[].qty` berkurang sesuai BOM.

---

### FASE 2 — BOM calculator
**File baru:** `lib/utils/bom_calculator.dart` → salin kode di **§5**.
**Test:** kasus 1 menu BOM `200 × qty 2 = 400`; props absolut tidak dikali ulang.

---

### FASE 3 — Antrian order offline (outbox)
**File baru:** `lib/services/storage/pending_order_service.dart`

```dart
class PendingOrderService {
  static const _key = 'pending_orders';

  static Future<List<Map<String, dynamic>>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> _saveAll(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }

  /// `order` = payload §2.2 (sudah berisi client_ref). Disimpan apa adanya.
  static Future<void> enqueue(Map<String, dynamic> order) async {
    final list = await getAll();
    list.add(order);
    await _saveAll(list);
  }
  /// Kirim semua order ke /pos/order/sync, lalu proses response per status.
  static Future<void> flush() async {
    if (!await NetworkService.isOnline()) return;
    final list = await getAll();
    if (list.isEmpty) return;
    try {
      final res = await OfflineSyncService(ApiClient().dio).postOrderSync(list);
      final results = (res.data['data'] as List).cast<Map>();
      // Hapus order yang created/duplicate; sisakan yang rejected.
      final keep = <Map<String, dynamic>>[];
      for (final order in list) {
        final r = results.firstWhere(
          (x) => x['client_ref'] == order['client_ref'],
          orElse: () => {},
        );
        final status = r['status'];
        if (status == 'created' || status == 'duplicate') {
          continue; // ACK → buang dari antrian
        }
        keep.add(order); // rejected / tidak ada di response → simpan untuk review
      }
      await _saveAll(keep);
    } catch (e, s) {
      CrashReporter.report(e, s, reason: 'pending_order_service.flush');
      // gagal kirim (mis. timeout) → biarkan antrian utuh, retry nanti
    }
  }

  static Future<int> count() async => (await getAll()).length;
}
```
**Test:** enqueue 2 order dummy → cek `count() == 2`. (flush diuji di FASE 7 saat online.)

---

### FASE 4 — Timer sync 5 menit
**File baru:** `lib/services/offline_sync_manager.dart`

```dart
class OfflineSyncManager {
  static Timer? _timer;
  static const _interval = Duration(minutes: 5);

  static void start() {
    _timer?.cancel();
    syncNow();
    _timer = Timer.periodic(_interval, (_) => syncNow());
  }

  static Future<void> syncNow() async {
    if (!await NetworkService.isOnline()) return; // offline → pakai snapshot lama
    try {
      final dio = ApiClient().dio;
      final snap = await OfflineSyncService(dio).getOfflineSync();
      await OfflineStockService.saveSnapshot(snap.data['data']);
      final menu = await MenuService(dio).getList();
      await OfflineStockService.saveMenu(menu.data['data']);
      await PendingOrderService.flush(); // online lagi → kirim antrian
    } catch (e, s) {
      CrashReporter.report(e, s, reason: 'offline_sync_manager.syncNow');
    }
  }

  static void stop() { _timer?.cancel(); _timer = null; }
}
```
**Daftarkan** di [lib/main.dart](lib/main.dart) setelah `dotenv.load`:
```dart
await dotenv.load(fileName: ".env");
OfflineSyncManager.start(); // ← tambah
```
**Test:** jalankan app online → cek log/`getSnapshot()` terisi; matikan internet → `syncNow` tidak crash.

---

### FASE 5 — Keranjang (cart) saat offline
**File:** [lib/views/pages/pesanan_baru_page.dart](lib/views/pages/pesanan_baru_page.dart) +
[lib/views/widgets/product_modal_widget.dart](lib/views/widgets/product_modal_widget.dart)

Saat ini add/update/delete cart **selalu** ke server. Saat offline harus pindah ke
`CartStorageService` (lokal). Pola:

```dart
if (await NetworkService.isOnline()) {
  await cartService.postCart(payload);   // alur lama
} else {
  await CartStorageService.addToCart(payload); // alur offline (sudah ada service-nya)
}
await onSaved(); // loadCart() harus baca dari lokal kalau offline
```

`loadCart()` di `pesanan_baru_page` juga harus baca dari `CartStorageService.getCart()` saat offline.
Begitu juga `getMenu()` → fallback ke `OfflineStockService.getMenu()` saat offline.

> ⚠️ Ini fase paling banyak sentuhan. Kerjakan hati-hati, jaga struktur item cart **sama** dengan
> yang dari server (`pos_menus_id`, `quantity`, `price`, `pos_cart_props`, dst) supaya BOM &
> payment jalan tanpa cabang tambahan.

**Test:** matikan internet → buka pesanan_baru → menu tetap tampil (dari lokal) → tambah item →
item masuk cart lokal → tutup-buka app → cart masih ada.

---

### FASE 6 — Cabang offline di pembayaran
**File:** [lib/views/pages/payment_page.dart](lib/views/pages/payment_page.dart),
fungsi `handlePayment` (sekitar [baris cek online](lib/views/pages/payment_page.dart#L701)).

Saat ini bila offline → **diblokir**. Ubah jadi: blokir voucher/compliment saja, sisanya simpan ke
antrian.

```dart
bool online = await NetworkService.isOnline();
if (!online) {
  // 1) Blokir voucher & compliment (kontrak §2.3)
  final isCompliment = selectedMethodName == 'Compliment' ||
      int.tryParse(selectedMethodId) == 4;
  if (isCompliment || barcodeList.isNotEmpty) {
    setState(() => isLoading = false);
    SnackbarUtil.show(context,
      title: 'Tidak Bisa Offline',
      message: 'Voucher & Compliment hanya bisa saat online.',
      status: SnackBarStatus.warning);
    return;
  }

  // 2) Validasi stok lokal
  final kurang = await OfflineStockService.validate(cartItems);
  if (kurang != null) {
    setState(() => isLoading = false);
    SnackbarUtil.show(context, title: 'Stok Tidak Cukup',
      message: '$kurang tidak mencukupi (stok offline).',
      status: SnackBarStatus.error);
    return;
  }

  // 3) Bangun payload offline (§2.2) — client_ref = _idempotencyKey yang sudah ada
  final offlineOrder = _buildOfflineOrderPayload(clientRef: idempotencyKey);

  // 4) Enqueue + decrement stok lokal + clear cart
  await PendingOrderService.enqueue(offlineOrder);
  await OfflineStockService.applyDecrement(cartItems);
  await CartStorageService.clearCart();

  // 5) Cetak struk (bluetooth tidak butuh internet)
  _idempotencyKey = null;
  _runBestEffort(() async => await BluetoothPrinterService.printStruk(/* dari cartItems */));

  // 6) Sukses
  paymentSuccessModal(0);
  setState(() => isLoading = false);
  return;
}
```

`_buildOfflineOrderPayload` membangun struktur §2.2: header + `pos_order_lines[]` dengan
`pos_order_lines_props` (dari `pos_cart_props`) dan `pos_order_lines_material` (dari
`BomCalculator.materialsForLine`). `created_at` = `DateTime.now().toIso8601String()` (offset +08:00),
`client_ref` = UUID yang sama dengan idempotency key.

**Test:** offline → bayar tunai → muncul sukses → cek `PendingOrderService.count()` bertambah, stok
lokal berkurang, struk tercetak. Coba bayar Compliment offline → diblokir.

---

### FASE 7 — UI: tombol hamburger + halaman Pending Payment
**File:** [pesanan_baru_page.dart](lib/views/pages/pesanan_baru_page.dart) + `pending_payment_page.dart` (baru).

1. Di samping tombol "Proses Pembayaran"
   ([baris ~791](lib/views/pages/pesanan_baru_page.dart#L791)), bungkus dengan `Row` lalu tambah
   tombol kotak ber-icon `Icons.menu` + `PopupMenuButton` berisi item **"Riwayat"** → push
   `PendingPaymentPage`.
2. `PendingPaymentPage`:
   - `initState` → kalau online, panggil `PendingOrderService.flush()` lalu reload (auto-submit).
   - Tampilkan list dari `PendingOrderService.getAll()`.
   - Tombol **"Kirim Ulang"** per item (atau global) → `flush()` manual (cek online dulu).
   - Badge jumlah pending + status.

**Test:** buat 2 order offline → buka Riwayat saat masih offline → 2 item tampil → nyalakan internet
→ buka Riwayat lagi → auto-submit → list kosong (status `created`/`duplicate`). Matikan jaringan
saat submit di tengah → item tetap ada, retry berikut tidak dobel.

---

### FASE 8 — Guardrail (batas offline 1 jam + indikator)
- Bandingkan `now - offline_synced_at`. Jika **> 1 jam** dan masih offline → banner/snackbar
  peringatan "Sudah lebih dari 1 jam tanpa sinkron. Sambungkan internet."
- Tampilkan `synced_at` ("Stok per HH:mm") di header pesanan_baru.
- Manfaatkan [network_indicator.dart](lib/views/widgets/network_indicator.dart) yang sudah ada untuk
  status koneksi.

**Test:** set jam mundur / mock `offline_synced_at` lebih dari 1 jam → peringatan muncul.

---

### FASE 9 — Skenario testing wajib (jangan diasumsikan)
1. Jual offline → online → order ter-flush, **tidak dobel**, struk sudah tercetak.
2. Koneksi putus di tengah flush → order tetap di antrian → retry pakai `client_ref` sama →
   server balas `duplicate`.
3. App di-kill / reboot saat antrian berisi → antrian utuh saat dibuka lagi.
4. Kirim ulang order yang server sudah proses → `duplicate` → dihapus dari antrian.
5. Stok offline turun saat jual; **reset** ke nilai server setelah sync 5 menit.
6. Compliment/voucher offline → **diblokir** UI.
7. Dua transaksi offline beruntun → dua `client_ref` beda → dua order tersimpan.

---

## 7. Checklist Ringkas

- [ ] FASE 0 — `postOrderSync` di `offline_sync_service.dart`
- [ ] FASE 1 — `OfflineStockService` (snapshot/validate/decrement/reset)
- [ ] FASE 2 — `BomCalculator`
- [ ] FASE 3 — `PendingOrderService` (enqueue/flush, hapus hanya saat created/duplicate)
- [ ] FASE 4 — `OfflineSyncManager` timer 5 menit + daftar di `main.dart`
- [ ] FASE 5 — Cart offline (`CartStorageService` fallback) + menu offline
- [ ] FASE 6 — Cabang offline `handlePayment` (blokir voucher/compliment, enqueue, decrement, cetak)
- [ ] FASE 7 — Tombol hamburger "Riwayat" + `PendingPaymentPage` (auto + manual)
- [ ] FASE 8 — Guardrail 1 jam + label `synced_at`
- [ ] FASE 9 — Lolos 7 skenario testing

---

## Ringkasan Aturan Kunci

| Area | Aturan |
|---|---|
| Topologi | 1 tablet / 1 outlet (konflik nihil) |
| Transaksi | Local-first; offline → `pending_orders`, selalu berhasil |
| Endpoint | `GET /pos/offline-sync` (snapshot+BOM), `POST /pos/order/sync` (batch) |
| Idempotensi | `client_ref` (UUID device), stabil saat retry; server balas `duplicate` |
| Antrian | Hapus item **hanya** saat `created`/`duplicate`; `rejected` → review manual |
| Stok | Decrement pakai BOM (NISIK); **reset** dari snapshot server tiap sync |
| `skip_validation` | Pakai flag, **jangan** tebak dari `uom` |
| Larangan offline | Voucher & Compliment (`pos_order_method_id = 4`) diblokir |
| Guardrail | Peringatkan bila offline > 1 jam |
