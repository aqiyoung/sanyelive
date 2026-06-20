#!/usr/bin/env python3
"""把 known_sources.json 里的 URL 合并到 channels_cn.json 对应 channel 的 sources 字段.

背景 (6/18 老板拍):
- assets/data/channels_cn.json: 484 个 channel, **所有 sources: [] 空的**
- assets/data/known_sources.json: 134 个 key, **真实 source URL 在这里** (21 CCTV + 14 卫视 + 99 其他)
- 没人把 known_sources 合并进 channels_cn.json, 导致 CCTV5 + 卫视在 APP 里没源

逻辑 (按 known_sources 走):
1. 已有 channel (id 匹配): 填充 sources 字段
2. 已有 channel 且 sources 非空: 跳过 (幂等)
3. **没有 channel (id 不在 channels_cn.json)**: 创建一个新 entry (id/name/alt_names/country='CN'/sources)

用法:
    python3 scripts/merge_known_sources.py

输出:
    - 原地改写 assets/data/channels_cn.json
    - 打印合并数 + CCTV5 / 卫视 验证
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANNELS_PATH = os.path.join(ROOT, 'assets', 'data', 'channels_cn.json')
KNOWN_PATH = os.path.join(ROOT, 'assets', 'data', 'known_sources.json')


def _source_priority(s):
    """Source URL 优先级评分 — 越高越优先保留 (v0.3.8+125 限制 top-5 用)."""
    url = s if isinstance(s, str) else (s.get('url') if isinstance(s, dict) else '')
    if not url:
        return -1000
    score = 0
    # 已知好 CDN 加分
    good_domains = (
        'live.fanmingming.com',
        'ottrrs.hl.chinamobile.com',
        'ott.mobaibox.com',
        'cdnlive.',
        'newlive.',
    )
    for d in good_domains:
        if d in url:
            score += 10
            break
    # https 略优先
    if url.startswith('https://'):
        score += 2
    # localhost / 127.0.0.1 最低
    if '127.0.0.1' in url or 'localhost' in url:
        score -= 100
    # 短域名略优先
    score += max(0, 80 - len(url))
    return score


# 已知 ID 别名: 频道 name → known_sources key (无 .cn)
NAME_TO_KNOWN_KEY = {
    'CCTV-5': 'CCTV5',
    'CCTV-5+': 'CCTV5Plus',
    'CCTV-1': 'CCTV1',
    'CCTV-2': 'CCTV2',
    'CCTV-3': 'CCTV3',
    'CCTV-4': 'CCTV4',
    'CCTV-6': 'CCTV6',
    'CCTV-7': 'CCTV7',
    'CCTV-8': 'CCTV8',
    'CCTV-9': 'CCTV9',
    'CCTV-10': 'CCTV10',
    'CCTV-11': 'CCTV11',
    'CCTV-12': 'CCTV12',
    'CCTV-13': 'CCTV13',
    'CCTV-14': 'CCTV14',
    'CCTV-15': 'CCTV15',
    'CCTV-16': 'CCTV16',
    'CCTV-17': 'CCTV17',
    'CCTV-4 Europe': 'CCTV4Europe',
    'CCTV-4 America': 'CCTV4America',
    'CCTV-News': 'CCTVNEWS',
}

# 已知 alt_names (中文名) → 频道主名 (English), 用于新建 channel 时的 name 字段
ALT_TO_NAME = {
    '北京卫视': 'Beijing Satellite TV',
    '安徽卫视': 'Anhui Satellite TV',
    '广东卫视': 'Guangdong Satellite TV',
    '海南卫视': 'Hainan Satellite TV',
    '湖北卫视': 'Hubei Satellite TV',
    '江苏卫视': 'Jiangsu Satellite TV',
    '山东卫视': 'Shandong Satellite TV',
    '深圳卫视': 'Shenzhen Satellite TV',
    '四川卫视': 'Sichuan Satellite TV',
    '延边卫视': 'Yanbian Satellite TV',
    '浙江卫视': 'Zhejiang Satellite TV',
    '兵团卫视': 'Bingtuan Satellite TV',
    '吉林卫视': 'Jilin Satellite TV',
    '云南卫视': 'Yunnan Satellite TV',
}


def channel_possible_ids(ch):
    """根据 channel 推可能的 known_sources key (无 .cn 后缀)."""
    cid = ch.get('id', '')
    name = ch.get('name', '')
    candidates = [
        cid,
        cid.replace('.cn', ''),
    ]
    # 已知 ID 别名 (CCTV-5 特殊情况: 频道 id 是 CCTV5, name 是 CCTV-5)
    alias = NAME_TO_KNOWN_KEY.get(name)
    if alias:
        candidates.append(alias)
    return [c for c in candidates if c]


def key_to_name(known_key):
    """known_sources key (无 .cn) → 推测的 channel name."""
    # CCTV1, CCTV2 ... CCTV17
    m = re.match(r'^CCTV(\d+)$', known_key)
    if m:
        return f'CCTV-{m.group(1)}'
    if known_key == 'CCTVNEWS':
        return 'CCTV-News'
    if known_key == 'CCTV4Europe':
        return 'CCTV-4 Europe'
    if known_key == 'CCTV4America':
        return 'CCTV-4 America'
    if known_key == 'CCTV5Plus':
        return 'CCTV-5+'
    if known_key == 'CCTV5':
        return 'CCTV-5'
    # SatelliteTV: BeijingSatelliteTV → Beijing Satellite TV
    name = known_key.replace('SatelliteTV', ' Satellite TV')
    return name


def key_to_alt(known_key):
    """known_sources key → 中文 alt_names (用于新建 channel)."""
    # CCTV1..CCTV17
    m = re.match(r'^CCTV(\d+)$', known_key)
    if m:
        return [f'CCTV-{m.group(1)}']
    if known_key == 'CCTVNEWS':
        return ['CCTV-新闻', 'CCTV-13']
    if known_key == 'CCTV4Europe':
        return ['CCTV-4 欧洲', 'CCTV-4E']
    if known_key == 'CCTV4America':
        return ['CCTV-4 美洲', 'CCTV-4A']
    if known_key == 'CCTV5Plus':
        return ['CCTV-5+', 'CCTV-5 体育赛事']
    if known_key == 'CCTV5':
        return ['CCTV-5', 'CCTV-5 体育']
    if known_key == 'CCTV1':
        return ['CCTV-1', 'CCTV-1 综合']
    if known_key == 'CCTV2':
        return ['CCTV-2', 'CCTV-2 财经']
    if known_key == 'CCTV3':
        return ['CCTV-3', 'CCTV-3 综艺']
    if known_key == 'CCTV6':
        return ['CCTV-6', 'CCTV-6 电影']
    if known_key == 'CCTV7':
        return ['CCTV-7', 'CCTV-7 军事农业']
    if known_key == 'CCTV8':
        return ['CCTV-8', 'CCTV-8 电视剧']
    if known_key == 'CCTV9':
        return ['CCTV-9', 'CCTV-9 纪录']
    if known_key == 'CCTV10':
        return ['CCTV-10', 'CCTV-10 科教']
    if known_key == 'CCTV11':
        return ['CCTV-11', 'CCTV-11 戏曲']
    if known_key == 'CCTV12':
        return ['CCTV-12', 'CCTV-12 社会与法']
    if known_key == 'CCTV14':
        return ['CCTV-14', 'CCTV-14 少儿']
    if known_key == 'CCTV15':
        return ['CCTV-15', 'CCTV-15 音乐']
    if known_key == 'CCTV16':
        return ['CCTV-16', 'CCTV-16 奥运']
    if known_key == 'CCTV17':
        return ['CCTV-17', 'CCTV-17 农业农村']
    if known_key == 'CCTV13':
        return ['CCTV-13', 'CCTV-13 新闻']
    if known_key == 'CCTV4':
        return ['CCTV-4', 'CCTV-4 中文国际']
    # SatelliteTV: 中文卫视名
    sat_to_zh = {
        'BeijingSatelliteTV': '北京卫视',
        'AnhuiSatelliteTV': '安徽卫视',
        'GuangdongSatelliteTV': '广东卫视',
        'HainanSatelliteTV': '海南卫视',
        'HubeiSatelliteTV': '湖北卫视',
        'JiangsuSatelliteTV': '江苏卫视',
        'ShandongSatelliteTV': '山东卫视',
        'ShenzhenSatelliteTV': '深圳卫视',
        'SichuanSatelliteTV': '四川卫视',
        'YanbianSatelliteTV': '延边卫视',
        'ZhejiangSatelliteTV': '浙江卫视',
        'BingtuanSatelliteTV': '兵团卫视',
        'JilinSatelliteTV': '吉林卫视',
        'YunnanSatelliteTV': '云南卫视',
    }
    if known_key in sat_to_zh:
        return [sat_to_zh[known_key]]
    return []


def merge():
    with open(CHANNELS_PATH, encoding='utf-8') as f:
        channels = json.load(f)
    with open(KNOWN_PATH, encoding='utf-8') as f:
        known = json.load(f)

    by_id = {c['id']: c for c in channels}
    merged = 0
    created = 0
    skipped = 0
    no_match = []

    # Step 1: 对每个已知 source key, 看 channels_cn.json 有没有匹配的 channel
    for k, urls in known.items():
        # 跳过注释键 (以 // 开头) 和非 list 值
        if k.startswith('//') or not isinstance(urls, list):
            continue
        # 尝试多种 ID 形式
        possible_channel_ids = [k, k.replace('.cn', '')]
        # 频道 id 通常是 .cn 后缀
        channel_id = k if k.endswith('.cn') else f'{k}.cn'

        if channel_id in by_id:
            ch = by_id[channel_id]
            existing = ch.get('sources') or []
            if existing:
                skipped += 1
                continue
            ch['sources'] = [{'url': u, 'type': 'hls'} for u in urls]
            merged += 1
        else:
            # 创建新 channel
            base = k.replace('.cn', '')
            new_ch = {
                'id': channel_id,
                'name': key_to_name(base),
                'country': 'CN',
                'categories': [],
                'alt_names': key_to_alt(base),
                'website': None,
                'logo': None,
                'is_nsfw': False,
                'sources': [{'url': u, 'type': 'hls'} for u in urls],
            }
            channels.append(new_ch)
            by_id[channel_id] = new_ch
            created += 1

    # Step 2: 对 channels_cn.json 里仍没 sources 的频道, 报告
    for c in channels:
        if not c.get('sources'):
            no_match.append(c.get('id', '?'))

    # Step 3 (v0.3.8+125): 限制每个 channel 的 sources 数量 ≤ 5
    # (SourceFailover 不会跳 5 个源,  CI channels_cn_asset_test 验证).  按
    # known 优先 + 不同域名优先 选 top-5.
    truncated = 0
    for c in channels:
        sources = c.get('sources') or []
        if not sources:
            continue
        # Dedup URLs first
        seen_urls = set()
        deduped = []
        for s in sources:
            url = s if isinstance(s, str) else (s.get('url') if isinstance(s, dict) else None)
            if not url or url in seen_urls:
                continue
            seen_urls.add(url)
            deduped.append(s)
        # Sort by priority (known-good CDN first)
        sorted_sources = sorted(deduped, key=_source_priority, reverse=True)
        # Truncate to top-5
        if len(sorted_sources) > 5:
            truncated += 1
            c['sources'] = sorted_sources[:5]
        else:
            c['sources'] = sorted_sources

    with open(CHANNELS_PATH, 'w', encoding='utf-8') as f:
        json.dump(channels, f, ensure_ascii=False, indent=2)

    print(f'=== merge_known_sources.py ===')
    print(f'Total channels: {len(channels)}')
    print(f'Merged (existing): {merged}')
    print(f'Created (new):     {created}')
    print(f'Skipped (has src): {skipped}')
    print(f'Still empty:       {len(no_match)}')
    print(f'Truncated (src>5): {truncated}')

    # 验证 CCTV5 + 卫视
    print('\n=== CCTV5 + 卫视 验证 ===')
    cctv5_total = 0
    weishi_total = 0
    for ch in channels:
        name = ch.get('name', '')
        alt = ch.get('alt_names', [])
        src_n = len(ch.get('sources', []))
        if name in ('CCTV-5', 'CCTV-5+'):
            cctv5_total += src_n
            print(f'  {name} (id={ch.get("id")}): {src_n} sources')
        elif '卫视' in name or any('卫视' in a for a in alt):
            weishi_total += src_n
            print(f'  {name} (id={ch.get("id")}): {src_n} sources')
    print(f'\nCCTV5 合计: {cctv5_total} sources (期望 ≥ 2)')
    print(f'卫视 合计: {weishi_total} sources (期望 ≥ 14)')

    if cctv5_total < 2:
        print('⚠️  CCTV5 合并失败, 检查 known_sources.json 的 key')
        sys.exit(1)
    if weishi_total < 14:
        print('⚠️  卫视合并数不足 14, 检查 ID 匹配')
        sys.exit(1)
    print('\n✅ 全部 OK')


if __name__ == '__main__':
    merge()
