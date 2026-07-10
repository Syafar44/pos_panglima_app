import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/services/network_service.dart';
import 'package:pos_panglima_app/services/order_service.dart';
import 'package:pos_panglima_app/services/storage/profile_storage_service.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';

/// Menyimpan foto lampiran transaksi offline (key = `client_ref`) dan
/// mengunggahnya ke server begitu order-nya berhasil tersinkron — meniru alur
/// online yang selalu mengirim lampiran (`POST /pos/order-lampiran`).
///
/// Alur:
/// 1. Saat bayar offline → [save] path foto + client_ref.
/// 2. Saat order tersinkron (`/pos/order/sync`) → [attachDocumentNumber]
///    mencatat `document_number` hasil sync.
/// 3. [flush] mencari id order numerik dari `document_number` lalu meng-upload
///    lampiran, dan menghapus file lokal setelah sukses.
class PendingLampiranService {
  static const _key = 'pending_lampiran';

  static Future<Map<String, dynamic>> _getMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  static Future<void> _saveMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map));
  }

  /// Simpan path foto lampiran untuk order offline (key = client_ref).
  static Future<void> save(String clientRef, String filePath) async {
    final map = await _getMap();
    map[clientRef] = {'path': filePath, 'document_number': null};
    await _saveMap(map);
  }

  /// Catat document_number hasil sync supaya lampiran bisa di-link ke id order.
  static Future<void> attachDocumentNumber(
      String clientRef, String? docNum) async {
    if (docNum == null) return;
    final map = await _getMap();
    final entry = map[clientRef];
    if (entry is Map) {
      entry['document_number'] = docNum;
      map[clientRef] = entry;
      await _saveMap(map);
    }
  }

  static Future<int> count() async => (await _getMap()).length;

  static Future<void> remove(String clientRef) async {
    final map = await _getMap();
    final entry = map.remove(clientRef);
    if (entry is Map && entry['path'] is String) {
      try {
        final f = File(entry['path'] as String);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    await _saveMap(map);
  }

  /// Upload semua lampiran yang ordernya sudah tersinkron (punya document_number).
  static Future<void> flush() async {
    if (!await NetworkService.isOnline()) return;
    final map = await _getMap();
    if (map.isEmpty) return;

    final profile = await ProfileStorageService.get();
    final userId = (profile?['userId'] as num?)?.toInt();
    if (userId == null) return; // tidak bisa lookup order tanpa user

    final orderService = OrderService(ApiClient().dio);

    for (final clientRef in map.keys.toList()) {
      final entry = map[clientRef];
      if (entry is! Map) continue;
      final path = entry['path'] as String?;
      final docNum = entry['document_number'] as String?;

      if (path == null) {
        await remove(clientRef);
        continue;
      }
      // Order belum tersinkron → belum ada document_number, tunggu siklus berikut.
      if (docNum == null) continue;

      final file = File(path);
      if (!file.existsSync()) {
        await remove(clientRef);
        continue;
      }

      try {
        // Cari id order numerik dari document_number (search = nomor dokumen).
        final res = await orderService.getOrderList(userId, 1, 10, docNum);
        final list = (res.data['data']?['data'] as List?) ?? [];
        int? orderId;
        for (final o in list) {
          final m = Map<String, dynamic>.from(o as Map);
          if (m['document_number']?.toString() == docNum) {
            orderId = (m['id'] as num?)?.toInt();
            break;
          }
        }
        if (orderId == null) continue; // belum muncul di server, retry nanti

        final fileName = path.split(Platform.pathSeparator).last;
        final mimeType = lookupMimeType(path) ?? 'application/octet-stream';
        final formData = FormData.fromMap({
          'pos_orders_id': orderId,
          'name': fileName,
          'mime_type': mimeType,
          'file': await MultipartFile.fromFile(path, filename: fileName),
        });
        await orderService.postLampiran(formData);
        debugPrint('[PendingLampiran] $clientRef → terunggah (order $orderId)');
        await remove(clientRef); // sukses → hapus file + mapping
      } catch (e, s) {
        debugPrint('[PendingLampiran] $clientRef gagal upload: $e');
        CrashReporter.report(e, s, reason: 'pending_lampiran_service.flush');
        // biarkan tersimpan untuk dicoba lagi pada sync berikutnya
      }
    }
  }
}
