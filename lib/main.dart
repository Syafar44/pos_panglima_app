import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:pos_panglima_app/services/camera_service.dart';
import 'package:pos_panglima_app/services/helper/splash_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:pos_panglima_app/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_panglima_app/utils/notif_utils.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await saveNotifToPrefs(message.notification?.title, message.notification?.body);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await BluetoothPrinterService.requestPermissions();

  await BluetoothPrinterService.loadLastPrinter();

  final cameraService = CameraService();

  await cameraService.requestPermissionOnly();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    await saveNotifToPrefs(initialMessage.notification?.title, initialMessage.notification?.body);
  }

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    await saveNotifToPrefs(message.notification?.title, message.notification?.body);

    incomingNotifNotifier.value = {
      'title': message.notification?.title ?? 'Notifikasi',
      'body': message.notification?.body ?? '',
    };
  });

  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    await saveNotifToPrefs(message.notification?.title, message.notification?.body);

    incomingNotifNotifier.value = {
      'title': message.notification?.title ?? 'Notifikasi',
      'body': message.notification?.body ?? '',
    };
  });

  final prefs = await SharedPreferences.getInstance();

  final isVisible = prefs.getBool('notif_visible') ?? false;

  if (isVisible) {
    incomingNotifNotifier.value = {
      'title': prefs.getString('notif_title') ?? '',
      'body': prefs.getString('notif_body') ?? '',
    };
  }

  await checkInventoryReminderOnStartup(prefs);

  // await Hive.initFlutter();

  // await Hive.openBox('menuBox');

  await dotenv.load(fileName: ".env");

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'POS Panglima',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: AppBarTheme(
          foregroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        navigationDrawerTheme: NavigationDrawerThemeData(
          indicatorColor: Colors.white,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
      home: SplashScreen(),
    );
  }
}
