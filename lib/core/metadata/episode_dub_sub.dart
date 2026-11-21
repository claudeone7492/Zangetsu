import '../models/episode.dart';

enum AudioKind { dub, sub }

/// Collapses episode rows that differ only by their audio tag.
///
/// A source often lists `Episode 1 (Dub)` and `Episode 1 (Sub)` as two rows,
/// which doubles the list and makes the numbers look wrong. Hikari's
/// `EpisodeDubSub` keeps one row and records the available audio. This is the
/// same rule over Zangetsu's `Episode.title`.
class EpisodeDubSub {
  const EpisodeDubSub._();

  static final RegExp _dub = RegExp(
    r'\b(dub(?:bed)?|english\s*dub|latino|doblaje|castellano)\b',
    caseSensitive: false,
  );
  static final RegExp _sub = RegExp(
    r'\b(sub(?:bed|title)?s?|legendado|vostfr|softsub)\b',
    caseSensitive: false,
  );
  static final RegExp _bracketAudio = RegExp(r'[\(\[]([^\)\]]*?)[\)\]]');

  static AudioKind? kindOf(String? title) {
    final text = title ?? '';
    if (text.isEmpty) return null;
    if (_dub.hasMatch(text)) return AudioKind.dub;
    if (_sub.hasMatch(text)) return AudioKind.sub;
    return null;
  }

  static String baseName(String? title) {
    var name = (title ?? '').trim();
    if (name.isEmpty) return '';
    name = name.replaceAllMapped(_bracketAudio, (m) {
      final inner = m.group(1) ?? '';
      return _dub.hasMatch(inner) || _sub.hasMatch(inner) ||
              inner.trim().toLowerCase() == 'audio'
          ? ' '
          : m.group(0)!;
    });
    name = name.replaceAll(_dub, ' ').replaceAll(_sub, ' ');
    name = name.replaceAll(
      RegExp(r'\boriginal\s+audio\b', caseSensitive: false),
      ' ',
    );
    return name
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^[-–—:·|\s]+|[-–—:·|\s]+$'), '');
  }

  static List<Episode> merge(List<Episode> episodes) {
    if (episodes.isEmpty) return episodes;
    final groups = <String, List<Episode>>{};
    final order = <String>[];
    for (final episode in episodes) {
      final base = baseName(episode.title).toLowerCase();
      final key = '${episode.number ?? ''}|$base';
      if (!groups.containsKey(key)) order.add(key);
      groups.putIfAbsent(key, () => []).add(episode);
    }
    if (groups.length == episodes.length) return episodes;

    final out = <Episode>[];
    for (final key in order) {
      final group = groups[key]!;
      if (group.length == 1) {
        out.add(group.first);
        continue;
      }
      final kinds = group.map((e) => kindOf(e.title)).whereType<AudioKind>().toSet();
      final keep = group.firstWhere(
        (e) => kindOf(e.title) == AudioKind.dub,
        orElse: () => group.first,
      );
      final label = kinds.contains(AudioKind.dub)
          ? 'Dub'
          : (kinds.contains(AudioKind.sub) ? 'Sub' : null);
      final base = baseName(keep.title);
      out.add(
        keep.copyWith(
          title: label == null ? base : '$base ($label)',
        ),
      );
    }
    out.sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0));
    return out;
  }
}
