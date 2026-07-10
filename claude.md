oke bantu saya update untuk @inpentory_transver buat file inventory.md yang berisi instsuksi

jadi buat kondisi if pada code ini

SizedBox(
width: double.infinity,
height: 48,
child: ElevatedButton(
onPressed: submitRealisasi,
style: ElevatedButton.styleFrom(
backgroundColor: AppColors.primary,
foregroundColor: Colors.white,
elevation: 0,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12),
),
),
child: const Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
Icon(Icons.check_circle_outline),
SizedBox(width: 8),
Text(
'Konfirmasi Terima Barang',
style: TextStyle(
fontSize: 16,
fontWeight: FontWeight.bold,
),
),
],
),
),
),

jika pada username ambil dari sharedreferen username -> pastikan cek dulu,
lalu cek apakah ada kata "Gerai Panglima" atau tidak, kalau tidak maka tetap gunakan code di atas,

kalau ada maka pakai dan fungsi baru
ya itu ada 2 tombol Realisasi Partial dan Realisasi Close,

nah buatkan 2 fungsi yang menampung api berikut
ini partial
inventory/inventory_transfer/:id/realisasi-partial

{
"inventory_transfer_lines": [
{ "id": 9001, "realisasi": 5 },
{ "id": 9002, "realisasi": 5 }
]
}
implementasinya bisa cek cek fungsi submitRealisasi

yang ini close
inventory/inventory_transfer/:id/close

{
"approve_users_id": 7
}

tambahkan petch tersebut ke @inventory_service terlebih dahulu

selanjutnya pada @reception_inventory_page
tambah colom baru hanya untuk yang username yang ada nama "Gerai Panglima" nya
tambah colom di sebelah realisasi dengan warna hijau dengan nama Telah Terealisasi, atau "Final Realisasi"
untuk isinya di ambil dari inventoryDetail nanti cek dimana perubahannya

Jelaskan tahapan-tahapan yang harus dilakukan untuk mengimplementasikan fitur ini, anggap nanti yang mengimplementasikan adalah junior programmer atau model AI yang lebih murah.

# Fitur: Inventory Transfer — Realisasi Gerai Panglima

## Konteks

File terkait: `@inventory_transfer`, `@inventory_service`, `@reception_inventory_page`

---

## Tahap 1 — Tambah 2 endpoint ke `inventory_service`

Tambahkan dua fungsi baru ke file `inventory_service`. Jadikan referensi fungsi `submitRealisasi` yang sudah ada untuk pola HTTP request, error handling, dan penggunaan token.

**Fungsi 1: `realisasiPartial(id, lines)`**

- Method: `PATCH`
- Endpoint: `inventory/inventory_transfer/:id/realisasi-partial`
- Body:

```json
{
  "inventory_transfer_lines": [
    { "id": 9001, "realisasi": 5 },
    { "id": 9002, "realisasi": 5 }
  ]
}
```

**Fungsi 2: `realisasiClose(id, approveUsersId)`**

- Method: `PATCH`
- Endpoint: `inventory/inventory_transfer/:id/close`
- Body:

```json
{ "approve_users_id": 7 }
```

---

## Tahap 2 — Buat fungsi submit baru di halaman transfer

Di halaman `@inventory_transfer`, buat dua fungsi baru:

- `submitRealisasiPartial()` — memanggil `realisasiPartial()` dari service, dengan payload dari data lines yang ada di halaman
- `submitRealisasiClose()` — memanggil `realisasiClose()`, dengan `approve_users_id` diambil dari SharedPreferences (field: `user_id` atau yang relevan — cek dulu isinya)

Jadikan `submitRealisasi()` yang sudah ada sebagai referensi pola implementasi.

---

## Tahap 3 — Tambah kondisi berdasarkan username

Di halaman `@inventory_transfer`, ambil nilai `username` dari SharedPreferences.

Buat kondisi:

```dart
if (username.contains("Gerai Panglima")) {
  // tampilkan 2 tombol baru (lihat Tahap 4)
} else {
  // tampilkan tombol lama "Konfirmasi Terima Barang" seperti semula
}
```

Cek terlebih dahulu key yang digunakan untuk menyimpan username di SharedPreferences sebelum mengambilnya.

---

## Tahap 4 — Ganti tombol secara kondisional

Ganti widget tombol yang ada (kode di bawah) dengan kondisi dari Tahap 3:

```dart
// Tombol lama (tetap dipakai jika bukan Gerai Panglima):
SizedBox(
  width: double.infinity,
  height: 48,
  child: ElevatedButton(
    onPressed: submitRealisasi,
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline),
        SizedBox(width: 8),
        Text(
          'Konfirmasi Terima Barang',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  ),
),
```

Jika username mengandung "Gerai Panglima", tampilkan **dua tombol** side-by-side:

- **Tombol kiri**: "Realisasi Partial" → `onPressed: submitRealisasiPartial`
- **Tombol kanan**: "Realisasi Close" → `onPressed: submitRealisasiClose`

Gunakan warna dan style yang sama dengan tombol lama. Gunakan `Row` dengan `Expanded` agar keduanya mengisi lebar layar.

---

## Tahap 5 — Tambah kolom "Final Realisasi" di tabel penerimaan

Di halaman `@reception_inventory_page`, tambahkan kolom baru **hanya untuk user yang username-nya mengandung "Gerai Panglima"**.

- Posisi kolom: **di sebelah kanan kolom "Realisasi"**
- Nama header: `Final Realisasi` (atau `Telah Terealisasi`)
- Warna header/teks: **hijau** (gunakan `Colors.green` atau `AppColors` yang relevan)
- Isi data: Cek dulu di response `inventoryDetail` — cari field yang menunjukkan realisasi final/konfirmasi (kemungkinan field seperti `final_realisasi`, `realisasi_close`, atau serupa). Jika belum tahu fieldnya, print dulu seluruh response `inventoryDetail` ke console untuk inspeksi.

---

## Catatan untuk implementor

- Ikuti urutan tahap secara berurutan (1 → 2 → 3 → 4 → 5)
- Setiap tahap sebaiknya ditest dulu sebelum lanjut ke tahap berikutnya
- Jangan hardcode nilai `approve_users_id` — ambil dari SharedPreferences
- Jika ragu dengan nama key di SharedPreferences, cetak semua key yang tersimpan untuk inspeksi

oke ke step selanjutnya
pada inventory ini
[InventoryDetail] {
I/flutter (19593): "id": 1693,
I/flutter (19593): "document_number": "IT26060640",
I/flutter (19593): "entry": "1781492799",
I/flutter (19593): "date": "2026-06-15T00:00:00Z",
I/flutter (19593): "from_outlet_hub_id": 8,
I/flutter (19593): "from_outlet_hub_name": "Gudang Utama - Samarinda",
I/flutter (19593): "to_outlet_hub_id": 90,
I/flutter (19593): "to_outlet_hub_name": "Gerai Panglima - Juanda",
I/flutter (19593): "remarks": "TESTING DUMMY SJ GERAI PARSIAL",
I/flutter (19593): "approve": 0,
I/flutter (19593): "approve_users_id": 7,
I/flutter (19593): "approve_date": "",
I/flutter (19593): "created_by": 1,
I/flutter (19593): "token": "7a81056f603bf6aeda021943cd1369a2d4e39887",
I/flutter (19593): "to_outlet_hub_types_id": 6,
I/flutter (19593): "label": "IT",
I/flutter (19593): "created_at": "2026-06-15T11:06:39Z",
I/flutter (19593): "updated_at": "2026-06-15T11:06:39Z",
I/flutter (19593): "inventory_transfer_lines": [
I/flutter (19593): {
I/flutter (19593): "id": 17285,
I/flutter (19593): "inventory_transfer_id": 1693,
I/flutter (19593): "item_id": 4,
I/flutter (19593): "item_code": "ITM26020004",
I/flutter (19593): "item_name": "Amplang Pipih 150 Gr",
I/flutter (19593): "quantity": 10,
I/flutter (19593): "
I/flutter (19593): [InventoryDetail] realisasi": 3,
I/flutter (19593): "reject": null,
I/flutter (19593): "uoms_id": 5,
I/flutter (19593): "uoms": "NISIK",
I/flutter (19593): "uoms_code": "Pcs",
I/flutter (19593): "uoms_schemas_id": 3,
I/flutter (19593): "remarks": "",
I/flutter (19593): "from_warehouse_code": "SMRWHUT",
I/flutter (19593): "to_warehouse_code": "GPJWHUT",
I/flutter (19593): "created_at": "0001-01-01T00:00:00Z",
I/flutter (19593): "updated_at": "2026-06-15T04:17:24Z"
I/flutter (19593): }
I/flutter (19593): ]
I/flutter (19593): }

final pada colom realisasi kurangakn dengan final realisasinya gitu, terus saat submit
yang di input di tambahkan dengan final realisasi gitu mengerti?
