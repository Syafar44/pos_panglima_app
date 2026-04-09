import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> resetNotif() async {
  // Reset notifier agar banner hilang dari UI
  incomingNotifNotifier.value = null;

  // Reset SharedPreferences agar tidak muncul lagi saat app dibuka ulang
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('notif_visible', false);
  await prefs.remove('notif_title');
  await prefs.remove('notif_body');
}
