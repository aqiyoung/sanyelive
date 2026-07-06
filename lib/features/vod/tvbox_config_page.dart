/// TVBox 配置页 - 管理 TVBox 视频源

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/vod/vod_providers.dart';
import '../../data/vod/tvbox_config.dart';

/// 默认 TVBox 配置地址
const kDefaultTVBoxUrls = [
  'https://raw.githubusercontent.com/YuanHsing/freed/master/TVBox/meow.json',
  'https://raw.liucn.cc/box/m.json',
  'https://9280.kstore.space/wex.json',
];

class TVBoxConfigPage extends ConsumerStatefulWidget {
  const TVBoxConfigPage({super.key});

  @override
  ConsumerState<TVBoxConfigPage> createState() => _TVBoxConfigPageState();
}

class _TVBoxConfigPageState extends ConsumerState<TVBoxConfigPage> {
  late TextEditingController _urlController;
  bool _showPreview = false;
  TVBoxConfig? _previewConfig;

  @override
  void initState() {
    super.initState();
    final currentUrl = ref.read(tvboxConfigProvider).configUrl ?? '';
    _urlController = TextEditingController(text: currentUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 TVBox 配置地址')),
      );
      return;
    }
    await ref.read(tvboxConfigProvider.notifier).load(url);
    if (mounted) {
      final state = ref.read(tvboxConfigProvider);
      if (state.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: ${state.error}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载成功: ${state.config!.macCMSSites.length} 个视频源')),
        );
        context.pop();
      }
    }
  }

  Future<void> _doPreview() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    try {
      final config = await TVBoxConfig.fetch(url);
      setState(() {
        _previewConfig = config;
        _showPreview = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('预览失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final configState = ref.watch(tvboxConfigProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('TVBox 配置', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 配置地址输入
            const Text('视频源地址', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: '输入 TVBox 配置 URL',
                hintStyle: const TextStyle(color: Color(0xFF6E6E6E)),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: configState.loading ? null : _loadConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: configState.loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('加载配置', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _doPreview,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Color(0xFF9E9E9E),
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('预览', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 默认地址快捷选择
            const Text('快捷选择', style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
            const SizedBox(height: 8),
            ...kDefaultTVBoxUrls.map((url) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: () {
                      _urlController.text = url;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link, color: Color(0xFF6E6E6E), size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              url,
                              style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),

            // 当前配置状态
            if (configState.config != null) ...[
              const SizedBox(height: 20),
              const Text('已加载配置', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(label: '视频源', value: '${configState.config!.macCMSSites.length} 个'),
                    _InfoRow(label: '直播源', value: '${configState.config!.lives.length} 个'),
                    _InfoRow(label: '配置地址', value: configState.configUrl ?? ''),
                  ],
                ),
              ),
            ],

            // 预览结果
            if (_showPreview && _previewConfig != null) ...[
              const SizedBox(height: 20),
              const Text('预览结果', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(label: 'MacCMS API', value: '${_previewConfig!.macCMSSites.length} 个'),
                    _InfoRow(label: 'JS 插件', value: '${_previewConfig!.sites.where((s) => s.type == 3).length} 个（不支持）'),
                    _InfoRow(label: '直播源', value: '${_previewConfig!.lives.length} 个'),
                    const SizedBox(height: 8),
                    const Text('可用站点:', style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
                    const SizedBox(height: 4),
                    ..._previewConfig!.macCMSSites.take(10).map((site) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 12),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  site.name,
                                  style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )),
                    if (_previewConfig!.macCMSSites.length > 10)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '...还有 ${_previewConfig!.macCMSSites.length - 10} 个',
                          style: const TextStyle(color: Color(0xFF6E6E6E), fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
          Text(value, style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13)),
        ],
      ),
    );
  }
}