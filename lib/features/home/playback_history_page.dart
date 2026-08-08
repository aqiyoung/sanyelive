import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../widgets/liquid_glass_container.dart';
import '../../services/playback_history_service.dart';

/// 播放历史记录页
class PlaybackHistoryPage extends StatefulWidget {
  const PlaybackHistoryPage({super.key});

  @override
  State<PlaybackHistoryPage> createState() => _PlaybackHistoryPageState();
}

class _PlaybackHistoryPageState extends State<PlaybackHistoryPage> {
  List<PlaybackHistoryEntry> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await PlaybackHistoryService.load();
    setState(() { _items = items; _loaded = true; });
  }

  Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('playback_history');
    setState(() => _items = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgBase,
      appBar: AppBar(
        backgroundColor: context.bgBase,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.fgMain),
          onPressed: () => context.pop(),
        ),
        title: Text('播放记录', style: TextStyle(color: context.fgMain, fontSize: 18, fontWeight: FontWeight.w700)),
        actions: _items.isEmpty
            ? null
            : [
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: context.fgSub, size: 20),
                  onPressed: () {
                    showDialog(
                      context: context,
                      barrierColor: Colors.black.withValues(alpha: 0.35),
                      builder: (ctx) => LiquidGlassContainer(
                        variant: LiquidGlassVariant.light,
                        borderRadius: 24,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('清空记录', style: TextStyle(color: context.fgMain, fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            Text('确定清空所有播放记录？', style: TextStyle(color: context.fgSub)),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消', style: TextStyle(color: context.fgSub))),
                                const SizedBox(width: 8),
                                TextButton(onPressed: () { Navigator.pop(ctx); _clear(); }, child: Text('清空', style: TextStyle(color: context.fgAccent))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
      ),
      body: !_loaded
          ? Center(child: CircularProgressIndicator(color: context.fgSub, strokeWidth: 2))
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, color: context.fgSub.withValues(alpha: 0.6), size: 56),
                      const SizedBox(height: 12),
                      Text('暂无播放记录', style: TextStyle(color: context.fgSub.withValues(alpha: 0.5), fontSize: 14)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => Divider(color: context.fgBorder, height: 1),
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                        leading: Container(
                          width: 52,
                          height: 72,
                          decoration: BoxDecoration(
                            color: context.bgCardHigh,
                            borderRadius: BorderRadius.circular(6),
                            image: item.posterUrl != null && item.posterUrl!.isNotEmpty
                                ? DecorationImage(image: NetworkImage(item.posterUrl!), fit: BoxFit.cover, onError: (_, __) {})
                                : null,
                          ),
                        ),
                        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.fgMain, fontSize: 14, fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          '${item.playedAt.month.toString().padLeft(2, '0')}-${item.playedAt.day.toString().padLeft(2, '0')} ${item.playedAt.hour.toString().padLeft(2, '0')}:${item.playedAt.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: context.fgSub, fontSize: 11),
                        ),
                        onTap: () => context.go('/player/vod?url=${Uri.encodeComponent(item.url)}&title=${Uri.encodeComponent(item.title)}'),
                      );
                    },
                  ),
                ),
    );
  }
}
