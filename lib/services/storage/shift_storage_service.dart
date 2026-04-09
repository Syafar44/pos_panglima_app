import 'package:shared_preferences/shared_preferences.dart';

class ShiftStorageService {
  static const String _shiftIdKey = 'active_shift_id';
  static const String _cashKey = 'active_cash';

  /// Simpan shift id
  static Future<void> saveShiftId(int shiftId, int cash) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_shiftIdKey, shiftId);
    await prefs.setInt(_cashKey, cash);
  }

  static Future<int?> getShiftId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_shiftIdKey);
  }

  static Future<int?> getCash() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cashKey);
  }

  /// Cek apakah shift sedang aktif
  static Future<bool> hasActiveShift() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_shiftIdKey);
  }

  /// Hapus shift id (saat close shift)
  static Future<void> clearShift() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shiftIdKey);
    await prefs.remove(_cashKey);
  }
}
