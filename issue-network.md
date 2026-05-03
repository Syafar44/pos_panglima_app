# Issue: Submit POS Order Loading Lama (5-10 detik)

## Konteks

Saat user menekan tombol bayar pada [payment_page.dart](lib/views/pages/payment_page.dart), proses "submit order" terasa lambat (5-10 detik) sebelum UI berpindah / snackbar sukses muncul. Pertanyaan: ini masalah jaringan atau bukan?

Dokumen ini membahas kemungkinan penyebab + tahapan perbaikan, ditujukan untuk junior programmer / model AI yang lebih kecil. Setiap tahap ditulis sebagai task terpisah agar bisa dieksekusi & diverifikasi satu-per-satu.

---

## Status Eksekusi (Keputusan)

| Tahap | Status | Catatan |
|-------|--------|---------|
| 3.1 Stopwatch tiap langkah | OPSIONAL | Tools diagnosa, jalankan kalau perlu data konkret. |
| 3.2 Log ukuran payload | OPSIONAL | Sama seperti di atas. |
| 3.3 curl test | OPSIONAL | Hanya kalau hasil 3.1 menunjukkan backend lambat. |
| **4.1 Paralelisasi print + upload** | **DIIMPLEMENTASI** | Risiko minim karena transaksi berikutnya berjarak 1-2 menit. Wajib pertahankan disable button submit selama proses berjalan. |
| 4.2 Optimistic UI | DITUNDA | Belum perlu, lihat hasil 4.1 dulu. |
| 4.3 Kompres foto | TIDAK PERLU | Ukuran foto sudah kecil (50-70 KB), kompres tidak memberi dampak signifikan. |
| 4.4 Keep-alive Dio | DITUNDA | Optimasi mikro, lakukan terakhir kalau benar perlu. |
| 4.5 Network-aware retry | DITUNDA | Butuh idempotency key dari backend. |
| 4.6 Eskalasi backend | KONDISIONAL | Hanya kalau curl test (3.3) menunjukkan backend yang lambat. |
| **4.7 Popup peringatan eksekusi lama** | **DIIMPLEMENTASI** | Baru. Kalau submit > 15 detik, tampilkan dialog non-blocking agar user tahu. |

---

## 1. Apa yang Sebenarnya Terjadi Saat "Submit"

Buka [payment_page.dart:200-350](lib/views/pages/payment_page.dart#L200-L350). Dalam **satu blok try yang sama**, urutan await-nya:

1. `orderService.postOrder(payloadOrder)` — **HTTP POST** ke backend
2. `BluetoothPrinterService.printStruk(...)` — **cetak struk via Bluetooth** (sequential, blocking)
3. `cameraService.initialize()` — **inisialisasi kamera**
4. `cameraService.capture()` — **ambil foto**
5. `orderService.postLampiran(formData)` — **upload multipart** (foto bisa MB-an)
6. `clearVouchers()` + `cameraService.dispose()`

Yang dirasakan user sebagai "loading submit order" sebenarnya adalah **akumulasi** dari ke-6 langkah tersebut, bukan hanya HTTP call. Ini **clue penting**: sebelum menyimpulkan "ini masalah jaringan", kita harus tahu langkah mana yang lambat.

---

## 2. Hipotesis Penyebab

### 2.1 Network (kemungkinan tinggi)

| Penyebab | Indikasi |
|----------|----------|
| Backend lambat memproses order | `postOrder` saja sudah > 3 detik |
| Upload lampiran (foto) lambat | Foto besar (> 1 MB) + jaringan lemah |
| Latency tinggi (jaringan WiFi/3G outlet jelek) | Semua request lambat, tidak hanya POST order |
| TLS handshake mahal di setiap request | Request pertama selalu lebih lambat dari berikutnya |
| DNS lookup lambat | Delay di awal request (variabel) |
| Backend belum gzip / response besar | Response > 100 KB |

### 2.2 Non-Network (sering diabaikan)

| Penyebab | Indikasi |
|----------|----------|
| `printStruk` Bluetooth blocking | Lambat hanya kalau printer tersambung; kalau printer mati → cepat |
| Kamera init + capture (`initialize`+`capture`) lambat | Lambat di device tertentu, bisa 1-3 detik |
| File foto besar (no compression) | `postLampiran` jadi lambat, dan disk I/O juga |
| Dio belum reuse koneksi (no keep-alive adapter) | Setiap request membuka socket baru |
| Sequential await yang harusnya bisa paralel | Cetak struk + upload foto dilakukan satu-per-satu |
| `setState` berat saat building list cart yang panjang | Frame drop sebelum/sesudah submit |

**Kesimpulan awal:** kemungkinan besar campuran (1) backend + (2) cetak struk + (3) capture+upload foto. Jangan langsung asumsikan "ini network" sebelum diukur.

---

## 3. Tahap Diagnosa (Sebelum Perbaikan)

> **Penting:** Jangan langsung "perbaiki" sebelum tahu sumbernya. Salah diagnosa = waste effort.

### Tahap 3.1 — Tambah Stopwatch untuk Tiap Langkah

**Tujuan:** ukur durasi tiap langkah submit secara terpisah.

**File:** [lib/views/pages/payment_page.dart](lib/views/pages/payment_page.dart)

**Apa yang dilakukan:**
1. Cari fungsi yang berisi blok `try { ... orderService.postOrder ... }` (sekitar [line 200](lib/views/pages/payment_page.dart#L200)).
2. Sebelum tiap `await` (postOrder, printStruk, cameraService.initialize, capture, postLampiran), ukur waktunya:

   ```dart
   final sw = Stopwatch()..start();
   final response = await orderService.postOrder(payloadOrder);
   debugPrint('[TIMING] postOrder: ${sw.elapsedMilliseconds}ms');
   sw.reset();

   await BluetoothPrinterService.printStruk(...);
   debugPrint('[TIMING] printStruk: ${sw.elapsedMilliseconds}ms');
   sw.reset();
   ```

3. Lakukan submit 5x di kondisi normal, **catat hasil rata-rata** untuk tiap langkah.
4. Lakukan 5x lagi di kondisi jaringan jelek (matikan WiFi, pakai data seluler).
5. Lakukan 5x dengan printer **mati** (untuk isolasi efek printStruk).

**Output yang diharapkan:** tabel seperti ini:

| Langkah | WiFi normal | Data seluler | Printer mati |
|---------|-------------|--------------|--------------|
| postOrder | ?? ms | ?? ms | ?? ms |
| printStruk | ?? ms | ?? ms | ?? ms |
| cameraService.initialize | ?? ms | ?? ms | ?? ms |
| capture | ?? ms | ?? ms | ?? ms |
| postLampiran | ?? ms | ?? ms | ?? ms |

**Kriteria selesai:** sudah punya angka konkret untuk tiap langkah. Tanpa data ini, semua "perbaikan" hanya tebak-tebakan.

### Tahap 3.2 — Cek Ukuran Payload & Response

**Tujuan:** pastikan payload tidak abnormal besar.

**Apa yang dilakukan:**
1. Tambah Dio interceptor sementara di [dio_client.dart](lib/services/helper/dio_client.dart) untuk log ukuran request/response:

   ```dart
   onRequest: (options, handler) {
     debugPrint('[NET] ${options.method} ${options.path} '
                'body=${options.data?.toString().length ?? 0}B');
     handler.next(options);
   },
   onResponse: (response, handler) {
     debugPrint('[NET] ${response.statusCode} ${response.requestOptions.path} '
                'resp=${response.data?.toString().length ?? 0}B');
     handler.next(response);
   },
   ```

2. Lakukan submit, lihat ukuran:
   - Body `postOrder`: harusnya < 5 KB.
   - Body `postLampiran`: ini yang paling besar (foto). Catat MB-nya.
   - Response: kalau > 50 KB curigai backend mengirim data berlebihan.

**Kriteria selesai:** tahu ukuran kira-kira tiap call.

### Tahap 3.3 — Cek dengan curl/Postman dari Device atau Komputer Outlet

**Tujuan:** isolasi apakah lambat di app atau di backend.

**Apa yang dilakukan:**
1. Ambil endpoint POST `/pos/order` (lihat [order_service.dart:9](lib/services/order_service.dart#L9)).
2. Dari komputer di outlet yang sama, jalankan curl:
   ```bash
   curl -w "@curl-format.txt" -o /dev/null -s -X POST <BASE_URL>/pos/order \
        -H "Authorization: Bearer <token>" -H "apikey: <key>" \
        -d '<payload-json>'
   ```
   Dengan `curl-format.txt` berisi:
   ```
   time_namelookup:  %{time_namelookup}\n
   time_connect:     %{time_connect}\n
   time_appconnect:  %{time_appconnect}\n
   time_starttransfer: %{time_starttransfer}\n
   time_total:       %{time_total}\n
   ```
3. Bandingkan `time_total` curl vs `[TIMING] postOrder` di tahap 3.1.
   - Kalau curl juga lambat → masalah backend / network ISP. Bukan tugas Flutter.
   - Kalau curl cepat tapi app lambat → masalah di sisi Dio/Flutter.

**Kriteria selesai:** tahu apakah backend itu sendiri lambat.

---

## 4. Tahapan Perbaikan (Berdasarkan Hasil Diagnosa)

> Lakukan **berurutan dari yang paling mungkin berdampak** ke yang spekulatif. Setiap tahap satu PR/commit terpisah agar mudah di-revert kalau tidak membantu.

### Tahap 4.1 — Paralelkan Print Struk + Upload Foto (Dampak Tinggi) ✅ DIIMPLEMENTASI

**Asumsi:** print struk dan upload foto tidak saling tergantung — keduanya bisa dijalankan paralel setelah `postOrder` selesai.

**Konteks tambahan (kenapa risiko minim):** transaksi berikutnya di outlet ini berjarak rata-rata 1-2 menit, jadi kalau ada efek samping race condition (mis. print masih jalan saat upload selesai), user masih punya buffer waktu. **Wajib:** tombol submit harus tetap di-disable selama proses berjalan agar tidak ada double tap.

**File:** [payment_page.dart:200-350](lib/views/pages/payment_page.dart#L200-L350)

**Apa yang dilakukan:**

1. Saat ini struktur sequential:
   ```dart
   final response = await orderService.postOrder(...);     // 1. butuh dulu
   await BluetoothPrinterService.printStruk(...);          // 2. cetak
   await cameraService.initialize();                       // 3. init kamera
   final file = await cameraService.capture();             // 4. ambil foto
   await orderService.postLampiran(formData);              // 5. upload foto
   ```

2. Refactor agar setelah `postOrder` selesai, jalankan paralel:
   ```dart
   final response = await orderService.postOrder(payloadOrder);
   final orderId = response.data['data']['id'];
   final documentNumber = response.data['data']['document_number'];

   final printFuture = BluetoothPrinterService.printStruk(...);

   final uploadFuture = () async {
     await cameraService.initialize();
     final file = await cameraService.capture();
     if (file == null) return;
     final formData = FormData.fromMap({...});
     await orderService.postLampiran(formData);
   }();

   await Future.wait([printFuture, uploadFuture]);
   ```

3. **Hati-hati:** `cameraService.dispose()` harus tetap dipanggil di akhir (di `finally` block) supaya kamera tidak leak.

**Cara verifikasi:**
- Stopwatch total submit harus turun. Contoh: kalau printStruk 2s + upload 3s sequential → 5s, paralel → ~3s.
- Kalau printer mati / tidak terhubung, tidak boleh menghambat upload (cek logic `printStruk` apakah throw atau diam).

### Tahap 4.2 — Optimistic UI / Tampilkan Sukses Lebih Cepat

**Asumsi:** user tidak perlu menunggu cetak struk + upload foto selesai untuk pindah halaman. Yang penting `postOrder` sudah sukses (transaksi terekam di backend).

**File:** [payment_page.dart](lib/views/pages/payment_page.dart)

**Apa yang dilakukan:**
1. Setelah `postOrder` sukses, langsung:
   - Tampilkan snackbar "Transaksi berhasil"
   - Pindah ke halaman berikutnya / reset cart
2. Print struk + upload foto dijalankan di **background** (tidak di-await) dengan handler error sendiri.

**Risiko & mitigasi:**
- Kalau print/upload gagal di background, user sudah pindah halaman → **wajib** ada queue retry. Print queue sudah ada di [bluetooth_printer_service.dart:319](lib/services/bluetooth_printer_service.dart#L319) (`_processQueue`). Untuk upload foto, perlu dibuat queue serupa atau simpan ke local + retry.
- Tampilkan indikator kecil di pojok bahwa "sedang mencetak / mengunggah" agar user paham masih ada proses.

**Catatan:** Jangan lakukan tahap ini sebelum tahap 4.1, karena queue yang baik baru bisa dirancang setelah arsitektur paralel jelas.

### Tahap 4.3 — Kompres Foto Sebelum Upload ❌ TIDAK DILAKUKAN

**Alasan dilewati:** ukuran foto bukti pembayaran yang dihasilkan `cameraService.capture()` saat ini sudah sangat kecil (~50-70 KB). Kompres tidak memberi dampak terukur, dan menambah dependency baru tanpa benefit nyata adalah overhead.

**Kapan tahap ini perlu ditinjau ulang:** kalau resolusi kamera dinaikkan (mis. ganti device dengan kamera lebih tinggi) atau backend mulai meminta resolusi lebih tinggi → ukuran foto naik > 500 KB. Saat itu baru pertimbangkan kompres.

### Tahap 4.4 — Aktifkan HTTP Keep-Alive di Dio

**Asumsi:** setiap request saat ini membuka koneksi TCP+TLS baru. Kalau hipotesis tahap 3.1 menunjukkan request kedua lebih cepat dari pertama, kemungkinan ini benar.

**File:** [dio_client.dart](lib/services/helper/dio_client.dart)

**Apa yang dilakukan:**
1. Ganti adapter Dio agar reuse koneksi:
   ```dart
   import 'package:dio/io.dart';
   import 'dart:io';

   dio.httpClientAdapter = IOHttpClientAdapter(
     createHttpClient: () {
       final client = HttpClient();
       client.idleTimeout = const Duration(seconds: 30);
       return client;
     },
   );
   ```
2. **Verifikasi tidak merusak interceptor token** — uji login + 1 transaksi end-to-end.

**Catatan:** ini optimasi mikro (hemat 100-300ms per request setelah call pertama). Hanya lakukan kalau Tahap 3.1 / 3.3 menunjukkan TLS handshake jadi bottleneck.

### Tahap 4.5 — Tambah Network-Aware Timeout & Retry

**Asumsi:** kadang request lambat karena jaringan timeout, dan user retry manual. Lebih baik retry otomatis untuk request idempotent.

**File:** [dio_client.dart](lib/services/helper/dio_client.dart)

**Apa yang dilakukan:**
1. **JANGAN** retry `postOrder` otomatis — bisa double order. Order POST harus idempotent dulu di backend (pakai client-side request id).
2. Boleh retry untuk:
   - `getProfile`, `getCurrentShift`, dan GET lainnya
   - `postLampiran` (kalau backend pakai upsert berdasar `pos_orders_id`)
3. Tambah timeout berbeda per endpoint:
   - Default 30s sudah ada.
   - `postOrder`: turunkan ke 15s (kalau lebih dari itu, hampir pasti backend overload).
4. Kalau timeout: tampilkan error yang jelas + opsi "Coba Lagi", **bukan** retry diam-diam.

### Tahap 4.6 — Review Backend (Bukan Tugas Flutter)

Kalau Tahap 3.3 (curl) menunjukkan backend itu sendiri yang lambat untuk `POST /pos/order`, ini **bukan** masalah app. Eskalasi ke tim backend dengan data:
- Sample timing curl
- Ukuran payload + response
- Jam saat lambat (untuk korelasi dengan load server)
- IP outlet (untuk korelasi dengan ISP)

### Tahap 4.7 — Popup Peringatan Eksekusi Lama ✅ DIIMPLEMENTASI

**Tujuan:** kalau proses submit memakan waktu > 15 detik (mis. karena jaringan turun di tengah jalan), tampilkan dialog non-blocking agar user tahu apa yang terjadi dan tidak menyangka aplikasi crash.

**File:** [payment_page.dart](lib/views/pages/payment_page.dart)

**Apa yang dilakukan:**
1. Saat `handlePayment()` dimulai, jalankan `Timer(Duration(seconds: 15), ...)`.
2. Kalau timer selesai dan submit **masih jalan** (`isLoading == true`), tampilkan dialog dengan pesan:
   - Judul: "Pemrosesan Lama"
   - Isi: "Transaksi memakan waktu lebih lama dari biasanya. Periksa koneksi internet Anda. Jangan tutup aplikasi — proses tetap berjalan di latar."
   - Tombol: "Tutup" (cukup menutup dialog, **tidak** memicu retry).
3. Saat `handlePayment` selesai (sukses atau error) di blok `finally`, panggil `timer.cancel()` agar dialog tidak nyangkut muncul setelah selesai.

**Kenapa tidak ada tombol "Coba Lagi" di dialog:** `postOrder` mungkin sudah berhasil di backend tapi response belum sampai ke client. Kalau user tap retry → double order. Aman: cukup beritahu user, biarkan submit selesai sendiri (atau gagal dengan timeout Dio 30s).

**Cara verifikasi:**
- Jalankan submit di kondisi normal → dialog **tidak** muncul.
- Matikan WiFi tepat setelah tap "Selesaikan Pembayaran" → dialog harus muncul setelah ~15 detik, lalu Dio timeout (~30s) memunculkan modal error.
- Submit normal yang selesai dalam 5 detik → dialog tidak boleh muncul belakangan.

---

## 5. Urutan Prioritas Eksekusi

### Yang dieksekusi sekarang
1. **Tahap 4.1** — paralelisasi `printStruk` + camera+upload setelah `postOrder` selesai.
2. **Tahap 4.7** — popup peringatan kalau submit > 15 detik.

Pastikan tombol submit tetap di-disable selama `isLoading == true` (sudah ada via `onPressed: isLoading ? null : handlePayment` di [payment_page.dart](lib/views/pages/payment_page.dart) — **jangan dihapus**).

### Yang ditunda / kondisional
- **Tahap 3.1 / 3.2 / 3.3** (diagnosa) — jalankan kalau perbaikan 4.1 + 4.7 belum cukup.
- **Tahap 4.2** (optimistic UI) — kalau hasil 4.1 masih kurang.
- **Tahap 4.4** (keep-alive) — optimasi mikro.
- **Tahap 4.5** (retry) — butuh idempotency key di backend.
- **Tahap 4.6** (eskalasi backend) — kalau curl test menunjukkan backend lambat.

### Yang tidak akan dilakukan
- **Tahap 4.3** (kompres foto) — sudah kecil (50-70 KB), tidak ada manfaat.

---

## 6. Definition of Done

Fitur dianggap selesai kalau:

- [ ] Ada hasil pengukuran (Tahap 3.1) sebelum & sesudah perbaikan, ditempel di PR description.
- [ ] Total durasi dari tap "Bayar" sampai UI berpindah/snackbar sukses **< 3 detik** di jaringan normal.
- [ ] Tidak ada regresi: print struk tetap keluar, foto tetap ter-upload.
- [ ] Kalau print/upload gagal, user tetap dapat notifikasi (tidak silent fail).
- [ ] Tidak ada double order saat user double-tap tombol bayar (cek ada guard `isLoading` / `isSubmitting`).

---

## 7. Hal yang HARUS Dihindari

- **Jangan** melakukan retry otomatis `postOrder` tanpa idempotency key dari backend → bisa double charge.
- **Jangan** menjalankan `postOrder` di background tanpa await → user tidak tahu kalau gagal.
- **Jangan** menambah dependency baru (kompres, retry library) tanpa konfirmasi senior.
- **Jangan** menyentuh `dio_client.dart` tanpa testing semua flow login & transaksi end-to-end — ini singleton dipakai semua service.
- **Jangan** menghapus `cameraService.dispose()` saat refactor — kamera akan stuck di device.
- **Jangan** asumsi "ini pasti masalah backend" tanpa data dari Tahap 3.3.
