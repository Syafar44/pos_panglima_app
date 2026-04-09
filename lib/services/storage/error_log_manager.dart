import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'error_log.dart';

class ErrorLogManager {
  static const String _storageKey = 'error_logs';

  static Future<void> saveLog({
    required String title,
    required String description,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final logs = await getLogs();

    final newLog = ErrorLog(
      title: title,
      description: description,
      createdAt: DateTime.now(),
    );

    logs.add(newLog);

    final encoded = logs.map((log) => log.toMap()).toList();

    await prefs.setString(_storageKey, jsonEncode(encoded));
  }

  static Future<List<ErrorLog>> getLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw == null) return [];
    debugPrint(raw);

    final List<dynamic> decoded = jsonDecode(raw);
    return decoded
        .map((item) => ErrorLog.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  // // Kirim semua log ke API, lalu hapus jika sukses
  // static Future<bool> sendLogsToApi() async {
  //   final logs = await getLogs();
  //   if (logs.isEmpty) return true;

  //   try {
  //     final response = await http.post(
  //       Uri.parse(_apiUrl),
  //       headers: {'Content-Type': 'application/json'},
  //       body: jsonEncode({'logs': logs.map((log) => log.toMap()).toList()}),
  //     );

  //     if (response.statusCode == 200 || response.statusCode == 201) {
  //       await clearLogs(); // Hapus setelah berhasil dikirim
  //       return true;
  //     }

  //     return false;
  //   } catch (e) {
  //     // Tetap simpan log jika gagal kirim
  //     return false;
  //   }
  // }

  // Hapus semua log dari SharedPreferences
  static Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
