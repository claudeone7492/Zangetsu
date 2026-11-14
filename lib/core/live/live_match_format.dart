// Pure helpers for live-sports card enrichment.
//
// The streams themselves come from the sports sources; the score, clock and
// status come from a keyless scoreboard (see LiveMatchEnrichment). This file
// holds the two decisions that need to be right and are worth testing on their
// own: which scoreboard row belongs to a fixture, and how its numbers read on
// the card.

/// Statuses a scoreboard uses while a match is being played. Anything here maps
/// to the card's LIVE treatment; everything else is treated as "not started"
/// (keep the source's own countdown) or "finished" (FT).
const Set<String> kLiveStatuses = {
  '1H',
  '2H',
  'HT',
  'ET',
  'BT',
  'PEN',
  'LIVE',
  'INT',
};

/// Normalizes a team name to its comparison tokens: lowercased, accents folded
/// to ASCII, punctuation dropped, and the club-noise words that appear on one
/// side of a fixture but not the other (`fc`, `cf`, `sc`, `ac`, the age-suffix
/// `b`/`ii`) removed.
List<String> teamTokens(String name) {
  final folded = _fold(name);
  final raw = folded
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .split(' ')
      .where((t) => t.isNotEmpty);
  const noise = {'fc', 'cf', 'sc', 'ac', 'afc', 'club', 'the'};
  final out = <String>[];
  for (final t in raw) {
    if (noise.contains(t)) continue;
    // A trailing roman-numeral / letter side ("Slovácko B") is not the club.
    if (RegExp(r'^(i{1,3}|iv|v|vi|b|ii)$').hasMatch(t)) continue;
    out.add(t);
  }
  return out.isEmpty ? raw.toList() : out;
}

/// How alike two team names are, 0..1. Token-set overlap, so "Slovácko B"
/// matches "Slovacko" and "FC Barcelona" matches "Barcelona", while "United"
/// alone does not match "City".
double teamSimilarity(String a, String b) {
  final ta = teamTokens(a).toSet();
  final tb = teamTokens(b).toSet();
  if (ta.isEmpty || tb.isEmpty) return 0;
  final inter = ta.intersection(tb).length;
  return inter / (ta.length < tb.length ? ta.length : tb.length);
}

/// Index of the scoreboard row in [fixtures] that best matches a fixture card
/// titled [title], or -1 when none clears the bar. Each row is `[home, away]`.
///
/// A fixture title is usually "Home vs Away", so each row is scored in both
/// orders and the better one wins; a row must reach [min] on *both* teams, which
/// is what keeps "Arsenal vs Chelsea" from matching "Arsenal vs Tottenham".
int bestFixtureMatch(
  String title,
  List<List<String>> fixtures, {
  double min = 0.5,
}) {
  final text = _fold(title);
  var best = -1;
  var bestScore = 0.0;
  for (var i = 0; i < fixtures.length; i++) {
    final row = fixtures[i];
    if (row.length < 2) continue;
    final home = row[0], away = row[1];
    final forward = [
      teamSimilarity(text, home),
      teamSimilarity(text, away),
    ];
    final reverse = [
      teamSimilarity(text, away),
      teamSimilarity(text, home),
    ];
    final fMin = forward[0] < forward[1] ? forward[0] : forward[1];
    final rMin = reverse[0] < reverse[1] ? reverse[0] : reverse[1];
    final score = fMin > rMin ? fMin : rMin;
    if (score >= min && score > bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return best;
}

/// The card's second line for a scoreboard row, or null when the row adds
/// nothing a source wouldn't already say (a fixture that hasn't kicked off).
///
/// [status] is the scoreboard's raw status; [clock] is its own display string
/// for the live minute ("67'", "HT"), used verbatim when present.
String? liveMatchInfo({
  required String home,
  required String away,
  required int? homeScore,
  required int? awayScore,
  required String status,
  String? clock,
}) {
  final live = kLiveStatuses.contains(status.toUpperCase());
  final finished = status.toUpperCase() == 'FT';
  if (!live && !finished) return null;
  final hs = homeScore, as = awayScore;
  final score = (hs != null && as != null) ? ' $hs-$as ' : ' v ';
  final tail = live
      ? (clock != null && clock.isNotEmpty ? clock : status)
      : 'FT';
  return '$home$score$away \u00B7 $tail';
}

/// Whether a fixture title already carries a score ("Home 2 - 1 Away"). A
/// source that prints the score on the card (MovieBox does) has nothing to gain
/// from the scoreboard and everything to lose — enriching it would drop the
/// league line the source wrote in favour of a bare score. Only scoreless cards
/// (StreamFree's "Home vs Away") are worth a scoreboard lookup.
bool hasInlineScore(String title) =>
    RegExp(r'\d\s*-\s*\d').hasMatch(title);

/// The countdown badge for a fixture that hasn't kicked off, recomputed from
/// its kickoff so the card stays honest while the rail sits on screen. Null
/// once kickoff has passed — the scoreboard (or the source's LIVE flag) takes
/// over then.
String? liveCountdown(int startMs, DateTime now) {
  final secs = (startMs - now.millisecondsSinceEpoch) ~/ 1000;
  if (secs <= 0) return null;
  final mins = secs ~/ 60;
  final days = mins ~/ 1440;
  if (days >= 1) return 'in ${days}d';
  final hours = mins ~/ 60;
  if (hours >= 1) return 'in ${hours}h ${mins % 60}m';
  return 'in ${mins}m';
}

/// Lowercases and strips combining diacritics so "Slovácko" → "slovacko".
String _fold(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿāăąēĕėęěĭīįıōŏőūŭůűųǖǘǚǜ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyaaaaaaeeeeiiiiioooouuuuuuuu';
  final lower = s.toLowerCase();
  final buf = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final idx = from.indexOf(ch);
    buf.write(idx >= 0 ? to[idx] : ch);
  }
  return buf.toString();
}
