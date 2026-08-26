import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/menu_service.dart';
import 'package:pos_panglima_app/services/network_service.dart';
import 'package:pos_panglima_app/services/offline_cart_sync.dart';
import 'package:pos_panglima_app/services/offline_sync_service.dart';
import 'package:pos_panglima_app/services/storage/offline_stock_service.dart';
import 'package:pos_panglima_app/services/storage/pending_lampiran_service.dart';
import 'package:pos_panglima_app/services/storage/pending_order_service.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';

class OfflineSyncManager {
  static Timer? _timer;
  static const _interval = Duration(minutes: 5);

  static void start() {
    _timer?.cancel();
    syncNow(); // sync sekali langsung
    _timer = Timer.periodic(_interval, (_) => syncNow());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Satu siklus sync: tarik snapshot + menu → flush antrian pending.
  static Future<void> syncNow() async {
    // Heartbeat: tiap tick (start + setiap 5 menit) tercetak, jadi mudah cek
    // apakah timer benar-benar berjalan. Timer hanya berdetak saat app di
    // foreground — di-suspend OS saat app di-background, lanjut lagi saat resume.
    debugPrint('[OfflineSync] tick @ ${DateTime.now().toIso8601String()}');
    if (!await NetworkService.isOnline()) {
      debugPrint('[OfflineSync] skip: offline');
      return;
    }
    try {
      final dio = ApiClient().dio;

      // Tarik snapshot stok + BOM
      final snapRes =
          await OfflineSyncService(dio).getOfflineSync();
      final snapData =
          snapRes.data['data'] as Map<String, dynamic>?;
      if (snapData != null) {
        await OfflineStockService.saveSnapshot(snapData);
        debugPrint('[OfflineSync] snapshot disimpan — '
            'stocks=${(snapData['stocks'] as List?)?.length ?? 0}, '
            'bom=${(snapData['bom'] as List?)?.length ?? 0}'
            '${snapData['bom'] == null ? ' (FIELD bom TIDAK ADA dari server!)' : ''}');
      } else {
        debugPrint('[OfflineSync] snapshot data NULL dari server.');
      }

      // Tarik menu untuk fallback offline di pesanan_baru
      final menuRes = await MenuService(dio).getList();
      final menuData = menuRes.data['data'];
      if (menuData is List) {
        await OfflineStockService.saveMenu(menuData);
      }

      // Hapus item yang sudah dibayar offline dari cart server (anti muncul lagi).
      await OfflineCartSync.flushServerCartDeletions();

      // Flush antrian order offline
      await PendingOrderService.flush();

      // Upload lampiran foto untuk order yang sudah tersinkron.
      await PendingLampiranService.flush();
    } catch (e, s) {
      CrashReporter.report(e, s, reason: 'offline_sync_manager.syncNow');
    }
  }
}
