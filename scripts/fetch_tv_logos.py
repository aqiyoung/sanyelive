#!/usr/bin/env python3
"""打包中文频道台标到 assets/logos, 使 TV 模式离线显示台标.

数据源 (优先级):
  1. channels_cn.json 自带的 `logo` 字段 (Gitee 直链, 主要为 CCTV 等) -> 直接用 URL
  2. fanmingming/live/tv 扁平 PNG (GitHub, 全量含卫视/地方) -> 按归一化频道名匹配
  3. Gitee mytv-android/myTVlogo -> 按归一化频道名匹配 (补充)

下载动作在 CI 运行器 (GitHub Actions) 执行 —— 真实环境能直连 GitHub/Gitee.
本地 --dry 仅统计匹配率 (配合 --fm-list/--gitee-list 离线清单, 不联网下载大图).

输出:
  assets/logos/<channel_id>.png  台标图片 (id 含 .cn 等字符, 作为文件名)
  assets/logos/manifest.json     { "<channel_id>": "<filename>" } 命中清单
显示层据此用 AssetImage 优先离线渲染, 命中不到再回退运行时的 logoUrl / 文字台标.
"""
import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request

FM_RAW = "https://raw.githubusercontent.com/fanmingming/live/main/tv/"
GITEE_RAW = "https://gitee.com/mytv-android/myTVlogo/raw/main/img/"
DEFAULT_DATA = "assets/data/channels_cn.json"
DEFAULT_OUT = "assets/logos"
DEFAULT_MANIFEST = "assets/logos/manifest.json"


def norm(s: str) -> str:
    s = (s or "").lower()
    s = re.sub(r"[\s\-·\._（）()]", "", s)
    return s


def _make_opener():
    proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("HTTP_PROXY")
    handlers = []
    if proxy:
        handlers.append(urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
    return urllib.request.build_opener(*handlers)


_OPENER = _make_opener()


def _http_get(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    return _OPENER.open(req, timeout=timeout).read()


def load_name_list(path: str, strip_prefix: str = "", strip_suffix: str = "") -> dict:
    """读取本地清单, 返回 { 归一化名: 原始名 } 便于回查原始文件名构造 URL."""
    out: dict = {}
    if not path or not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as fp:
        for line in fp:
            line = line.strip()
            if not line:
                continue
            name = line
            if strip_prefix and name.startswith(strip_prefix):
                name = name[len(strip_prefix):]
            if strip_suffix and name.endswith(strip_suffix):
                name = name[: -len(strip_suffix)]
            out[norm(name)] = name
    return out


def load_gitee_online() -> dict:
    names: dict = {}
    for page in range(1, 12):
        try:
            data = json.loads(_http_get(
                f"https://gitee.com/api/v5/repos/mytv-android/myTVlogo/contents/img?per_page=100&page={page}"
            ))
            if not isinstance(data, list):
                break
            for x in data:
                names[norm(x["name"])] = x["name"]
        except Exception as e:  # noqa: BLE001
            print(f"  [warn] gitee list page {page}: {e}", file=sys.stderr)
            break
    return names


def main() -> int:
    ap = argparse.ArgumentParser(description="打包中文频道台标到 app 内")
    ap.add_argument("--data", default=DEFAULT_DATA)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--manifest", default=DEFAULT_MANIFEST)
    ap.add_argument("--fm-list", help="本地 fanmingming 名字清单 (每行 tv/xxx.png)")
    ap.add_argument("--gitee-list", help="本地 gitee 名字清单")
    ap.add_argument("--dry", action="store_true", help="只统计匹配率, 不下载")
    args = ap.parse_args()

    with open(args.data, encoding="utf-8") as fp:
        channels = json.load(fp)
    os.makedirs(args.out, exist_ok=True)

    fm = load_name_list(args.fm_list, strip_prefix="tv/", strip_suffix=".png") if args.fm_list else {}
    if args.fm_list:
        print(f"  fanmingming 清单: {len(fm)}")
    if args.gitee_list:
        gitee = load_name_list(args.gitee_list)
        print(f"  gitee 清单: {len(gitee)}")
    else:
        gitee = load_gitee_online()

    manifest: dict = {}
    matched = 0
    unmatched = []
    for ch in channels:
        cid = ch.get("id")
        name = ch.get("name") or ch.get("displayName") or ""
        cand = [name] + list(ch.get("alt_names") or []) + [str(cid).replace(".cn", "")]
        logo = ch.get("logo")
        url = None
        if logo:
            url = logo  # 自带 Gitee 直链优先
        else:
            for cn in cand:
                fmhit = fm.get(norm(cn))
                if fmhit:
                    url = FM_RAW + urllib.parse.quote(fmhit) + ".png"
                    break
            if not url:
                for cn in cand:
                    ghit = gitee.get(norm(cn))
                    if ghit:
                        url = GITEE_RAW + urllib.parse.quote(ghit)
                        break
        if not url:
            unmatched.append(name or cid)
            continue
        if args.dry:
            matched += 1
            manifest[cid] = None
            continue
        try:
            data = _http_get(url)
            if not data or len(data) < 100:
                print(f"  [skip] {cid}: 下载内容过小 ({len(data) if data else 0})", file=sys.stderr)
                continue
            fn = f"{cid}.png"
            with open(os.path.join(args.out, fn), "wb") as fp:
                fp.write(data)
            manifest[cid] = fn
            matched += 1
        except Exception as e:  # noqa: BLE001
            print(f"  [skip] {cid} {name}: {e}", file=sys.stderr)

    if not args.dry:
        with open(args.manifest, "w", encoding="utf-8") as fp:
            json.dump(manifest, fp, ensure_ascii=False, indent=2)
    print(f"匹配/下载台标: {matched}/{len(channels)}")
    if args.dry and unmatched:
        print(f"\n未匹配 ({len(unmatched)}):")
        print("  " + "、".join(unmatched[:60]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
