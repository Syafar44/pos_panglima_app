# State Loading di Mobile App: Masalah & Solusi

> Panduan lengkap mengelola loading state pada aplikasi mobile — mencakup kendala jaringan, state management, UX, dan masalah spesifik mobile.

---

## Kenapa State Loading Harus Dijaga?

Loading state adalah jembatan antara aksi pengguna dan respons sistem. Kalau tidak dijaga dengan baik, pengalaman pengguna bisa rusak — bahkan di sisi fungsional sekalipun. Tiga dampak utama kalau loading state tidak dikelola:

- **UI "hang"** — spinner berputar tanpa henti tanpa ada resolusi
- **Data kacau** — race condition membuat data tampil tidak konsisten
- **Crash** — `setState()` dipanggil pada widget yang sudah di-dispose

---

## 1. Masalah Jaringan

### 1.1 Timeout / Koneksi Lambat

**Masalah:** Request dikirim tapi server tidak merespons dalam waktu wajar. App terasa "hang" tanpa kejelasan kepada pengguna.

**Solusi:**
- Pasang batas waktu eksplisit (disarankan 15–30 detik)
- Tampilkan pesan informatif: *"Koneksi lambat, harap tunggu…"*
- Sediakan tombol **Retry** setelah timeout

```dart
// Flutter - set timeout eksplisit
http.get(uri).timeout(
  Duration(seconds: 15),
  onTimeout: () => throw TimeoutException('Request timeout'),
);
```

---

### 1.2 Tidak Ada Koneksi Internet

**Masalah:** User melakukan aksi tanpa koneksi. App loading terus atau crash diam-diam tanpa memberi tahu pengguna.

**Solusi:**
- Cek status koneksi **sebelum** request (gunakan package `connectivity_plus` di Flutter)
- Tampilkan UI khusus "Tidak ada koneksi" dengan opsi refresh
- Implementasi **offline mode** / cache untuk data kritis

```dart
// Cek koneksi sebelum request
final connectivityResult = await Connectivity().checkConnectivity();
if (connectivityResult == ConnectivityResult.none) {
  showNoConnectionUI();
  return;
}
```

---

### 1.3 Koneksi Terputus di Tengah Request

**Masalah:** Request sudah dimulai, lalu sinyal hilang tiba-tiba. State loading tidak pernah berubah karena callback tidak terpanggil.

**Solusi:**
- Tangkap exception `SocketException` / `NetworkException`
- Reset loading state **selalu** di blok `finally`
- Simpan state "pending" agar bisa dilanjutkan saat koneksi kembali

```dart
try {
  setState(() => isLoading = true);
  await fetchData();
} on SocketException {
  showError('Koneksi terputus. Periksa jaringan Anda.');
} finally {
  setState(() => isLoading = false); // WAJIB — selalu reset!
}
```

---

### 1.4 Server Error (5xx) atau Client Error (4xx)

**Masalah:** Request berhasil sampai ke server, tapi server membalas dengan kode error. Banyak app mengabaikan ini dan tetap menampilkan loading.

**Solusi:**
- Parsing status code HTTP secara eksplisit — jangan hanya cek apakah request "selesai"
- Bedakan pesan error sesuai konteks:
  - `500` → "Server sedang gangguan, coba beberapa saat lagi"
  - `404` → "Data tidak ditemukan"
  - `401/403` → redirect ke halaman login

```dart
final response = await http.get(uri);

switch (response.statusCode) {
  case 200:
    handleSuccess(response.body);
    break;
  case 401:
  case 403:
    redirectToLogin();
    break;
  case 404:
    showError('Data tidak ditemukan');
    break;
  case 500:
  default:
    showError('Server sedang gangguan. Coba lagi nanti.');
}
```

---

## 2. Masalah State Management

### 2.1 Loading State Tidak Direset

**Masalah:** Exception tidak tertangkap → `isLoading` tetap `true` → spinner berputar selamanya.

**Pola yang benar:** Loading **wajib** direset di `finally`, bukan hanya di blok sukses.

```dart
// ❌ SALAH — loading tidak direset saat error
Future<void> fetchData() async {
  isLoading = true;
  final data = await api.getData(); // kalau ini throw, isLoading tidak pernah false
  isLoading = false;
}

// ✅ BENAR — finally menjamin reset selalu terjadi
Future<void> fetchData() async {
  try {
    setState(() => isLoading = true);
    final data = await api.getData();
    setState(() => this.data = data);
  } catch (e) {
    setState(() => errorMessage = e.toString());
  } finally {
    setState(() => isLoading = false); // selalu dieksekusi
  }
}
```

---

### 2.2 Race Condition

**Masalah:** User menekan tombol berkali-kali → multiple request berjalan bersamaan → respons datang tidak berurutan → data tampil kacau atau tidak konsisten.

**Solusi:**
- Nonaktifkan tombol saat loading berlangsung
- Gunakan teknik **debounce** atau **cancel token**
- Batalkan request sebelumnya jika ada request baru

```dart
// Menggunakan CancelToken (Dio)
CancelToken? _cancelToken;

Future<void> fetchData() async {
  _cancelToken?.cancel('Request baru dimulai'); // batalkan yang lama
  _cancelToken = CancelToken();

  try {
    setState(() => isLoading = true);
    final response = await dio.get(url, cancelToken: _cancelToken);
    setState(() => data = response.data);
  } on DioException catch (e) {
    if (!CancelToken.isCancel(e)) {
      showError(e.message);
    }
  } finally {
    setState(() => isLoading = false);
  }
}
```

---

### 2.3 `setState()` Setelah Widget Dispose

**Masalah:** Request selesai tapi user sudah pindah halaman → `setState()` dipanggil di widget yang sudah tidak ada di widget tree → **crash**.

**Solusi:** Selalu cek `mounted` sebelum memanggil `setState()`.

```dart
Future<void> fetchData() async {
  final result = await api.getData();

  // Cek mounted sebelum setState
  if (!mounted) return;
  setState(() {
    data = result;
    isLoading = false;
  });
}
```

---

### 2.4 Loading Terlalu Cepat (Flash / Flicker)

**Masalah:** Loading muncul lalu langsung hilang dalam < 200ms → UI "kedip" yang tidak nyaman dilihat pengguna.

**Solusi:** Pasang minimum durasi tampil loading (150–300ms) agar transisi terasa halus.

```dart
Future<void> fetchWithMinDuration() async {
  setState(() => isLoading = true);

  await Future.wait([
    api.getData(),
    Future.delayed(Duration(milliseconds: 300)), // minimum tampil
  ]);

  setState(() => isLoading = false);
}
```

---

## 3. Masalah UX & Tampilan

| Masalah | Dampak | Solusi |
|---|---|---|
| Tidak ada indikator loading | User bingung, merasa app tidak responsif | Selalu tampilkan spinner, shimmer, atau skeleton UI |
| Loading menghalangi seluruh layar | Blokir interaksi lain yang tidak perlu diblokir | Pakai partial/inline loading untuk refresh data |
| Tidak ada feedback saat gagal | User tidak tahu apa yang terjadi | Wajib tampilkan pesan error yang actionable + tombol retry |
| Tombol masih bisa diklik saat loading | Memicu race condition | Disable semua tombol terkait saat loading |
| Tidak ada batas waktu loading | Spinner muter selamanya | Selalu pasang timeout + opsi retry |
| Skeleton/shimmer tidak sesuai layout | Transisi terasa "loncat" | Sesuaikan skeleton dengan bentuk konten aslinya |

---

### Pilihan Indikator Loading

```
Spinner         → Aksi singkat, tidak diketahui durasinya
Progress Bar    → Upload/download dengan progress yang bisa dihitung
Skeleton/Shimmer → List atau konten terstruktur (pengalaman terbaik)
Overlay penuh   → Hanya untuk aksi kritis yang memblokir (misal: submit pembayaran)
Inline indicator → Refresh/lazy load di tengah halaman
```

---

## 4. Masalah Spesifik Mobile

### 4.1 App ke Background Saat Loading

**Masalah:** User switch app atau layar mati di tengah request → callback bisa tidak dipanggil atau timer menjadi tidak akurat.

**Solusi:** Handle `AppLifecycleState` — batalkan atau simpan ulang request saat app kembali ke foreground.

```dart
class _MyWidgetState extends State<MyWidget> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isLoading) {
      // App kembali ke foreground — restart request jika perlu
      retryRequest();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
```

---

### 4.2 Rotasi Layar / Widget Rebuild

**Masalah:** Rotasi layar memicu rebuild widget → loading state hilang atau request dipanggil ulang dari awal.

**Solusi:** Gunakan state management yang survive rebuild (Provider, Riverpod, BLoC) — jangan simpan loading state hanya di `StatefulWidget` lokal untuk operasi panjang.

```dart
// ❌ SALAH — state hilang saat rotate (StatefulWidget lokal)
class _FetchWidgetState extends State<FetchWidget> {
  bool isLoading = false; // hilang saat rebuild
}

// ✅ BENAR — pakai Provider/Riverpod agar state persisten
final dataProvider = FutureProvider<List<Item>>((ref) async {
  return await api.getItems(); // tidak di-trigger ulang saat rebuild
});
```

---

### 4.3 Memory Leak

**Masalah:** Stream atau listener tidak dibersihkan → loading state terus berjalan di background → konsumsi memori terus naik.

**Solusi:** Selalu `dispose()` controller dan batalkan subscription di `dispose()`.

```dart
class _MyWidgetState extends State<MyWidget> {
  StreamSubscription? _subscription;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _subscription?.cancel();  // batalkan stream
    _cancelToken?.cancel();   // batalkan request aktif
    super.dispose();
  }
}
```

---

## 5. Pola Ideal: Alur Loading yang Aman

```
User Action
    │
    ▼
Cek koneksi internet
    │
    ├── Tidak ada ──► Tampilkan UI "Offline" + tombol retry
    │
    ▼
Set isLoading = true
Disable tombol / input
    │
    ▼
Kirim request (dengan timeout & cancel token)
    │
    ├── [try] Berhasil ────────► Tampilkan data
    │
    ├── [catch] Timeout ───────► "Koneksi lambat" + Retry
    │
    ├── [catch] Network Error ──► "Koneksi terputus" + Retry
    │
    ├── [catch] 4xx/5xx ────────► Pesan error spesifik + Retry
    │
    └── [finally] ─────────────► isLoading = false
                                 Enable kembali tombol / input
```

> **Aturan emas:** Loading state harus **selalu punya jalan keluar** — baik sukses maupun gagal. Tidak boleh ada kondisi di mana loading bisa "nyangkut" selamanya tanpa feedback ke pengguna.

---

## Referensi Package (Flutter)

| Kebutuhan | Package |
|---|---|
| Cek status koneksi | `connectivity_plus` |
| HTTP client dengan cancel token | `dio` |
| State management | `riverpod` / `flutter_bloc` / `provider` |
| Skeleton loading | `shimmer` / `skeletonizer` |
| Debounce input | `rxdart` |
