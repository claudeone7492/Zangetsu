import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/player/player_skins.dart';

void main() {
  test('every skin has a spec', () {
    for (final skin in PlayerSkin.values) {
      expect(PlayerSkins.of(skin).skin, skin);
    }
  });

  test('minimal hides the title and dims least', () {
    final minimal = PlayerSkins.of(PlayerSkin.minimal);
    final classic = PlayerSkins.of(PlayerSkin.classic);
    expect(minimal.showTitle, isFalse);
    expect(minimal.scrimOpacity, lessThan(classic.scrimOpacity));
  });
}
