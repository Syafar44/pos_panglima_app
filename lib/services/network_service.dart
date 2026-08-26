import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  // Cache singkat: panggilan isOnline() yang beruntun (mis. saat scan barcode
  // satu item memicu savedToCart → loadCart → flushServerCartDeletions) tidak
  // masing-masing melakukan DNS lookup (yang lambat). Dalam window ini semua
  // pakai hasil yang sama, jadi penambahan item terasa instan.
  static bool? _cached;
  static DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(seconds: 2);

  /// Cek koneksi. Hasil di-cache selama [_cacheTtl]. Set [force] = true untuk
  /// memaksa pengecekan baru (mis. tombol refresh manual).
  static Future<bool> isOnline({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      return _cached!;
    }
    final result = await _check();
    _cached = result;
    _cachedAt = now;
    return result;
  }

  static Future<bool> _check() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult.isEmpty ||
          connectivityResult.every((r) => r == ConnectivityResult.none)) {
        return false;
      }

      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 2));

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }
}
