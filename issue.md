# Catatan Perbaikan - POS Panglima App

> Dokumen ini berisi daftar perbaikan yang perlu diimplementasikan, dikelompokkan berdasarkan folder/file.
> Setiap item memiliki **Prioritas** (Tinggi / Sedang / Rendah) dan **Langkah Implementasi** yang jelas.

---

## Daftar Isi

1. [pubspec.yaml - Dependency Salah Tempat](#1-pubspecyaml---dependency-salah-tempat)
2. [lib/main.dart - Duplikasi Kode Notifikasi](#2-libmaindart---duplikasi-kode-notifikasi)
3. [lib/data/constants.dart - Hapus Data Dummy Tidak Terpakai](#3-libdataconstantsdart---hapus-data-dummy-tidak-terpakai)
4. [lib/data/notifiers.dart - Bersihkan Notifier Tidak Jelas](#4-libdatanotifiersdart---bersihkan-notifier-tidak-jelas)
5. [lib/services/helper/dio_client.dart - Timeout Terlalu Lama](#5-libserviceshelperdio_clientdart---timeout-terlalu-lama)
6. [lib/services/sift_service.dart - Typo Nama File & Class](#6-libservicessift_servicedart---typo-nama-file--class)
7. [lib/services/notification_service.dart - File Kosong](#7-libservicesnotification_servicedart---file-kosong)
8. [lib/services/storage/menu_local_service.dart - Seluruh File Dikomentari](#8-libservicesstoragemenu_local_servicedart---seluruh-file-dikomentari)
9. [lib/services/repositories/cart_repository.dart - Kode Mati (Hive Tidak Aktif)](#9-libservicesrepositoriescart_repositorydart---kode-mati-hive-tidak-aktif)
10. [lib/services/bluetooth_printer_service.dart - Hardcoded & print()](#10-libservicesbluetooth_printer_servicedart---hardcoded--print)
11. [lib/views/widgets/startsift_modal.dart & endsift_modal.dart - Duplikasi RupiahFormatter](#11-libviewswidgetsstartsift_modaldart--endsift_modaldart---duplikasi-rupiahformatter)
12. [lib/views/widgets/product_modal_widget.dart & update_product_modal_widget.dart - Duplikasi Masif](#12-libviewswidgetsproduct_modal_widgetdart--update_product_modal_widgetdart---duplikasi-masif)
13. [lib/views/pages/pesanan_baru_page.dart - Duplikasi Parsing insufficient_stock](#13-libviewspagespesanan_baru_pagedart---duplikasi-parsing-insufficient_stock)
14. [lib/views/pages/payment_page.dart - Hardcoded Values](#14-libviewspagespayment_pagedart---hardcoded-values)
15. [lib/views/pages/inventory_page.dart & pengaturan_page.dart - Duplikasi _buildMenuItem](#15-libviewspagesinventory_pagedart--pengaturan_pagedart---duplikasi-_buildmenuitem)
16. [lib/views/pages/riwayat_penjualan_page.dart - Typo pada variabel](#16-libviewspagesriwayat_penjualan_pagedart---perbaikan-minor)
17. [lib/views/widgets_tree.dart - Pages Diinstansiasi Sebagai Konstanta](#17-libviewswidgets_treedart---pages-diinstansiasi-sebagai-konstanta)
18. [lib/views/widgets/confirm_modal.dart - Hapus Kode Lama yang Dikomentari](#18-libviewswidgetsconfirm_modaldart---hapus-kode-lama-yang-dikomentari)
19. [lib/views/pages/comming_page.dart - Typo Nama File](#19-libviewspagescomming_pagedart---typo-nama-file)
20. [GLOBAL - Ganti Semua print() dengan debugPrint()](#20-global---ganti-semua-print-dengan-debugprint)
21. [GLOBAL - Memory Leak pada StreamSubscription](#21-global---memory-leak-pada-streamsubscription)
22. [GLOBAL - ApiClient Dibuat Ulang di Setiap Page](#22-global---apiclient-dibuat-ulang-di-setiap-page)
23. [GLOBAL - Duplikasi _loadShiftStatus](#23-global---duplikasi-_loadshiftstatus)
24. [GLOBAL - Versi Aplikasi Hardcoded di Banyak Tempat](#24-global---versi-aplikasi-hardcoded-di-banyak-tempat)

---

## 1. pubspec.yaml - Dependency Salah Tempat

**Prioritas:** Tinggi
**File:** `pubspec.yaml`

**Masalah:**
`hive_generator` dan `build_runner` adalah tools untuk **code generation** dan seharusnya berada di `dev_dependencies`, bukan `dependencies`. Ini menyebabkan ukuran APK membengkak.

**Langkah Implementasi:**
1. Buka file `pubspec.yaml`
2. Pindahkan 2 baris berikut dari `dependencies:` ke `dev_dependencies:`:
   ```yaml
   # HAPUS dari dependencies:
   hive_generator: ^2.0.1
   build_runner: ^2.4.13
   ```
3. Tambahkan ke `dev_dependencies:`:
   ```yaml
   dev_dependencies:
     flutter_test:
       sdk: flutter
     flutter_lints: ^5.0.0
     hive_generator: ^2.0.1    # ← tambahkan di sini
     build_runner: ^2.4.13     # ← tambahkan di sini
   ```
4. Jalankan `flutter pub get` untuk memverifikasi

---

## 2. lib/main.dart - Duplikasi Kode Notifikasi

**Prioritas:** Sedang
**File:** `lib/main.dart`

**Masalah:**
Kode untuk menyimpan notifikasi ke SharedPreferences diulang **4 kali** (baris 16-22, 43-51, 55-66, 72-86) dengan logika yang sama persis.

**Langkah Implementasi:**
1. Buat fungsi helper baru di `lib/utils/notif_utils.dart`:
   ```dart
   Future<void> saveNotifToPrefs(String? title, String? body) async {
     final prefs = await SharedPreferences.getInstance();
     await prefs.setString('notif_title', title ?? 'Notifikasi');
     await prefs.setString('notif_body', body ?? '');
     await prefs.setBool('notif_visible', true);
   }
   ```
   > **Catatan:** File `notif_utils.dart` sudah ada dan berisi fungsi `resetNotif()`. Tambahkan fungsi baru di file tersebut.
2. Di `main.dart`, ganti semua blok duplikat dengan pemanggilan fungsi ini:
   ```dart
   await saveNotifToPrefs(message.notification?.title, message.notification?.body);
   ```
3. Pastikan import `notif_utils.dart` di `main.dart`
4. Test: Pastikan notifikasi foreground, background, dan app-opened masih bekerja

---

## 3. lib/data/constants.dart - Hapus Data Dummy Tidak Terpakai

**Prioritas:** Rendah
**File:** `lib/data/constants.dart`

**Masalah:**
File ini berisi `listCategory` dan `dummyRGP` yang merupakan data dummy produk. Data sebenarnya sudah diambil dari API (`menuService.getList()`). Data dummy ini tidak dipakai di manapun dan hanya menambah noise.

**Langkah Implementasi:**
1. Cek apakah `listCategory` atau `dummyRGP` diimport di file lain:
   ```
   grep -r "listCategory\|dummyRGP" lib/
   ```
2. Jika tidak dipakai di manapun, hapus seluruh isi file atau hapus file-nya
3. Jika masih dipakai (misal untuk fallback), tambahkan komentar penjelasan

---

## 4. lib/data/notifiers.dart - Bersihkan Notifier Tidak Jelas

**Prioritas:** Rendah
**File:** `lib/data/notifiers.dart`

**Masalah:**
- `isValue` bertipe `ValueNotifier<dynamic>` tanpa penjelasan apapun. Nama dan tipe-nya tidak deskriptif.
- `isDarkModeNotifier` dideklarasikan tapi dark mode tidak diimplementasikan di app.

**Langkah Implementasi:**
1. Cari penggunaan `isValue` di seluruh project:
   ```
   grep -r "isValue" lib/
   ```
2. Jika tidak dipakai, hapus deklarasinya
3. Jika dipakai, ganti namanya menjadi lebih deskriptif sesuai fungsinya
4. Lakukan hal yang sama untuk `isDarkModeNotifier` - jika dark mode belum diimplementasikan, hapus notifier ini
5. Lakukan hal yang sama untuk `isTargetNotifier`

---

## 5. lib/services/helper/dio_client.dart - Timeout Terlalu Lama

**Prioritas:** Tinggi
**File:** `lib/services/helper/dio_client.dart`

**Masalah:**
`connectTimeout` dan `receiveTimeout` di-set ke **600000ms (10 menit)**. Ini terlalu lama. User akan menunggu 10 menit sebelum melihat error timeout. Standar yang wajar adalah 15-30 detik.

**Langkah Implementasi:**
1. Buka file `lib/services/helper/dio_client.dart`
2. Ubah baris 12-13:
   ```dart
   // SEBELUM:
   connectTimeout: const Duration(milliseconds: 600000),
   receiveTimeout: const Duration(milliseconds: 600000),
   
   // SESUDAH:
   connectTimeout: const Duration(seconds: 30),
   receiveTimeout: const Duration(seconds: 30),
   ```
3. Test: Matikan WiFi dan coba lakukan request. Pastikan error muncul dalam ~30 detik, bukan 10 menit

---

## 6. lib/services/sift_service.dart - Typo Nama File & Class

**Prioritas:** Sedang
**File:** `lib/services/sift_service.dart`

**Masalah:**
Nama file `sift_service.dart` dan class `SiftService` salah eja. Seharusnya `shift_service.dart` dan `ShiftService`. Ini membingungkan developer lain.

**Langkah Implementasi:**
1. Rename file: `lib/services/sift_service.dart` → `lib/services/shift_service.dart`
2. Di dalam file, rename class:
   ```dart
   // SEBELUM:
   class SiftService {
   
   // SESUDAH:
   class ShiftService {
   ```
3. Cari semua file yang mengimport `sift_service.dart`:
   ```
   grep -r "sift_service" lib/
   ```
   File yang perlu diubah:
   - `lib/views/widgets/startsift_modal.dart`
   - `lib/views/widgets/endsift_modal.dart`
4. Di setiap file tersebut:
   - Ubah import: `sift_service.dart` → `shift_service.dart`
   - Ubah deklarasi: `SiftService` → `ShiftService`
   - Ubah variabel: `siftService` → `shiftService`
5. Jalankan `flutter analyze` untuk memastikan tidak ada error

---

## 7. lib/services/notification_service.dart - File Kosong

**Prioritas:** Rendah
**File:** `lib/services/notification_service.dart`

**Masalah:**
File ini kosong (hanya 1 baris). Tidak berisi kode apapun.

**Langkah Implementasi:**
1. Cek apakah file ini diimport di manapun:
   ```
   grep -r "notification_service" lib/
   ```
2. Jika tidak diimport, hapus file ini
3. Jika diimport, implementasikan atau hapus import-nya

---

## 8. lib/services/storage/menu_local_service.dart - Seluruh File Dikomentari

**Prioritas:** Rendah
**File:** `lib/services/storage/menu_local_service.dart`

**Masalah:**
Seluruh isi file dikomentari. File ini seharusnya untuk menyimpan menu secara lokal menggunakan Hive, tapi fitur tersebut tidak aktif (Hive init juga dikomentari di `main.dart` baris 100-102).

**Langkah Implementasi:**
1. Cek apakah file ini diimport di manapun:
   ```
   grep -r "menu_local_service" lib/
   ```
2. Jika tidak diimport, hapus file ini
3. Jika masih direncanakan untuk dipakai di masa depan, biarkan tapi tambahkan komentar TODO di atas file

---

## 9. lib/services/repositories/cart_repository.dart - Kode Mati (Hive Tidak Aktif)

**Prioritas:** Rendah
**File:** `lib/services/repositories/cart_repository.dart`

**Masalah:**
File ini menggunakan Hive (`Hive.box<CartItem>`), tapi inisialisasi Hive di `main.dart` sudah dikomentari (baris 100-102). File ini tidak bisa berfungsi.

**Langkah Implementasi:**
1. Cek apakah `CartRepository` digunakan di manapun:
   ```
   grep -r "CartRepository" lib/
   ```
2. Jika tidak dipakai, hapus file ini dan juga model terkait:
   - `lib/models/cart_item.dart`
   - `lib/models/cart_item.g.dart`
   - `lib/models/cart_variant.dart`
   - `lib/models/cart_variant.g.dart`
3. Jika masih direncanakan, biarkan tapi tambahkan komentar TODO

---

## 10. lib/services/bluetooth_printer_service.dart - Hardcoded & print()

**Prioritas:** Sedang
**File:** `lib/services/bluetooth_printer_service.dart`

**Masalah:**
1. Kontak bisnis (WhatsApp, Instagram, Facebook, Website) di-hardcode langsung di kode (baris 244-247)
2. Banyak `print()` statement untuk debugging (baris 68, 84, 87, 88, 96, 127, 159)

**Langkah Implementasi:**

### Langkah A - Pindahkan Kontak ke Konfigurasi:
1. Buat konstanta di file baru `lib/data/app_config.dart`:
   ```dart
   class AppConfig {
     static const String whatsapp = '082220002237';
     static const String instagram = '@Jajanpanglima';
     static const String facebook = '@Jajan Panglima';
     static const String website = 'www.rotigembungpanglima.com';
   }
   ```
2. Di `bluetooth_printer_service.dart`, ganti hardcoded text:
   ```dart
   bluetooth.printCustom("Whatsapp  : ${AppConfig.whatsapp}", 0, 0);
   bluetooth.printCustom("Instagram : ${AppConfig.instagram}", 0, 0);
   // dst...
   ```

### Langkah B - Ganti print() dengan debugPrint():
1. Import `flutter/foundation.dart`
2. Ganti semua `print(...)` dengan `debugPrint(...)` di file ini
3. Ini mencegah log bocor ke production

---

## 11. lib/views/widgets/startsift_modal.dart & endsift_modal.dart - Duplikasi RupiahFormatter

**Prioritas:** Sedang
**File:**
- `lib/views/widgets/startsift_modal.dart` (baris 564-582)
- `lib/views/widgets/endsift_modal.dart` (baris 651-669)

**Masalah:**
Class `RupiahFormatter` (TextInputFormatter) didefinisikan **identik** di kedua file.

**Langkah Implementasi:**
1. Buat file baru `lib/utils/rupiah_formatter.dart`:
   ```dart
   import 'package:flutter/services.dart';
   import 'package:intl/intl.dart';

   class RupiahFormatter extends TextInputFormatter {
     final formatter = NumberFormat.currency(
       locale: 'id_ID',
       symbol: 'Rp ',
       decimalDigits: 0,
     );

     @override
     TextEditingValue formatEditUpdate(oldValue, newValue) {
       final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
       if (text.isEmpty) return const TextEditingValue(text: '');
       final result = formatter.format(int.parse(text));
       return TextEditingValue(
         text: result,
         selection: TextSelection.collapsed(offset: result.length),
       );
     }
   }
   ```
2. Hapus class `RupiahFormatter` dari kedua file modal
3. Tambahkan import di kedua file:
   ```dart
   import 'package:pos_panglima_app/utils/rupiah_formatter.dart';
   ```
4. Fungsi `parseRupiah` juga duplikat di kedua file. Pindahkan ke `rupiah_formatter.dart`:
   ```dart
   int parseRupiah(String text) {
     return int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
   }
   ```
5. Jalankan `flutter analyze` untuk verifikasi

---

## 12. lib/views/widgets/product_modal_widget.dart & update_product_modal_widget.dart - Duplikasi Masif

**Prioritas:** Tinggi
**File:**
- `lib/views/widgets/product_modal_widget.dart` (~810 baris)
- `lib/views/widgets/update_product_modal_widget.dart` (~987 baris)

**Masalah:**
Kedua file ini memiliki duplikasi besar:
- `_buildStepButton` - identik
- Timer logic (`_startDecreasing`, `_startIncreasing`, `_stopTimer`) - identik
- Bagian UI untuk thumbnail, stepper, variant chips, diskon - hampir identik
- `_loadShiftStatus` dan `_showWarningShift` - identik

**Langkah Implementasi:**

### Langkah A - Ekstrak Widget StepButton:
1. Buat file `lib/views/components/ui/step_button.dart`:
   ```dart
   Widget buildStepButton({
     required IconData icon,
     required Color color,
     required VoidCallback onTap,
     required VoidCallback onLongPress,
     required VoidCallback onLongPressEnd,
   }) {
     return GestureDetector(
       onLongPressStart: (_) => onLongPress(),
       onLongPressEnd: (_) => onLongPressEnd(),
       child: IconButton(
         style: IconButton.styleFrom(
           backgroundColor: color,
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
           minimumSize: const Size(45, 45),
         ),
         onPressed: onTap,
         icon: Icon(icon, size: 22, color: Colors.black87),
       ),
     );
   }
   ```
2. Import dan gunakan di kedua modal widget

### Langkah B - Ekstrak Mixin untuk Timer Logic:
1. Buat file `lib/utils/quantity_timer_mixin.dart`:
   ```dart
   mixin QuantityTimerMixin {
     Timer? _timer;
     final Duration _interval = Duration(milliseconds: 100);
     
     void startTimer(VoidCallback action) {
       _timer = Timer.periodic(_interval, (_) => action());
     }
     
     void stopTimer() {
       _timer?.cancel();
     }
   }
   ```
2. Gunakan mixin ini di kedua widget state

### Langkah C - Hapus kode duplikat di kedua file dan gunakan komponen yang sudah diekstrak

---

## 13. lib/views/pages/pesanan_baru_page.dart - Duplikasi Parsing insufficient_stock

**Prioritas:** Sedang
**File:**
- `lib/views/pages/pesanan_baru_page.dart` (baris 70-98)
- `lib/views/widgets/product_modal_widget.dart` (baris 160-196)

**Masalah:**
Logika parsing error `insufficient_stock` dari API response **identik** di kedua file.

**Langkah Implementasi:**
1. Buat fungsi helper di file baru `lib/utils/stock_parser.dart`:
   ```dart
   List<Map<String, String>> parseInsufficientStock(String message) {
     final String stockPart = message.replaceFirst('insufficient_stock: ', '');
     final List<String> stockItems = stockPart.split('; ');
     
     return stockItems.map((item) {
       final RegExp regex = RegExp(r'^(.*?): required ([\d.]+), stock ([\d.]+)$');
       final match = regex.firstMatch(item.trim());
       final String cleanName = (match?.group(1) ?? item)
           .replaceAll(RegExp(r'\s*\(ITM\d+\)'), '');
       return {
         'name': cleanName,
         'required': match?.group(2) ?? '-',
         'stock': match?.group(3) ?? '-',
       };
     }).toList();
   }
   ```
2. Ganti logika duplikat di kedua file:
   ```dart
   if (message.contains('insufficient_stock')) {
     final parsedItems = parseInsufficientStock(message);
     showDialog(
       context: context,
       builder: (_) => ModalInsufficientStock(items: parsedItems),
     );
   }
   ```
3. Hapus kode parsing lama di kedua file

---

## 14. lib/views/pages/payment_page.dart - Hardcoded Values

**Prioritas:** Tinggi
**File:** `lib/views/pages/payment_page.dart`

**Masalah:**
- `customers_id: 16` di-hardcode pada baris 196 (payload order). Ini berbahaya karena akan selalu mengirim customer ID 16 untuk semua transaksi.
- Variabel `dicount` (baris 37) adalah typo, seharusnya `discount`.

**Langkah Implementasi:**

### Langkah A - Fix Hardcoded Customer ID:
1. Buka `lib/views/pages/payment_page.dart`
2. Cari baris `"customers_id": 16`
3. Ganti dengan customer ID yang dinamis. Ambil dari profil user yang sudah di-fetch di `getProfile()`:
   ```dart
   "customers_id": int.tryParse(customerId.toString()) ?? 0,
   ```
4. Pastikan `customerId` sudah ter-set sebelum payload dibuat

### Langkah B - Fix Typo:
1. Ganti semua `dicount` menjadi `discount` di file ini
2. Cari: `dicount` → Ganti: `discount`

---

## 15. lib/views/pages/inventory_page.dart & pengaturan_page.dart - Duplikasi _buildMenuItem

**Prioritas:** Rendah
**File:**
- `lib/views/pages/inventory_page.dart` (baris 410-466)
- `lib/views/pages/pengaturan_page.dart` (baris 675-731)

**Masalah:**
Widget `_buildMenuItem` hampir identik di kedua file.

**Langkah Implementasi:**
1. Buat widget baru `lib/views/components/ui/sidebar_menu_item.dart`:
   ```dart
   class SidebarMenuItem extends StatelessWidget {
     final bool isActive;
     final IconData icon;
     final String label;
     final VoidCallback onTap;
     
     // ... build method dengan UI yang sama
   }
   ```
2. Import dan gunakan di `inventory_page.dart` dan `pengaturan_page.dart`
3. Hapus method `_buildMenuItem` dari kedua file

---

## 16. lib/views/pages/riwayat_penjualan_page.dart - Perbaikan Minor

**Prioritas:** Rendah
**File:** `lib/views/pages/riwayat_penjualan_page.dart`

**Masalah:**
- Variabel `isLoadingOrdersList`, `isLoadingOrdersDetail`, `isLoadingUserId`, `isFirstLoad` menggunakan `late bool ... = true/false`. Penggunaan `late` tidak diperlukan jika langsung diinisialisasi.

**Langkah Implementasi:**
1. Ubah:
   ```dart
   // SEBELUM:
   late bool isLoadingOrdersList = true;
   late bool isLoadingOrdersDetail = true;
   late bool isLoadingUserId = true;
   late bool isFirstLoad = true;
   
   // SESUDAH:
   bool isLoadingOrdersList = true;
   bool isLoadingOrdersDetail = true;
   bool isLoadingUserId = true;
   bool isFirstLoad = true;
   ```

---

## 17. lib/views/widgets_tree.dart - Pages Diinstansiasi Sebagai Konstanta

**Prioritas:** Sedang
**File:** `lib/views/widgets_tree.dart`

**Masalah:**
Semua halaman diinstansiasi sekali dalam list `pages` (baris 13-22) di top-level. Ini berarti:
- Semua halaman langsung dibuat saat app dimulai (meski belum dibuka)
- State halaman bisa stale karena tidak dibuat ulang saat navigasi

**Langkah Implementasi:**
1. Ubah list `pages` agar menggunakan builder function:
   ```dart
   List<Map<String, dynamic>> pages = [
     {'name': 'Pesanan Baru', 'builder': () => PesananBaruPage()},
     {'name': 'Riwayat Penjualan', 'builder': () => RiwayatPenjualanPage()},
     {'name': 'Laporan', 'builder': () => LaporanPage()},
     {'name': 'Inventory', 'builder': () => InventoryPage()},
     {'name': 'Pengaturan', 'builder': () => PengaturanPage()},
   ];
   ```
2. Di `WidgetTree`, ubah penggunaan:
   ```dart
   // SEBELUM:
   body: pages[value]['page'],
   
   // SESUDAH:
   body: pages[value]['builder'](),
   ```

---

## 18. lib/views/widgets/confirm_modal.dart - Hapus Kode Lama yang Dikomentari

**Prioritas:** Rendah
**File:**
- `lib/views/widgets/confirm_modal.dart` (baris 1-101 dikomentari)
- `lib/views/components/ui/custom_checkbox.dart` (baris 1-39 dikomentari)
- `lib/utils/modal_insufficient_stock.dart` (baris 1-101 dikomentari)

**Masalah:**
Kode versi lama yang sudah di-replace tetap ada dalam bentuk komentar. Ini membuat file sulit dibaca dan menambah noise.

**Langkah Implementasi:**
1. Buka setiap file di atas
2. Hapus seluruh blok kode yang dikomentari (kode lama)
3. Sisakan hanya kode aktif
4. Verifikasi bahwa kode yang tersisa masih berfungsi (tidak ada dependensi ke kode lama)

---

## 19. lib/views/pages/comming_page.dart - Typo Nama File

**Prioritas:** Rendah
**File:** `lib/views/pages/comming_page.dart`

**Masalah:**
Nama file salah eja: `comming` seharusnya `coming`.

**Langkah Implementasi:**
1. Rename file: `comming_page.dart` → `coming_page.dart`
2. Cari semua import yang mereferensi file ini:
   ```
   grep -r "comming_page" lib/
   ```
3. Update semua import path
4. Jalankan `flutter analyze`

---

## 20. GLOBAL - Ganti Semua print() dengan debugPrint()

**Prioritas:** Tinggi

**Masalah:**
`print()` digunakan di banyak file untuk debugging. Di production, `print()` bisa memperlambat app dan membocorkan informasi sensitif (seperti token, response data).

**File yang perlu diubah:**
| File | Baris |
|------|-------|
| `bluetooth_printer_service.dart` | 68, 84, 87, 88, 96, 127, 159 |
| `error_log_manager.dart` | 33 |
| `product_modal_widget.dart` | 102 |
| `update_product_modal_widget.dart` | 193 |
| `payment_page.dart` | 160 |
| `startsift_modal.dart` | 65 |
| `endsift_modal.dart` | 111, 117, 409 |
| `pesanan_baru_page.dart` | 273 |

**Langkah Implementasi:**
1. Di setiap file di atas, lakukan find & replace:
   - `print(` → `debugPrint(`
2. Pastikan setiap file sudah meng-import:
   ```dart
   import 'package:flutter/foundation.dart';
   ```
   > **Catatan:** Jika file sudah import `package:flutter/material.dart`, `debugPrint` sudah tersedia tanpa import tambahan.
3. Jalankan `flutter analyze` untuk memastikan tidak ada error

---

## 21. GLOBAL - Memory Leak pada StreamSubscription

**Prioritas:** Tinggi

**Masalah:**
Di beberapa file, `bluetooth.onStateChanged().listen(...)` dipanggil di `initState()` tanpa menyimpan `StreamSubscription` dan membatalkannya di `dispose()`. Ini menyebabkan memory leak.

**File yang perlu diperbaiki:**
- `lib/views/pages/pengaturan_page.dart` (baris 46-49)
- `lib/views/pages/payment_page.dart` (baris 86-89)
- `lib/views/pages/riwayat_penjualan_page.dart` (baris 45-49)

**Langkah Implementasi (untuk setiap file):**
1. Tambahkan import di atas file:
   ```dart
   import 'dart:async';
   ```
2. Tambahkan variabel di dalam State class:
   ```dart
   StreamSubscription? _bluetoothSubscription;
   ```
3. Di `initState()`, simpan subscription:
   ```dart
   // SEBELUM:
   BluetoothPrinterService.bluetooth.onStateChanged().listen((state) { ... });
   
   // SESUDAH:
   _bluetoothSubscription = BluetoothPrinterService.bluetooth.onStateChanged().listen((state) { ... });
   ```
4. Tambahkan atau update `dispose()`:
   ```dart
   @override
   void dispose() {
     _bluetoothSubscription?.cancel();
     super.dispose();
   }
   ```

**Tambahan - Timer di modal widget:**

File `product_modal_widget.dart` dan `update_product_modal_widget.dart` memiliki `_timer` tapi tidak dibatalkan di `dispose()`.

1. Tambahkan `dispose()` di kedua file:
   ```dart
   @override
   void dispose() {
     _timer?.cancel();
     super.dispose();
   }
   ```

---

## 22. GLOBAL - ApiClient Dibuat Ulang di Setiap Page

**Prioritas:** Sedang

**Masalah:**
`ApiClient()` di-instantiate ulang di setiap page:
- `pesanan_baru_page.dart`
- `payment_page.dart`
- `inventory_page.dart`
- `pengaturan_page.dart`
- `riwayat_penjualan_page.dart`
- `laporan_page.dart`
- `startsift_modal.dart`
- `endsift_modal.dart`

Setiap kali `ApiClient()` dibuat, Dio instance baru dibuat, interceptor baru ditambahkan. Ini boros memori.

**Langkah Implementasi:**
1. Ubah `ApiClient` menjadi Singleton di `lib/services/helper/dio_client.dart`:
   ```dart
   class ApiClient {
     static final ApiClient _instance = ApiClient._internal();
     factory ApiClient() => _instance;
     
     final Dio dio = Dio();
     final storage = const FlutterSecureStorage();
     
     ApiClient._internal() {
       // ... konfigurasi dio yang sudah ada
     }
     
     // ... method lainnya tetap sama
   }
   ```
2. Tidak perlu mengubah kode di page-page lain karena `ApiClient()` sekarang selalu mengembalikan instance yang sama
3. Test: Pastikan login, logout, dan semua API call masih berfungsi normal

---

## 23. GLOBAL - Duplikasi _loadShiftStatus

**Prioritas:** Rendah

**Masalah:**
Method `_loadShiftStatus()` dengan logika identik ada di:
- `pesanan_baru_page.dart`
- `product_modal_widget.dart`
- `update_product_modal_widget.dart`
- `drawer_widget.dart`

**Langkah Implementasi:**
1. Karena ini adalah fungsi simple yang cukup 3 baris, alternatif terbaik adalah membuat static utility:
   ```dart
   // Di lib/utils/shift_utils.dart
   import 'package:pos_panglima_app/services/storage/shift_storage_service.dart';
   
   Future<bool> checkShiftActive() async {
     return await ShiftStorageService.hasActiveShift();
   }
   ```
2. Atau biarkan saja dan terima duplikasi minor ini karena sangat simpel

---

## 24. GLOBAL - Versi Aplikasi Hardcoded di Banyak Tempat

**Prioritas:** Rendah

**Masalah:**
String `V.1.0.0` atau `Versi 1.0.0` di-hardcode di:
- `lib/views/pages/inventory_page.dart` (baris 129)
- `lib/views/pages/pengaturan_page.dart` (baris 200)
- `lib/views/widgets/drawer_widget.dart` (baris 104)

Ketika versi diupdate, developer harus mengubah di 3+ tempat.

**Langkah Implementasi:**
1. Tambahkan konstanta versi di `lib/data/app_config.dart` (buat file ini jika belum ada):
   ```dart
   class AppConfig {
     static const String appVersion = '1.0.0';
   }
   ```
2. Di setiap file, ganti hardcoded version:
   ```dart
   // SEBELUM:
   Text('V.1.0.0', ...)
   
   // SESUDAH:
   Text('V.${AppConfig.appVersion}', ...)
   ```

---

## Ringkasan Prioritas

### Tinggi (Harus segera dikerjakan)
| # | Issue | File |
|---|-------|------|
| 1 | Dependency salah tempat di pubspec.yaml | `pubspec.yaml` |
| 5 | Timeout 10 menit di Dio | `dio_client.dart` |
| 12 | Duplikasi masif di product modal | `product_modal_widget.dart`, `update_product_modal_widget.dart` |
| 14 | Hardcoded customer_id: 16 | `payment_page.dart` |
| 20 | print() harus diganti debugPrint() | Multiple files |
| 21 | Memory leak StreamSubscription | Multiple files |

### Sedang (Dikerjakan setelah yang tinggi selesai)
| # | Issue | File |
|---|-------|------|
| 2 | Duplikasi kode notifikasi | `main.dart` |
| 6 | Typo SiftService → ShiftService | `sift_service.dart` |
| 10 | Hardcoded kontak bisnis | `bluetooth_printer_service.dart` |
| 11 | Duplikasi RupiahFormatter | `startsift_modal.dart`, `endsift_modal.dart` |
| 13 | Duplikasi parsing insufficient_stock | `pesanan_baru_page.dart`, `product_modal_widget.dart` |
| 17 | Pages diinstansiasi sebagai konstanta | `widgets_tree.dart` |
| 22 | ApiClient bukan singleton | `dio_client.dart` |

### Rendah (Nice to have)
| # | Issue | File |
|---|-------|------|
| 3 | Data dummy tidak terpakai | `constants.dart` |
| 4 | Notifier tidak jelas | `notifiers.dart` |
| 7 | File kosong | `notification_service.dart` |
| 8 | File seluruhnya dikomentari | `menu_local_service.dart` |
| 9 | Hive tidak aktif | `cart_repository.dart` |
| 15 | Duplikasi _buildMenuItem | `inventory_page.dart`, `pengaturan_page.dart` |
| 16 | late bool tidak perlu | `riwayat_penjualan_page.dart` |
| 18 | Kode lama dikomentari | Multiple files |
| 19 | Typo nama file | `comming_page.dart` |
| 23 | Duplikasi _loadShiftStatus | Multiple files |
| 24 | Versi hardcoded | Multiple files |
