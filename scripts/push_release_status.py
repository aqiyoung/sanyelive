#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""汇总多个 GitHub 仓库的最新发布，聚合推送一条消息到 Telegram。

参照 sanyelive/.github/workflows/release.yml 里的「推送新版本到 Telegram」步骤：
- 复用同样的 sendMessage 调用方式与 TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID 机密
- 把「单仓发版推送」扩成「多仓发布状态汇总」

用法：
  python3 scripts/push_release_status.py                 # 用环境变量里的机密真发
  python3 scripts/push_release_status.py --dry-run       # 只打印待发消息，不发送（本地调试）
  python3 scripts/push_release_status.py --chat 123456   # 覆盖 chat_id

依赖：gh（GitHub CLI，复用本地 gh auth 或 CI 的 GITHUB_TOKEN）、curl（发 Telegram）。
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone, timedelta

# 北京时间 (UTC+8)
BJ = timezone(timedelta(hours=8))

# 要汇总的项目：显示名 + GitHub slug
# 想加/换项目，直接改这个列表即可（与 sanyelive 的 PROJECTS 对齐）
PROJECTS = [
    ("视界 sanyelive", "aqiyoung/sanyelive"),
    ("Synapse", "aqiyoung/synapse"),
    ("三页云盘 (openlist-android)", "aqiyoung/openlist-android"),
    ("FeiNiuMusic", "aqiyoung/FeiNiuMusic"),
    ("OpenClaw", "aqiyoung/openclaw"),
]

# 与 sanyelive release.yml 里写死的默认 chat 一致
DEFAULT_CHAT_ID = "460212872"


def gh_api(path):
    """用 gh api 取原始 JSON。复用本地 gh auth 或 CI 的 GITHUB_TOKEN。失败返回 None。"""
    r = subprocess.run(
        ["gh", "api", path, "-H", "Accept: application/vnd.github+json"],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return r.stdout.strip()


def fmt_date(iso):
    """ISO8601 -> 北京时间 YYYY-MM-DD（拿不到日期时返回空串）。"""
    if not iso:
        return ""
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(BJ)
        return dt.strftime("%Y-%m-%d")
    except Exception:
        return ""


def get_release_info(repo):
    """返回 (tag, name, published_iso, html_url) 或 None。

    优先取 latest release（排除 draft/prerelease 的正式发布）；
    若该仓没有正式 release，回退到最新 tag（并尽量补上 tag 对应 commit 的日期）。
    """
    out = gh_api(f"repos/{repo}/releases/latest")
    if out:
        try:
            d = json.loads(out)
            tag = d.get("tag_name")
            if tag:
                return (
                    tag,
                    d.get("name") or tag,
                    d.get("published_at"),
                    d.get("html_url") or f"https://github.com/{repo}/releases/tag/{tag}",
                )
        except Exception:
            pass

    # 回退：最新 tag
    tags = gh_api(f"repos/{repo}/tags")
    if tags:
        try:
            arr = json.loads(tags)
            if arr:
                tag = arr[0]["name"]
                published = None
                sha = (arr[0].get("commit") or {}).get("sha")
                if sha:
                    c = gh_api(f"repos/{repo}/commits/{sha}")
                    if c:
                        try:
                            published = json.loads(c)["commit"]["committer"]["date"]
                        except Exception:
                            pass
                return (
                    tag,
                    tag,
                    published,
                    f"https://github.com/{repo}/releases/tag/{tag}",
                )
        except Exception:
            pass
    return None


def build_message():
    now = datetime.now(BJ).strftime("%Y-%m-%d %H:%M")
    lines = [f"📊 项目发布状态汇总（{now} 北京时间）", ""]
    for disp, repo in PROJECTS:
        info = get_release_info(repo)
        if info:
            tag, name, published, url = info
            pdate = fmt_date(published) or "日期未知"
            extra = "" if name == tag else f"（{name}）"
            lines.append(f"🔹 {disp} — {tag}{extra}")
            lines.append(f"   📅 {pdate} · 🔗 {url}")
        else:
            lines.append(f"🔹 {disp} — 暂无发布")
            lines.append(f"   🔗 https://github.com/{repo}")
        lines.append("")
    return "\n".join(lines).strip()


def send_telegram(token, chat_id, text):
    """调 Telegram Bot API sendMessage。失败（如 token 失效 / chat 未 /start）返回非 0。"""
    r = subprocess.run(
        [
            "curl", "-f", "-X", "POST",
            f"https://api.telegram.org/bot{token}/sendMessage",
            "--data-urlencode", f"chat_id={chat_id}",
            "--data-urlencode", f"text={text}",
        ],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        sys.stderr.write("::error::Telegram 推送失败 — 检查 TELEGRAM_BOT_TOKEN 是否有效、"
                         "chat_id 是否与该 bot /start 过\n")
        sys.stderr.write(r.stderr)
        sys.exit(1)
    print("✅ Telegram 推送成功")


def main():
    ap = argparse.ArgumentParser(description="汇总多仓最新发布并推送到 Telegram")
    ap.add_argument("--dry-run", action="store_true", help="只打印待发消息，不发送")
    ap.add_argument("--chat", default=os.environ.get("TELEGRAM_CHAT_ID", DEFAULT_CHAT_ID),
                    help="Telegram chat_id（默认 460212872，可用 env TELEGRAM_CHAT_ID 覆盖）")
    ap.add_argument("--token", default=os.environ.get("TELEGRAM_BOT_TOKEN", ""),
                    help="Telegram bot token（默认读 env TELEGRAM_BOT_TOKEN）")
    args = ap.parse_args()

    msg = build_message()
    print("===== 待发送消息 =====")
    print(msg)
    print("=====================")

    if args.dry_run:
        print("（dry-run，未发送）")
        return

    if not args.token:
        sys.stderr.write("::error::缺少 TELEGRAM_BOT_TOKEN（设置环境变量 --token 或 secret）\n")
        sys.exit(1)

    send_telegram(args.token, args.chat, msg)


if __name__ == "__main__":
    main()
