import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_panglima_app/services/cart_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/network_service.dart';
import 'package:pos_panglima_app/services/storage/offline_stock_service.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';

/// Migrasi cart yang dibuat saat offline ke cart server begitu kembali online.
///
/// Item yang dibuat offline ditandai `_offline: true`. Saat online, item-item
/// itu di-`postCart` ke server supaya tidak hilang saat `loadCart` menarik cart
/// dari server. Item yang memang berasal dari server (tanpa flag) tidak ikut
/// dikirim agar tidak terjadi duplikasi.
class OfflineCartSync {
  static bool _busy = false;
  static const _pendingDeleteKey = 'server_cart_pending_delete';

  /// Catat id baris cart yang sudah dikonsumsi oleh order offline supaya dihapus
  /// dari cart server saat online. Hanya untuk item yang berasal dari server
  /// (sudah pernah ter-migrasi); item murni offline tidak ada di server.
  static Future<void> markForServerDeletion(List<int> ids) async {
    if (ids.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_pendingDeleteKey) ?? [];
    final merged = {...existing, ...ids.map((e) => e.toString())}.toList();
    await prefs.setStringList(_pendingDeleteKey, merged);
  }

  /// Hapus item yang sudah dikonsumsi order offline dari cart server (best-effort).
  /// Mencegah item yang sudah dibayar offline muncul lagi di keranjang.
  static Future<void> flushServerCartDeletions() async {
    if (!await NetworkService.isOnline()) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_pendingDeleteKey) ?? [];
    if (ids.isEmpty) return;

    final cartService = CartService(ApiClient().dio);
    final remaining = <String>[];
    for (final idStr in ids) {
      final id = int.tryParse(idStr);
      if (id == null) continue;
      try {
        await cartService.deleteCart(id);
      } on DioException catch (e) {
        // 404/400 = item memang sudah tidak ada di server → anggap selesai.
        final code = e.response?.statusCode;
        if (code != 404 && code != 400) remaining.add(idStr);
      } catch (_) {
        remaining.add(idStr);
      }
    }

    if (remaining.isEmpty) {
      await prefs.remove(_pendingDeleteKey);
    } else {
      await prefs.setStringList(_pendingDeleteKey, remaining);
    }
  }

  /// Dorong item offline ke server. Mengembalikan jumlah item yang gagal
  /// (mis. ditolak server karena stok). Aman dipanggil berkali-kali: kalau
  /// tidak ada item offline atau sedang berjalan, langsung no-op.
  static Future<int> migrateToServer() async {
    if (_busy) return 0;

    final snapshot = await OfflineStockService.getCartSnapshot();
    final offlineItems =
        snapshot.where((e) => e['_offline'] == true).toList();
    if (offlineItems.isEmpty) return 0;

    _busy = true;
    int failed = 0;
    final postedIds = <dynamic>[];
    try {
      final cartService = CartService(ApiClient().dio);
      for (final item in offlineItems) {
        try {
          await cartService.postCart(_toPayload(item));
          postedIds.add(item['id']);
        } catch (e, s) {
          failed++;
          CrashReporter.report(e, s,
              reason: 'offline_cart_sync.migrateToServer');
        }
      }

      // Buang item yang sudah berhasil dikirim dari snapshot lokal supaya tidak
      // terkirim dua kali kalau pengambilan cart server gagal setelah ini.
      if (postedIds.isNotEmpty) {
        final remaining =
            snapshot.where((e) => !postedIds.contains(e['id'])).toList();
        await OfflineStockService.saveCartSnapshot(remaining);
      }
    } finally {
      _busy = false;
    }
    return failed;
  }

  static Map<String, dynamic> _toPayload(Map<String, dynamic> item) {
    return {
      'pos_menus_id': item['pos_menus_id'],
      'quantity': item['quantity'],
      'price': item['price'],
      'subtotal': item['subtotal'] ?? 0,
      'tax': item['tax'] ?? 0,
      'is_percentage': item['is_percentage'] ?? 0,
      'discount': item['discount'] ?? 0,
      'discount_val': item['discount_val'] ?? 0,
      'total': item['total'] ?? 0,
      'max_qty': item['max_qty'] ?? 0,
      'pos_cart_props': (item['pos_cart_props'] as List? ?? [])
          .map((p) => {
                'pos_menus_id': p['pos_menus_id'],
                'quantity': p['quantity'],
              })
          .toList(),
    };
  }
}
