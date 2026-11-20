/// Single source of truth for the music catalogue's shape.
///
/// The base URL, the home rows, their row limits and the catalogue's stable id
/// all live here rather than inline in [JioSaavnSource] so a fork (or a mirror
/// whose host moved) changes one constant, and so the service, the models and
/// the UI agree on the same id without repeating the literal.
library;

/// Stable id stamped on every track this catalogue produces and used to route a
/// track back to its source at play time. Changing it orphans anything already
/// persisted under the old id, so treat it as a wire value.
const String kMusicSourceId = 'jiosaavn';

/// Human-readable catalogue name for the settings row and error messages.
const String kMusicSourceName = 'JioSaavn';

/// Catalogue root. Overridable at build time because the community mirror this
/// points at is not operated by us: a dead host must not need a code change.
const String kMusicApiBaseUrl = String.fromEnvironment(
  'MUSIC_API_BASE_URL',
  defaultValue: 'https://saavn.dev/api',
);

/// One home row: the catalogue query behind it, plus a stable [id] the UI uses
/// to look up a localised heading. [fallbackTitle] is what a source that does
/// not know [id] shows — an unknown row still renders, just untranslated.
class MusicHomeRow {
  const MusicHomeRow({
    required this.id,
    required this.query,
    required this.fallbackTitle,
  });

  final String id;
  final String query;
  final String fallbackTitle;
}

/// The home rows, in display order. Each is one catalogue query, which is why
/// this is the only place a row's search term appears.
const List<MusicHomeRow> kMusicHomeRows = [
  MusicHomeRow(id: 'trending', query: 'trending', fallbackTitle: 'Trending'),
  MusicHomeRow(
    id: 'newReleases',
    query: 'new releases',
    fallbackTitle: 'New releases',
  ),
  MusicHomeRow(id: 'lofi', query: 'lofi', fallbackTitle: 'Lo-fi'),
];

/// How many tracks each home row asks for.
const int kMusicRowLimit = 20;

/// How many tracks a search page asks for.
const int kMusicSearchLimit = 30;
