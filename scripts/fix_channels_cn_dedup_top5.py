#!/usr/bin/env python3
"""一次性修复 assets/data/channels_cn.json:
1. 去除重复 id (合并 sources + 保留最完整字段).
2. sources 数量限制 top-5 (SourceFailover 不会跳 5 个源).

用法:
    python3 scripts/fix_channels_cn_dedup_top5.py

输出:
    - 原地改写 assets/data/channels_cn.json
    - 打印去重数 + 截断数
"""
import json
import os
import re
from collections import Counter
from urllib.parse import urlparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANNELS_PATH = os.path.join(ROOT, 'assets', 'data', 'channels_cn.json')

# Source 优先级评分 (SourceFailover 实际尝试顺序):
# - localhost / 127.0.0.1 → 最低 (本地无效)
# - http:// → 比 https:// 略低 (后者优先)
# - 域名短 (CDN) → 优先 (快)
# - 已知好源 (bkpcp, mobaibox, chinanetcenter, fanmingming) → 加分
KNOWN_GOOD_DOMAINS = (
    'ottrrs.hl.chinamobile.com',
    'ott.mobaibox.com',
    'live.fanmingming.com',
    'gslb.',
    'cdnlive.',
    'newlive.',
    'tsfile.',
    'hls.',
)


def source_score(s):
    """Source URL 评分 — 越高越优先."""
    if isinstance(s, dict):
        url = s.get('url', '')
    else:
        url = s if isinstance(s, str) else ''
    if not url:
        return -1000
    parsed = urlparse(url)
    score = 0
    # 已知好源加分
    for d in KNOWN_GOOD_DOMAINS:
        if d in url:
            score += 10
            break
    # https 比 http 略优先 (现代 CDN)
    if parsed.scheme == 'https':
        score += 2
    # localhost / 内网 IP 最低 (SourceFailover 跳内网不实际能访问)
    if parsed.hostname in ('127.0.0.1', 'localhost', '0.0.0.0'):
        score -= 100
    # IPv4 公网 (38.x, 74.x, 173.x 等) 跟 IPv4 国内 (112.x, 116.x, 120.x, 221.x, 222.x) 区分
    # 国内 ISP CDN 优先 (老板实际在国内看)
    hn = parsed.hostname or ''
    if re.match(r'^(1[0-9]{2}|2[0-3][0-9]|3[0-9]{2}|5[0-9]{2}|6[0-3][0-9]|11[0-9]|12[0-9]|22[0-9])\.', hn):
        score += 1
    # 短域名优先
    score += max(0, 50 - len(url))
    return score


def dedupe_channels(channels):
    """去重 id — 同 id 同 name 的合并 sources;  同 id 不同 name 的两条
    按 name 后缀重命名 (已知重复:  CGNT.cn@CNIPTV 新闻频道 + 记录频道, id 冲突)."""
    # 第一遍:  收集每个 id 下的所有 entries, 按 name 区分
    by_id = {}
    order = []
    for c in channels:
        cid = c.get('id')
        if cid not in by_id:
            by_id[cid] = []
            order.append(cid)
        by_id[cid].append(c)

    out = []
    renamed = []
    for cid in order:
        entries = by_id[cid]
        if len(entries) == 1:
            out.append(entries[0])
            continue
        # 多条同 id —  按 name 分组
        by_name = {}
        for c in entries:
            name = c.get('name', '')
            by_name.setdefault(name, []).append(c)
        if len(by_name) == 1:
            # 同 id 同 name — 真重复,  合并 sources
            base = entries[0]
            for other in entries[1:]:
                base = _merge_sources_into(base, other)
            out.append(base)
            merged_count = sum(len(c.get('sources', [])) for c in entries)
            renamed.append((cid, f'合并 sources (合计 {len(base.get("sources", []))} 个 URL)'))
            continue
        # 不同 name — 保留第一条原 id,  其余重命名
        first = entries[0]
        out.append(first)
        for other in entries[1:]:
            dist = _distinguish_suffix(other.get('name', ''))
            new_id = f'{cid}_{dist}' if dist else f'{cid}_dup'
            # 避免新 id 也撞
            suffix_n = 2
            base_new_id = new_id
            while any(o.get('id') == new_id for o in out):
                new_id = f'{base_new_id}{suffix_n}'
                suffix_n += 1
            other['id'] = new_id
            out.append(other)
            renamed.append((cid, f'重命名 "{other.get("name", "")}" → {new_id}'))
    return out, renamed


def _merge_sources_into(base, other):
    """把 [other].sources 合并进 [base].sources (URL 去重)."""
    base_sources = base.get('sources') or []
    other_sources = other.get('sources') or []
    seen_urls = set()
    merged = []
    for s in base_sources + other_sources:
        url = s if isinstance(s, str) else (s.get('url') if isinstance(s, dict) else None)
        if not url or url in seen_urls:
            continue
        seen_urls.add(url)
        merged.append(s)
    base['sources'] = merged
    return base


def _distinguish_suffix(name):
    """从 channel name 抽出区分后缀 (用于重命名)."""
    # 常见频道类型后缀
    suffixes = [
        ('新闻', 'news'),
        ('记录', 'doc'),
        ('纪录', 'doc'),
        ('科教', 'science'),
        ('文艺', 'art'),
        ('影视', 'movie'),
        ('电视剧', 'tv'),
        ('综艺', 'variety'),
        ('体育', 'sport'),
        ('财经', 'finance'),
        ('国际', 'intl'),
        ('少儿', 'kids'),
        ('音乐', 'music'),
        ('戏曲', 'opera'),
        ('高清', 'hd'),
    ]
    for zh, en in suffixes:
        if zh in name:
            return en
    return ''


def truncate_sources(channels, limit=5):
    """Sources 截断到 top-N 按 score 排序.  返回 (channel_id, old_count, new_count) 列表."""
    truncated = []
    for c in channels:
        sources = c.get('sources') or []
        if len(sources) <= limit:
            continue
        sorted_sources = sorted(sources, key=source_score, reverse=True)
        new_sources = sorted_sources[:limit]
        c['sources'] = new_sources
        truncated.append((c['id'], len(sources), limit))
    return truncated


def main():
    with open(CHANNELS_PATH, encoding='utf-8') as f:
        channels = json.load(f)

    print(f'加载 {len(channels)} channels')

    # Step 1: 去重 id
    deduped, renamed = dedupe_channels(channels)
    print(f'去重后 {len(deduped)} channels')
    if renamed:
        print(f'id 处理 ({len(renamed)}):')
        for cid, action in renamed:
            print(f'  {cid} → {action}')

    # Step 2: 截断 sources 到 top-5
    truncated = truncate_sources(deduped, limit=5)
    print(f'sources > 5 截断 ({len(truncated)}):')
    for cid, old, new in truncated:
        print(f'  {cid}: {old} → {new}')

    # 写回
    with open(CHANNELS_PATH, 'w', encoding='utf-8') as f:
        json.dump(deduped, f, ensure_ascii=False, indent=2)

    # 验证
    with open(CHANNELS_PATH, encoding='utf-8') as f:
        final = json.load(f)
    ids = [c['id'] for c in final]
    dup = [k for k, v in Counter(ids).items() if v > 1]
    over = [(c['id'], len(c.get('sources', []))) for c in final if len(c.get('sources', [])) > 5]
    print(f'\n=== 验证 ===')
    print(f'channels: {len(final)}')
    print(f'重复 id: {len(dup)} ({dup})')
    print(f'sources > 5: {len(over)} ({over})')
    if dup or over:
        print('⚠️  仍有残留问题')
        return 1
    print('✅ 全部 OK')


if __name__ == '__main__':
    import sys
    sys.exit(main())
