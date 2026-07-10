import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache metode pembayaran & metode pesanan ke local storage supaya halaman
/// pembayaran tetap bisa dibuka saat offline. Diisi saat login & saat halaman
/// pembayaran berhasil memuat dari server.
class MethodStorageService {
  static const String _paymentKey = 'payment_methods_cache';
  static const String _orderKey = 'order_methods_cache';

  static Future<void> save(List payment, List order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paymentKey, jsonEncode(payment));
    await prefs.setString(_orderKey, jsonEncode(order));
  }

  static Future<List<Map<String, dynamic>>> getPaymentMethods() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_paymentKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getOrderMethods() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_orderKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
