import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:pos_panglima_app/services/auth_service.dart';
import 'package:pos_panglima_app/services/helper/dio_client.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Best-effort sinkronisasi FCM token ke server.
///
/// Dipakai di 3 titik:
/// - Setelah login berhasil → fire-and-forget supaya tidak memblok UI.
/// - `onTokenRefresh` di `main.dart` → token bisa rotate sewaktu-waktu.
/// - Startup app → retry kalau pernah gagal di login sebelumnya.
class FcmTokenService {
  static const String _usersIdKey = 'fcm_users_id';
  static const String _syncedTokenKey = 'fcm_synced_token';

  /// Simpan users_id untuk dipakai sync FCM token di kemudian hari.
  static Future<void> saveUsersId(int usersId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_usersIdKey, usersId);
  }

  /// Hapus state FCM. Panggil saat logout.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usersIdKey);
    await prefs.remove(_syncedTokenKey);
  }

  /// Sinkronkan FCM token ke server. Best-effort:
  /// - Tidak melempar exception apa-apa ke pemanggil.
  /// - Skip kalau users_id belum ada (user belum login).
  /// - Skip kalau token sama dengan yang sudah pernah sukses dikirim.
  static Future<void> syncToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final usersId = prefs.getInt(_usersIdKey);
      if (usersId == null) return;

      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken == null || fcmToken.isEmpty) return;

      // Skip kalau token sama sudah pernah sukses dikirim — hindari spam server.
      final lastSynced = prefs.getString(_syncedTokenKey);
      if (lastSynced == fcmToken) return;

      final authService = AuthService(ApiClient().dio);
      await authService.postFcmToken({
        'users_id': usersId,
        'fcm_token': fcmToken,
        'tipe': Platform.isIOS ? 'ios' : 'android',
      });

      await prefs.setString(_syncedTokenKey, fcmToken);
      if (kDebugMode) debugPrint('[FCM] Token synced for user $usersId');
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[FCM] Sync failed: $e');
      CrashReporter.report(e, stack, reason: 'fcm_token_service.syncToken');
    }
  }
}
