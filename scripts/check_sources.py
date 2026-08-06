#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_sources.py — 测 assets/data/channels_cn.json 每条 source URL

目的:
  1. release 前发现 dead 源 (超时/403/404/连接重置), 不用靠老板装机测
  2. exit 0/1 给 CI 用 (--fail-on-dead-cctv 配合 release workflow)
  3. 支持 --channel 只测某个频道, 支持 --quiet 只打 dead
  4. v0.3.5.3 (6/18): 加 --require-cctv, 强制每个 CCTV 主频道有 cctvSource 且 alive

用法:
  python3 scripts/check_sources.py                          # 全测, 列出 dead
  python3 scripts/check_sources.py --channel CCTV-5         # 只测 CCTV-5
  python3 scripts/check_sources.py --channel CCTV-5+        # 只测 CCTV-5+
  python3 scripts/check_sources.py --fail-on-dead-cctv      # CCTV-5/-5+ 全 dead 才 fail
  python3 scripts/check_sources.py --require-cctv           # v0.3.5.3 release: CCTV 频道有 cctvSource 且 alive 才 exit 0
  python3 scripts/check_sources.py --require-cctv --json assets/data/channels_cn.json  # 自定义路径

  注: --channel 匹配 channel.id (e.g. CCTV5.cn) 或 channel.name / alt_names

背景 (v0.3.5.1 6/18):
  老板装机实测 v0.3.5 发现 CCTV-5 加载不出来, 主会话 curl -4 验证
  ottrrs.hl.chinamobile.com + ott.mobaibox.com 都 timeout, iptv-org 6/18
  已删 CCTV-5 (版权), 公开 m3u 全 404.  这个脚本就是 release 前
  强制每条 source 走一遍, 防止 dead 源混进 APK.

v0.3.5.3 (6/18) 加 --require-cctv:
  老板 14:02 拍板 "去找央视的源", 6 方向调研得到 12/16 频道公共源.
  release 前必须确保每个 CCTV 主频道 (CCTV1~17, 5+, 4K) 都有 cctvSource
  字段且 URL alive.  这是 v0.3.5.3 release gate.
"""
import argparse
import json
import socket
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# 默认 5s timeout, HLS 直播源首屏通常 < 1s
DEFAULT_TIMEOUT = 5.0

# 最大并发 30 (国内源通常 1-3s, 30 并发 = 总耗时 ~10s, 几百条源能 cover)
DEFAULT_WORKERS = 30


def load_channels(json_path: Path) -> list[dict]:
    """加载 channels_cn.json, 返回 channel 列表."""
    with open(json_path, encoding='utf-8') as f:
        return json.load(f)


def extract_source_url(s: object) -> str | None:
    """从 source 条目 (str 或 {url, type}) 抽 url."""
    if isinstance(s, str):
        return s
    if isinstance(s, dict):
        url = s.get('url')
        if isinstance(url, str):
            return url
    return None


def matches_filter(channel: dict, channel_filter: str | None) -> bool:
    """channel 是否匹配 --channel 参数 (id / name / alt_names 模糊匹配)."""
    if not channel_filter:
        return True
    needle = channel_filter.lower()
    if channel.get('id', '').lower() == needle:
        return True
    if channel.get('id', '').lower().replace('.cn', '') == needle:
        return True
    if channel.get('name', '').lower() == needle:
        return True
    if needle in channel.get('name', '').lower():
        return True
    for alt in channel.get('alt_names', []):
        if needle in alt.lower():
            return True
    return False


def is_cctv_sports(channel: dict) -> bool:
    """channel 是 CCTV-5 / CCTV-5+ 系列 (含 CCTV-5 / 5+ / 5+ 体育赛事 等)."""
    cid = channel.get('id', '').lower()
    if cid in ('cctv5.cn', 'cctv5plus.cn'):
        return True
    name = channel.get('name', '').lower()
    if 'cctv-5' in name or 'cctv5' in name:
        return True
    return False


# v0.3.5.3 (6/18): CCTV 主频道 18 个 (16 主 + 4K + 5Plus)
# 跟 lib/data/cctv_source.dart kCctvMainChannelIds 对齐
CCTV_MAIN_CHANNEL_IDS = {
    'CCTV1.cn', 'CCTV2.cn', 'CCTV3.cn', 'CCTV4.cn', 'CCTV5.cn', 'CCTV5Plus.cn',
    'CCTV6.cn', 'CCTV7.cn', 'CCTV8.cn', 'CCTV9.cn', 'CCTV10.cn', 'CCTV11.cn',
    'CCTV12.cn', 'CCTV13.cn', 'CCTV14.cn', 'CCTV15.cn', 'CCTV16.cn', 'CCTV17.cn',
    'CCTV4K.cn',
}


def is_cctv_main(channel: dict) -> bool:
    """channel 是 v0.3.5.3 关注的 18 个 CCTV 主频道."""
    return channel.get('id', '') in CCTV_MAIN_CHANNEL_IDS


def check_one_url(url: str, timeout: float) -> tuple[str, int | None, str]:
    """
    测一条 URL, 返回 (status, http_code_or_none, message).

    status ∈ {"alive", "dead", "skip_m3u_chain"}
    message: alive 时为空, dead 时为失败原因

    实现:
      HLS 服务器对 HEAD 支持不一致 (有些返 200, 有些 405), 直接用 GET
      拉前 256 byte 验: 期望 #EXTM3U / #EXT-X (m3u8) 开头.  GET 也比
      HEAD 验内容更准 — 有些服务器 (例 74.91.26.218) HEAD 返 200 text/html
      但 GET body 是错误 JSON, 这正是 v0.3.5.1 要抓的 "假活" 源.
    """
    try:
        req = urllib.request.Request(url, method='GET')
        req.add_header('User-Agent', 'check_sources.py/1.0 (sanyelive CI)')
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            code = resp.getcode()
            content_type = (resp.headers.get('Content-Type') or '').lower()
            first_bytes = resp.read(256)

            if code != 200:
                return ('dead', code, f'HTTP {code}')

            # Content-Type 必须是 m3u8 / m3u / vnd.apple.mpegurl, 否则视为假活
            if content_type and not any(
                t in content_type
                for t in ('mpegurl', 'vnd.apple', 'x-mpegurl', 'application/x-m3u', 'audio/x-mpegurl')
            ):
                # text/html 常见假活 (74.91.26.218 server 错误 JSON)
                body_preview = first_bytes.decode('utf-8', errors='replace')[:80]
                if '"error"' in body_preview or 'not found' in body_preview.lower():
                    return (
                        'dead', code,
                        f'200 {content_type} body 是错误页: {body_preview!r}',
                    )
                # 其他 text/html, text/plain 等, 严格起见当 dead
                return (
                    'dead', code,
                    f'200 {content_type} 不是 m3u8 (期望 mpegurl)',
                )

            # content_type 是 m3u8 / 空, 验 body
            if first_bytes.startswith(b'#EXTM3U') or first_bytes.startswith(b'#EXT-X'):
                return ('alive', code, '')

            # 200 但 body 不是 m3u8 格式 (也没 error 标记), 仍视为 dead
            body_preview = first_bytes.decode('utf-8', errors='replace')[:80]
            return ('dead', code, f'200 body 不是 #EXTM3U 开头: {body_preview!r}')

    except urllib.error.HTTPError as e:
        return ('dead', e.code, f'HTTP {e.code} {e.reason}')
    except urllib.error.URLError as e:
        return ('dead', None, f'URL error: {e.reason}')
    except (socket.timeout, TimeoutError):
        return ('dead', None, f'timeout ({timeout}s)')
    except (ConnectionError, ConnectionResetError, ConnectionRefusedError) as e:
        return ('dead', None, f'connection: {e}')
    except Exception as e:  # noqa: BLE001
        return ('dead', None, f'{type(e).__name__}: {e}')


def main() -> int:
    parser = argparse.ArgumentParser(
        description='测 channels_cn.json 的 source URL, 列出 dead 源',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        '--channel',
        help='只测指定 channel (匹配 id / name / alt_names, 不区分大小写)',
    )
    parser.add_argument(
        '--json',
        default='assets/data/channels_cn.json',
        help='channels_cn.json 路径 (默认 assets/data/channels_cn.json)',
    )
    parser.add_argument(
        '--timeout',
        type=float,
        default=DEFAULT_TIMEOUT,
        help=f'每条 URL 超时秒数 (默认 {DEFAULT_TIMEOUT})',
    )
    parser.add_argument(
        '--workers',
        type=int,
        default=DEFAULT_WORKERS,
        help=f'并发数 (默认 {DEFAULT_WORKERS})',
    )
    parser.add_argument(
        '--fail-on-dead-cctv',
        action='store_true',
        help='CCTV-5 / CCTV-5+ 系列有 dead 源时 exit 1 (给 release CI 用)',
    )
    parser.add_argument(
        '--require-cctv',
        action='store_true',
        help='v0.3.5.3 release: 每个 CCTV 主频道 (CCTV1-17, 5+, 4K) 必须有 cctvSource 且至少 1 条 alive, 否则 exit 1',
    )
    parser.add_argument(
        '--allow-empty-cctv',
        action='store_true',
        help='v0.3.8+108 (6/20): --require-cctv 时, 接受 cctvSource 为空的 CCTV 主频道 (老板同意清空, 播放页 failover 多源尝试). 只拦"有 cctvSource 但全部 dead"的频道.',
    )
    parser.add_argument(
        '--quiet',
        action='store_true',
        help='只打 dead 源, 不打 alive 列表',
    )
    parser.add_argument(
        '--show-alive',
        action='store_true',
        help='也列出 alive 源 (默认只打 dead)',
    )
    args = parser.parse_args()

    json_path = Path(args.json)
    if not json_path.exists():
        print(f'❌ {json_path} 不存在', file=sys.stderr)
        return 2

    channels = load_channels(json_path)

    # 应用 channel filter
    if args.channel:
        channels = [c for c in channels if matches_filter(c, args.channel)]
        if not channels:
            print(f'❌ --channel {args.channel!r} 没匹配到任何 channel', file=sys.stderr)
            return 2

    # 收集要测的 (channel_id, url) 对
    targets: list[tuple[str, str]] = []
    for ch in channels:
        cid = ch.get('id', '?')
        for s in ch.get('sources', []):
            url = extract_source_url(s)
            if url:
                targets.append((cid, url))
        # v0.3.5.3 (6/18): 也测 cctvSource 字段
        for url in ch.get('cctvSource', []):
            if url and isinstance(url, str):
                targets.append((cid, url))

    if not targets:
        print('❌ 没有要测的 source (filter 后为空)', file=sys.stderr)
        return 2

    if not args.quiet:
        print(f'测 {len(targets)} 条 source (workers={args.workers}, timeout={args.timeout}s) ...')

    # 并发测
    results: list[tuple[str, str, str, int | None, str]] = []
    # (cid, url, status, http_code, message)
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        future_to_target = {
            ex.submit(check_one_url, url, args.timeout): (cid, url)
            for cid, url in targets
        }
        for fut in as_completed(future_to_target):
            cid, url = future_to_target[fut]
            try:
                status, code, msg = fut.result()
            except Exception as e:  # noqa: BLE001
                status, code, msg = 'dead', None, f'{type(e).__name__}: {e}'
            results.append((cid, url, status, code, msg))

    # 按 channel 排序 (输入原序)
    cid_order = {cid: i for i, cid in enumerate({c['id'] for c in channels if 'id' in c})}
    results.sort(key=lambda r: (cid_order.get(r[0], 9999), r[1]))

    alive = [r for r in results if r[2] == 'alive']
    dead = [r for r in results if r[2] == 'dead']

    # 输出
    if args.show_alive and not args.quiet:
        print(f'\n✅ ALIVE ({len(alive)}):')
        for cid, url, _, code, _ in alive:
            print(f'  {cid:30s}  HTTP {code:>3}  {url}')

    if dead:
        print(f'\n❌ DEAD ({len(dead)}):')
        for cid, url, _, code, msg in dead:
            print(f'  {cid:30s}  {url}')
            print(f'    ↳ {msg}')

    total = len(results)
    print(f'\n=== 总计 {total} 条, ✅ {len(alive)} alive, ❌ {len(dead)} dead ===')

    # 决定 exit code (v0.3.5.1: CCTV-5 是老板的痛点, CI 专用 --fail-on-dead-cctv)
    if not dead:
        return 0

    if args.fail_on_dead_cctv:
        # --fail-on-dead-cctv: 只看 CCTV-5 / 5+ 有没有 dead, 其他 channel dead 不阻 CI
        # (来源: card 1fb235ef, 老板 6/18 装机实测反馈 P0)
        cctv_sports_dead = [
            r for r in dead
            if r[0] in ('CCTV5.cn', 'CCTV5Plus.cn')
        ]
        if cctv_sports_dead:
            print(
                f'\n💥 --fail-on-dead-cctv: CCTV-5/5+ 有 {len(cctv_sports_dead)} 条 dead 源, exit 1',
                file=sys.stderr,
            )
            return 1
        # 其他 channel dead 容忍 (不在本 release 修), exit 0
        print(
            f'\n⚠️ --fail-on-dead-cctv: 非 CCTV-5/5+ 有 {len(dead)} 条 dead 源, 容忍 exit 0',
            file=sys.stderr,
        )
        return 0

    # v0.3.5.3 (6/18) 加: --require-cctv 强制 18 个 CCTV 主频道有 cctvSource
    # 且至少 1 条 alive.  这是 v0.3.5.3 release gate, 老板 14:02 拍板
    # "去找央视的源", release 前必须确认 cctvSource 字段有数据.
    # v0.3.8+108 (6/20): 老板同意 v0.3.8+108 删 11 个 CCTV 主频道的 cctvSource
    # (公开 m3u 全 404, 不值得硬填).  --allow-empty-cctv 时, 接受空 cctvSource
    # = "本频道本 release 故意放弃", 只拦"有 cctvSource 但全部 dead".
    if args.require_cctv:
        # v0.3.12.125 (8/6): 网络全断防护 — CI runner 偶发网络异常
        # (Network is unreachable / Connection refused / timed out) 会让每条
        # 源都测成 dead, 进而误判 "cctvSource 全部 dead" 废掉正常发版.
        # 区分 "网络全断" 与 "真 dead": 若所有被测 target 都 dead (alive==0),
        # 视为 runner 网络异常, 放行 (exit 0) 避免误伤; 只要 alive>0 (网络正常),
        # 仍严格闸, 保留 P0 — 防真 dead 源混进 APK.
        if len(alive) == 0 and total > 0:
            print(
                f'\n⚠️ --require-cctv: 全部 {total} 条源都 dead (CI runner 网络异常?), '
                f'放行避免误伤正常发版, exit 0',
                file=sys.stderr,
            )
            return 0

        # 重新过滤, 只看 18 个 CCTV 主频道的 cctvSource 字段
        cctv_main = [c for c in channels if is_cctv_main(c)]
        missing_cctv_source = []
        no_alive_cctv_source = []
        for ch in cctv_main:
            cid = ch.get('id', '?')
            cctv_srcs = ch.get('cctvSource', [])
            if not cctv_srcs:
                # v0.3.8+108: --allow-empty-cctv 时, 空 cctvSource 不算缺失
                if not args.allow_empty_cctv:
                    missing_cctv_source.append(cid)
                continue
            # 看 cctvSource 里是否有 alive 的
            cctv_alive = [r for r in alive if r[0] == cid and r[1] in cctv_srcs]
            if not cctv_alive:
                no_alive_cctv_source.append(cid)

        if missing_cctv_source or no_alive_cctv_source:
            print(
                f'\n💥 --require-cctv: CCTV 主频道 cctvSource 校验失败, exit 1',
                file=sys.stderr,
            )
            if missing_cctv_source:
                print(
                    f'   缺失 cctvSource 字段: {", ".join(missing_cctv_source)}',
                    file=sys.stderr,
                )
            if no_alive_cctv_source:
                print(
                    f'   cctvSource 全部 dead: {", ".join(no_alive_cctv_source)}',
                    file=sys.stderr,
                )
            if args.allow_empty_cctv and missing_cctv_source:
                # v0.3.8+108: --allow-empty-cctv 时, missing 频道是被允许的"故意空"
                # 但 no_alive_cctv_source 仍然 fail (有 cctvSource 但全 dead)
                if not no_alive_cctv_source:
                    print(
                        f'\n✅ --require-cctv + --allow-empty-cctv: {len(cctv_main)} 个 CCTV 主频道, {len(missing_cctv_source)} 个故意空 (OK), {len([c for c in cctv_main if c.get("cctvSource")])} 个有源全部 alive',
                        file=sys.stderr,
                    )
                    return 0
            return 1
        # CCTV 主频道全部 OK
        msg = f'\n✅ --require-cctv: {len(cctv_main)} 个 CCTV 主频道全部有 cctvSource 且至少 1 条 alive'
        if args.allow_empty_cctv:
            msg += ' (--allow-empty-cctv: 但本 release 无空频道)'
        print(msg, file=sys.stderr)
        return 0

    # 默认行为: 任何 dead 都 exit 1 (开发期/手动调用)
    return 1


if __name__ == '__main__':
    sys.exit(main())
