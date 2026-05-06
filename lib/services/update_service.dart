import 'dart:io';
import 'package:in_app_update/in_app_update.dart';
import 'package:pos_panglima_app/utils/crash_reporter.dart';

class UpdateService {
  static Future<AppUpdateInfo?> check() async {
    if (!Platform.isAndroid) return null;
    try {
      return await InAppUpdate.checkForUpdate();
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'update_service.check');
      return null;
    }
  }

  static Future<bool> startFlexible() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      return result == AppUpdateResult.success;
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'update_service.startFlexible');
      return false;
    }
  }

  static Future<void> completeFlexible() async {
    if (!Platform.isAndroid) return;
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'update_service.completeFlexible');
    }
  }

  static Future<bool> startImmediate() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      return result == AppUpdateResult.success;
    } catch (e, stack) {
      CrashReporter.report(e, stack, reason: 'update_service.startImmediate');
      return false;
    }
  }
}
