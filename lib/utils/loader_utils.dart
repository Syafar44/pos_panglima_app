import 'package:flutter/material.dart';

class ModernLoading extends StatefulWidget {
  final String? message;
  final Color? color;
  final double size;
  final double strokeWidth;
  final Duration timeout;
  final VoidCallback? onRetry; // fungsi retry dikirim dari luar

  const ModernLoading({
    super.key,
    this.message,
    this.color,
    this.size = 45,
    this.strokeWidth = 4,
    this.timeout = const Duration(seconds: 5),
    this.onRetry, // opsional, jika null tombol retry tidak muncul
  });

  @override
  State<ModernLoading> createState() => _ModernLoadingState();
}

class _ModernLoadingState extends State<ModernLoading> {
  bool _isTimedOut = false;

  @override
  void initState() {
    super.initState();
    _startTimeout();
  }

  void _startTimeout() {
    Future.delayed(widget.timeout, () {
      if (mounted) {
        setState(() => _isTimedOut = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.color ?? Colors.amber;
    final showRetryButton = _isTimedOut && widget.onRetry != null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showRetryButton == false)
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  strokeWidth: widget.strokeWidth,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    activeColor.withOpacity(0.2),
                  ),
                ),
              ),
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  strokeWidth: widget.strokeWidth,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                ),
              ),
            ],
          ),

        if (widget.message != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.message!,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],

        if (showRetryButton) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _isTimedOut = false);
              _startTimeout();
              widget.onRetry?.call();
            },
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text(
              'Coba Lagi',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              backgroundColor: Colors.red.shade50,
              side: BorderSide(
                color: Colors.red,
                width: 1.5,
              ), // Garis pinggir lebih tegas
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  12,
                ), // Sudut yang lebih lembut
              ),
            ),
          ),
        ],
      ],
    );
  }
}
