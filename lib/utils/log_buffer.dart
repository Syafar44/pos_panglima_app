import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class LogEntry {
  final String timestamp;
  final String message;

  LogEntry({required this.timestamp, required this.message});

  @override
  String toString() => '[$timestamp] $message';
}

class LogBuffer {
  static const int _maxEntries = 300;
  static final List<LogEntry> _entries = [];

  static List<LogEntry> get entries => List.unmodifiable(_entries);

  static void add(String? message) {
    if (message == null || message.isEmpty) return;
    final ts = DateFormat('HH:mm:ss').format(DateTime.now());
    _entries.add(LogEntry(timestamp: ts, message: message));
    if (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }
  }

  static void clear() => _entries.clear();

  static String toText() => _entries.map((e) => e.toString()).join('\n');
}

/// Call once in main() before runApp() to wire LogBuffer into debugPrint.
void initLogBuffer() {
  debugPrint = (String? message, {int? wrapWidth}) {
    LogBuffer.add(message);
    debugPrintSynchronously(message, wrapWidth: wrapWidth);
  };
}
