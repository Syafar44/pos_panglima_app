import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:hive_flutter/adapters.dart';
import 'package:pos_panglima_app/services/bluetooth_printer_service.dart';
import 'package:pos_panglima_app/services/camera_service.dart';
import 'package:pos_panglima_app/services/helper/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await BluetoothPrinterService.requestPermissions();

  await BluetoothPrinterService.loadLastPrinter();

  final cameraService = CameraService();

  await cameraService.requestPermissionOnly();

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
