///
/// 数据源:  远程 hero_videos.json (运营改 JSON 即推送, 无需发版).
///
/// 默认位置:  aqiyoung/iptv-channels-organized/main/hero_videos.json
/// (与频道同源仓库; 周 cron 只重建 channels/*.json + meta.json, 不触碰此文件).
/// 想换地方改 [_heroVideosUrl] 即可.
///
/// 失败策略:  远程拉不到 / 超时 / 解析错 → 兜底读本地 assets/data/hero_videos.json
/// (默认 [] → 专区自动隐藏).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'models/hero_video.dart';

const _heroVideosUrl =
    'https://raw.githubusercontent.com/aqiyoung/iptv-channels-organized/main/hero_videos.json';

const _localAsset = 'assets/data/hero_videos.json';

class HeroVideosSource {
  HeroVideosSource({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  /// 拉远程 hero 视频列表.  超时 10s.  远程失败 → 兜底本地 assets.
  /// 返回已过滤过期项的最终列表.
  Future<List<HeroVideo>> fetch({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    List<HeroVideo> list;
    try {
      final resp =
          await _client.get(Uri.parse(_heroVideosUrl)).timeout(timeout);
      if (resp.statusCode != 200) {
        throw HeroVideosException('GET → ${resp.statusCode}');
      }
      list = HeroVideo.listFromJson(json.decode(resp.body));
    } catch (e) {
      debugPrint('HeroVideosSource: remote failed ($e), fallback local');
      list = await _loadLocal();
    }
    final now = DateTime.now();
    return list.where((v) => !_isExpired(v, now)).toList();
  }

  Future<List<HeroVideo>> _loadLocal() async {
    try {
      final str = await rootBundle.loadString(_localAsset);
      return HeroVideo.listFromJson(json.decode(str));
    } catch (_) {
      return const [];
    }
  }

  static bool _isExpired(HeroVideo v, DateTime now) {
    if (v.expiry == null || v.expiry!.isEmpty) return false;
    final exp = DateTime.tryParse(v.expiry!);
    if (exp == null) return false;
    return now.isAfter(exp);
  }
}

class HeroVideosException implements Exception {
  HeroVideosException(this.message);
  final String message;
  @override
  String toString() => 'HeroVideosException: $message';
}

final heroVideosSourceProvider = Provider<HeroVideosSource>((ref) {
  final source = HeroVideosSource();
  ref.onDispose(() => source._client.close());
  return source;
});

class HeroVideosNotifier extends AsyncNotifier<List<HeroVideo>> {
  @override
  Future<List<HeroVideo>> build() async {
    final source = ref.read(heroVideosSourceProvider);
    return source.fetch();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(heroVideosSourceProvider).fetch());
  }
}

final heroVideosProvider =
    AsyncNotifierProvider<HeroVideosNotifier, List<HeroVideo>>(
  HeroVideosNotifier.new,
);
