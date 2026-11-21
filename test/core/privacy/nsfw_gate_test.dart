import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/privacy/nsfw_gate.dart';

void main() {
  tearDown(() => NsfwGate.setHideAdult(false));

  test('shows everything by default', () {
    final items = ['Normal Show', 'Hentai Academy'];
    expect(
      NsfwGate.filter(items, title: (e) => e),
      ['Normal Show', 'Hentai Academy'],
    );
  });

  test('hides adult titles when enabled', () {
    NsfwGate.setHideAdult(true);
    final items = ['Normal Show', 'Hentai Academy', '18+ Cut'];
    expect(
      NsfwGate.filter(items, title: (e) => e),
      ['Normal Show'],
    );
  });

  test('honours an explicit adult flag', () {
    NsfwGate.setHideAdult(true);
    expect(
      NsfwGate.filter(
        ['Anything'],
        title: (e) => e,
        flagged: (_) => true,
      ),
      isEmpty,
    );
  });

  test('recognises the usual markers', () {
    expect(NsfwGate.isAdultTitle('Ecchi Club'), isTrue);
    expect(NsfwGate.isAdultTitle('R18 version'), isTrue);
    expect(NsfwGate.isAdultTitle('Adventure Time'), isFalse);
  });
}
