#!/usr/bin/env python3
"""打包中文频道台标到 assets/logos, 使 TV 模式离线显示台标.

数据源 (优先级):
  1. channels_cn.json 自带的 `logo` 字段 (Gitee 直链, 主要为 CCTV) -> 直接用 URL
  2. fanmingming/live/tv 扁平 PNG (GitHub) -> 按频道名匹配
       - 主下载通道: `gh api` (沙箱 / CI 均认证可用, 返回 base64 不踩 raw 重定向坑)
       - 兜底: raw.githubusercontent.com 直连 (带重定向编码修复)
  3. Gitee mytv-android/myTVlogo -> 按频道名匹配 (兜底, 带重定向编码修复)
       * 注意: 该源卫视命名不规整 (如 `BRTV北京卫视.png`), 仅作补充

输出:
  assets/logos/<channel_id>.png  台标图片
  assets/logos/manifest.json     { "<channel_id>": "<filename>" } 命中清单
显示层据此用 AssetImage 优先离线渲染, 命中不到再回退运行时的 logoUrl / 文字台标.

用法:
  python3 scripts/fetch_tv_logos.py                 # 真实下载 (gh api 优先)
  python3 scripts/fetch_tv_logos.py --dry           # 只统计匹配率, 不下载
  python3 scripts/fetch_tv_logos.py --force         # 忽略已存在的本地 png 重新下载
"""
import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

FM_API_REPO = "fanmingming/live"
FM_RAW = "https://raw.githubusercontent.com/fanmingming/live/main/tv/"
GITEE_RAW = "https://gitee.com/mytv-android/myTVlogo/raw/main/img/"
DEFAULT_DATA = "assets/data/channels_cn.json"
DEFAULT_OUT = "assets/logos"
DEFAULT_MANIFEST = "assets/logos/manifest.json"

# 英文/拼音省份 -> 中文省份. 用于把 LiaoningTV/HebeiTV 这类英文 id/name
# 翻成中文, 再去台标源 (按中文命名的 辽宁卫视.png 等) 里匹配.
# 注: 山西=shanxi / 陕西=shaanxi 拼音区分; 内蒙古=neimenggu; 西藏=xizang/tibet.
PINYIN_PROVINCE = {
    "beijing": "北京", "tianjin": "天津", "shanghai": "上海", "chongqing": "重庆",
    "hebei": "河北", "shanxi": "山西", "liaoning": "辽宁", "jilin": "吉林",
    "heilongjiang": "黑龙江", "jiangsu": "江苏", "zhejiang": "浙江", "anhui": "安徽",
    "fujian": "福建", "jiangxi": "江西", "shandong": "山东", "henan": "河南",
    "hubei": "湖北", "hunan": "湖南", "guangdong": "广东", "hainan": "海南",
    "sichuan": "四川", "guizhou": "贵州", "yunnan": "云南", "shaanxi": "陕西",
    "gansu": "甘肃", "qinghai": "青海", "taiwan": "台湾",
    "neimenggu": "内蒙古", "neimeng": "内蒙古",
    "guangxi": "广西",
    "xizang": "西藏", "tibet": "西藏",
    "ningxia": "宁夏",
    "xinjiang": "新疆",
    "xianggang": "香港", "hongkong": "香港",
    "aomen": "澳门", "macau": "澳门",
}


def pinyin_province_candidates(*raws) -> list:
    """从英文/拼音 id/name 推出中文省份候选 (卫视/电视台/纯省名).

    例如 "LiaoningTV.cn" / "Liaoning TV" -> ["辽宁卫视","辽宁电视台","辽宁"].
    中文名 (如 "湖南卫视") 经 [^a-z] 清洗后为空, 不产生候选 (本就按中文匹配).
    """
    out = []
    for raw in raws:
        if not raw:
            continue
        py = re.sub(r"[^a-z]", "", str(raw).lower())
        # 去掉可叠加后缀: henanTVSatellite -> henan
        py = re.sub(
            r"(tv|satellite|channel|radio|station|live|hd|sd|4k|8k|cn|com|net|org)+$",
            "",
            py,
        )
        cn = PINYIN_PROVINCE.get(py)
        if cn:
            out += [f"{cn}卫视", f"{cn}电视台", cn]
    return out



_IMG_EXT = re.compile(r"\.(png|jpe?g|svg|webp)$", re.I)


def norm(s: str) -> str:
    """归一化频道名: 小写, 去空格/连字符/间隔点/全角括号. 不删 '.', 避免破坏扩展名."""
    s = (s or "").lower()
    s = re.sub(r"[\s\-·（）()]", "", s)
    return s


def fname_key(fn: str) -> str:
    """文件名 -> 匹配键 (去掉图片扩展名后归一化)."""
    return norm(_IMG_EXT.sub("", fn))


# --------------------------------------------------------------------------- #
# 通用 HTTP: 修复 gitee raw 302 重定向到未编码中文 URL 触发的 ascii 编码错误
# --------------------------------------------------------------------------- #
class _RedirectFix(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # gitee raw 会把中文文件名原样放在 Location, 导致 http.client 编码失败.
        # 这里把 Location 里非 ASCII 的路径段重新 percent-encode.
        try:
            newurl.encode("ascii")
        except UnicodeEncodeError:
            p = urllib.parse.urlparse(newurl)
            path = urllib.parse.quote(p.path, safe="/")
            query = urllib.parse.quote(p.query, safe="=&")
            newurl = urllib.parse.urlunparse(
                (p.scheme, p.netloc, path, p.params, query, p.fragment)
            )
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_opener = urllib.request.build_opener(_RedirectFix())


def _http_get(url: str, timeout: int = 40) -> bytes:
    # gitee raw 直链可能含未编码中文路径 (如 .../img/东方卫视.png),
    # 直接请求会触发 http.client 的 ascii 编码错误. 这里把 path/query 重新编码.
    try:
        url.encode("ascii")
    except UnicodeEncodeError:
        p = urllib.parse.urlparse(url)
        path = urllib.parse.quote(p.path, safe="/")
        query = urllib.parse.quote(p.query, safe="=&")
        url = urllib.parse.urlunparse((p.scheme, p.netloc, path, p.params, query, p.fragment))
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    return _opener.open(req, timeout=timeout).read()


# --------------------------------------------------------------------------- #
# gh api (优先通道, 沙箱/CI 均可用, 返回 base64)
# --------------------------------------------------------------------------- #
def _gh_api(path: str) -> object:
    """调用 `gh api`, 返回解析后的 JSON. 失败抛异常."""
    out = subprocess.run(
        ["gh", "api", path],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if out.returncode != 0:
        raise RuntimeError(f"gh api {path} failed: {out.stderr.strip()[:200]}")
    return json.loads(out.stdout)


def gh_available() -> bool:
    return shutil.which("gh") is not None


def fetch_fm_names_via_gh() -> dict:
    """通过 gh api 列出 fanmingming/tv 全部文件名 -> { 归一化名: 原始名 }."""
    names: dict = {}
    page = 1
    while True:
        try:
            data = _gh_api(
                f"repos/{FM_API_REPO}/contents/tv?ref=main&per_page=100&page={page}"
            )
        except Exception as e:  # noqa: BLE001
            print(f"  [warn] gh list page {page}: {e}", file=sys.stderr)
            break
        if not isinstance(data, list):
            break
        for x in data:
            n = x.get("name", "")
            if n.lower().endswith(".png"):
                names[fname_key(n)] = n
        if len(data) < 100:
            break
        page += 1
        if page > 30:
            break
    return names


def download_via_gh(name: str) -> bytes:
    """通过 gh api 下载单个 tv/<name> 的 base64 内容."""
    enc = urllib.parse.quote(name)
    data = _gh_api(f"repos/{FM_API_REPO}/contents/tv/{enc}?ref=main")
    content = data.get("content")
    if not content:
        raise RuntimeError("empty content")
    return base64.b64decode(content)


def load_gitee_online() -> dict:
    names: dict = {}
    for page in range(1, 12):
        try:
            data = json.loads(
                _http_get(
                    f"https://gitee.com/api/v5/repos/mytv-android/myTVlogo/contents/img?per_page=100&page={page}"
                )
            )
        except Exception as e:  # noqa: BLE001
            print(f"  [warn] gitee list page {page}: {e}", file=sys.stderr)
            break
        if not isinstance(data, list):
            break
        for x in data:
            n = x.get("name", "")
            names[fname_key(n)] = n
        if len(data) < 100:
            break
    return names


def main() -> int:
    ap = argparse.ArgumentParser(description="打包中文频道台标到 app 内")
    ap.add_argument("--data", default=DEFAULT_DATA)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--manifest", default=DEFAULT_MANIFEST)
    ap.add_argument("--dry", action="store_true", help="只统计匹配率, 不下载")
    ap.add_argument("--force", action="store_true", help="重新下载已存在的 png")
    args = ap.parse_args()

    with open(args.data, encoding="utf-8") as fp:
        channels = json.load(fp)
    os.makedirs(args.out, exist_ok=True)

    # 1) fanmingming 名称清单 (gh api 优先, 失败回退离线/空)
    fm: dict = {}
    if gh_available():
        print("  [info] 通过 gh api 拉取 fanmingming/tv 清单 ...")
        fm = fetch_fm_names_via_gh()
        print(f"  fanmingming 清单: {len(fm)}")
    else:
        print("  [warn] 无 gh cli, 跳过 fanmingming (将尝试 raw/gitee)")

    # 2) gitee 兜底清单
    gitee = load_gitee_online()
    if gitee:
        print(f"  gitee 清单: {len(gitee)}")

    manifest: dict = {}
    matched = 0
    unmatched = []
    for ch in channels:
        cid = ch.get("id")
        name = ch.get("name") or ch.get("displayName") or ""
        cand = (
            [name]
            + list(ch.get("alt_names") or [])
            + [str(cid).replace(".cn", ""), str(cid)]
            # 英文/拼音 id/name -> 中文省份 -> 合成候选 (辽宁卫视 等)
            + pinyin_province_candidates(
                cid, name, *(ch.get("alt_names") or [])
            )
        )
        logo = ch.get("logo")
        url = None
        src = None  # 'gh' | 'raw' | 'gitee' | 'logo'
        # 优先级: fanmingming(gh, 干净 base64, 无重定向坑) -> logo 直链(gitee) -> gitee 名称匹配
        for cn in cand:
            fmhit = fm.get(fname_key(cn))
            if fmhit:
                url, src = fmhit, "gh"
                break
        if not url and logo:
            url, src = logo, "logo"
        if not url:
            for cn in cand:
                ghit = gitee.get(fname_key(cn))
                if ghit:
                    url, src = ghit, "gitee"
                    break

        if not url:
            unmatched.append(name or cid)
            continue

        if args.dry:
            matched += 1
            manifest[cid] = f"{cid}.png"
            continue

        fn = f"{cid}.png"
        out_path = os.path.join(args.out, fn)
        if os.path.exists(out_path) and not args.force:
            manifest[cid] = fn
            matched += 1
            continue

        try:
            if src == "gh":
                data = download_via_gh(url)
            elif src == "logo":
                data = _http_get(url)
            else:  # raw / gitee -> 走修复后的 opener
                data = _http_get(
                    (FM_RAW if src == "raw" else GITEE_RAW) + urllib.parse.quote(url)
                )
            if not data or len(data) < 100:
                print(f"  [skip] {cid}: 内容过小 ({len(data) if data else 0})", file=sys.stderr)
                continue
            with open(out_path, "wb") as fp:
                fp.write(data)
            manifest[cid] = fn
            matched += 1
        except Exception as e:  # noqa: BLE001
            print(f"  [skip] {cid} {name}: {e}", file=sys.stderr)

    if not args.dry:
        # 仅合并已成功下载的; 不抹掉已提交的旧清单里仍存在的条目
        prev: dict = {}
        if os.path.exists(args.manifest):
            try:
                prev = json.load(open(args.manifest, encoding="utf-8"))
            except Exception:  # noqa: BLE001
                prev = {}
        for k, v in prev.items():
            if k not in manifest and os.path.exists(os.path.join(args.out, v)):
                manifest[k] = v
        with open(args.manifest, "w", encoding="utf-8") as fp:
            json.dump(manifest, fp, ensure_ascii=False, indent=2)

    print(f"匹配/下载台标: {matched}/{len(channels)}")
    if unmatched:
        print(f"\n未匹配 ({len(unmatched)}):")
        print("  " + "、".join(unmatched[:60]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
