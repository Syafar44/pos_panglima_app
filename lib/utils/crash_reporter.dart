import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashReporter {
  static Future<void> report(
    Object error,
    StackTrace? stack, {
    required String reason,
    Map<String, dynamic>? context,
  }) async {
    if (kDebugMode) {
      debugPrint('[CrashReporter] $reason → $error');
      if (context != null) debugPrint('[CrashReporter] context: $context');
      return;
    }

    final info = context?.entries
            .map((e) => DiagnosticsProperty(e.key, e.value))
            .toList() ??
        const <DiagnosticsNode>[];

    await FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: reason,
      information: info,
      fatal: false,
    );
  }
}
