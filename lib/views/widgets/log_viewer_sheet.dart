import 'package:flutter/material.dart';
import 'package:pos_panglima_app/data/app_config.dart';
import 'package:pos_panglima_app/utils/log_buffer.dart';
import 'package:share_plus/share_plus.dart';

class LogViewerSheet extends StatefulWidget {
  const LogViewerSheet({super.key});

  @override
  State<LogViewerSheet> createState() => _LogViewerSheetState();
}

class _LogViewerSheetState extends State<LogViewerSheet> {
  late List<LogEntry> _entries;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _entries = List.from(LogBuffer.entries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _share() {
    final header =
        'POS Panglima v${AppConfig.version} — Log ${DateTime.now()}\n'
        '─────────────────────────────\n';
    SharePlus.instance.share(ShareParams(text: header + LogBuffer.toText()));
  }

  void _clear() {
    LogBuffer.clear();
    setState(() => _entries = []);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              _buildHandle(),
              _buildHeader(context),
              Expanded(
                child: _entries.isEmpty
                    ? const Center(
                        child: Text(
                          'Tidak ada log',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '[${entry.timestamp}] ',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  TextSpan(
                                    text: entry.message,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: _colorForMessage(entry.message),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Debug Log',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          Text(
            '${_entries.length} baris',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Hapus log',
            onPressed: _clear,
          ),
          IconButton(
            icon: const Icon(Icons.share, size: 20),
            tooltip: 'Kirim ke Dev',
            onPressed: _entries.isEmpty ? null : _share,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Tutup',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Color _colorForMessage(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('error') || lower.contains('exception')) {
      return Colors.red[700]!;
    }
    if (lower.contains('warn') || lower.contains('gagal')) {
      return Colors.orange[800]!;
    }
    if (lower.contains('[crashreporter]')) {
      return Colors.purple[700]!;
    }
    return Colors.black87;
  }
}

void showLogViewer(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const LogViewerSheet(),
  );
}
