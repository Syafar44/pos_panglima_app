import 'dart:io';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  CameraController? _controller;

  Future<void> requestPermissionOnly() async {
    await Permission.camera.request();
  }

  Future<void> initialize() async {
    final cameras = await availableCameras();

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
  }

  Future<File?> capture() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        print("Camera not initialized");
        return null;
      }

      final XFile file = await _controller!.takePicture();
      return File(file.path);
    } catch (e) {
      print("Camera capture error: $e");
      return null;
    }
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
