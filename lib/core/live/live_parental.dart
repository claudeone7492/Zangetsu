/// Parental controls for live channels.
///
/// Two separate jobs that are easy to conflate:
///
///   • A **rating** on a programme, which the EPG or provider supplies. That
///     decides whether a channel is hidden from a browsing surface.
///   • A **PIN**, which decides whether an adult can reveal it. Reusing the
///     app-lock PIN would be wrong: that gates the whole app, and a household
///     where a child knows the app PIN is exactly the case this exists for.
///
/// So this holds its own salted PIN hash and its own hidden-channel set.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Content ratings, ordered least to most restricted.
///
/// Providers use wildly different scales; these are the buckets they collapse
/// into. [restrictiveness] is the comparison that matters — "is this programme
/// above the household's ceiling".
enum ContentRating {
  /// No rating published.
  unrated(0, 'Unrated'),

  /// Suitable for all — U, TV-Y, G.
  all(1, 'U'),

  /// Parental guidance — PG, TV-PG.
  guidance(2, 'PG'),

  /// 12 and over — 12, TV-14.
  teen(3, '12'),

  /// 15 and over.
  mature(4, '15'),

  /// 18 and over — 18, TV-MA, R.
  adult(5, '18');

  const ContentRating(this.restrictiveness, this.label);

  final int restrictiveness;
  final String label;

  /// True when this rating is above [ceiling] and should be hidden.
  bool exceeds(ContentRating ceiling) =>
      restrictiveness > ceiling.restrictiveness;
}

/// Parse a provider's rating string into a [ContentRating].
///
/// Deliberately forgiving: providers write "TV-MA", "18+", "R", "adult",
/// "Not Rated" and dozens of other spellings, and a rating we fail to parse
/// should hide content rather than reveal it — an unknown "X" is more likely to
/// be explicit than suitable for a child.
ContentRating parseRating(String? raw) {
  if (raw == null) return ContentRating.unrated;
  final s = raw.toLowerCase().trim();
  if (s.isEmpty) return ContentRating.unrated;

  if (s.contains('adult') ||
      s.contains('xxx') ||
      s.contains('explicit') ||
      s == '18' ||
      s == '18+' ||
      s == 'tv-ma' ||
      s == 'r' ||
      s == 'nc-17' ||
      s == 'x') {
    return ContentRating.adult;
  }
  if (s == '15' || s == '15+' || s == 'ma15+') {
    return ContentRating.mature;
  }
  if (s == 'tv-14' || s == '14' || s == '14+') {
    return ContentRating.teen;
  }
  if (s == '12' || s == '12+' || s == 'm' || s == 'pg-13' || s == 'pg13') {
    return ContentRating.teen;
  }
  if (s == 'pg' || s == 'tv-pg' || s == 'parental guidance') {
    return ContentRating.guidance;
  }
  if (s == 'u' ||
      s == 'g' ||
      s == 'tv-y' ||
      s == 'tv-y7' ||
      s == 'tv-g' ||
      s == 'all' ||
      s == 'everyone') {
    return ContentRating.all;
  }
  if (s.contains('not rated') || s == 'nr' || s == 'unrated') {
    return ContentRating.unrated;
  }
  // A number we recognise as 18+ in another spelling, else unknown.
  final digits = int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '');
  if (digits != null) {
    if (digits >= 18) return ContentRating.adult;
    if (digits >= 15) return ContentRating.mature;
    if (digits >= 12) return ContentRating.teen;
  }
  return ContentRating.unrated;
}

/// The parental settings: a PIN, a rating ceiling, and explicit channel hides.
///
/// The PIN is stored as a salted SHA-256 hash in secure storage, the same
/// approach as [AppLock] — a plaintext PIN on disk is not a lock.
class LiveParental extends ChangeNotifier {
  LiveParental({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _pinKey = 'live_parental_pin';
  static const String _saltKey = 'live_parental_salt';
  static const String _ceilingKey = 'live_parental_ceiling';
  static const String _hiddenKey = 'live_parental_hidden';

  final FlutterSecureStorage _storage;

  ContentRating _ceiling = ContentRating.adult;
  final Set<String> _hiddenChannels = {};
  bool _pinSet = false;
  bool _unlocked = false;
  var _loaded = false;

  /// The highest rating shown without unlocking. Defaults to [ContentRating.adult]
  /// so a fresh install hides nothing until a parent chooses to.
  ContentRating get ceiling => _ceiling;

  /// Channels explicitly hidden regardless of rating — the "hide this one"
  /// list, for a channel whose rating the provider never published.
  Set<String> get hiddenChannels => Set.unmodifiable(_hiddenChannels);

  bool get pinSet => _pinSet;

  /// True while this session has been unlocked. Reset on app background, not
  /// persisted, so a PIN is required again next launch.
  bool get unlocked => _unlocked;

  /// True when nothing is being restricted — lets callers skip filtering.
  bool get isInactive =>
      _ceiling == ContentRating.adult && _hiddenChannels.isEmpty;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final ceiling = await _storage.read(key: _ceilingKey);
      _ceiling = ContentRating.values.firstWhere(
        (r) => r.name == ceiling,
        orElse: () => ContentRating.adult,
      );
      final pin = await _storage.read(key: _pinKey);
      _pinSet = pin != null && pin.isNotEmpty;
      final hidden = await _storage.read(key: _hiddenKey);
      if (hidden != null && hidden.isNotEmpty) {
        final decoded = jsonDecode(hidden);
        if (decoded is List) {
          _hiddenChannels.addAll(decoded.whereType<String>());
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[parental] load failed: $e');
    }
  }

  /// Set or replace the PIN. Requires the current PIN when one already exists,
  /// so a child can't change the lock they can't open.
  Future<bool> setPin(String pin, {String? current}) async {
    await ensureLoaded();
    if (pin.trim().length < 4) return false;
    if (_pinSet) {
      if (current == null || !await verifyPin(current)) return false;
    }
    final salt = _newSalt();
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _pinKey, value: _hash(pin, salt));
    _pinSet = true;
    notifyListeners();
    return true;
  }

  /// Check [pin] and, on success, unlock this session.
  Future<bool> verifyPin(String pin) async {
    await ensureLoaded();
    final salt = await _storage.read(key: _saltKey);
    final stored = await _storage.read(key: _pinKey);
    if (salt == null || stored == null) return false;
    final ok = _hash(pin, salt) == stored;
    if (ok) {
      _unlocked = true;
      notifyListeners();
    }
    return ok;
  }

  /// Re-lock without forgetting the PIN.
  void lock() {
    if (!_unlocked) return;
    _unlocked = false;
    notifyListeners();
  }

  /// Remove the PIN entirely. Requires it, so the lock can't be removed by
  /// someone who can't open it.
  Future<bool> clearPin(String current) async {
    if (!await verifyPin(current)) return false;
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _saltKey);
    _pinSet = false;
    _unlocked = true;
    notifyListeners();
    return true;
  }

  Future<void> setCeiling(ContentRating rating) async {
    await ensureLoaded();
    if (_ceiling == rating) return;
    _ceiling = rating;
    await _storage.write(key: _ceilingKey, value: rating.name);
    notifyListeners();
  }

  /// Hide or show one channel by id. Persisted as a set.
  Future<void> setHidden(String channelId, bool hidden) async {
    await ensureLoaded();
    if (channelId.trim().isEmpty) return;
    final changed = hidden
        ? _hiddenChannels.add(channelId)
        : _hiddenChannels.remove(channelId);
    if (!changed) return;
    await _storage.write(key: _hiddenKey, value: jsonEncode(_hiddenChannels.toList()));
    notifyListeners();
  }

  /// Whether a channel with [rating] and [channelId] should be visible now.
  ///
  /// An unlocked session sees everything: the PIN is the escape hatch, and a
  /// parent who has just entered it shouldn't have to fight the filter.
  bool isVisible({required ContentRating rating, String? channelId}) {
    if (_unlocked) return true;
    if (channelId != null && _hiddenChannels.contains(channelId)) return false;
    return !rating.exceeds(_ceiling);
  }

  /// Filter a list of items by their rating, keeping the visible ones.
  List<T> filter<T>(
    Iterable<T> items, {
    required ContentRating Function(T) ratingOf,
    String? Function(T)? channelIdOf,
  }) {
    if (isInactive || _unlocked) return items.toList();
    return [
      for (final item in items)
        if (isVisible(
          rating: ratingOf(item),
          channelId: channelIdOf?.call(item),
        ))
          item,
    ];
  }

  static String _newSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
