import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/live/epg_store.dart';
import 'package:watch_app/core/live/xmltv_parser.dart';

const String _guide = '''<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="test">
  <channel id="bbc1.uk">
    <display-name>BBC One</display-name>
    <display-name>BBC1</display-name>
  </channel>
  <channel id="itv1.uk">
    <display-name>ITV 1</display-name>
  </channel>
  <programme start="20260101120000 +0000" stop="20260101130000 +0000" channel="bbc1.uk">
    <title>Midday News</title>
    <desc>The lunchtime bulletin.</desc>
    <category>News</category>
  </programme>
  <programme start="20260101130000 +0000" stop="20260101140000 +0000" channel="bbc1.uk">
    <title>Afternoon Film</title>
    <icon src="https://img.example/film.jpg"/>
    <episode-num system="xmltv_ns">1.4.</episode-num>
  </programme>
  <programme start="20260101120000 +0100" stop="20260101130000 +0100" channel="itv1.uk">
    <title>Local Time Show</title>
  </programme>
  <!-- No stop: must still be kept with a nominal slot. -->
  <programme start="20260101140000 +0000" channel="itv1.uk">
    <title>Open Ended</title>
  </programme>
  <!-- No start: must be dropped. -->
  <programme channel="itv1.uk">
    <title>Broken Row</title>
  </programme>
</tv>
''';

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('epg_test_');
    Hive.init(dir.path);
  });

  group('XmltvParser.parseTimestamp', () {
    test('parses a UTC timestamp', () {
      final t = XmltvParser.parseTimestamp('20260101120000 +0000');
      expect(t, DateTime.utc(2026, 1, 1, 12));
    });

    test('applies a positive offset by subtracting it', () {
      // 12:00 at +0100 is 11:00 UTC.
      final t = XmltvParser.parseTimestamp('20260101120000 +0100');
      expect(t, DateTime.utc(2026, 1, 1, 11));
    });

    test('applies a negative offset by adding it', () {
      // 12:00 at -0500 is 17:00 UTC.
      final t = XmltvParser.parseTimestamp('20260101120000 -0500');
      expect(t, DateTime.utc(2026, 1, 1, 17));
    });

    test('treats a bare timestamp as UTC', () {
      expect(
        XmltvParser.parseTimestamp('20260101120000'),
        DateTime.utc(2026, 1, 1, 12),
      );
    });

    test('accepts a date with no time part', () {
      expect(
        XmltvParser.parseTimestamp('20260101'),
        DateTime.utc(2026, 1, 1),
      );
    });

    test('rejects malformed input instead of throwing', () {
      expect(XmltvParser.parseTimestamp(null), isNull);
      expect(XmltvParser.parseTimestamp(''), isNull);
      expect(XmltvParser.parseTimestamp('nonsense'), isNull);
      expect(XmltvParser.parseTimestamp('20261301120000'), isNull); // month 13
    });
  });

  group('XmltvParser.parse', () {
    test('reads channels, programmes and display names', () {
      final guide = const XmltvParser().parse(_guide);

      expect(guide.channelNames['bbc1.uk'], ['BBC One', 'BBC1']);
      expect(guide.programmes['bbc1.uk'], hasLength(2));
      expect(guide.programmes['bbc1.uk']!.first.title, 'Midday News');
      expect(guide.programmes['bbc1.uk']!.first.description,
          'The lunchtime bulletin.');
      expect(guide.programmes['bbc1.uk']!.first.category, 'News');
    });

    test('normalises a local-offset programme to UTC', () {
      final guide = const XmltvParser().parse(_guide);
      final itv = guide.programmes['itv1.uk']!.firstWhere(
        (p) => p.title == 'Local Time Show',
      );
      expect(itv.start, DateTime.utc(2026, 1, 1, 11));
    });

    test('keeps a programme with no stop, giving it a nominal slot', () {
      final guide = const XmltvParser().parse(_guide);
      final open = guide.programmes['itv1.uk']!.firstWhere(
        (p) => p.title == 'Open Ended',
      );
      expect(open.duration, const Duration(minutes: 30));
    });

    test('drops a programme with no start but keeps the rest', () {
      final guide = const XmltvParser().parse(_guide);
      final titles = guide.programmes['itv1.uk']!.map((p) => p.title);
      expect(titles, isNot(contains('Broken Row')));
      expect(titles, contains('Local Time Show'));
    });

    test('sorts programmes by start time', () {
      final guide = const XmltvParser().parse(_guide);
      final starts = guide.programmes['bbc1.uk']!.map((p) => p.start).toList();
      final sorted = [...starts]..sort();
      expect(starts, sorted);
    });

    test('reads the icon and xmltv_ns episode number', () {
      final guide = const XmltvParser().parse(_guide);
      final film = guide.programmes['bbc1.uk']!.firstWhere(
        (p) => p.title == 'Afternoon Film',
      );
      expect(film.iconUrl, 'https://img.example/film.jpg');
      expect(film.episodeNumber, '1.4.');
    });

    test('malformed XML yields an empty guide rather than throwing', () {
      final guide = const XmltvParser().parse('<tv><channel');
      expect(guide.isEmpty, isTrue);
      expect(guide.programmes, isEmpty);
    });
  });

  group('EpgGuide lookups', () {
    late EpgGuide guide;

    setUp(() => guide = const XmltvParser().parse(_guide));

    test('nowOn finds the programme covering an instant', () {
      final p = guide.nowOn('bbc1.uk', at: DateTime.utc(2026, 1, 1, 12, 30));
      expect(p?.title, 'Midday News');
    });

    test('nowOn is null outside every slot', () {
      expect(guide.nowOn('bbc1.uk', at: DateTime.utc(2026, 1, 1, 23)), isNull);
    });

    test('nextOn finds the following programme', () {
      final p = guide.nextOn('bbc1.uk', at: DateTime.utc(2026, 1, 1, 12, 30));
      expect(p?.title, 'Afternoon Film');
    });

    test('between clips to the requested window', () {
      final rows = guide.between(
        'bbc1.uk',
        from: DateTime.utc(2026, 1, 1, 12, 30),
        to: DateTime.utc(2026, 1, 1, 13, 30),
      );
      expect(rows.map((p) => p.title), ['Midday News', 'Afternoon Film']);
    });

    test('round-trips through JSON with times intact', () {
      final back = EpgGuide.fromJson(guide.toJson());
      expect(back.programmes['bbc1.uk'], hasLength(2));
      expect(
        back.programmes['bbc1.uk']!.first.start,
        DateTime.utc(2026, 1, 1, 12),
      );
      expect(back.channelNames['bbc1.uk'], ['BBC One', 'BBC1']);
    });
  });

  group('EpgStore (live server)', () {
    late HttpServer srv;
    late String base;
    late EpgStore store;

    setUp(() async {
      final box = await Hive.openBox<dynamic>(EpgStore.boxName);
      await box.clear();

      srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((req) async {
        if (req.uri.path == '/guide.xml') {
          req.response.headers.contentType = ContentType('application', 'xml');
          req.response.write(_guide);
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });
      base = 'http://127.0.0.1:${srv.port}';

      store = EpgStore(dio: Dio());
      await store.init();
    });

    tearDown(() async {
      await srv.close(force: true);
    });

    test('addSource fetches and caches the guide', () async {
      final ok = await store.addSource(EpgSource(url: '$base/guide.xml'));
      expect(ok, isTrue);
      expect(store.isEmpty, isFalse);
      expect(store.schedule('bbc1.uk'), hasLength(2));
      expect(store.isStale(store.sources.single), isFalse);
    });

    test('a failed fetch keeps the previous cache', () async {
      await store.addSource(EpgSource(url: '$base/guide.xml'));
      expect(store.schedule('bbc1.uk'), hasLength(2));

      // 404 must not blank the guide.
      final ok = await store.refresh(
        source: EpgSource(url: '$base/missing.xml'),
      );
      expect(ok, isFalse);
      expect(store.schedule('bbc1.uk'), hasLength(2));
    });

    test('resolveChannelId matches by tvg-id then display name', () async {
      await store.addSource(EpgSource(url: '$base/guide.xml'));

      expect(store.resolveChannelId(tvgId: 'bbc1.uk'), 'bbc1.uk');
      expect(store.resolveChannelId(tvgName: 'ITV 1'), 'itv1.uk');
      expect(
        store.resolveChannelId(displayName: 'bbc one'),
        'bbc1.uk',
        reason: 'display-name match is case-insensitive',
      );
      expect(store.resolveChannelId(tvgId: 'unknown.channel'), isNull);
    });

    test('rehydrates the guide from Hive on a fresh store', () async {
      await store.addSource(EpgSource(url: '$base/guide.xml'));

      final reopened = EpgStore(dio: Dio());
      await reopened.init();

      expect(reopened.schedule('bbc1.uk'), hasLength(2));
      expect(reopened.sources, hasLength(1));
    });

    test('installDefaults is a no-op once a source exists', () async {
      await store.installDefaults();
      expect(store.sources, isNotEmpty);
      final count = store.sources.length;
      await store.installDefaults();
      expect(store.sources.length, count);
    });

    test('clear empties the guide', () async {
      await store.addSource(EpgSource(url: '$base/guide.xml'));
      await store.clear();
      expect(store.isEmpty, isTrue);
    });
  });
}
