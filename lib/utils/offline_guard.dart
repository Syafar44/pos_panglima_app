import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/app_settings.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';

/// Penjaga transaksi offline.
///
/// Dipanggil di dalam cabang OFFLINE (saat sudah dipastikan device offline).
class OfflineGuard {
  OfflineGuard._();

  /// Return `true` jika transaksi offline sedang DIBLOKIR
  /// ([AppSettings.offlineMode] == false) — sekaligus menampilkan pesan.
  /// Return `false` jika boleh lanjut (fitur offline aktif).
  static bool blocked(BuildContext context) {
    if (AppSettings.offlineMode) return false;
    SnackbarUtil.show(
      context,
      title: 'Mode Offline Dimatikan',
      message:
          'Transaksi tidak bisa dilakukan saat offline. Sambungkan internet terlebih dahulu.',
      status: SnackBarStatus.warning,
    );
    return true;
  }
}
