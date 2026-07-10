import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Menyimpan profil pengguna (nama, users_id, outlet/customer id) ke local
/// storage saat login, supaya payload order tetap benar saat transaksi offline.
/// Ditimpa setiap kali login ulang.
class ProfileStorageService {
  static const String _key = 'user_profile';

  static Future<void> save({
    required int userId,
    required String userName,
    String? customerId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'userId': userId,
        'userName': userName,
        'customerId': customerId,
      }),
    );
  }

  static Future<Map<String, dynamic>?> get() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
