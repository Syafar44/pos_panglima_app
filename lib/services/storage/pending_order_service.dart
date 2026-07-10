import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/network_service.dart';
import 'package:pos_panglima_app/services/offline_sync_service.dart';
import 'package:pos_panglima_app/services/storage/pending_lampiran_service.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';

class PendingOrderService {
  static const _key = 'pending_orders';

  static Future<List<Map<String, dynamic>>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> _saveAll(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }

  /// Tambah satu order ke antrian. `order` harus sudah berisi `client_ref`.
  static Future<void> enqueue(Map<String, dynamic> order) async {
    final list = await getAll();
    // Hindari duplikat client_ref di antrian (mis. bug double-tap)
    final exists =
        list.any((o) => o['client_ref'] == order['client_ref']);
    if (!exists) {
      list.add(order);
      await _saveAll(list);
    }
  }

  static Future<int> count() async => (await getAll()).length;

  /// Pastikan `created_at` memiliki offset zona waktu (RFC3339). Server (Go)
  /// menolak timestamp tanpa offset. Order lama yang terlanjur tersimpan tanpa
  /// offset ikut dirapikan di sini sebelum dikirim. Item yang sudah benar
  /// (mengandung `Z` atau `±HH:MM`) dibiarkan apa adanya.
  static List<Map<String, dynamic>> _normalizeCreatedAt(
      List<Map<String, dynamic>> orders) {
    final hasOffset = RegExp(r'(Z|[+-]\d{2}:\d{2})$');
    return orders.map((o) {
      final ca = o['created_at']?.toString();
      if (ca == null || ca.isEmpty || hasOffset.hasMatch(ca)) return o;
      final dt = DateTime.tryParse(ca);
      if (dt == null) return o;
      final local = dt.toLocal();
      final off = local.timeZoneOffset;
      final sign = off.isNegative ? '-' : '+';
      final h = off.inHours.abs().toString().padLeft(2, '0');
      final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
      return {...o, 'created_at': '${local.toIso8601String()}$sign$h:$m'};
    }).toList();
  }

  /// Kirim semua pending order ke /pos/order/sync.
  /// Hanya hapus dari antrian bila status = created / duplicate.
  /// Kembalikan true jika flush sukses (meski sebagian rejected).
  static Future<bool> flush() async {
    if (!await NetworkService.isOnline()) {
      debugPrint('[PendingSync] flush dibatalkan: offline.');
      return false;
    }
    final list = await getAll();
    debugPrint('[PendingSync] mulai flush — ${list.length} order di antrian.');
    if (list.isEmpty) return true;
    try {
      final clientRefs =
          list.map((o) => o['client_ref']).toList();
      debugPrint('[PendingSync] POST /pos/order/sync → client_ref: $clientRefs');

      // Rapikan created_at (tambah offset zona waktu) sebelum kirim.
      final payload = _normalizeCreatedAt(list);

      final res =
          await OfflineSyncService(ApiClient().dio).postOrderSync(payload);

      debugPrint(
          '[PendingSync] response status: ${res.statusCode}, body: ${res.data}');

      final results = (res.data['data'] as List? ?? []).cast<Map>();
      final keep = <Map<String, dynamic>>[];
      for (final order in list) {
        final r = results.firstWhere(
          (x) => x['client_ref'] == order['client_ref'],
          orElse: () => <String, dynamic>{},
        );
        final status = r['status'] as String?;
        debugPrint(
            '[PendingSync] ${order['client_ref']} → status: ${status ?? 'no_response'}'
            '${r['message'] != null ? ' (${r['message']})' : ''}');
        if (status == 'created' || status == 'duplicate') {
          // Catat document_number agar lampiran offline bisa di-link & diunggah.
          await PendingLampiranService.attachDocumentNumber(
            order['client_ref']?.toString() ?? '',
            r['document_number']?.toString(),
          );
          continue; // ACK → buang
        }
        // rejected / tidak ada di response → simpan untuk review manual
        keep.add({
          ...order,
          '_sync_status': status ?? 'no_response',
        });
      }
      await _saveAll(keep);
      debugPrint(
          '[PendingSync] selesai — ${list.length - keep.length} terkirim, '
          '${keep.length} disimpan untuk review.');
      return true;
    } on DioException catch (e, s) {
      debugPrint(
          '[PendingSync] DioException pada ${e.requestOptions.path} '
          '→ statusCode: ${e.response?.statusCode}, '
          'type: ${e.type}, '
          'response: ${e.response?.data}, '
          'message: ${e.message}');
      CrashReporter.report(e, s, reason: 'pending_order_service.flush');
      return false;
    } catch (e, s) {
      debugPrint('[PendingSync] error tak terduga: $e');
      CrashReporter.report(e, s, reason: 'pending_order_service.flush');
      return false;
    }
  }

  /// Hapus satu order dari antrian berdasarkan client_ref.
  static Future<void> remove(String clientRef) async {
    final list = await getAll();
    list.removeWhere((o) => o['client_ref'] == clientRef);
    await _saveAll(list);
  }

  /// Hapus seluruh antrian (hati-hati — hanya untuk testing atau reset).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
