import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kInventoryPending = 'inventory_pending';
const _kInventoryCount = 'inventory_unapproved_count';

Future<void> resetNotif() async {
  final prefs = await SharedPreferences.getInstance();

  // Hapus data notif Firebase dari SharedPreferences
  await prefs.setBool('notif_visible', false);
  await prefs.remove('notif_title');
  await prefs.remove('notif_body');

  // Jika masih ada inventory yang belum dikerjakan, tampilkan kembali remindernya
  final inventoryPending = prefs.getBool(_kInventoryPending) ?? false;
  if (inventoryPending) {
    final count = prefs.getInt(_kInventoryCount) ?? 0;
    if (count > 0) {
      incomingNotifNotifier.value = _buildInventoryNotif(count);
      return;
    }
  }

  incomingNotifNotifier.value = null;
}

Future<void> saveNotifToPrefs(String? title, String? body) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('notif_title', title ?? 'Notifikasi');
  await prefs.setString('notif_body', body ?? '');
  await prefs.setBool('notif_visible', true);
}

/// Simpan reminder inventory ke SharedPreferences dan tampilkan ke notifier.
/// Dipanggil setiap kali ada surat jalan yang belum diterima.
Future<void> saveInventoryReminder(int count) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kInventoryPending, true);
  await prefs.setInt(_kInventoryCount, count);
  incomingNotifNotifier.value = _buildInventoryNotif(count);
}

/// Hapus reminder inventory. Dipanggil ketika semua surat jalan sudah diterima.
Future<void> clearInventoryReminder() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kInventoryPending);
  await prefs.remove(_kInventoryCount);
  if (incomingNotifNotifier.value?['type'] == 'inventory') {
    incomingNotifNotifier.value = null;
  }
}

/// Cek SharedPreferences dan tampilkan reminder inventory jika masih pending.
/// Dipanggil saat startup app.
Future<void> checkInventoryReminderOnStartup(SharedPreferences prefs) async {
  final inventoryPending = prefs.getBool(_kInventoryPending) ?? false;
  if (inventoryPending) {
    final count = prefs.getInt(_kInventoryCount) ?? 0;
    if (count > 0) {
      incomingNotifNotifier.value = _buildInventoryNotif(count);
    }
  }
}

Map<String, String> _buildInventoryNotif(int count) => {
  'type': 'inventory',
  'title': 'Surat Jalan Menunggu Konfirmasi',
  'body': '$count surat jalan belum diterima. Segera konfirmasi.',
};
