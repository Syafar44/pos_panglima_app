import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pos_panglima_app/data/notifiers.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:pos_panglima_app/services/camera_service.dart';
import 'package:pos_panglima_app/services/fcm_token_service.dart';
import 'package:pos_panglima_app/services/helper/splash_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:pos_panglima_app/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_panglima_app/services/offline_sync_manager.dart';
import 'package:pos_panglima_app/utils/log_buffer.dart';
import 'package:pos_panglima_app/utils/notif_utils.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await saveNotifToPrefs(
    message.notification?.title,
    message.notification?.body,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initLogBuffer();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await BluetoothPrinterService.requestPermissions();

  await BluetoothPrinterService.loadLastPrinter();
  await BluetoothPrinterService.loadPrintQueue();

  final cameraService = CameraService();

  await cameraService.requestPermissionOnly();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    await saveNotifToPrefs(
      initialMessage.notification?.title,
      initialMessage.notification?.body,
    );
  }

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    await saveNotifToPrefs(
      message.notification?.title,
      message.notification?.body,
    );

    incomingNotifNotifier.value = {
      'title': message.notification?.title ?? 'Notifikasi',
      'body': message.notification?.body ?? '',
    };
  });

  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    await saveNotifToPrefs(
      message.notification?.title,
      message.notification?.body,
    );

    incomingNotifNotifier.value = {
      'title': message.notification?.title ?? 'Notifikasi',
      'body': message.notification?.body ?? '',
    };
  });

  // FCM token bisa rotate sewaktu-waktu (reinstall, clear data, dsb).
  // Kalau tidak disinkronkan, notifikasi push akan diam-diam berhenti jalan.
  FirebaseMessaging.instance.onTokenRefresh.listen((_) {
    FcmTokenService.syncToken();
  });

  // Retry sync di startup — no-op kalau user belum login atau token sama
  // dengan yang sudah sukses dikirim sebelumnya.
  // ignore: unawaited_futures
  FcmTokenService.syncToken();

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

  OfflineSyncManager.start();

  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50MB

  runApp(const MyApp());
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
        appBarTheme: const AppBarTheme(
          foregroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        navigationDrawerTheme: const NavigationDrawerThemeData(
          indicatorColor: Colors.white,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
