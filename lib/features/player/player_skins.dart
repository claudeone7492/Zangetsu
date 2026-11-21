
/// The player's visual skin.
enum PlayerSkin { classic, glass, minimal }

class PlayerSkinSpec {
  const PlayerSkinSpec({
    required this.skin,
    required this.scrimOpacity,
    required this.panelOpacity,
    required this.showTitle,
  });

  final PlayerSkin skin;
  final double scrimOpacity;
  final double panelOpacity;
  final bool showTitle;
}

class PlayerSkins {
  const PlayerSkins._();

  static const Map<PlayerSkin, PlayerSkinSpec> specs = {
    PlayerSkin.classic: PlayerSkinSpec(
      skin: PlayerSkin.classic,
      scrimOpacity: 0.55,
      panelOpacity: 0.85,
      showTitle: true,
    ),
    PlayerSkin.glass: PlayerSkinSpec(
      skin: PlayerSkin.glass,
      scrimOpacity: 0.25,
      panelOpacity: 0.45,
      showTitle: true,
    ),
    PlayerSkin.minimal: PlayerSkinSpec(
      skin: PlayerSkin.minimal,
      scrimOpacity: 0.15,
      panelOpacity: 0.6,
      showTitle: false,
    ),
  };

  static PlayerSkinSpec of(PlayerSkin skin) => specs[skin]!;

  /// The skin a stored name refers to, falling back to [PlayerSkin.classic] so
  /// a value written by a future build cannot break the overlay.
  static PlayerSkin parse(String? value) => PlayerSkin.values.firstWhere(
    (skin) => skin.name == value,
    orElse: () => PlayerSkin.classic,
  );
}
