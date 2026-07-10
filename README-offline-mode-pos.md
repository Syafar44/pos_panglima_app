# Panduan Implementasi Offline Mode pada POS

Dokumen ini merangkum metode dan hal-hal yang **wajib diperhatikan** saat mengimplementasikan offline mode pada aplikasi POS, dengan fokus khusus pada pencegahan **selisih** dan **missing data**, terutama pada stok.

## Prinsip Inti

> **Transaksi penjualan adalah fakta yang tidak boleh hilang, sedangkan stok adalah angka turunan yang harus direkonsiliasi server — bukan sesuatu yang divalidasi ketat di sisi device saat offline.**

Begitu kerangka berpikir ini dipegang, sebagian besar keputusan desain menjadi jelas.

---

## 1. Local-First sebagai Fondasi

Setiap transaksi harus ditulis ke database lokal lebih dulu dan **selalu** berhasil, terlepas ada koneksi atau tidak. Jangan pernah menjadikan keberhasilan transaksi bergantung pada response server.

- Untuk data relasional POS (`order`, `order_items`, `payments`, `stock_movements`), gunakan **Drift** atau **sqflite** ketimbang Hive/Isar — karena dibutuhkan query agregasi dan transaksi ACID lokal, bukan sekadar key-value.
- Kalau kasir sudah menerima uang dan barang sudah keluar toko, transaksi itu **sudah terjadi di dunia nyata**. Tidak boleh ada skenario di mana sync gagal lalu transaksi hilang.
- Penjualan offline dicatat sebagai kebenaran; selisih stok ditangani belakangan lewat rekonsiliasi — **bukan dengan menolak sync**.

---

## 2. Outbox Pattern (Antrian Sinkronisasi)

Buat tabel antrian terpisah (`sync_queue`) dengan kolom: `status` (`pending` / `syncing` / `synced` / `failed`), `payload`, `retry_count`, dan `timestamp`. Sebuah worker akan menguras antrian saat online.

- Deteksi koneksi dengan `connectivity_plus`.
- Jalankan di background dengan `workmanager` (opsional).

**Wajib diperhatikan:**

- **Jangan hapus item dari antrian sampai server mengirim ACK eksplisit.** Penyebab paling umum missing data adalah menandai "synced" setelah request terkirim, padahal response belum sampai.
- Antrian harus **persisten dan tahan crash**: jika app di-kill atau tablet reboot di tengah sync, antrian harus tetap utuh saat app dibuka lagi.
- Retry dengan **exponential backoff**, dan batasi agar item yang gagal terus tidak memblokir item lain.

---

## 3. Idempotency

Setiap transaksi mendapat **UUID yang digenerate di client** sebagai *idempotency key*. Server melakukan dedup berdasarkan UUID ini.

- Jika client mengirim ulang karena tidak menerima ACK (padahal server sebenarnya sudah memproses), server tidak menghitung dobel.
- Prinsip ini sama dengan logika anti-duplicate-submission pada payment flow, tetapi kini berlaku di **seluruh layer sync**, bukan hanya saat online.

---

## 4. Stok — Bagian Paling Kritis

Tiga aturan yang mencegah selisih:

### a. Kirim delta, bukan nilai absolut
Device **tidak boleh** mengirim `stok produk X = 47`. Device mengirim `terjual 3 unit produk X` (delta `−3`), lalu server yang menerapkan delta ke angka otoritatifnya. Mengirim nilai absolut membuat dua device offline saling menimpa dan dipastikan menghasilkan selisih.

### b. Catat pergerakan stok sebagai append-only log
Buat tabel `stock_movements` dengan field: `jenis` (`sale`, `restock`, `adjustment`, `transfer`), `qty`, `ref_transaksi`, `timestamp`, `device_id`.

- Stok aktual = hasil **agregasi log**, bukan satu kolom angka yang terus ditimpa.
- Ini adalah event-sourcing versi ringan: server bisa menghitung ulang stok dari nol kapan saja, dan setiap selisih dapat ditelusuri sampai ke event penyebabnya.

### c. Server adalah satu-satunya sumber kebenaran stok
- Stok yang ditampilkan di tablet adalah **snapshot/cache** — tandai sebagai estimasi dan tampilkan waktu sync terakhir.
- Jangan biarkan kasir menganggap angka stok di layar sebagai kebenaran mutlak saat offline dalam waktu lama.

---

## 5. Overselling: Terima, Deteksi, Laporkan — Jangan Cegah

Jika dua tablet di outlet yang sama sama-sama offline dan keduanya menjual unit terakhir, saat sync stok akan menjadi `−1`.

- **Tidak ada cara sempurna mencegah ini selama device offline** — ini sifat dari *shared mutable state* tanpa koordinasi.
- Rancang sistem untuk **mendeteksi dan melaporkan**, bukan menolak sync (barang sudah terlanjur keluar).
- Server menerima kedua transaksi, stok menjadi negatif, lalu **di-flag untuk rekonsiliasi** dan muncul di laporan harian sebagai anomali.

### Pengaruh topologi outlet

| Topologi | Kompleksitas konflik |
|----------|----------------------|
| **Satu tablet per outlet** | Konflik praktis nyaris tidak ada — hanya satu device yang menyentuh stok outlet. Server tinggal menerapkan delta berurutan. |
| **Beberapa tablet berbagi stok satu outlet** | Kasus konkuren yang sulit; butuh strategi flag/rekonsiliasi di atas, plus kemungkinan konsep stok "reserved". |

> **Catatan untuk `pos_panglima_app`:** Karena menargetkan banyak outlet di Redmi Pad 2, pastikan dulu apakah **satu tablet per outlet** atau **beberapa tablet per outlet**. Jawaban ini menentukan seberapa besar effort pada conflict resolution.

---

## 6. Urutan & Jam (Penyebab Selisih yang Halus)

- Jangan percaya jam device untuk mengurutkan event antar-device — jam tablet bisa salah set.
- Pakai **sequence number per device** (counter monotonik yang naik tiap event) + `device_id`, sehingga server dapat mendeteksi *gap* (menerima seq 1, 2, 4 berarti seq 3 hilang dan harus diminta ulang).
- Untuk urutan global, biarkan **server** yang menetapkan urutan final saat menerima.
- Timestamp (WIB) tetap berguna untuk **audit**, tetapi bukan untuk menentukan urutan otoritatif.

---

## 7. Master Data (Produk & Harga) — Arah Berlawanan

- Aliran data untuk produk, harga, dan diskon: **satu arah dari server ke client** (last-write-wins dari server).
- Client **tidak boleh** memodifikasi master data saat offline.
- Tarik update master saat online, simpan lokal; transaksi offline merujuk ke versi master yang ada saat itu.
- Simpan `price_at_sale` di `order_item` agar kalau harga berubah setelah sync, nilai transaksi historis **tidak ikut berubah**.

---

## 8. Guardrail Operasional

- Indikator offline yang jelas di UI kasir.
- Batas durasi maksimal device boleh offline sebelum dipaksa sync.
- Laporan rekonsiliasi harian yang menyorot stok negatif/anomali untuk dicek manual oleh tim outlet.

---

## 9. Skenario Testing yang Wajib

Uji eksplisit (jangan diasumsikan):

1. **Penjualan konkuren** dari beberapa device dalam kondisi offline.
2. **Koneksi putus di tengah sync** (sebelum ACK diterima).
3. **App di-kill / tablet reboot** saat antrian masih berisi.
4. **Kirim ulang transaksi** yang server sebenarnya sudah proses (uji idempotency).

> Jika keempat skenario ini lolos tanpa selisih atau data hilang, arsitektur sudah solid.

---

## Ringkasan Cepat

| Area | Aturan kunci |
|------|--------------|
| Transaksi | Local-first, selalu berhasil, tidak bergantung server |
| Sync | Outbox pattern, hapus dari antrian hanya setelah ACK |
| Dedup | UUID idempotency key dari client |
| Stok | Kirim **delta**, simpan **append-only log**, server = sumber kebenaran |
| Overselling | Terima → deteksi → flag → laporkan; jangan cegah |
| Urutan | Sequence number per device, server tetapkan urutan final |
| Master data | Satu arah server → client, simpan `price_at_sale` |

---

## Langkah Berikutnya (opsional)

- Rancang skema konkret tabel `sync_queue` dan `stock_movements` untuk Drift/sqflite.
- Desain endpoint sync batch di sisi Laravel (handling idempotency key + response delta stok).
- Tentukan topologi outlet (satu vs banyak tablet) sebagai dasar detail conflict resolution.
