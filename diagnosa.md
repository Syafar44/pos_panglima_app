# Diagnosa

Pengujian dari sisi Flutter untuk membuktikan penyebab POS lambat / tidak merespon di WiFi outlet — tanpa perlu akses ke server.

Konteks: pos_panglima_app (Flutter + Laravel), tablet Redmi Pad 2, multi-outlet.

Prinsip dasarnya: **client bisa membaca sinyal yang dikirim server tanpa perlu masuk ke servernya.** Beberapa pengujian di bawah cukup untuk menutup kasus sendirian.

---

## 1. Baca response header — bukti terkuat

Laravel middleware `throttle` **otomatis** menempelkan header rate limit di setiap response. Kamu tinggal membacanya.

```dart
dio.interceptors.add(InterceptorsWrapper(
  onResponse: (res, handler) {
    final h = res.headers;
    debugPrint('limit=${h.value('x-ratelimit-limit')} '
               'sisa=${h.value('x-ratelimit-remaining')} '
               'status=${res.statusCode}');
    handler.next(res);
  },
  onError: (e, handler) {
    debugPrint('TYPE=${e.type} status=${e.response?.statusCode} '
               'retry-after=${e.response?.headers.value('retry-after')}');
    handler.next(e);
  },
));
```

Cara bacanya:

- `x-ratelimit-remaining` merosot ke angka kecil di WiFi outlet tapi tetap tinggi di hotspot → dugaan rate limit per IP **terbukti**, tanpa menyentuh server.
- Muncul status **429** → tidak ada lagi yang perlu diperdebatkan.
- Header `retry-after` muncul → server memang sedang menahan kamu, bukan jaringan yang rusak.

---

## 2. Probe berlapis — pisahkan DNS / TCP / TLS

Ini yang memberitahu kamu *di lapisan mana* koneksi mati.

```dart
Future<void> probe(String host, {int port = 443}) async {
  final sw = Stopwatch()..start();

  final addrs = await InternetAddress.lookup(host);
  debugPrint('DNS  ${sw.elapsedMilliseconds}ms -> ${addrs.map((a) => a.address)}');
  debugPrint('IPv6? ${addrs.any((a) => a.type == InternetAddressType.IPv6)}');

  sw.reset();
  final s = await Socket.connect(addrs.first, port,
      timeout: const Duration(seconds: 5));
  debugPrint('TCP  ${sw.elapsedMilliseconds}ms');
  await s.close();

  sw.reset();
  final t = await SecureSocket.connect(host, port,
      timeout: const Duration(seconds: 10));
  debugPrint('TLS  ${sw.elapsedMilliseconds}ms');
  await t.close();
}
```

Tabel pembacaan:

| Yang gagal / lambat | Artinya |
|---|---|
| DNS gagal atau >2 detik | DNS router outlet bermasalah |
| DNS OK, TCP gagal / hang | conntrack router penuh, atau firewall/fail2ban |
| TCP OK, **TLS hang** | hampir pasti MTU/PPPoE — paket besar dibuang |
| Semua OK, tapi respon lama | masalah di server/query, bukan jaringan |
| Ada alamat IPv6 di daftar | curigai AAAA record yang tidak dilayani server |

Baris TLS itu yang paling penting. **TCP jalan tapi TLS menggantung** adalah tanda tangan MTU yang sangat khas, dan ini satu-satunya cara membedakannya dari sisi client.

---

## 3. Hitung request/menit yang dikirim app sendiri

Bisa diaudit tanpa jaringan outlet — cukup jalankan app normal 5 menit dan hitung.

```dart
int count = 0;
DateTime window = DateTime.now();

// di onRequest:
count++;
if (DateTime.now().difference(window).inMinutes >= 1) {
  debugPrint('=== $count request/menit ===');
  count = 0;
  window = DateTime.now();
}
```

Matematikanya: satu tablet mengirim 25 req/menit × 4 tablet di satu outlet = server melihat **100 req/menit dari satu IP**. Batas default Laravel adalah 60. Ketemu.

Sumber yang perlu ditelusuri kalau angkanya tinggi:

- `Timer.periodic` untuk auto-refresh
- polling status pesanan
- sync stok berkala
- cek notifikasi update in-app
- refresh saldo / ringkasan kasir

Sering kali ada 3–4 timer berjalan bersamaan dan tidak ada yang mematikannya saat halaman ditutup. Cek `dispose()` di setiap halaman yang punya timer.

---

## 4. Audit pagination

Bukan sekadar "ada limit atau tidak", tapi **berapa besar payload sebenarnya**.

```dart
onResponse: (res, handler) {
  final bytes = utf8.encode(jsonEncode(res.data)).length;
  debugPrint('${res.requestOptions.path} -> ${(bytes / 1024).toStringAsFixed(1)} KB');
  handler.next(res);
}
```

Urutkan hasilnya dari terbesar, lalu periksa satu per satu:

- **Riwayat / laporan transaksi** — apakah mengirim `per_page`? Berapa nilainya? Kalau tidak dikirim, kamu bergantung pada default backend yang tidak kamu kendalikan.
- **Daftar produk** — diambil ulang setiap masuk halaman kasir, atau di-cache?
- **Daftar Big Order** — filter chip (Semua / Belum lunas / Lunas / Selesai / Batal) dikirim ke server sebagai query param, atau semua data diambil lalu difilter di client? Kalau yang kedua, itu masalah.
- **Infinite scroll** — ada yang tidak pernah berhenti menambah halaman?

Ambang praktis: apa pun di atas **500 KB per request** layak dipertanyakan.

---

## 5. Klasifikasi error, jangan cuma "gagal"

```dart
switch (e.type) {
  case DioExceptionType.connectionTimeout: // jaringan / firewall
  case DioExceptionType.receiveTimeout:    // server lambat memproses
  case DioExceptionType.connectionError:   // DNS / TCP gagal total
  case DioExceptionType.badResponse:       // server menjawab, cek status code
}
```

Simpan **tipe error + timestamp + endpoint** ke file lokal di tablet. Setelah seminggu, pola akan terlihat sendiri:

- mayoritas `connectionTimeout` dan menumpuk di jam ramai → jaringan
- `receiveTimeout` menyebar rata sepanjang hari → query / server

Efek sampingnya juga bagus: pesan error yang membedakan penyebab mengubah laporan kasir dari "POS-nya error" menjadi informasi yang bisa dipakai.

---

## 6. Catatan metode

Jalankan probe di **dua tablet bersamaan** — satu di WiFi outlet, satu di hotspot, endpoint yang sama, detik yang sama.

Perbandingan berpasangan seperti ini jauh lebih kuat daripada mengukur satu per satu di waktu berbeda, karena beban server menjadi variabel konstan. Kalau diukur terpisah, kamu tidak pernah bisa membantah argumen "mungkin kebetulan servernya lagi ramai".

---

## 7. Urutan pengerjaan

1. Pasang interceptor header (bagian 1) — paling murah, potensi langsung menutup kasus.
2. Hitung request/menit (bagian 3) — bisa dikerjakan hari ini tanpa ke outlet.
3. Audit ukuran payload (bagian 4) — juga bisa dari meja sendiri.
4. Bawa dua tablet ke outlet, jalankan probe berlapis (bagian 2).
5. Pasang logging error terklasifikasi (bagian 5), biarkan berjalan seminggu.

Tiga langkah pertama tidak butuh akses ke outlet maupun ke server. Kerjakan itu dulu sebelum menjadwalkan kunjungan.
