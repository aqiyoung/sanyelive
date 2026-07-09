import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/colors.dart';
import '../../../data/providers/vod_provider.dart';
import '../../../data/models/vod_source.dart';
import '../../../services/vod_source_registry.dart';

/// 分类 ID 与子分类映射
const _categoryMap = {
  'movie': {
    'label': '电影',
    'typeId': 20,
    'subs': ['全部', '动作', '科幻', '喜剧', '爱情', '悬疑', '动画', '犯罪', '战争'],
  },
  'series': {
    'label': '电视剧',
    'typeId': 30,
    'subs': ['全部', '国产剧', '欧美剧', '日韩剧', '悬疑', '古装', '都市', '家庭'],
  },
  'variety': {
    'label': '综艺',
    'typeId': 45,
    'subs': ['全部', '真人秀', '选秀', '脱口秀', '访谈', '竞技', '生活', '音乐'],
  },
  'anime': {
    'label': '动漫',
    'typeId': 39,
    'subs': ['全部', '国产', '日本', '欧美', '热血', '搞笑', '恋爱', '奇幻'],
  },
  'documentary': {
    'label': '纪录片',
    'typeId': 46,
    'subs': ['全部', '人文', '自然', '历史', '军事', '科技', '社会', '美食'],
  },
  'sports': {
    'label': '体育',
    'typeId': 33,
    'subs': ['全部', '足球', '篮球', '网球', '赛车', '搏击', '极限', '电竞'],
  },
  // v0.3.13.0: 海外剧场 — 欧美剧/英剧/海外剧.  typeId 仅作参考 (实际由活跃源
  // typeIds 决定),  所以这里的 typeId 值不重要,  只要 label/subs 即可.
  'overseas': {
    'label': '海外剧场',
    'typeId': 26,
    'subs': ['全部', '欧美剧', '英剧', '韩剧', '日剧'],
  },
};

/// 视界 VOD 二级分类浏览页
/// 根据传入的 category 类型，直接显示对应子分类 + 内容
class VodCategoryBrowserPage extends ConsumerStatefulWidget {
  const VodCategoryBrowserPage({super.key, required this.category});

  /// 分类 key，如 'movie', 'series', 'variety'
  final String category;

  @override
  ConsumerState<VodCategoryBrowserPage> createState() => _VodCategoryBrowserPageState();
}

class _VodCategoryBrowserPageState extends ConsumerState<VodCategoryBrowserPage> {
  int _selectedSub = 0;

  Map<String, dynamic> get _config => _categoryMap[widget.category] ?? _categoryMap['movie']!;
  List<String> get _subs => _config['subs'] as List<String>;

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final label = config['label'] as String;
    final typeId = config['typeId'] as int;
    final subList = _subs;

    // v0.3.13.0: 按 category key 直接路由到对应 provider (不再硬编码 typeId 匹配).
    // anime/documentary/sports/overseas 无独立 provider 时 fallback 到 movies.
    final provider = switch (widget.category) {
      'series' => vodSeriesProvider,
      'variety' => vodVarietyProvider,
      'overseas' => vodOverseasProvider,
      'movie' || _ => vodMoviesProvider,
    };
    final async = ref.watch(provider);

    return Scaffold(
      backgroundColor: context.bgBase,
      appBar: AppBar(
        backgroundColor: context.bgBase,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.fgMain),
          onPressed: () => context.pop(),
        ),
        title: Text(label, style: TextStyle(color: context.fgMain, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── v0.3.13.0: VOD 源选择芯片栏 ──────────────────────
          _VodSourceChipBar(),
          // ─── 二级分类标签 ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8),
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 16),
                itemCount: subList.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final active = i == _selectedSub;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedSub = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? context.fgAccent.withValues(alpha: 0.13) : context.bgCardHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: active ? context.fgAccent : context.fgBorder),
                      ),
                      child: Text(
                        subList[i],
                        style: TextStyle(
                          color: active ? context.fgAccent : context.fgSub,
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          // ─── 内容区 ────────────────────────────────────────────
          Expanded(
            child: async.when(
              loading: () => Center(child: CircularProgressIndicator(color: context.fgSub, strokeWidth: 2)),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('加载失败', style: TextStyle(color: context.fgSub, fontSize: 13)),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Center(child: Text('暂无内容', style: TextStyle(color: context.fgSub)));
                }
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.65,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    return GestureDetector(
                      onTap: () {
                        if (item.sourceUrls.isNotEmpty) {
                          context.go('/player/vod?url=${Uri.encodeComponent(item.sourceUrls.first)}&title=${Uri.encodeComponent(item.title)}');
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: context.bgCardHigh,
                                borderRadius: BorderRadius.circular(8),
                                image: item.hasPoster
                                    ? DecorationImage(
                                        image: NetworkImage(item.posterUrl!),
                                        fit: BoxFit.cover,
                                        onError: (_, __) {},
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.fgMain, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// v0.3.13.0: VOD 源选择芯片栏 — 横向滚动 + 当前活跃源高亮 + + 添加.
class _VodSourceChipBar extends ConsumerWidget {
  const _VodSourceChipBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(vodSourceRegistryProvider);
    final sources = registry.sources;
    final activeId = registry.activeSourceId;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              itemCount: sources.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = sources[i];
                final active = s.id == activeId;
                return ChoiceChip(
                  label: Text(
                    s.name,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: active,
                  onSelected: (_) =>
                      ref.read(vodSourceRegistryProvider).setActiveSource(s.id),
                  selectedColor: scheme.primary,
                  labelStyle: TextStyle(
                    color: active ? scheme.onPrimary : scheme.onSurface,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
            ),
          ),
          // + 按钮 — 添加自定义源.
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            tooltip: '添加影视源',
            onPressed: () => _showAddSourceDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showAddSourceDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    var scheme = VodTypeIdScheme.bfzyapi;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('添加影视源'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '如: 量子资源',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'MacCMS API 地址',
                    hintText: 'https://xxx.com/api.php/provide/vod',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('typeId 方案:'),
                    const SizedBox(width: 8),
                    DropdownButton<VodTypeIdScheme>(
                      value: scheme,
                      items: VodTypeIdScheme.values
                          .map((e) => DropdownMenuItem(
                              value: e, child: Text(e.label)))
                          .toList(),
                      onChanged: (v) => setLocal(() => scheme = v ?? scheme),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final url = urlCtrl.text.trim();
                if (name.isEmpty || url.isEmpty) return;
                String host;
                try {
                  host = Uri.parse(url).host;
                } catch (_) {
                  host = 'vod';
                }
                final id = '${host}_${DateTime.now().millisecondsSinceEpoch}';
                ref.read(vodSourceRegistryProvider).addSource(VodSource(
                      id: id,
                      name: name,
                      baseUrl: url,
                      typeIds: scheme.typeIds,
                    ));
                Navigator.pop(ctx);
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }
}
