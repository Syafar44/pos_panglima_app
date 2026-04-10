import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class SkeletonLoader {
  static final Color _baseColor = Colors.grey.shade300;
  static final Color _highlightColor = Colors.grey.shade100;
  // 1. Loading untuk List Riwayat Penjualan (Card List)
  static Widget listHistorySkeleton() {
    return ListView.builder(
      itemCount: 6, // Tampilkan 6 baris bayangan
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 120, height: 12, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(width: 80, height: 10, color: Colors.white),
                    ],
                  ),
                ),
                Container(width: 60, height: 15, color: Colors.white),
              ],
            ),
          ),
        );
      },
    );
  }

  // 2. Loading untuk Detail Penjualan (Mirip Struk/Invoice)
  static Widget detailHistorySkeleton() {
    return Shimmer.fromColors(
      baseColor: _baseColor,
      highlightColor: _highlightColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Buttons (Share & Cetak)
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Section 1: Informasi Penjualan
            Container(width: 150, height: 18, color: Colors.white), // Title
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              childAspectRatio: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: List.generate(
                4,
                (index) => Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Section 2: Informasi Pembayaran
            Container(width: 180, height: 18, color: Colors.white), // Title
            const SizedBox(height: 16),
            Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 32),

            // Section 3: Riwayat Penerimaan
            Container(width: 160, height: 18, color: Colors.white), // Title
            const SizedBox(height: 16),
            Container(
              height: 80,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget detailLaporanSkeleton() {
    return Shimmer.fromColors(
      baseColor: _baseColor,
      highlightColor: _highlightColor,
      child: Column(
        // crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            childAspectRatio: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: List.generate(
              2,
              (index) => Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  static Widget detailInventorySkeleton() {
    return Shimmer.fromColors(
      baseColor: _baseColor,
      highlightColor: _highlightColor,
      child: Column(
        // crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Column(
            children: List.generate(
              2,
              (index) => Container(
                margin: EdgeInsets.only(bottom: 24),
                height: 150, // sesuaikan tinggi
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget menuSkeleton(Duration timeout, VoidCallback? onRetry) {
    return _MenuSkeletonWithRetry(timeout: timeout, onRetry: onRetry);
  }
}

class _MenuSkeletonWithRetry extends StatefulWidget {
  final Duration timeout;
  final VoidCallback? onRetry;

  const _MenuSkeletonWithRetry({required this.timeout, this.onRetry});

  @override
  State<_MenuSkeletonWithRetry> createState() => _MenuSkeletonWithRetryState();
}

class _MenuSkeletonWithRetryState extends State<_MenuSkeletonWithRetry> {
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
    final showRetryButton = _isTimedOut && widget.onRetry != null;

    if (showRetryButton) {
      // Tampilkan tombol retry
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Gagal memuat menu',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
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
                side: const BorderSide(color: Colors.red, width: 1.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Tampilkan shimmer skeleton
    return Shimmer.fromColors(
      baseColor: SkeletonLoader._baseColor,
      highlightColor: SkeletonLoader._highlightColor,
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 15,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 160, // ← atur tinggi item di sini
              ),
              itemBuilder: (context, index) => Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
