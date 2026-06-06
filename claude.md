buat file payment-issue.md yang berisikan perbaikan untuk payment, ya itu pada @payment_page.dart pada handlePayment yang utama postnya, kenapa karena datanya harus valid dan akuran untuk di kirim agar tidak ada miss data, misal jangan sampai ada data yang di kirim tidak sesuai  inputnya

contoh : 
        Map<String, dynamic> payloadOrder = {
            "customers_id": 16, // memang default
            "pos_shifts_id": shiftId,
            "outlet_hub_id": int.tryParse(customerId.toString()) ?? 0, <= seperti ini seharusnya tidak boleh nilanya 0, nilainya harus sesuai
            "users_id": userId,
            "pos_payment_method_id":
                int.tryParse(selectedPaymentNonTunaiId.toString()) ?? 0, <= seperti ini seharusnya tidak boleh nilanya 0, nilainya harus sesuai
            "pos_order_method_id":
                int.tryParse(selectedMethodId.toString()) ?? 0, <= seperti ini seharusnya tidak boleh nilanya 0, nilainya harus sesuai
            "subtotal_amount": subTotal,
            "discount_amount": subTotal - totalPayment + nominalVoucher,
            "tax_amount": 0.00,
            "total_amount": totalPayment - nominalVoucher,
            "pay_amount": finalPayment,
            "voucher_barcodes": barcodeList,
            "is_cash": 1,
          };

Sama pada subTotal, totalPayment, Serta finalPayment tidak boleh sama sekali mengirim data dengan nilai 0, karena data yang dikirim harus benar benar valid

Jelaskan tahapan-tahapan yang harus dilakukan untuk mengimplementasikan fitur ini, anggap nanti yang mengimplementasikan adalah junior programmer atau model AI yang lebih murah.


## Tugas

Buat file `payment-issue.md` yang berisi daftar perbaikan validasi data pada alur payment di `payment_page.dart`, khususnya pada fungsi `handlePayment` yang mengirim data order ke server (POST request).

## Konteks Masalah

Saat ini, payload order dikirim tanpa validasi yang memadai. Banyak field menggunakan pola `int.tryParse(...) ?? 0` yang berarti jika parsing gagal, nilai diam-diam menjadi `0` dan tetap dikirim ke server. Ini menyebabkan **miss data** — server menerima data yang tidak valid tanpa ada error di sisi client.

## Field yang Harus Divalidasi

### Kategori 1: Field ID — Tidak boleh bernilai 0 atau null

Field berikut adalah ID referensi. Jika nilainya `0`, artinya data tidak valid dan request **harus ditolak sebelum dikirim**.

- `outlet_hub_id` — saat ini: `int.tryParse(customerId.toString()) ?? 0`
- `pos_payment_method_id` — saat ini: `int.tryParse(selectedPaymentNonTunaiId.toString()) ?? 0`
- `pos_order_method_id` — saat ini: `int.tryParse(selectedMethodId.toString()) ?? 0`

### Kategori 2: Field Nominal — Tidak boleh bernilai 0 (kecuali memang transaksi gratis yang valid)

Field berikut adalah nilai uang. Mengirim `0` berarti transaksi tidak masuk akal.

- `subtotal_amount` (variabel: `subTotal`)
- `total_amount` (variabel: `totalPayment - nominalVoucher`)
- `pay_amount` (variabel: `finalPayment`)

### Kategori 3: Field yang boleh default

- `customers_id: 16` — default, tidak perlu diubah
- `users_id` — dari session, asumsikan sudah valid
- `tax_amount: 0.00` — boleh nol
- `is_cash: 1` — flag, boleh default

## Yang Harus Dilakukan

1. **Audit semua field dalam `payloadOrder`** di fungsi `handlePayment`. Identifikasi mana saja yang masih menggunakan pola `?? 0` atau fallback diam-diam lainnya.

2. **Tambahkan validasi SEBELUM request dikirim.** Jika ada field Kategori 1 atau Kategori 2 yang nilainya `0`, `null`, atau tidak valid:
   - Jangan kirim request
   - Tampilkan pesan error spesifik ke pengguna (misalnya: "Metode pembayaran belum dipilih")
   - Log error untuk debugging

3. **Untuk setiap field yang divalidasi**, tuliskan:
   - Nama field dan variabel sumbernya
   - Kondisi yang dianggap tidak valid
   - Pesan error yang ditampilkan ke pengguna
   - Lokasi kode (baris/fungsi) yang perlu diubah

4. **Tuliskan langkah implementasi step-by-step** yang bisa langsung dikerjakan oleh junior programmer atau AI model yang lebih murah — tanpa perlu memahami keseluruhan bisnis logic.

## Format Output

Tulis hasilnya dalam file `payment-issue.md` dengan struktur per field:
- Nama field di payload
- Variabel sumber di kode
- Kondisi tidak valid
- Risiko jika dikirim tanpa validasi
- Langkah perbaikan (step-by-step, dengan contoh kode)