# Changelog

All notable changes to this project will be documented in this file.

## 0.2.1 (2026-06-17)

- 5 项 UI 优化（状态栏/调试字/displayName/继续观看/分类标题）
- 引入 libmpv native（`media_kit_libs_video` 引入 Android native libmpv.so）
- 频道名自动中文化（iptv-org 英文 → 中文）
- CCTV5 源（`known_sources.json` 公开 m3u8 兑底）
- 状态栏反转 + 首页容器超出 修复
- Android 包名：`com.aqiyoung.iptv_app` → `com.threelive.iptv`（重命名 Kotlin 包 + 目录）

## 0.2.0 (2026-06-16)

- 收藏 + 搜索 + EPG + TV 焦点 + 启动恢复 + APK 打包
- `media_kit` + `media_kit_video` 卡 5 视频播放
- 修 v0.2.0 启动崩 `MediaKit.ensureInitialized must be called`
