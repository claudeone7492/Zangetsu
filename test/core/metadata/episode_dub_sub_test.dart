import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/episode_dub_sub.dart';
import 'package:watch_app/core/models/episode.dart';

Episode ep(String id, String title, int n) =>
    Episode(id: id, title: title, number: n.toDouble(), url: 'u$n');

void main() {
  test('reads the audio tag and strips it from the name', () {
    expect(EpisodeDubSub.kindOf('Episode 1 (Dub)'), AudioKind.dub);
    expect(EpisodeDubSub.kindOf('Episode 1 [Sub]'), AudioKind.sub);
    expect(EpisodeDubSub.kindOf('Episode 1'), isNull);
    expect(EpisodeDubSub.baseName('Episode 1 (Dub)'), 'Episode 1');
    expect(EpisodeDubSub.baseName('Episode 1 [Legendado]'), 'Episode 1');
  });

  test('merges dub and sub rows into one', () {
    final out = EpisodeDubSub.merge([
      ep('a', 'Episode 1 (Dub)', 1),
      ep('b', 'Episode 1 (Sub)', 1),
      ep('c', 'Episode 2', 2),
    ]);
    expect(out, hasLength(2));
    expect(out.first.title, 'Episode 1 (Dub)');
    expect(out.last.title, 'Episode 2');
  });

  test('leaves an already-unique list untouched', () {
    final rows = [ep('a', 'Pilot', 1), ep('b', 'Second', 2)];
    expect(identical(EpisodeDubSub.merge(rows), rows), isTrue);
  });
}
