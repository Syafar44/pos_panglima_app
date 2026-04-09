import 'dart:async';
import 'package:flutter/widgets.dart';

mixin QuantityTimerMixin {
  Timer? _timer;
  final Duration _interval = const Duration(milliseconds: 100);

  void startTimer(VoidCallback action) {
    _timer = Timer.periodic(_interval, (_) => action());
  }

  void stopTimer() => _timer?.cancel();

  void disposeTimer() => _timer?.cancel();
}
