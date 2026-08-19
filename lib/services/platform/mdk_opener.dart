import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../source_failover.dart';
import '../../utils/crash_logger.dart';

/// 对 [player] 应用全屏播放路径的渲染配置。
///
/// hwdec 已由 [mediaKitVideoControllerProvider] 在 VideoController 构造时锁定为
/// auto-safe (MediaCodec 硬件解码), 此处不再改动。
///
/// 关键背景 (ffprobe 实锤 + 真机实测):
///  - 卫视等渐进源正常 → 渲染器本身没坏。
///  - 央视腾讯云 `index.m3u8` 是多码流列表, libmpv 默认挑最高的 1920x1080@3.2Mbps
///    **1080i 隔行**主码流 → 在 Android 16 media_kit vo=gpu 管线上花屏 + 加载慢。
///  - ffprobe 实测央视流本身就是 **yuv420p(4:2:0)**, 与卫视同构; 故此前
///    `vf=format=fmt=yuv420p` 实为 no-op(本就 4:2:0), 不能修复花屏。
///  - **真因 = 拉了 1080i 1080p 主码流**。根治在源级: [CctvSourcePicker] 已把腾讯云
///    央视源改写为 720p 渐进子码流(`_td.m3u8`), 且 [MediaKitStreamOpener] 设
///    `hls-bitrate` 封顶(≤2Mbps)双保险 → 自动避开 1080p/1080i。
///  - `deinterlace`/`vf=format=fmt=yuv420p` 此处保留作**无害兜底**(渐进 720p 下
///    vf 是 no-op; 万一命中 4:2:2 源仍可转 yuv420p)。
///
/// 为什么用 vf 而不是 gpu-api/target-colorspace-hint: 后者必须在 vo 初始化前
/// 设置 (VideoController 构造时), 运行时 setProperty 太晚、不生效; vf 是运行时
/// 可重建滤镜链的属性, 在 open 前 setProperty 能真正起作用。
/// ⚠️ vf 滤镜链只有在帧回到内存时才生效 — 故 [mediaKitVideoControllerProvider]
/// 必须用 hwdec=auto-copy (auto-safe 直出 Surface 会绕过 vf)。
///
/// 央视源判定: 给定 URL 是否需要对央视源走**软件解码**兜花色问题。
///
/// ⚠️ 8-19 关键修正(真机日志铁证): 本设备软件解码(`hwdec=no`)**根本不显示画面**——
/// 仅出声音(媒体帧不走标准 Surface 上屏, media_kit 在部分 Android 上的已知问题)。
/// 日志实证: CCTV1/13 经腾讯云 `ldncctvwbcd _td` 软解 → `hwdec-current=no` →
/// 有声音没画面; 而卫视/222.223 经 `mediacodec-copy` 硬件解码 → 画面正常。
///
/// 因此软解**绝不能**用于能硬件解码的渐进流。判定收紧为:
///  - `_td`/`_hd`/`_ud`/`_md`/`_sd` 等**渐进子码流** → 返回 false(硬件解码)。
///    这些流已是 720p 渐进 H.264, 硬件解码不花屏, 且本设备软解不显示画面。
///  - 裸 `index.m3u8` **隔行主码流**(1080i, 历史上真绿紫花屏) → 返回 true(软件解码),
///    作为兜底, 避免命中隔行主码流时花屏。该裸流在用户网络几乎不会被命中
///    (CCTV1/13 首选已是 `_td`, 且即便命中软解无画面也好过花屏)。
bool _isLikelyCctv(String url) {
  final u = url.toLowerCase();
  if (!u.contains('ldncctvwbcd')) return false;
  // 渐进子码流 → 硬件解码(本设备软解不显示画面)。
  final isProgressive =
      RegExp(r'_(td|hd|ud|md|sd)\.m3u8$').hasMatch(u);
  if (isProgressive) return false;
  // 裸 index.m3u8 隔行主码流 → 软件解码兜底(规避 1080i 绿紫花屏)。
  return true;
}

/// 应用 hwdec 策略。
///
/// [software] = true → `hwdec=no` (纯软件解码): 颜色 100% 正确, 彻底规避
/// `vo=gpu` + `mediacodec-copy` 在部分 Android 设备上回拷内存后 GPU 上传的
/// 颜色格式错乱(绿紫噪点)。央视源已被改写为 720p 渐进, 软件解码 CPU 完全扛得住。
/// [software] = false → 恢复 `hwdec=auto-copy` (硬件解码, 其它频道沿用)。
///
/// ⚠️ hwdec 必须在 open 之前 setProperty 才对本次流生效。
Future<void> _applyHwdec(Player player, bool software) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  try {
    await platform.setProperty('hwdec', software ? 'no' : 'auto-copy');
  } catch (e, st) {
    debugPrint('_applyHwdec($software) failed: $e\n$st');
  }
}

/// 仅供 [MediaKitStreamOpener] 调用。
Future<void> configureDeinterlace(
  Player player, {
  bool? softwareDecode,
}) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  if (softwareDecode != null) await _applyHwdec(player, softwareDecode);
  try {
    // 全局 HLS 码率封顶: 多码流源(含央视腾讯云)自动不选 1080p, 改选 ≤2Mbps 子码流
    // → 加快加载 + 避开 1080i 花屏。单码流源/卫视(多为单码流)不受影响。
    await platform.setProperty('hls-bitrate', '2000000');
    await platform.setProperty('deinterlace', 'yes');
    // 强制标准像素格式: 兜底处理(ffprobe 实测央视流已为 yuv420p, 此处在渐进 720p
    // 下为 no-op; 若命中 4:2:2 源仍可转 yuv420p)。语法 format=fmt=yuv420p
    // (+230 漏写 fmt= 导致静默失效)。
    await platform.setProperty('vf', 'format=fmt=yuv420p');
  } catch (e, st) {
    debugPrint('configureDeinterlace failed: $e\n$st');
  }
}

/// 首页 Hero 小窗口预览的配置。
///
/// hwdec 已由 [mediaKitVideoControllerProvider] 锁定为 auto-copy, 此处不再改动。
/// 预览对隔行梳状纹不敏感, 故关掉 deinterlace 以省算力; 但仍强制 yuv420p 格式,
/// 避免央视流预览花屏 (与全屏同因)。vf 语法同 [configureDeinterlace]。
///
/// 仅供 [_TvHeroState._startPreview] 调用。
Future<void> configurePreview(
  Player player, {
  bool? softwareDecode,
}) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  if (softwareDecode != null) await _applyHwdec(player, softwareDecode);
  try {
    // 与全屏一致: HLS 码率封顶, 避免 Hero 预览也拉 1080p(慢 + 可能花屏)
    await platform.setProperty('hls-bitrate', '2000000');
    await platform.setProperty('deinterlace', 'no');
    await platform.setProperty('vf', 'format=fmt=yuv420p');
  } catch (e, st) {
    debugPrint('configurePreview failed: $e\n$st');
  }
}

/// 起播成功后 dump mpv 实际渲染参数, 便于真机排查花屏/灰屏。
///
/// Android 16 上 vo=gpu 管线花屏的修复方向: gpu-api / target-colorspace-hint /
/// vo / hwdec-current / imgfmt。这些属性能直接看出实际渲染路径是否正确。
///
/// [tag] 用于区分来源 (如 'hero-preview' / 全屏留空), 写入日志便于对照。
Future<void> dumpMpvRenderInfo(Player player, {String? tag}) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  final prefix = tag != null ? '[$tag] ' : '';
  const keys = <String>[
    'vo',
    'hwdec-current',
    'gpu-api',
    'target-colorspace-hint',
    'video-format',
    'video-params/imgfmt',
    'deinterlace-current',
    'width',
    'height',
    'current-vo',
  ];
  for (final k in keys) {
    try {
      final v = await platform.getProperty(k);
      debugPrint('[mpv] $prefix$k = $v');
      await CrashLogger.log('[mpv] $prefix$k = $v');
    } catch (e) {
      debugPrint('[mpv] $prefix$k = <unavailable: $e>');
      await CrashLogger.log('[mpv] $prefix$k = <unavailable: $e>');
    }
  }
}

/// media_kit 实现的 [StreamOpener]: 把 URL 真正打开到 [Player]。
///
/// open 不阻塞等到首帧, 而是监听 [Player.stream.playing] 判断是否起播成功,
/// 超时未起播则返回 false, 由 [SourceFailover] 切下一个源。
///
/// 单 Player 切换安全: 同一时刻只有一个 open 应视作"有效"。用 [_generation]
/// 标记每次 open, 已被更新 open 取代的旧调用在结果返回时直接作废 (返回 false),
/// 避免旧切换的成功事件污染新切换。cancel 改为 no-op —— 新 open 会自动
/// 替换当前流, 显式 stop 反而可能误杀正在起播的新流。
class MediaKitStreamOpener implements StreamOpener {
  MediaKitStreamOpener(this._player);

  final Player _player;

  /// 每次 [open] 自增, 用于识别"当前有效"的那次 open。
  int _generation = 0;

  @override
  Future<void> cancel(String url) async {
    // 不再 stop: 新 open 会替换当前流; 旧切换的 cancel 若 stop 会误杀新流.
  }

  /// 每次 [open] 前确保全屏去隔行配置生效。
  ///
  /// 不能用一次性守卫: 首页 Hero 预览会经 [configurePreview] 把共享 Player 的
  /// deinterlace 改回 no, 若此处只在首次 open 设置, 后续全屏 open 会沿用预览
  /// 留下的 no → 央视/卫视 1080i 隔行梳状花屏。故每次 open 都重新置 yes。
  ///
  /// [softwareDecode] 来自上层 (央视频道 → true): 央视走软件解码, 规避
  /// `vo=gpu` + mediacodec-copy 回拷内存的颜色错乱(绿紫花屏)。
  Future<void> _configurePlayer(bool softwareDecode) async {
    await configureDeinterlace(_player, softwareDecode: softwareDecode);
    if (softwareDecode) {
      // 央视/疑似源 → 软件解码兜花色错乱; 该次 open 的 [mpv] hwdec-current 应=no
      unawaited(CrashLogger.log(
          'decode: software(hwdec=no) for CCTV/likely-cctv source'));
    }
  }

  @override
  Future<bool> open(
    String url, {
    required Duration timeout,
    bool preferSoftwareDecode = false,
  }) async {
    final myGen = ++_generation;
    try {
      final software = preferSoftwareDecode || _isLikelyCctv(url);
      await _configurePlayer(software);
      final completer = Completer<bool>();
      late final StreamSubscription<dynamic> subPlaying;
      late final StreamSubscription<dynamic> subWidth;
      late final Timer timer;
      var gotPlaying = false;
      var gotVideo = false;
      void maybeComplete() {
        if (!completer.isCompleted && gotPlaying && gotVideo) {
          subPlaying.cancel();
          subWidth.cancel();
          timer.cancel();
          completer.complete(true);
        }
      }

      // 成功条件: 起播(有声音) **且** 视频宽度 > 0(视频帧真正解出来).
      // 背景: 央视 MPEG-2 源在 MediaCodec 硬解下音频能出、但视频帧解不出来 →
      // 仅看 `playing` 会被误判成功并卡在灰屏("有声音没画面"), 后续 H.264 源
      // 永无机会. 加 width 双保险: 不出帧的源会被判失败并自动切下一源.
      // 宽度归零时复位 gotVideo, 避免旧源残留宽度(切换瞬间)导致误判成功.
      subPlaying = _player.stream.playing.listen((playing) {
        if (playing) {
          gotPlaying = true;
          maybeComplete();
        }
      });
      subWidth = _player.stream.width.listen((w) {
        if (w != null && w > 0) {
          gotVideo = true;
          maybeComplete();
        } else {
          gotVideo = false;
        }
      });
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          subPlaying.cancel();
          subWidth.cancel();
          completer.complete(false);
        }
      });

      await _player.open(Media(url));
      final ok = await completer.future;
      // 等待期间已发生更新的切换 -> 本次结果作废.
      if (myGen != _generation) return false;
      if (ok) await dumpMpvRenderInfo(_player);
      return ok;
    } catch (e) {
      debugPrint('MediaKitStreamOpener.open failed: $e');
      return false;
    }
  }
}
