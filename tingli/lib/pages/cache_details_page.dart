import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/cache_service.dart';

class CacheDetailsPage extends StatefulWidget {
  const CacheDetailsPage({super.key});

  @override
  State<CacheDetailsPage> createState() => _CacheDetailsPageState();
}

class _CacheDetailsPageState extends State<CacheDetailsPage> {
  late Future<List<CacheEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = CacheService.listEntries();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = CacheService.listEntries();
    });
  }

  String _fmtBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('缓存详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              // 显示确认对话框
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => FutureBuilder<List<CacheEntry>>(
                  future: _future,
                  builder: (context, snapshot) {
                    final entries = snapshot.data ?? const [];
                    final total = entries.fold<int>(
                      0,
                      (sum, e) => sum + e.sizeBytes,
                    );
                    return AlertDialog(
                      title: const Text('确认清空缓存'),
                      content: Text(
                        '确定要清空所有已缓存的音视频文件吗？\n当前缓存: ${_fmtBytes(total)}',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            '确认清空',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );

              // 用户确认后才清空
              if (confirmed == true) {
                await CacheService.clearCache();
                if (!mounted) return;
                _refresh();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('缓存已清空')));
              }
            },
            tooltip: '清空缓存',
          ),
        ],
      ),
      body: FutureBuilder<List<CacheEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return const Center(child: Text('暂无缓存文件'));
          }
          final total = entries.fold<int>(0, (sum, e) => sum + e.sizeBytes);
          return Column(
            children: [
              ListTile(
                leading: const Icon(Icons.storage, color: Colors.teal),
                title: Text('共 ${entries.length} 个文件'),
                subtitle: Text('总计 ${_fmtBytes(total)}'),
              ),
              const Divider(height: 1),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      final dateStr = DateFormat(
                        'yyyy-MM-dd HH:mm',
                      ).format(e.modifiedAt);
                      return ListTile(
                        leading: const Icon(
                          Icons.insert_drive_file,
                          color: Colors.grey,
                        ),
                        title: Text(
                          e.relativePath,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${_fmtBytes(e.sizeBytes)} · $dateStr'),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('删除缓存'),
                                content: Text('确定要删除\n${e.relativePath}\n吗？'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text(
                                      '删除',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await CacheService.deleteEntry(e.relativePath);
                              if (mounted) _refresh();
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
