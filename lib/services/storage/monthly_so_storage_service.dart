import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Penyimpanan lokal Stock Opname Bulanan.
///
/// Menghitung satu gudang bisa memakan berjam-jam dan ratusan baris, sering di
/// area tanpa sinyal. Karena itu:
/// - seluruh baris disimpan lokal saat dokumen dibuka (satu kali unduh),
/// - setiap isian tersimpan lokal SEKETIKA, sebelum ada permintaan jaringan,
/// - baris yang belum terkirim ditandai `dirty` dan tidak boleh hilang karena
///   logout, pembaruan aplikasi, atau membuka dokumen lain.
///
/// Satu dokumen = satu entri SharedPreferences (`monthly_so_doc_<id>`) supaya
/// membuka dokumen lain tidak pernah menimpa isian dokumen sebelumnya.
class MonthlySoStorageService {
  MonthlySoStorageService._();

  static const String _docPrefix = 'monthly_so_doc_';
  static const String _idemPrefix = 'monthly_so_idem_';

  static String _docKey(int id) => '$_docPrefix$id';
  static String _idemKey(int id) => '$_idemPrefix$id';

  /// Simpan snapshot dokumen (header + seluruh baris) hasil unduh awal.
  static Future<void> saveDoc(
    int id, {
    required Map<String, dynamic> header,
    required List<Map<String, dynamic>> lines,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _docKey(id),
      jsonEncode({
        'header': header,
        'lines': lines,
        'saved_at': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// Perbarui hanya bagian `lines` (dipanggil tiap kali isian berubah).
  /// Header yang sudah tersimpan dipertahankan.
  static Future<void> saveLines(
    int id,
    List<Map<String, dynamic>> lines,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_docKey(id));
    final Map<String, dynamic> doc = raw != null
        ? Map<String, dynamic>.from(jsonDecode(raw))
        : <String, dynamic>{};
    doc['lines'] = lines;
    doc['saved_at'] = DateTime.now().toIso8601String();
    await prefs.setString(_docKey(id), jsonEncode(doc));
  }

  /// Snapshot lokal dokumen, atau `null` bila belum pernah diunduh.
  static Future<Map<String, dynamic>?> getDoc(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_docKey(id));
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      // Data lokal rusak — perlakukan seperti belum ada supaya bisa diunduh
      // ulang, bukan membuat halaman gagal terbuka.
      return null;
    }
  }

  /// Baris lokal dokumen (kosong bila belum pernah diunduh).
  static Future<List<Map<String, dynamic>>> getLines(int id) async {
    final doc = await getDoc(id);
    final lines = doc?['lines'];
    if (lines is! List) return [];
    return lines.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Hapus data lokal satu dokumen (dipakai setelah submit berhasil).
  static Future<void> clearDoc(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_docKey(id));
    await prefs.remove(_idemKey(id));
  }

  /// Kunci idempotensi submit dokumen ini — dibuat sekali lalu DIPAKAI ULANG
  /// untuk setiap percobaan ulang. Membuat UUID baru saat retry justru
  /// membatalkan pengamannya (submit & notifikasi approver bisa dobel).
  static Future<String> idempotencyKey(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_idemKey(id));
    if (existing != null && existing.isNotEmpty) return existing;
    final key = const Uuid().v4();
    await prefs.setString(_idemKey(id), key);
    return key;
  }

  /// Id dokumen yang masih menyimpan isian belum tersinkron.
  static Future<List<int>> docIdsWithDirtyLines() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = <int>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_docPrefix)) continue;
      final id = int.tryParse(key.substring(_docPrefix.length));
      if (id == null) continue;
      final lines = await getLines(id);
      if (lines.any((l) => l['dirty'] == true)) ids.add(id);
    }
    return ids;
  }
}
