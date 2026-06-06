# Payment Validation Issue — `payment_page.dart`

Dokumen ini berisi audit dan rencana perbaikan validasi data pada fungsi `handlePayment` di [lib/views/pages/payment_page.dart](lib/views/pages/payment_page.dart). Tujuannya: **mencegah pengiriman payload yang tidak valid ke server** (terutama nilai `0` yang muncul karena fallback `?? 0` yang silent).

---

## Konteks Singkat

Fungsi `handlePayment` ([payment_page.dart:228-448](lib/views/pages/payment_page.dart#L228-L448)) membangun **3 jenis payload** berbeda tergantung kondisi:

| Skenario | Lokasi Payload | Kondisi |
| --- | --- | --- |
| **Tunai (cash)** | [payment_page.dart:262-277](lib/views/pages/payment_page.dart#L262-L277) | `selectedMethodName != 'Compliment'` && `selectedTab == 0` |
| **Non Tunai** | [payment_page.dart:297-313](lib/views/pages/payment_page.dart#L297-L313) | `selectedMethodName != 'Compliment'` && `selectedTab == 1` |
| **Compliment** | [payment_page.dart:338-353](lib/views/pages/payment_page.dart#L338-L353) | `selectedMethodName == 'Compliment'` |

Saat ini **tidak ada satupun validasi** sebelum `orderService.postOrder(payloadOrder)` dipanggil. Semua field yang menggunakan `int.tryParse(...) ?? 0` akan diam-diam mengirim `0` jika sumbernya null/invalid.

---

## Audit Field per Payload

### Field dengan Risiko Tinggi (`?? 0` silent fallback)

| Field | Variabel Sumber | Tipe Sumber | Risiko |
| --- | --- | --- | --- |
| `outlet_hub_id` | `customerId` ([payment_page.dart:63](lib/views/pages/payment_page.dart#L63)) | `String?` | Bila `getProfile()` ([payment_page.dart:450](lib/views/pages/payment_page.dart#L450)) gagal/`customer` list kosong → `customerId == null` → terkirim sebagai `0` |
| `pos_payment_method_id` (Non Tunai) | `selectedPaymentNonTunaiId` ([payment_page.dart:88](lib/views/pages/payment_page.dart#L88)) | `String` default `"1"` | Bila user belum memilih metode pembayaran → tetap default `"1"`, tapi jika pernah di-reset ke string non-numeric → `0` |
| `pos_order_method_id` | `selectedMethodId` ([payment_page.dart:86](lib/views/pages/payment_page.dart#L86)) | `String` default `"1"` | Sama seperti di atas |
| `pos_shifts_id` | `shiftId` ([payment_page.dart:64](lib/views/pages/payment_page.dart#L64)) | `int?` | Bila `_loadShiftId()` ([payment_page.dart:502](lib/views/pages/payment_page.dart#L502)) belum selesai atau shift belum dimulai → `null` → server menerima `null` |
| `users_id` | `userId` ([payment_page.dart:57](lib/views/pages/payment_page.dart#L57)) | `int?` | Bila `getProfile()` gagal → `null` |

### Field Nominal — Tidak boleh `0`

| Field | Rumus | Risiko |
| --- | --- | --- |
| `subtotal_amount` | `subTotal` | Bila cart kosong / `loadCart()` gagal → `0` |
| `total_amount` | `totalPayment - nominalVoucher` | Bila `totalPayment == 0` atau voucher >= total → `0` atau negatif |
| `pay_amount` | `finalPayment` (cash) / `totalPayment - nominalVoucher` (non-cash) | Bila tidak diinput → `0` |

---

## Spesifikasi Validasi per Field

### Kategori 1 — Field ID (HARUS > 0)

#### 1.1 `outlet_hub_id`
- **Variabel sumber:** `customerId` (String?)
- **Kondisi tidak valid:** `customerId == null` atau `int.tryParse(customerId) == null` atau hasil parse `<= 0`
- **Pesan error:** `"Data outlet tidak ditemukan. Silakan login ulang."`
- **Lokasi kode:** [payment_page.dart:265, 300, 341](lib/views/pages/payment_page.dart#L265)
- **Risiko jika dikirim `0`:** Order tercatat dengan outlet salah/tidak ada → laporan penjualan kacau, tidak bisa di-rekonsiliasi.

#### 1.2 `pos_payment_method_id` (khusus Non Tunai)
- **Variabel sumber:** `selectedPaymentNonTunaiId` (String)
- **Kondisi tidak valid:** `int.tryParse(selectedPaymentNonTunaiId) == null` atau `<= 0`
- **Pesan error:** `"Metode pembayaran non-tunai belum dipilih."`
- **Lokasi kode:** [payment_page.dart:303](lib/views/pages/payment_page.dart#L303)
- **Catatan:** Tunai dan Compliment hard-code ke `11`, jadi tidak butuh validasi.
- **Risiko jika dikirim `0`:** Server tidak tahu jenis pembayaran → akuntansi salah.

#### 1.3 `pos_order_method_id`
- **Variabel sumber:** `selectedMethodId` (String)
- **Kondisi tidak valid:** `int.tryParse(selectedMethodId) == null` atau `<= 0`
- **Pesan error:** `"Metode pesanan (Takeaway/Dine In) belum dipilih."`
- **Lokasi kode:** [payment_page.dart:268-269, 304-305, 344](lib/views/pages/payment_page.dart#L268-L269)
- **Risiko jika dikirim `0`:** Tipe order tidak teridentifikasi.

#### 1.4 `pos_shifts_id`
- **Variabel sumber:** `shiftId` (int?)
- **Kondisi tidak valid:** `shiftId == null` atau `shiftId <= 0`
- **Pesan error:** `"Shift belum dimulai. Mulai shift terlebih dahulu."`
- **Lokasi kode:** [payment_page.dart:264, 299, 340](lib/views/pages/payment_page.dart#L264)
- **Risiko jika dikirim `null`:** Order tidak terikat ke shift manapun → laporan shift tidak akurat.

#### 1.5 `users_id`
- **Variabel sumber:** `userId` (int?)
- **Kondisi tidak valid:** `userId == null` atau `userId <= 0`
- **Pesan error:** `"Sesi pengguna tidak valid. Silakan login ulang."`
- **Lokasi kode:** [payment_page.dart:266, 301, 342](lib/views/pages/payment_page.dart#L266)

---

### Kategori 2 — Field Nominal (HARUS > 0)

#### 2.1 `subtotal_amount` (variabel `subTotal`)
- **Kondisi tidak valid:** `subTotal <= 0`
- **Pesan error:** `"Keranjang kosong atau total tidak valid."`
- **Lokasi kode:** [payment_page.dart:270, 306, 345](lib/views/pages/payment_page.dart#L270)

#### 2.2 `total_amount` (rumus `totalPayment - nominalVoucher`)
- **Kondisi tidak valid:** `(totalPayment - nominalVoucher) <= 0`
- **Pesan error:** `"Total bayar tidak valid. Periksa voucher atau keranjang."`
- **Lokasi kode:** [payment_page.dart:273, 309, 348](lib/views/pages/payment_page.dart#L273)
- **Catatan:** Untuk **Compliment**, total memang bisa `0` secara bisnis. Lihat **Catatan Khusus Compliment** di bawah.

#### 2.3 `pay_amount` (variabel `finalPayment` untuk cash)
- **Kondisi tidak valid:** `finalPayment <= 0` ATAU `finalPayment < (totalPayment - nominalVoucher)` (uang yang dibayar kurang)
- **Pesan error:** `"Nominal pembayaran tidak mencukupi total."`
- **Lokasi kode:** [payment_page.dart:274](lib/views/pages/payment_page.dart#L274)

---

### Catatan Khusus: Compliment

Pada path Compliment ([payment_page.dart:333-372](lib/views/pages/payment_page.dart#L333-L372)), secara bisnis nilai `pay_amount` boleh sama dengan total bayar (bukan `0`), karena Compliment biasanya tetap memiliki `subTotal` dan `total_amount` yang representatif (item tetap ada, hanya tidak dibayar secara nyata). Validasi nominal **tetap berlaku** — `subTotal > 0` wajib. Yang berbeda hanya: tidak perlu validasi `finalPayment >= total` karena pay_amount = total.

---

## Rancangan Solusi: Helper `_validatePayload`

Daripada menyalin-tempel `if` di 3 tempat, buat **satu helper validasi** yang dipanggil sebelum tiap `postOrder`. Helper mengembalikan `String?` — `null` artinya valid, non-null artinya pesan error untuk ditampilkan.

```dart
/// Mengembalikan pesan error pertama yang ditemukan, atau null jika semua valid.
String? _validateOrderPayload({
  required int? shiftIdVal,
  required int? userIdVal,
  required String? customerIdVal,
  required String orderMethodIdStr,
  required String? paymentMethodIdStr, // null untuk tunai/compliment (hard-coded 11)
  required int subTotalVal,
  required int totalAmountVal,
  required int? payAmountVal, // null = skip (compliment)
}) {
  // Kategori 1 — IDs
  if (shiftIdVal == null || shiftIdVal <= 0) {
    return "Shift belum dimulai. Mulai shift terlebih dahulu.";
  }
  if (userIdVal == null || userIdVal <= 0) {
    return "Sesi pengguna tidak valid. Silakan login ulang.";
  }
  final outletId = int.tryParse(customerIdVal ?? '');
  if (outletId == null || outletId <= 0) {
    return "Data outlet tidak ditemukan. Silakan login ulang.";
  }
  final orderMethodId = int.tryParse(orderMethodIdStr);
  if (orderMethodId == null || orderMethodId <= 0) {
    return "Metode pesanan belum dipilih.";
  }
  if (paymentMethodIdStr != null) {
    final pmId = int.tryParse(paymentMethodIdStr);
    if (pmId == null || pmId <= 0) {
      return "Metode pembayaran non-tunai belum dipilih.";
    }
  }

  // Kategori 2 — Nominal
  if (subTotalVal <= 0) {
    return "Keranjang kosong atau subtotal tidak valid.";
  }
  if (totalAmountVal <= 0) {
    return "Total bayar tidak valid. Periksa voucher atau keranjang.";
  }
  if (payAmountVal != null && payAmountVal < totalAmountVal) {
    return "Nominal pembayaran tidak mencukupi total.";
  }

  return null;
}
```

---

## Langkah Implementasi Step-by-Step

Target audiens: junior programmer / AI model lebih murah. Lakukan sesuai urutan, jangan lewat.

### Step 1 — Tambahkan helper validasi

Di dalam class `_PaymentPageState` (di [payment_page.dart](lib/views/pages/payment_page.dart)), tambahkan method baru `_validateOrderPayload` (copy dari snippet di atas). Letakkan **tepat di atas** fungsi `handlePayment` (sekitar baris 228).

### Step 2 — Refactor path "Tunai" (selectedTab == 0)

Ubah blok di [payment_page.dart:253-277](lib/views/pages/payment_page.dart#L253-L277) menjadi:

```dart
if (selectedTab == 0) {
  finalPayment = totalPayment - nominalVoucher;

  if (selectedPayment == 'rounded') {
    finalPayment = roundedAmount;
  } else if (selectedPayment == 'custom') {
    finalPayment = customAmount;
  }

  final totalAmount = totalPayment - nominalVoucher;

  // VALIDASI — sebelum kirim ke server
  final err = _validateOrderPayload(
    shiftIdVal: shiftId,
    userIdVal: userId,
    customerIdVal: customerId,
    orderMethodIdStr: selectedMethodId,
    paymentMethodIdStr: null, // tunai = hard-code 11
    subTotalVal: subTotal,
    totalAmountVal: totalAmount,
    payAmountVal: finalPayment,
  );
  if (err != null) {
    setState(() => isLoading = false);
    slowTimer.cancel();
    if (!mounted) return;
    SnackbarUtil.show(
      context,
      title: "Data Tidak Valid",
      message: err,
      status: SnackBarStatus.warning,
    );
    debugPrint('handlePayment validation failed (tunai): $err');
    return;
  }

  Map<String, dynamic> payloadOrder = {
    "customers_id": 16,
    "pos_shifts_id": shiftId,
    "outlet_hub_id": int.parse(customerId!), // safe: sudah divalidasi
    "users_id": userId,
    "pos_payment_method_id": 11,
    "pos_order_method_id": int.parse(selectedMethodId),
    "subtotal_amount": subTotal,
    "discount_amount": subTotal - totalPayment + nominalVoucher,
    "tax_amount": 0.00,
    "total_amount": totalAmount,
    "pay_amount": finalPayment,
    "voucher_barcodes": barcodeList,
    "is_cash": 1,
  };

  // ...lanjutan kode existing (postOrder + print)
}
```

**Perhatikan:** ganti `int.tryParse(...) ?? 0` dengan `int.parse(...)` karena validasi sudah menjamin parse-able. Ini membuat kontrak eksplisit: "jika sampai ke sini, data pasti valid".

### Step 3 — Refactor path "Non Tunai" (selectedTab == 1)

Ubah blok di [payment_page.dart:296-313](lib/views/pages/payment_page.dart#L296-L313) dengan pola yang sama:

```dart
} else {
  final totalAmount = totalPayment - nominalVoucher;

  final err = _validateOrderPayload(
    shiftIdVal: shiftId,
    userIdVal: userId,
    customerIdVal: customerId,
    orderMethodIdStr: selectedMethodId,
    paymentMethodIdStr: selectedPaymentNonTunaiId, // <-- divalidasi
    subTotalVal: subTotal,
    totalAmountVal: totalAmount,
    payAmountVal: totalAmount, // non-tunai pay = total
  );
  if (err != null) {
    setState(() => isLoading = false);
    slowTimer.cancel();
    if (!mounted) return;
    SnackbarUtil.show(
      context,
      title: "Data Tidak Valid",
      message: err,
      status: SnackBarStatus.warning,
    );
    debugPrint('handlePayment validation failed (non-tunai): $err');
    return;
  }

  Map<String, dynamic> payloadOrder = {
    "customers_id": 16,
    "pos_shifts_id": shiftId,
    "outlet_hub_id": int.parse(customerId!),
    "users_id": userId,
    "pos_payment_method_id": int.parse(selectedPaymentNonTunaiId),
    "pos_order_method_id": int.parse(selectedMethodId),
    "subtotal_amount": subTotal,
    "discount_amount": subTotal - totalPayment + nominalVoucher,
    "tax_amount": 0.00,
    "total_amount": totalAmount,
    "pay_amount": totalAmount,
    "voucher_barcodes": barcodeList,
    "is_cash": 0,
  };

  // ...lanjutan kode existing
}
```

### Step 4 — Refactor path "Compliment"

Ubah blok di [payment_page.dart:333-353](lib/views/pages/payment_page.dart#L333-L353):

```dart
} else {
  final proceed = await showRemarksModal();
  if (!proceed) {
    setState(() => isLoading = false);
    slowTimer.cancel();
    return;
  }

  final totalAmount = totalPayment - nominalVoucher;

  final err = _validateOrderPayload(
    shiftIdVal: shiftId,
    userIdVal: userId,
    customerIdVal: customerId,
    orderMethodIdStr: selectedMethodId,
    paymentMethodIdStr: null, // compliment = hard-code 11
    subTotalVal: subTotal,
    totalAmountVal: totalAmount,
    payAmountVal: null, // compliment: skip cek "pay >= total"
  );
  if (err != null) {
    setState(() => isLoading = false);
    slowTimer.cancel();
    if (!mounted) return;
    SnackbarUtil.show(
      context,
      title: "Data Tidak Valid",
      message: err,
      status: SnackBarStatus.warning,
    );
    debugPrint('handlePayment validation failed (compliment): $err');
    return;
  }

  Map<String, dynamic> payloadOrder = {
    "customers_id": 16,
    "pos_shifts_id": shiftId,
    "outlet_hub_id": int.parse(customerId!),
    "users_id": userId,
    "pos_payment_method_id": 11,
    "pos_order_method_id": int.parse(selectedMethodId),
    "subtotal_amount": subTotal,
    "discount_amount": subTotal - totalPayment + nominalVoucher,
    "tax_amount": 0.00,
    "total_amount": totalAmount,
    "pay_amount": totalAmount,
    "is_cash": 1,
    "voucher_barcodes": barcodeList,
    "keterangan": _keteranganCompliment.text,
  };

  // ...lanjutan kode existing
}
```

> **Bug terpisah yang juga harus diperbaiki:** di kode existing baris [payment_page.dart:336](lib/views/pages/payment_page.dart#L336) — bila `proceed == false`, fungsi `return` langsung tapi `isLoading` tetap `true` dan `slowTimer` tidak di-cancel. Step 4 sudah memperbaiki ini.

### Step 5 — Test manual

Lakukan minimal 6 skenario uji manual:

1. **Tunai happy path** — semua field valid, cart isi, shift aktif → order terkirim.
2. **Belum mulai shift** → muncul snackbar `"Shift belum dimulai..."`, request **tidak terkirim**.
3. **Cart kosong** (`subTotal == 0`) → muncul snackbar `"Keranjang kosong atau subtotal tidak valid."`.
4. **Custom amount kurang dari total** → muncul snackbar `"Nominal pembayaran tidak mencukupi total."` (sebenarnya tombol sudah disabled di [payment_page.dart:1597-1602](lib/views/pages/payment_page.dart#L1597-L1602), tapi validasi tetap second-line-of-defense).
5. **Non Tunai tanpa pilih metode** (jika `selectedPaymentNonTunaiId` kebetulan invalid) → snackbar `"Metode pembayaran non-tunai belum dipilih."`.
6. **Compliment happy path** dengan keterangan terisi → order terkirim.

Untuk setiap kasus error: verifikasi via DevTools Network bahwa **tidak ada** POST `/orders` yang terkirim.

### Step 6 — Periksa state setelah error

Pastikan setelah validasi gagal:
- `isLoading == false` (tombol bisa ditekan lagi)
- `slowTimer.cancel()` sudah dipanggil (tidak ada dialog "Proses Lambat" muncul tiba-tiba)
- User bisa memperbaiki input dan mencoba ulang tanpa restart app

### Step 7 — Commit & PR

Commit message yang disarankan:

```
fix(payment): validate order payload before POST to prevent miss-data

- Add _validateOrderPayload helper to check IDs (shift, user, outlet,
  payment method, order method) and nominals (subtotal, total, pay)
- Reject request with specific user-facing error when any required field
  is null, unparseable, or <= 0
- Replace silent `int.tryParse(...) ?? 0` with explicit int.parse after
  validation
- Fix leaked isLoading/slowTimer when compliment remarks modal is canceled
```

---

## Checklist Implementasi

- [ ] Step 1: Helper `_validateOrderPayload` ditambahkan
- [ ] Step 2: Path Tunai pakai validasi + `int.parse`
- [ ] Step 3: Path Non Tunai pakai validasi + `int.parse`
- [ ] Step 4: Path Compliment pakai validasi + fix kebocoran `isLoading` saat batal
- [ ] Step 5: 6 skenario manual test lulus
- [ ] Step 6: Verifikasi state pasca-error bersih
- [ ] Step 7: Commit dan PR

---

## Ringkasan Field — Quick Reference

| Field Payload | Variabel | Tidak Valid Bila | Pesan Error |
| --- | --- | --- | --- |
| `pos_shifts_id` | `shiftId` | `null` atau `<= 0` | Shift belum dimulai. Mulai shift terlebih dahulu. |
| `users_id` | `userId` | `null` atau `<= 0` | Sesi pengguna tidak valid. Silakan login ulang. |
| `outlet_hub_id` | `customerId` | tidak bisa di-parse atau `<= 0` | Data outlet tidak ditemukan. Silakan login ulang. |
| `pos_order_method_id` | `selectedMethodId` | tidak bisa di-parse atau `<= 0` | Metode pesanan belum dipilih. |
| `pos_payment_method_id` (non-tunai) | `selectedPaymentNonTunaiId` | tidak bisa di-parse atau `<= 0` | Metode pembayaran non-tunai belum dipilih. |
| `subtotal_amount` | `subTotal` | `<= 0` | Keranjang kosong atau subtotal tidak valid. |
| `total_amount` | `totalPayment - nominalVoucher` | `<= 0` | Total bayar tidak valid. Periksa voucher atau keranjang. |
| `pay_amount` (tunai) | `finalPayment` | `< total_amount` | Nominal pembayaran tidak mencukupi total. |
