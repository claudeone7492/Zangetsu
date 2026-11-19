import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/live/dvr_store.dart';
import 'package:watch_app/core/live/xmltv_parser.dart';

EpgProgramme _prog({
  String channelId = 'bbc1.uk',
  String title = 'A Show',
  DateTime? start,
  DateTime? stop,
}) {
  final s = start ?? DateTime.utc(2026, 1, 1, 20);
  return EpgProgramme(
    channelId: channelId,
    title: title,
    start: s,
    stop: stop ?? s.add(const Duration(hours: 1)),
  );
}

DvrEntry _entry({
  DvrKind kind = DvrKind.recording,
  DateTime? start,
  String streamUrl = 'https://cdn.example/live.m3u8',
  int padding = 0,
  String channelId = 'bbc1.uk',
}) {
  final s = start ?? DateTime.utc(2026, 1, 1, 20);
  return DvrEntry(
    channelId: channelId,
    channelName: 'BBC One',
    title: 'A Show',
    start: s,
    stop: s.add(const Duration(hours: 1)),
    kind: kind,
    streamUrl: streamUrl,
    paddingMinutes: padding,
  );
}

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('dvr_test_');
    Hive.init(dir.path);
  });

  setUp(() async {
    final box = await Hive.openBox<dynamic>(DvrStore.boxName);
    await box.clear();
  });

  group('DvrEntry', () {
    test('id is stable per channel+start, so re-booking is idempotent', () {
      final a = _entry();
      final b = _entry();
      expect(a.id, b.id);
      expect(_entry(channelId: 'itv.uk').id, isNot(a.id));
    });

    test('padding extends the capture window both ways', () {
      final e = _entry(padding: 5);
      expect(e.captureStart, e.start.subtract(const Duration(minutes: 5)));
      expect(e.captureStop, e.stop.add(const Duration(minutes: 5)));
    });

    test('isLiveAt respects the padded window', () {
      final e = _entry(padding: 10);
      // 10 minutes before the billed start, but inside the padded window.
      expect(e.isLiveAt(DateTime.utc(2026, 1, 1, 19, 55)), isTrue);
      expect(e.isLiveAt(DateTime.utc(2026, 1, 1, 19, 45)), isFalse);
      expect(e.isLiveAt(DateTime.utc(2026, 1, 1, 21, 5)), isTrue);
      expect(e.isLiveAt(DateTime.utc(2026, 1, 1, 21, 15)), isFalse);
    });

    test('fromProgramme copies the EPG window and marks it created', () {
      final e = DvrEntry.fromProgramme(
        _prog(title: 'The News'),
        channelName: 'BBC One',
        kind: DvrKind.reminder,
      );
      expect(e.title, 'The News');
      expect(e.channelId, 'bbc1.uk');
      expect(e.start, DateTime.utc(2026, 1, 1, 20));
      expect(e.kind, DvrKind.reminder);
      expect(e.createdAt, isNotNull);
    });

    test('round-trips through JSON', () {
      final e = _entry(padding: 3);
      final back = DvrEntry.fromJson(e.toJson());
      expect(back.id, e.id);
      expect(back.title, e.title);
      expect(back.kind, DvrKind.recording);
      expect(back.paddingMinutes, 3);
      expect(back.streamUrl, e.streamUrl);
    });

    test('an unknown kind falls back to reminder rather than throwing', () {
      final json = _entry().toJson()..['kind'] = 'garbage';
      expect(DvrEntry.fromJson(json).kind, DvrKind.reminder);
    });
  });

  group('DvrStore', () {
    test('book persists and rehydrates', () async {
      final store = DvrStore();
      await store.book(_entry());
      expect(store.entries, hasLength(1));

      final reopened = DvrStore();
      await reopened.ensureLoaded();
      expect(reopened.entries, hasLength(1));
      expect(reopened.entries.single.title, 'A Show');
    });

    test('re-booking the same airing replaces rather than duplicates', () async {
      final store = DvrStore();
      await store.book(_entry());
      await store.book(_entry(padding: 5));
      expect(store.entries, hasLength(1));
      expect(store.entries.single.paddingMinutes, 5);
    });

    test('reminders and recordings are separated and sorted', () async {
      final store = DvrStore();
      await store.book(
        _entry(
          kind: DvrKind.reminder,
          channelId: 'itv.uk',
          start: DateTime.utc(2026, 1, 2, 20),
        ),
      );
      await store.book(
        _entry(kind: DvrKind.recording, start: DateTime.utc(2026, 1, 1, 20)),
      );
      expect(store.reminders.single.kind, DvrKind.reminder);
      expect(store.recordings.single.kind, DvrKind.recording);
    });

    test('cancel removes the booking', () async {
      final store = DvrStore();
      final e = await store.book(_entry());
      await store.cancel(e.id);
      expect(store.isEmpty, isTrue);
    });

    test('isBooked finds an airing regardless of kind', () async {
      final store = DvrStore();
      await store.book(_entry(kind: DvrKind.reminder));
      expect(
        store.isBooked('bbc1.uk', DateTime.utc(2026, 1, 1, 20)),
        isTrue,
      );
      expect(
        store.isBooked('bbc1.uk', DateTime.utc(2026, 1, 1, 21)),
        isFalse,
      );
    });

    test('attachStream makes a guide booking recordable', () async {
      final store = DvrStore();
      final e = await store.book(_entry(streamUrl: ''));
      expect(store.dueForCapture(at: DateTime.utc(2026, 1, 1, 20, 30)), isEmpty);

      await store.attachStream(e.id, 'https://cdn.example/live.m3u8');
      expect(
        store.dueForCapture(at: DateTime.utc(2026, 1, 1, 20, 30)),
        hasLength(1),
      );
    });

    test('dueForCapture only returns live, URL-bearing recordings', () async {
      final store = DvrStore();
      await store.book(
        _entry(kind: DvrKind.recording, start: DateTime.utc(2026, 1, 1, 20)),
      );
      // A reminder on a DIFFERENT channel, so it is a separate booking rather
      // than replacing the recording (id is channel+start).
      await store.book(
        _entry(
          kind: DvrKind.reminder,
          channelId: 'itv.uk',
          start: DateTime.utc(2026, 1, 1, 20),
        ),
      );
      expect(store.entries, hasLength(2));
      expect(
        store.dueForCapture(at: DateTime.utc(2026, 1, 1, 20, 30)),
        hasLength(1),
      );
      expect(
        store.dueForCapture(at: DateTime.utc(2026, 1, 1, 22)),
        isEmpty,
      );
    });

    test('missedCaptures includes a window that opened while asleep', () async {
      final store = DvrStore();
      await store.book(
        _entry(start: DateTime.utc(2026, 1, 1, 20)),
      );
      // Two minutes into the airing: dueForCapture also matches, and
      // missedCaptures flags it so a loop that started late still picks it up.
      expect(
        store.missedCaptures(at: DateTime.utc(2026, 1, 1, 20, 2)),
        hasLength(1),
      );
      expect(
        store.missedCaptures(at: DateTime.utc(2026, 1, 1, 19, 30)),
        isEmpty,
      );
    });

    test('prune drops old entries and keeps recent ones', () async {
      final store = DvrStore();
      final now = DateTime.now().toUtc();
      // Relative to now, so the test does not rot as the clock advances.
      await store.book(_entry(start: now.subtract(const Duration(days: 90))));
      await store.book(_entry(start: now.subtract(const Duration(days: 1))));
      final removed = await store.prune(keepDays: 30);
      expect(removed, 1);
      expect(store.entries, hasLength(1));
      expect(store.entries.single.start.isAfter(
        now.subtract(const Duration(days: 2)),
      ), isTrue);
    });
  });

  group('dueReminders', () {
    test('fires inside the look-ahead window only', () {
      final start = DateTime.utc(2026, 1, 1, 20);
      final entries = [_entry(kind: DvrKind.reminder, start: start)];
      expect(
        dueReminders(entries, at: start.subtract(const Duration(minutes: 1))),
        hasLength(1),
      );
      expect(
        dueReminders(entries, at: start.subtract(const Duration(minutes: 10))),
        isEmpty,
      );
      // Once it has started it is no longer "coming up".
      expect(dueReminders(entries, at: start), isEmpty);
    });

    test('ignores recordings', () {
      final start = DateTime.utc(2026, 1, 1, 20);
      expect(
        dueReminders(
          [_entry(kind: DvrKind.recording, start: start)],
          at: start.subtract(const Duration(minutes: 1)),
        ),
        isEmpty,
      );
    });

    test('notification id is stable per booking', () {
      final e = _entry(kind: DvrKind.reminder);
      final r1 = dueReminders(
        [e],
        at: e.start.subtract(const Duration(minutes: 1)),
      ).single;
      final r2 = dueReminders(
        [e],
        at: e.start.subtract(const Duration(minutes: 1)),
      ).single;
      expect(r1.notificationId, r2.notificationId);
    });
  });

  group('encode/decodeDvr', () {
    test('round-trips a schedule', () {
      final entries = [
        _entry(start: DateTime.utc(2026, 1, 1, 20)),
        _entry(kind: DvrKind.reminder, start: DateTime.utc(2026, 1, 2, 20)),
      ];
      final back = decodeDvr(encodeDvr(entries));
      expect(back, hasLength(2));
      expect(back.first.start, DateTime.utc(2026, 1, 1, 20));
    });

    test('malformed input yields an empty list, not a throw', () {
      expect(decodeDvr('not json'), isEmpty);
      expect(decodeDvr('{}'), isEmpty);
      expect(decodeDvr('[{"garbage":1}]'), isEmpty);
    });

    test('one bad row does not sink the good ones', () {
      final good = _entry().toJson();
      final back = decodeDvr('[{"garbage":1}, ${_jsonOf(good)}]');
      expect(back, hasLength(1));
    });
  });
}

String _jsonOf(Map<String, dynamic> m) {
  final parts = m.entries.map((e) {
    final v = e.value;
    return '"${e.key}":${v is String ? '"$v"' : v}';
  });
  return '{${parts.join(',')}}';
}
