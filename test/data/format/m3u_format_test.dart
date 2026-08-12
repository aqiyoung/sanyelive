import 'package:flutter_test/flutter_test.dart';
import 'package:sanyelive/data/format/format_registry.dart';
import 'package:sanyelive/data/format/m3u_format.dart';

void main() {
  group('M3uFormat.canParse', () {
    test('识别 #EXTM3U 头', () {
      const m3u = '#EXTM3U\n#EXTINF:-1,CCTV-1\nhttp://x/1.m3u8\n';
      expect(const M3uFormat().canParse(m3u), isTrue);
    });

    test('容忍前导空白与大小写', () {
      const m3u = '  \n#extm3u\n#EXTINF:-1,x\nhttp://x\n';
      expect(const M3uFormat().canParse(m3u), isTrue);
    });

    test('非 m3u 内容返回 false', () {
      const json = '[{"id":"CCTV1"}]';
      expect(const M3uFormat().canParse(json), isFalse);
    });
  });

  group('M3uFormat.parse', () {
    test('解析属性映射', () {
      const m3u = '''
#EXTM3U
#EXTINF:-1 tvg-id="CCTV1" tvg-logo="http://logo/c1.png" group-title="央视",CCTV-1 综合
http://example.com/cctv1.m3u8
#EXTINF:-1 tvg-id="CCTV5" tvg-logo="http://logo/c5.png" group-title="体育",CCTV-5 体育
http://example.com/cctv5.m3u8
''';
      final ch = const M3uFormat().parse(m3u);
      expect(ch, hasLength(2));

      expect(ch[0].id, 'm3u:CCTV1');
      expect(ch[0].name, 'CCTV-1 综合');
      expect(ch[0].logoUrl, 'http://logo/c1.png');
      expect(ch[0].categories, ['央视']);
      expect(ch[0].sources, ['http://example.com/cctv1.m3u8']);

      expect(ch[1].id, 'm3u:CCTV5');
      expect(ch[1].name, 'CCTV-5 体育');
      expect(ch[1].categories, ['体育']);
    });

    test('名字含逗号时取最后一个逗号之后', () {
      const m3u = '''
#EXTM3U
#EXTINF:-1 group-title="新闻",BBC, World News
http://example.com/bbc.m3u8
''';
      final ch = const M3uFormat().parse(m3u);
      expect(ch, hasLength(1));
      expect(ch[0].name, 'BBC, World News');
    });

    test('无 tvg-id 时用 name 兜底并去重', () {
      const m3u = '''
#EXTM3U
#EXTINF:-1 group-title="测试",测试台
http://a/1.m3u8
#EXTINF:-1 group-title="测试",测试台
http://a/2.m3u8
''';
      final ch = const M3uFormat().parse(m3u);
      expect(ch, hasLength(2));
      expect(ch[0].id, 'm3u:测试台');
      expect(ch[1].id, 'm3u:测试台#1');
    });

    test('group-title 按分号拆分多分类', () {
      const m3u = '''
#EXTM3U
#EXTINF:-1 group-title="体育;高清",CCTV-5
http://x/5.m3u8
''';
      final ch = const M3uFormat().parse(m3u);
      expect(ch[0].categories, ['体育', '高清']);
    });

    test('忽略空行与未知指令', () {
      const m3u = '''
#EXTM3U

#EXTVLCOPT:http-user-agent=Test
#EXTINF:-1,CCTV-1
http://x/1.m3u8
''';
      final ch = const M3uFormat().parse(m3u);
      expect(ch, hasLength(1));
      expect(ch[0].sources, ['http://x/1.m3u8']);
    });

    test('无 tvg-logo 时 logoUrl 为 null', () {
      const m3u = '#EXTM3U\n#EXTINF:-1,CCTV-1\nhttp://x/1.m3u8\n';
      final ch = const M3uFormat().parse(m3u);
      expect(ch[0].logoUrl, isNull);
      expect(ch[0].categories, ['未分类']);
    });
  });

  group('ChannelFormatRegistry', () {
    test('m3u 内容命中 m3u 格式', () {
      const m3u = '#EXTM3U\n#EXTINF:-1,CCTV-1\nhttp://x/1.m3u8\n';
      final ch = ChannelFormatRegistry.instance.parse(m3u);
      expect(ch, hasLength(1));
      expect(ch[0].name, 'CCTV-1');
    });

    test('json 内容命中 iptv_org_json 格式', () {
      const json = '[{"id":"CCTV1","name":"CCTV-1","country":"CN",'
          '"categories":[],"sources":["http://x/1.m3u8"]}]';
      final ch = ChannelFormatRegistry.instance.parse(json);
      expect(ch, hasLength(1));
      expect(ch[0].id, 'CCTV1');
    });

    test('parseWith 指定格式', () {
      const m3u = '#EXTM3U\n#EXTINF:-1,CCTV-1\nhttp://x/1.m3u8\n';
      final ch = ChannelFormatRegistry.instance.parseWith('m3u', m3u);
      expect(ch, hasLength(1));
    });

    test('未知格式 id 抛 ArgumentError', () {
      expect(
        () => ChannelFormatRegistry.instance.parseWith('nope', 'x'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('无可解析格式抛 FormatException', () {
      expect(
        () => ChannelFormatRegistry.instance.parse('just random text'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
