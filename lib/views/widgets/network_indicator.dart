import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';

enum _NetStatus { unknown, fast, medium, slow, offline }

class NetworkIndicatorWidget extends StatefulWidget {
  const NetworkIndicatorWidget({super.key});

  @override
  State<NetworkIndicatorWidget> createState() => _NetworkIndicatorWidgetState();
}

class _NetworkIndicatorWidgetState extends State<NetworkIndicatorWidget> {
  _NetStatus _status = _NetStatus.unknown;
  Timer? _refreshTimer;
  StreamSubscription? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _check();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _check(),
    );
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (_) => _check(),
    );
  }

  Future<void> _check() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.isEmpty || result.every((r) => r == ConnectivityResult.none)) {
        if (mounted) setState(() => _status = _NetStatus.offline);
        return;
      }

      final sw = Stopwatch()..start();
      final socket = await Socket.connect(
        '1.1.1.1',
        80,
        timeout: const Duration(seconds: 4),
      );
      sw.stop();
      socket.destroy();

      final ms = sw.elapsedMilliseconds;
      final next = ms < 150
          ? _NetStatus.fast
          : ms < 600
          ? _NetStatus.medium
          : _NetStatus.slow;

      if (mounted) setState(() => _status = next);
    } catch (_) {
      if (mounted) setState(() => _status = _NetStatus.offline);
    }
  }

  Color get _dotColor => switch (_status) {
    _NetStatus.fast => Colors.green,
    _NetStatus.medium => Colors.amber,
    _NetStatus.slow => Colors.orange,
    _NetStatus.offline => Colors.red,
    _NetStatus.unknown => Colors.grey,
  };

  String get _label => switch (_status) {
    _NetStatus.fast => 'Jaringan Baik',
    _NetStatus.medium => 'Jaringan Sedang',
    _NetStatus.slow => 'Jaringan Lambat',
    _NetStatus.offline => 'Tidak Ada Koneksi',
    _NetStatus.unknown => 'Memeriksa...',
  };

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _label,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.center,
                child: Icon(
                  _status == _NetStatus.offline ? Icons.wifi_off : Icons.wifi,
                  size: 22,
                  color: AppColors.primary,
                ),
              ),
              Positioned(
                right: -1,
                top: 3,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _dotColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
