# Implementasi `in_app_update` — Auto Update via Play Store

## Tujuan
Menambahkan mekanisme update otomatis ke aplikasi `pos_panglima_app` menggunakan plugin [`in_app_update`](https://pub.dev/packages/in_app_update) sehingga user dapat menerima notifikasi dan menginstal versi terbaru langsung dari dalam aplikasi tanpa harus membuka Play Store secara manual.

## Latar Belakang
Saat ini versi aplikasi ditampilkan di [pengaturan_page.dart](lib/views/pages/pengaturan_page.dart#L319) (`V.${AppConfig.version}`), namun tidak ada mekanisme deteksi update. User harus mengecek Play Store secara manual. Untuk perangkat POS yang stand-alone, update yang tertunda dapat menyebabkan inkonsistensi antara client lama vs API baru.

## Prasyarat & Batasan
- **Hanya Android**: plugin `in_app_update` adalah wrapper untuk Google Play Core Library. iOS tidak didukung — harus pakai mekanisme lain (App Store redirect).
- **Wajib distribusi via Play Store**: jika APK didistribusikan sideload (langsung APK), API update tidak akan menemukan versi baru. Pastikan aplikasi sudah terdaftar dan dirilis ke Play Console.
- **`versionCode` harus naik** di Play Console agar update terdeteksi. Saat ini di [pubspec.yaml](pubspec.yaml#L19): `2.0.2+12` — `+12` adalah versionCode.
- **Catatan inkonsistensi versi**: [`AppConfig.version`](lib/data/app_config.dart#L2) (`2.0.3`) tidak sinkron dengan `pubspec.yaml` (`2.0.2`). Perlu disinkronkan sebagai bagian dari pekerjaan ini.

## Scope

### In Scope
- Tambah dependency `in_app_update`
- Service wrapper `UpdateService` untuk encapsulate logika check / start update
- Trigger pengecekan update saat app startup (setelah splash, sebelum masuk halaman utama)
- Dua mode update:
  - **Flexible** (default): user tetap bisa pakai app sambil download di background, lalu prompt restart
  - **Immediate**: untuk update kritis — full-screen blocking, user wajib update
- UI snackbar/dialog konfirmasi saat update tersedia
- Sinkronisasi `AppConfig.version` ↔ `pubspec.yaml`

### Out of Scope
- Update untuk iOS (handle terpisah jika dibutuhkan)
- Force-update berdasarkan API custom (logika minimum-supported-version dari backend) — bisa jadi follow-up
- Distribusi non-Play Store (Huawei AppGallery, dsb.)

## Rencana Implementasi

### 1. Tambah Dependency
File: [pubspec.yaml](pubspec.yaml)

```yaml
dependencies:
  in_app_update: ^4.2.3
```

Lalu jalankan `flutter pub get`.

### 2. Sinkronkan Versi
File: [lib/data/app_config.dart](lib/data/app_config.dart)

Pilih satu sumber kebenaran. Rekomendasi: tetap dari `AppConfig.version` (mudah dibaca), update `pubspec.yaml` ke `2.0.3+13` (atau versi target rilis berikutnya).

Atau lebih baik — baca runtime via `package_info_plus` agar tidak ada duplikasi. Tapi itu refactor terpisah; untuk sekarang cukup sinkronkan manual.

### 3. Buat Service Wrapper
File baru: `lib/services/update_service.dart`

```dart
import 'package:in_app_update/in_app_update.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:flutter/foundation.dart';

class UpdateService {
  static Future<AppUpdateInfo?> check() async {
    try {
      return await InAppUpdate.checkForUpdate();
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'update_service.check');
      return null;
    }
  }

  static Future<bool> startFlexible() async {
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      return result == AppUpdateResult.success;
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'update_service.startFlexible');
      return false;
    }
  }

  static Future<void> completeFlexible() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'update_service.completeFlexible');
    }
  }

  static Future<bool> startImmediate() async {
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      return result == AppUpdateResult.success;
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'update_service.startImmediate');
      return false;
    }
  }
}
```

### 4. Integrasi Pengecekan Update
File: [lib/services/helper/splash_screen.dart](lib/services/helper/splash_screen.dart) (atau halaman home setelah login)

Trigger pengecekan setelah splash selesai loading data:

```dart
final info = await UpdateService.check();
if (info?.updateAvailability == UpdateAvailability.updateAvailable) {
  // Tampilkan dialog: "Versi baru tersedia. Update sekarang?"
  // Jika ya: panggil UpdateService.startFlexible()
  // Saat selesai download: tampilkan snackbar dengan tombol "Restart"
  //   yang memanggil UpdateService.completeFlexible()
}
```

Strategi:
- **Flexible** untuk update reguler (fitur baru, perbaikan bug minor)
- **Immediate** jika `info.immediateUpdateAllowed` true DAN ada flag dari backend / build config bahwa update bersifat kritis

### 5. Listener Status Download (Flexible Update)
`InAppUpdate.startFlexibleUpdate()` resolve setelah user terima dialog, tapi download terjadi background. Untuk menampilkan progress / prompt restart:

```dart
// Polling state atau listener — plugin v4.x mengembalikan AppUpdateResult
// langsung saat user accept, dan completeFlexibleUpdate() dipanggil saat
// app sudah di foreground lagi setelah download selesai.
```

Implementasi sederhana: simpan flag di `SharedPreferences` saat user terima update, cek saat resume app, lalu prompt `completeFlexibleUpdate`.

### 6. UI Trigger Manual (Opsional)
Tambah tombol "Cek Pembaruan" di [pengaturan_page.dart](lib/views/pages/pengaturan_page.dart) menu Profil, sebelah versioning, untuk user trigger manual.

### 7. Konfigurasi Android
File: [android/app/build.gradle.kts](android/app/build.gradle.kts)

Plugin `in_app_update` v4+ otomatis menambah dependency `play-core` / `app-update`. Pastikan `compileSdk` ≥ 33. Plugin sudah handle ini via `flutter.compileSdkVersion`.

Tidak perlu perubahan manifest tambahan.

## Testing Plan

Update via Play Store hanya dapat diuji dengan:
1. **Internal Testing Track** di Play Console — upload AAB versi N+1, install versi N di device, buka app → update prompt muncul
2. **Internal App Sharing** — lebih cepat untuk iterasi, generate URL khusus tester
3. Tidak bisa diuji via `flutter run` debug — `checkForUpdate()` akan return error/no-update

Test cases:
- [ ] App terbuka dengan versi lebih lama → prompt update muncul
- [ ] User pilih "Update" → download mulai di background (flexible)
- [ ] Download selesai → snackbar "Restart untuk apply" muncul
- [ ] User tap "Restart" → app restart dan menjalankan versi baru
- [ ] User pilih "Nanti" → app tetap jalan dengan versi lama, tidak crash
- [ ] Offline saat startup → `check()` return null, app jalan normal tanpa error
- [ ] Versi sama dengan Play Store → tidak ada prompt
- [ ] Update kritis (immediate) → blocking screen, tidak bisa skip

## Acceptance Criteria
- Pengguna dengan versi lama mendapat notifikasi update saat app startup
- Update flexible berjalan tanpa mengganggu transaksi yang sedang berjalan
- Crash atau error pada `checkForUpdate()` tidak menyebabkan app crash (handled, fallback ke normal flow)
- Versi `AppConfig.version` dan `pubspec.yaml` tersinkronisasi
- `flutter analyze` clean
- Tidak ada warning baru di Crashlytics terkait update flow

## Risiko & Mitigasi
| Risiko | Mitigasi |
|---|---|
| User dengan koneksi lambat — download stall | Gunakan flexible update (background download), tidak blocking |
| Plugin `in_app_update` versi terbaru breaking change | Pin ke versi yang sudah ditest; baca CHANGELOG sebelum upgrade |
| `play-core` library deprecated → `app-update` library | Plugin v4+ sudah migrasi ke library baru. Pastikan minimal v4.2.3 |
| Build size bertambah | Play Core dependency menambah ~200KB AAB. Acceptable |
| Test sulit di dev build | Gunakan Internal App Sharing track untuk validasi end-to-end |

## Referensi
- [Plugin pub.dev](https://pub.dev/packages/in_app_update)
- [Android In-app Updates docs](https://developer.android.com/guide/playcore/in-app-updates)
- [Migrasi ke Play App Update Library](https://developer.android.com/guide/playcore/migration)

## Estimasi Effort
- Setup + service wrapper: 0.5 hari
- Integrasi splash + dialog UI: 0.5 hari
- Test di Internal Track Play Console: 0.5 hari
- **Total: ~1.5 hari kerja**
