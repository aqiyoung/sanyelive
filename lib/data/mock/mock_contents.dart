import '../models/content.dart';

/// v0.3.11.62: 真实可播内容 — 直播频道源来自 channels_cn.json, VOD 来自 VOD-Org.
/// 海报墙卡片点击 → /player/vod://<url>?title=<片名> → 直接播放

const List<Content> kMockMovies = [
  Content(
    id: 'movie_cctv6',
    title: 'CCTV-6 电影',
    subtitle: '央视电影频道',
    type: 'movie',
    rating: 8.5,
    year: '直播',
    duration: '24小时',
    genres: ['电影', '直播'],
    description: '央视电影频道，经典影片轮播',
    sourceUrls: ['http://69.30.245.50/live/cctv6.m3u8'],
  ),
  Content(
    id: 'movie_cctv1',
    title: 'CCTV-1 综合',
    subtitle: '央视综合频道',
    type: 'movie',
    rating: 8.2,
    year: '直播',
    duration: '24小时',
    genres: ['综合', '直播'],
    description: '央视综合频道',
    sourceUrls: ['http://69.30.245.50/live/cctv1.m3u8'],
  ),
  Content(
    id: 'movie_cctv8',
    title: 'CCTV-8 电视剧',
    subtitle: '央视电视剧频道',
    type: 'movie',
    rating: 8.0,
    year: '直播',
    duration: '24小时',
    genres: ['电视剧', '直播'],
    description: '央视电视剧频道，热播剧集',
    sourceUrls: ['http://192.151.150.154/live/cctv8k.m3u8'],
  ),
  Content(
    id: 'movie_goldbergs',
    title: 'The Goldbergs',
    subtitle: 'S04E23',
    type: 'movie',
    rating: 8.3,
    year: 'VOD',
    duration: '22分钟',
    genres: ['喜剧', '美剧'],
    description: '80年代家庭喜剧',
    sourceUrls: ['https://vod007.the6tv.duckdns.org:2443/The_Goldbergs_S04E23.mp4/index.m3u8'],
  ),
  Content(
    id: 'movie_cctv5',
    title: 'CCTV-5 体育',
    subtitle: '央视体育频道',
    type: 'movie',
    rating: 7.9,
    year: '直播',
    duration: '24小时',
    genres: ['体育', '直播'],
    description: '央视体育频道',
    sourceUrls: ['https://live.fanmingming.com/cctv5.m3u8'],
  ),
];

const List<Content> kMockSeries = [
  Content(
    id: 'series_cctv8',
    title: 'CCTV-8 电视剧',
    subtitle: '热播剧场',
    type: 'series',
    rating: 8.0,
    year: '直播',
    genres: ['电视剧', '直播'],
    description: '央视电视剧频道',
    sourceUrls: ['http://192.151.150.154/live/cctv8k.m3u8'],
  ),
  Content(
    id: 'series_cctv1',
    title: 'CCTV-1 综合',
    subtitle: '黄金剧场',
    type: 'series',
    rating: 8.2,
    year: '直播',
    genres: ['综合', '直播'],
    description: '央视综合频道',
    sourceUrls: ['http://69.30.245.50/live/cctv1.m3u8'],
  ),
  Content(
    id: 'series_cctv4',
    title: 'CCTV-4 中文国际',
    subtitle: '亚洲版',
    type: 'series',
    rating: 7.8,
    year: '直播',
    genres: ['国际', '直播'],
    description: '央视中文国际频道',
    sourceUrls: ['http://107.150.60.122/live/cctv4hd.m3u8'],
  ),
];

const List<Content> kMockVariety = [
  Content(
    id: 'variety_cctv3',
    title: 'CCTV-3 综艺',
    subtitle: '央视综艺频道',
    type: 'variety',
    rating: 7.5,
    year: '直播',
    description: '央视综艺频道',
    sourceUrls: ['http://198.204.228.26/live/cctv3hd.m3u8'],
  ),
  Content(
    id: 'variety_cctv5plus',
    title: 'CCTV-5+ 体育赛事',
    subtitle: '央视体育赛事频道',
    type: 'variety',
    rating: 7.3,
    year: '直播',
    description: '央视体育赛事频道',
    sourceUrls: ['http://go.bkpcp.top/mg/cctv5plus'],
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
  kMockMovies[0], // CCTV-6 电影
  kMockMovies[3], // The Goldbergs VOD
  kMockMovies[4], // CCTV-5 体育
];
