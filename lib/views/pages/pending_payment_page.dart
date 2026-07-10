import 'package:flutter/material.dart';
import 'package:pos_panglima_app/services/network_service.dart';
import 'package:pos_panglima_app/services/offline_sync_manager.dart';
import 'package:pos_panglima_app/services/storage/pending_order_service.dart';
import 'package:pos_panglima_app/utils/app_colors.dart';
import 'package:pos_panglima_app/utils/convert.dart';
import 'package:pos_panglima_app/utils/snackbar_util.dart';

class PendingPaymentPage extends StatefulWidget {
  const PendingPaymentPage({super.key});

  @override
  State<PendingPaymentPage> createState() => _PendingPaymentPageState();
}

class _PendingPaymentPageState extends State<PendingPaymentPage> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  bool _flushing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadOrders();
    // Auto-flush kalau online
    final online = await NetworkService.isOnline();
    if (online && _orders.isNotEmpty) {
      await _flush(auto: true);
    }
  }

  Future<void> _loadOrders() async {
    final list = await PendingOrderService.getAll();
    if (!mounted) return;
    setState(() {
      _orders = list;
      _loading = false;
    });
  }

  Future<void> _flush({bool auto = false}) async {
    if (_flushing) return;
    if (!mounted) return;
    setState(() => _flushing = true);

    final online = await NetworkService.isOnline();
    if (!online) {
      setState(() => _flushing = false);
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: 'Offline',
        message: 'Sambungkan internet untuk mengirim pesanan.',
        status: SnackBarStatus.warning,
      );
      return;
    }

    await OfflineSyncManager.syncNow();
    await _loadOrders();

    if (!mounted) return;
    setState(() => _flushing = false);

    if (!auto && mounted) {
      final remaining = await PendingOrderService.count();
      if (!mounted) return;
      SnackbarUtil.show(
        context,
        title: remaining == 0 ? 'Berhasil' : 'Sebagian Gagal',
        message: remaining == 0
            ? 'Semua pesanan berhasil dikirim.'
            : '$remaining pesanan perlu dicek (rejected).',
        status: remaining == 0
            ? SnackBarStatus.success
            : SnackBarStatus.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Row(
          children: [
            const Text('Riwayat Pending'),
            if (_orders.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_orders.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!_loading && _orders.isNotEmpty)
            _flushing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.sync, color: Colors.white),
                    tooltip: 'Kirim Ulang Semua',
                    onPressed: _flush,
                  ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: () async {
                await _flush();
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _buildOrderCard(_orders[i]),
              ),
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.green.shade300,
          ),
          const SizedBox(height: 16),
          const Text(
            'Tidak ada pesanan pending',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          const Text(
            'Semua transaksi offline sudah terkirim.',
            style: TextStyle(fontSize: 13, color: Colors.black38),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final clientRef = order['client_ref']?.toString() ?? '-';
    final createdAt = order['created_at']?.toString() ?? '-';
    final total = (order['total_amount'] as num?)?.toInt() ?? 0;
    final lines = (order['pos_order_lines'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final syncStatus = order['_sync_status']?.toString();
    final isRejected = syncStatus != null;
    final methodId = (order['pos_order_method_id'] as num?)?.toInt() ?? 1;
    final isCash = (order['is_cash'] as num?)?.toInt() == 1;
    final totalQty = lines.fold<int>(
      0,
      (s, l) => s + ((l['quantity'] as num?)?.toInt() ?? 0),
    );

    String timeLabel = createdAt;
    try {
      final local = DateTime.parse(createdAt).toLocal();
      timeLabel =
          '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} '
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    } catch (_) {}

    final docTitle = clientRef.length >= 8
        ? 'OFFLINE-${clientRef.substring(0, 8).toUpperCase()}'
        : 'PESANAN OFFLINE';
    final Color accent = isRejected ? Colors.red : Colors.orange;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRejected ? Colors.red.shade200 : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: ikon + nomor + waktu, total di kanan
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      docTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeLabel,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Text(
                convertIDR(total),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16.0,
                  color: isRejected ? Colors.red.shade700 : AppColors.primary,
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 0.5),
          ),
          ...lines.take(3).map((line) {
            final name =
                line['pos_menus_name']?.toString() ??
                'Menu #${line['pos_menus_id']}';
            final qty = line['quantity'] ?? 0;
            final props = (line['pos_order_lines_props'] as List? ?? [])
                .cast<Map<String, dynamic>>();
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${qty}x',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  // Sub-item / varian (menu paket)
                  if (props.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 32, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: props.map((p) {
                          final pName =
                              p['pos_menus_name']?.toString() ??
                              'Item #${p['pos_menus_id']}';
                          final pQty = p['quantity'] ?? 0;
                          return Text(
                            '+ $pQty $pName',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            );
          }),
          if (lines.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '+${lines.length - 3} item lainnya',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),

          const SizedBox(height: 12),

          // Footer: badge info + chip status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    _buildSmallBadge(
                      icon: Icons.shopping_bag_outlined,
                      label: '$totalQty item',
                    ),
                    const SizedBox(width: 12),
                    _buildSmallBadge(
                      icon: isCash
                          ? Icons.payments_outlined
                          : Icons.account_balance_wallet_outlined,
                      label: isCash ? 'Tunai' : 'Non-tunai',
                    ),
                  ],
                ),
              ),
              _methodChip(methodId),
              const SizedBox(width: 8),
              _statusChip(syncStatus),
            ],
          ),

          // Catatan kalau ditolak server
          if (isRejected) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.red.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ditolak server ($syncStatus) — perlu dicek manual.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSmallBadge({required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }

  String _methodLabel(int id) {
    if (id == 1) return 'Takeaway';
    if (id == 2) return 'Delivery';
    return 'Lainnya';
  }

  Color _methodColor(int id) {
    if (id == 1) return Colors.teal;
    if (id == 2) return Colors.orange;
    return Colors.purple;
  }

  Widget _methodChip(int id) {
    final color = _methodColor(id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _methodLabel(id),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _statusChip(String? status) {
    final bool isPending = status == null;
    final Color color = isPending ? Colors.orange : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isPending ? 'Pending' : 'Rejected',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isPending ? Colors.orange.shade800 : Colors.red.shade700,
        ),
      ),
    );
  }
}
