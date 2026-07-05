import '../models/content.dart';

/// v0.3.11: Mock 点播数据 — 用于海报墙 Beta 版占位
/// 真实数据源接入后替换此文件
const List<Content> kMockMovies = [
  Content(
    id: 'movie_001',
    title: '流浪地球3',
    subtitle: 'The Wandering Earth III',
    type: 'movie',
    rating: 8.7,
    year: '2027',
    duration: '148分钟',
    genres: ['科幻', '冒险'],
    description: '太阳即将毁灭，人类在地球表面建造出巨大的推进器...',
    sourceUrls: ['https://example.com/movie001.m3u8'],
  ),
  Content(
    id: 'movie_002',
    title: '黑神话：悟空',
    subtitle: 'Black Myth: Wukong',
    type: 'movie',
    rating: 9.2,
    year: '2026',
    duration: '120分钟',
    genres: ['动作', '奇幻'],
    description: '根据中国经典小说《西游记》改编...',
    sourceUrls: ['https://example.com/movie002.m3u8'],
  ),
  Content(
    id: 'movie_003',
    title: '哪吒之魔童闹海',
    subtitle: 'Ne Zha 2',
    type: 'movie',
    rating: 8.5,
    year: '2025',
    duration: '110分钟',
    genres: ['动画', '奇幻'],
    description: '哪吒闹海的经典故事新编...',
    sourceUrls: ['https://example.com/movie003.m3u8'],
  ),
  Content(
    id: 'movie_004',
    title: '长安三万里',
    type: 'movie',
    rating: 8.3,
    year: '2026',
    duration: '168分钟',
    genres: ['动画', '历史'],
    description: '盛唐诗人李白与高适的壮阔人生...',
    sourceUrls: ['https://example.com/movie004.m3u8'],
  ),
  Content(
    id: 'movie_005',
    title: '战狼3',
    type: 'movie',
    rating: 7.8,
    year: '2026',
    duration: '135分钟',
    genres: ['动作', '军事'],
    description: '冷锋的又一轮热血征程...',
    sourceUrls: ['https://example.com/movie005.m3u8'],
  ),
];

const List<Content> kMockSeries = [
  Content(
    id: 'series_001',
    title: '三体',
    type: 'series',
    rating: 9.0,
    year: '2026',
    genres: ['科幻'],
    description: '根据刘慈欣同名小说改编...',
    sourceUrls: ['https://example.com/series001.m3u8'],
  ),
  Content(
    id: 'series_002',
    title: '庆余年 第三季',
    type: 'series',
    rating: 8.8,
    year: '2027',
    genres: ['古装', '权谋'],
    description: '范闲的传奇继续...',
    sourceUrls: ['https://example.com/series002.m3u8'],
  ),
  Content(
    id: 'series_003',
    title: '漫长的季节',
    type: 'series',
    rating: 9.4,
    year: '2025',
    genres: ['悬疑', '剧情'],
    description: '一桩悬案三个季节...',
    sourceUrls: ['https://example.com/series003.m3u8'],
  ),
];

const List<Content> kMockVariety = [
  Content(
    id: 'variety_001',
    title: '奔跑吧 第十一季',
    type: 'variety',
    rating: 7.5,
    year: '2026',
    description: '国民综艺再出发...',
    sourceUrls: ['https://example.com/variety001.m3u8'],
  ),
  Content(
    id: 'variety_002',
    title: '乘风破浪的姐姐',
    type: 'variety',
    rating: 8.0,
    year: '2026',
    description: '30位姐姐的舞台竞演...',
    sourceUrls: ['https://example.com/variety002.m3u8'],
  ),
];

/// 所有 mock 点播
const List<Content> kMockVodContents = [
  ...kMockMovies,
  ...kMockSeries,
  ...kMockVariety,
];

/// 推荐内容 (混合: 热门直播 + 精选点播)
final List<Content> kMockRecommended = [
  kMockMovies[0], // 流浪地球3
  kMockMovies[1], // 黑神话
  kMockSeries[0], // 三体
];
