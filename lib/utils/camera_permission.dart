import 'package:permission_handler/permission_handler.dart';

class CameraPermission {
  static Future<bool> request() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }
}
