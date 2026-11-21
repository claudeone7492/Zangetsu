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

  test('glass and minimal lighten the button groups, classic keeps 0.3', () {
    final classic = PlayerSkins.of(PlayerSkin.classic);
    final glass = PlayerSkins.of(PlayerSkin.glass);
    final minimal = PlayerSkins.of(PlayerSkin.minimal);
    expect(PlayerSkins.groupOpacity(classic), closeTo(0.3, 1e-9));
    expect(PlayerSkins.groupOpacity(glass), lessThan(0.3));
    expect(PlayerSkins.groupOpacity(minimal), lessThan(0.3));
    expect(
      PlayerSkins.groupOpacity(minimal),
      greaterThan(PlayerSkins.groupOpacity(glass)),
      reason: 'minimal is the mid-weight panel, not the lightest',
    );
  });

  test('a stored name that is not a skin falls back to classic', () {
    expect(PlayerSkins.parse('glass'), PlayerSkin.glass);
    expect(PlayerSkins.parse('minimal'), PlayerSkin.minimal);
    expect(PlayerSkins.parse('neon-from-the-future'), PlayerSkin.classic);
    expect(PlayerSkins.parse(null), PlayerSkin.classic);
  });

  test('every group opacity is a usable alpha', () {
    for (final skin in PlayerSkin.values) {
      final alpha = PlayerSkins.groupOpacity(PlayerSkins.of(skin));
      expect(alpha, greaterThan(0));
      expect(alpha, lessThan(1));
    }
  });
}
