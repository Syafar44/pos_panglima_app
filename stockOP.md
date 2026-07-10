# Update: Stock Opname Page

Dokumen ini berisi rencana perubahan untuk [lib/views/pages/stock_opname_page.dart](lib/views/pages/stock_opname_page.dart).

## Ringkasan Kebutuhan

1. **Tombol kembali (AppBar)** — saat user menekan kembali, cek apakah ada perubahan yang belum disimpan sebagai draft. Kalau ada, tampilkan modal peringatan dengan 2 tombol: **Batal** dan **Simpan Draft**. Tombol "Simpan Draft" memakai fungsi yang sudah ada (`_saveDraft`).
2. **Deteksi perubahan** — bandingkan data baseline (saat data dimuat) dengan data sekarang (qty aktual + keterangan tiap item). Kalau berbeda → ada perubahan → trigger peringatan.
3. **Fungsi `_submit`** — sebelum submit, simpan draft dulu baru submit, supaya tidak ada data yang hilang.

---

## Perubahan 1 — Deteksi Perubahan (Baseline Snapshot)

Tambahkan baseline ke `_StockOpnameItem` supaya bisa dibandingkan apakah ada perubahan. Header (tanggal, status, outlet, remarks) bersifat **read-only** dari server, jadi yang dibandingkan adalah data baris: **qty aktual** + **keterangan**.

### 1a. Update class `_StockOpnameItem`

**Before:**

```dart
class _StockOpnameItem {
  final int id;
  final String itemCode;
  final String itemName;
  final String uomCode;
  final int systemQty;
  final TextEditingController qtyController;
  final TextEditingController remarksController;

  _StockOpnameItem({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.uomCode,
    this.systemQty = 0,
    int actualQty = 0,
    String remarks = '',
  }) : qtyController = TextEditingController(
         text: actualQty > 0 ? '$actualQty' : '',
       ),
       remarksController = TextEditingController(text: remarks);

  void dispose() {
    qtyController.dispose();
    remarksController.dispose();
  }

  Map<String, dynamic> toUpdatePayload() => {
    'id': id,
    'actual_qty': int.tryParse(qtyController.text.trim()) ?? 0,
    'remarks': remarksController.text.trim(),
  };
}
```

**After:**

```dart
class _StockOpnameItem {
  final int id;
  final String itemCode;
  final String itemName;
  final String uomCode;
  final int systemQty;
  final TextEditingController qtyController;
  final TextEditingController remarksController;

  // Baseline untuk deteksi perubahan. Di-set saat data dimuat / setelah
  // draft tersimpan. Mutable supaya bisa di-commit ulang setelah simpan.
  int _baselineQty;
  String _baselineRemarks;

  _StockOpnameItem({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.uomCode,
    this.systemQty = 0,
    int actualQty = 0,
    String remarks = '',
  }) : qtyController = TextEditingController(
         text: actualQty > 0 ? '$actualQty' : '',
       ),
       remarksController = TextEditingController(text: remarks),
       _baselineQty = actualQty,
       _baselineRemarks = remarks;

  /// True kalau qty aktual atau keterangan berbeda dari baseline terakhir.
  bool get isDirty {
    final currentQty = int.tryParse(qtyController.text.trim()) ?? 0;
    return currentQty != _baselineQty ||
        remarksController.text.trim() != _baselineRemarks;
  }

  /// Jadikan nilai sekarang sebagai baseline baru.
  /// Panggil setelah draft berhasil disimpan supaya tidak dianggap "dirty" lagi.
  void commitBaseline() {
    _baselineQty = int.tryParse(qtyController.text.trim()) ?? 0;
    _baselineRemarks = remarksController.text.trim();
  }

  void dispose() {
    qtyController.dispose();
    remarksController.dispose();
  }

  Map<String, dynamic> toUpdatePayload() => {
    'id': id,
    'actual_qty': int.tryParse(qtyController.text.trim()) ?? 0,
    'remarks': remarksController.text.trim(),
  };
}
```

### 1b. Tambah helper `_hasUnsavedChanges()` di `_StockOpnamePageState`

Letakkan di dekat `_isReadOnly()`:

```dart
/// Cek apakah ada perubahan yang belum disimpan sebagai draft.
/// Data read-only (sudah submit) selalu dianggap tidak ada perubahan.
bool _hasUnsavedChanges() {
  if (_isReadOnly()) return false;
  return items.any((item) => item.isDirty);
}
```

> Catatan: field header (tanggal, status, outlet, remarks) tidak bisa diedit di
> halaman ini (`_pickDate` hanya menampilkan snackbar), jadi cukup membandingkan
> baris item. Kalau nanti header dibuat editable, tambahkan perbandingannya di sini.

---

## Perubahan 2 — Modal Peringatan Saat Kembali (AppBar)

### 2a. Ekstrak navigasi keluar ke helper `_navigateBack()`

Saat ini logika navigasi kembali ada inline di `leading` AppBar. Pindahkan ke helper supaya bisa dipakai ulang:

```dart
void _navigateBack() {
  isBackSO.value = false;
  selectedPageInventoryNotifier.value = 2;
  selectedPageNotifier.value = 3;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const WidgetTree()),
    (route) => false,
  );
}
```

### 2b. Tambah handler `_handleBack()` dengan modal peringatan

```dart
Future<void> _handleBack() async {
  // Tidak ada perubahan (atau sudah read-only) → langsung keluar.
  if (!_hasUnsavedChanges()) {
    _navigateBack();
    return;
  }

  final action = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      icon: const Icon(
        Icons.warning_amber_rounded,
        size: 48,
        color: Colors.orange,
      ),
      title: const Text(
        'Perubahan Belum Disimpan',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      content: const Text(
        'Ada perubahan yang belum disimpan sebagai draft. '
        'Simpan draft terlebih dahulu sebelum keluar?',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
      ),
      actionsPadding: const EdgeInsets.only(
        bottom: 24,
        left: 20,
        right: 20,
        top: 10,
      ),
      actions: [
        Row(
          children: [
            // Batal → tutup modal, tetap di halaman (tidak keluar).
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text(
                  'Batal',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Simpan Draft → pakai fungsi yang sudah ada lalu keluar.
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, 'save'),
                child: const Text(
                  'Simpan Draft',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  if (action == 'save') {
    await _saveDraft(); // fungsi yang sudah ada
    if (!mounted) return;
    // Keluar hanya jika draft benar-benar tersimpan (tidak ada sisa perubahan).
    // Kalau _saveDraft gagal, item masih dirty → user tetap di halaman.
    if (!_hasUnsavedChanges()) _navigateBack();
  }
  // 'cancel' atau modal di-dismiss → tetap di halaman.
}
```

> **Perilaku tombol:**
> - **Batal** → menutup modal, user tetap di halaman (tidak jadi keluar).
> - **Simpan Draft** → memanggil `_saveDraft()` (fungsi yang sudah ada), lalu
>   keluar jika simpan berhasil. Kalau gagal, user tetap di halaman supaya tidak
>   kehilangan data.

### 2c. Pakai `_handleBack()` di AppBar leading

**Before:**

```dart
leading: IconButton(
  icon: const Icon(Icons.arrow_back),
  onPressed: () {
    isBackSO.value = false;
    selectedPageInventoryNotifier.value = 2;
    selectedPageNotifier.value = 3;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WidgetTree()),
      (route) => false,
    );
  },
  tooltip: 'Kembali ke Menu Utama',
),
```

**After:**

```dart
leading: IconButton(
  icon: const Icon(Icons.arrow_back),
  onPressed: _handleBack,
  tooltip: 'Kembali ke Menu Utama',
),
```

### 2d. (Opsional tapi disarankan) Tangkap tombol back hardware/gesture

Supaya tombol back fisik Android / gesture juga terlindungi, bungkus `Scaffold`
di `_buildScaffold` dengan `PopScope`:

```dart
Widget _buildScaffold(BuildContext context) {
  return PopScope(
    canPop: false, // navigasi keluar dikontrol manual via _handleBack
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      _handleBack();
    },
    child: Scaffold(
      // ... isi Scaffold tetap sama
    ),
  );
}
```

---

## Perubahan 3 — `_submit` Simpan Draft Sebelum Submit

Tujuan: pastikan data terbaru (qty + keterangan yang baru diketik tapi belum
ditekan "Simpan Draft") ikut tersimpan sebelum submit, supaya **tidak ada data
yang hilang**.

Saat ini `_submit` sudah memanggil `updateDraftSO` sebelum `submitSO`, tetapi
perlu dipastikan: **jika simpan draft gagal, jangan lanjut submit** (jangan
submit data lama). Bagian akhir `_submit` jadi seperti ini:

**Before:**

```dart
try {
  await stockOpnameService.updateDraftSO(widget.id, {
    'lines': items.map((item) => item.toUpdatePayload()).toList(),
  });
  await stockOpnameService.submitSO(widget.id);
  if (!mounted) return;
  SnackbarUtil.show(
    context,
    title: 'Stock opname dikirim',
    message: 'Data stock opname berhasil disubmit.',
    status: SnackBarStatus.success,
  );
  isBackSO.value = false;
  selectedPageInventoryNotifier.value = 2;
  selectedPageNotifier.value = 3;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const WidgetTree()),
    (route) => false,
  );
} catch (e, stack) {
  CrashReporter.report(e, stack, reason: 'stock_opname_page.submit');
  if (!mounted) return;
  SnackbarUtil.show(
    context,
    title: 'Gagal submit',
    message: 'Terjadi kendala saat submit stock opname. Coba kembali.',
    status: SnackBarStatus.error,
  );
} finally {
  if (mounted) setState(() => isSubmitting = false);
}
```

**After:**

```dart
try {
  // 1) Simpan draft dulu dengan data terbaru — supaya tidak ada data yang
  //    hilang kalau user mengetik lalu langsung submit tanpa "Simpan Draft".
  await stockOpnameService.updateDraftSO(widget.id, {
    'lines': items.map((item) => item.toUpdatePayload()).toList(),
  });
  // Sinkronkan baseline supaya tidak terdeteksi "dirty" lagi.
  for (final item in items) {
    item.commitBaseline();
  }

  // 2) Baru submit.
  await stockOpnameService.submitSO(widget.id);

  if (!mounted) return;
  SnackbarUtil.show(
    context,
    title: 'Stock opname dikirim',
    message: 'Data stock opname berhasil disubmit.',
    status: SnackBarStatus.success,
  );
  isBackSO.value = false;
  selectedPageInventoryNotifier.value = 2;
  selectedPageNotifier.value = 3;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const WidgetTree()),
    (route) => false,
  );
} catch (e, stack) {
  CrashReporter.report(e, stack, reason: 'stock_opname_page.submit');
  if (!mounted) return;
  SnackbarUtil.show(
    context,
    title: 'Gagal submit',
    message: 'Terjadi kendala saat submit stock opname. Coba kembali.',
    status: SnackBarStatus.error,
  );
} finally {
  if (mounted) setState(() => isSubmitting = false);
}
```

> Karena `updateDraftSO` dan `submitSO` berada di dalam `try` yang sama, kalau
> `updateDraftSO` gagal (lempar exception), `submitSO` **tidak akan jalan** dan
> langsung masuk ke `catch` — jadi tidak akan submit data lama. Tambahan
> `commitBaseline()` opsional (karena halaman akan ditutup setelah submit), tapi
> berguna agar konsisten jika navigasi gagal.

---

## Perubahan 4 — Commit Baseline Setelah `_saveDraft` Berhasil

Agar setelah menekan "Simpan Draft" tombol kembali tidak lagi menganggap ada
perubahan, commit baseline setelah simpan sukses.

**Before (potongan `_saveDraft`):**

```dart
await stockOpnameService.updateDraftSO(widget.id, payload);
if (!mounted) return;
SnackbarUtil.show(
  context,
  title: 'Draft tersimpan',
  message: 'Stock opname disimpan sebagai draft.',
  status: SnackBarStatus.success,
);
```

**After:**

```dart
await stockOpnameService.updateDraftSO(widget.id, payload);
// Update baseline → perubahan dianggap sudah tersimpan.
for (final item in items) {
  item.commitBaseline();
}
if (!mounted) return;
SnackbarUtil.show(
  context,
  title: 'Draft tersimpan',
  message: 'Stock opname disimpan sebagai draft.',
  status: SnackBarStatus.success,
);
```

---

## Checklist Implementasi

- [ ] `_StockOpnameItem`: tambah `_baselineQty`, `_baselineRemarks`, getter `isDirty`, method `commitBaseline()`, dan set baseline di constructor.
- [ ] Tambah `_hasUnsavedChanges()` di state.
- [ ] Ekstrak `_navigateBack()` dan tambah `_handleBack()` dengan modal (Batal / Simpan Draft).
- [ ] Ganti `onPressed` AppBar leading → `_handleBack`.
- [ ] (Opsional) Bungkus `Scaffold` dengan `PopScope` untuk back hardware/gesture.
- [ ] `_submit`: pastikan simpan draft (`updateDraftSO`) dijalankan sebelum `submitSO` + `commitBaseline()`.
- [ ] `_saveDraft`: tambah `commitBaseline()` setelah simpan sukses.

## Catatan Alur

- **Submit langsung tanpa Simpan Draft** → tetap aman karena `_submit` memanggil
  `updateDraftSO` lebih dulu (data terbaru ikut tersimpan).
- **Kembali dengan perubahan** → modal muncul; pilih **Simpan Draft** untuk
  simpan + keluar, atau **Batal** untuk tetap mengedit.
- **Kembali tanpa perubahan** → langsung keluar tanpa modal.
- **Data sudah disubmit (read-only)** → `_hasUnsavedChanges()` selalu `false`,
  jadi kembali langsung keluar tanpa modal.
