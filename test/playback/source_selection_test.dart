import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/playback/source_selection.dart';

VideoSource _s(String q, AudioKind k) => VideoSource(
  url: 'https://x/$q',
  quality: q,
  container: SourceContainer.hls,
  kind: k,
);

void main() {
  test('sortByQuality orders high→low, unknown last', () {
    final out = sortByQuality([
      _s('480p', AudioKind.sub),
      _s('1080p', AudioKind.sub),
      _s('', AudioKind.sub),
      _s('720p', AudioKind.sub),
    ]);
    expect(out.map((s) => s.quality).toList(), ['1080p', '720p', '480p', '']);
  });

  test('availableKinds lists distinct kinds present', () {
    final kinds = availableKinds([
      _s('720p', AudioKind.sub),
      _s('720p', AudioKind.dub),
      _s('480p', AudioKind.sub),
    ]);
    expect(kinds.contains(AudioKind.sub), true);
    expect(kinds.contains(AudioKind.dub), true);
    expect(kinds.length, 2);
  });

  test('pickDefault prefers requested kind at highest quality', () {
    final all = [
      _s('480p', AudioKind.sub),
      _s('1080p', AudioKind.dub),
      _s('1080p', AudioKind.sub),
    ];
    final picked = pickDefault(all, prefer: AudioKind.sub);
    expect(picked!.kind, AudioKind.sub);
    expect(picked.quality, '1080p');
  });

  test('pickDefault falls back to any kind when preferred absent', () {
    final all = [_s('720p', AudioKind.dub)];
    expect(pickDefault(all, prefer: AudioKind.sub)!.kind, AudioKind.dub);
  });

  test('sourcesForKind filters', () {
    final all = [_s('720p', AudioKind.sub), _s('720p', AudioKind.dub)];
    expect(sourcesForKind(all, AudioKind.dub).single.kind, AudioKind.dub);
  });

  test('waits briefly for a saved quality before using early links', () async {
    var polls = 0;
    final resolved = await waitForPreferredQuality(
      initial: [_s('720p', AudioKind.sub)],
      preferredQuality: '1080p',
      preferredKind: AudioKind.sub,
      poll: () async {
        polls++;
        return (sources: [_s('1080p', AudioKind.sub)], done: false);
      },
      pollInterval: Duration.zero,
    );

    expect(polls, 1);
    expect(resolved.map((source) => source.quality), ['720p', '1080p']);
  });

  test(
    'does not satisfy a quality preference with the other audio cut',
    () async {
      var polls = 0;
      final resolved = await waitForPreferredQuality(
        initial: [_s('720p', AudioKind.sub)],
        preferredQuality: '1080p',
        preferredKind: AudioKind.sub,
        poll: () async {
          polls++;
          return (
            sources: [
              VideoSource(
                url: 'https://x/${polls == 1 ? 'dub' : 'sub'}/1080p',
                quality: '1080p',
                container: SourceContainer.hls,
                kind: polls == 1 ? AudioKind.dub : AudioKind.sub,
              ),
            ],
            done: polls == 2,
          );
        },
        pollInterval: Duration.zero,
      );

      expect(polls, 2);
      expect(resolved.map((source) => source.kind), [
        AudioKind.sub,
        AudioKind.dub,
        AudioKind.sub,
      ]);
    },
  );

  // A resolution preference has to pick the STARTING source, because for a
  // provider that ships one file per quality there is nothing to switch once
  // playback has begun — swapping then would change server, audio and subs.
  group('pickDefault preferQuality', () {
    final all = [
      _s('2160p', AudioKind.sub),
      _s('1080p', AudioKind.sub),
      _s('480p', AudioKind.sub),
    ];

    test('starts on the source matching the preference', () {
      expect(pickDefault(all, preferQuality: '1080p')!.quality, '1080p');
      expect(pickDefault(all, preferQuality: '480p')!.quality, '480p');
    });

    test('the best server at or below the preference wins', () {
      final gap = [_s('2160p', AudioKind.sub), _s('480p', AudioKind.sub)];
      expect(pickDefault(gap, preferQuality: '720p')!.quality, '480p');
      // A 1080p preference is a cap: 720p is inside it, 1440p is not. The
      // nearest-number rule used to pick 1440p here and pay for it.
      final cap = [_s('1440p', AudioKind.sub), _s('720p', AudioKind.sub)];
      expect(pickDefault(cap, preferQuality: '1080p')!.quality, '720p');
    });

    test('auto/highest/null keep the existing highest-first default', () {
      expect(pickDefault(all, preferQuality: 'auto')!.quality, '2160p');
      expect(pickDefault(all, preferQuality: 'highest')!.quality, '2160p');
      expect(pickDefault(all)!.quality, '2160p');
    });

    test('preference never escapes the requested audio kind', () {
      final mixed = [_s('1080p', AudioKind.dub), _s('480p', AudioKind.sub)];
      final picked = pickDefault(
        mixed,
        prefer: AudioKind.sub,
        preferQuality: '1080p',
      );
      expect(picked!.kind, AudioKind.sub);
      expect(picked.quality, '480p');
    });

    test('sources carrying no resolution fall back, never crash', () {
      final none = [_s('', AudioKind.sub), _s('auto', AudioKind.sub)];
      expect(pickDefault(none, preferQuality: '1080p'), isNotNull);
      expect(pickDefault([], preferQuality: '1080p'), isNull);
    });
  });

  group('default quality lands on a server that carries it', () {
    VideoSource labelled(String label, [String? quality]) => VideoSource(
      url: 'https://x/${label.hashCode}',
      quality: quality,
      label: label,
      container: SourceContainer.hls,
      kind: AudioKind.sub,
    );

    test('heightFromText reads the server label, not a bare number', () {
      expect(heightFromText('HDHub · FSL [1080p]'), 1080);
      expect(heightFromText('4K · UHD'), 2160);
      expect(heightFromText('FHD web-dl'), 1080);
      expect(heightFromText('1080p'), 1080);
      // A year is not a resolution, and neither is a bitrate.
      expect(heightFromText('Blade Runner 2049 (2017)'), isNull);
      expect(heightFromText('server 2500 kbps'), isNull);
      expect(heightFromText(null), isNull);
    });

    test('sourceHeight prefers the quality field, then the label', () {
      expect(sourceHeight(labelled('1080p WEB', '720p')), 720);
      expect(sourceHeight(labelled('1080p WEB')), 1080);
      expect(sourceHeight(labelled('Server 2')), isNull);
    });

    test('a preference picks the best at-or-below server', () {
      final mixed = [
        labelled('Mirror A [2160p]'),
        labelled('Mirror B [1080p]'),
        labelled('Mirror C [480p]'),
      ];
      expect(pickDefault(mixed, preferQuality: '1080p')!.label, 'Mirror B [1080p]');
      expect(pickDefault(mixed, preferQuality: '720p')!.label, 'Mirror C [480p]');
    });

    test('when every server is taller, the lowest one above wins', () {
      final tall = [labelled('A [2160p]'), labelled('B [1440p]')];
      expect(pickDefault(tall, preferQuality: '1080p')!.label, 'B [1440p]');
    });

    test('two servers at the wanted height: discovery order decides', () {
      final same = [labelled('First [720p]'), labelled('Second [720p]')];
      expect(pickDefault(same, preferQuality: '720p')!.label, 'First [720p]');
    });
  });

  group('resolutionPx', () {
    test('reads real resolutions and the usual shorthand', () {
      expect(resolutionPx('1080p'), 1080);
      expect(resolutionPx('4K'), 2160);
      expect(resolutionPx('FHD'), 1080);
    });

    test('names that state no resolution give null', () {
      expect(resolutionPx(null), isNull);
      expect(resolutionPx('auto'), isNull);
      expect(resolutionPx('highest'), isNull);
      expect(resolutionPx('Doodstream'), isNull);
    });
  });
}
