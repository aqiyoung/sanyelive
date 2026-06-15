# IPTV APP

> 极简新中式设计 - Flutter 全平台 - 家用电视/盒子场景

## 数据源

- 频道：iptv-org/iptv (M3U)
- 节目表：iptv-org/epg (XMLTV)
- 频道元数据：iptv-org/database

## 技术栈

- Flutter 3.22+ (Android TV / iOS / Web)
- media_kit 跨平台播放
- 设计语言：新中式 - 暖色调 (Terracotta #C96442) - 衬线标题

## 路线图

- 1. 仓库脚手架 <- current
- 2. 设计系统 (theme/字体/配色) + 3 个核心 widget
- 3. 数据层 (iptv-org 抓取 + Channel/EPG 模型 + 精简版 JSON)
- 4. 主页 + 分类页 + 频道列表 UI
- 5. 播放页 + media_kit 集成 + SourceFailover
- 6. 收藏 + 搜索 + EPG + TV 端焦点 + APK 打包

## License

MIT
