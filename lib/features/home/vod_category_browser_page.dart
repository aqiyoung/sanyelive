import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/providers/vod_provider.dart';
import '../../../data/models/content.dart';

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

    // 根据 typeId 获取对应 provider
    final provider = typeId == 20
        ? vodMoviesProvider
        : typeId == 30
            ? vodSeriesProvider
            : typeId == 45
                ? vodVarietyProvider
                : vodMoviesProvider;
    final async = ref.watch(provider);

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101010),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        color: active ? const Color(0x22E53935) : const Color(0xFF242424),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: active ? const Color(0xFFE53935) : Colors.white.withOpacity(0.04)),
                      ),
                      child: Text(
                        subList[i],
                        style: TextStyle(
                          color: active ? Colors.white : const Color(0xFFD6D6D6),
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
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('加载失败', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(child: Text('暂无内容', style: TextStyle(color: Colors.white54)));
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
                                color: const Color(0xFF242424),
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
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
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
