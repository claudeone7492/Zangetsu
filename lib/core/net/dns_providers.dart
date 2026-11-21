import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../hive/safe_box.dart';

/// One DNS entry, ported from Hikari's `net/DnsProviders.kt`.
@immutable
class DnsProvider {
  const DnsProvider(
    this.key,
    this.label, {
    this.url = '',
    this.bootstrap = const [],
    this.plain = const [],
    this.note = '',
  });

  /// Stable id, persisted.
  final String key;
  final String label;

  /// The DNS-over-HTTPS endpoint. Empty for [DnsProviders.system], for
  /// [DnsProviders.custom] until the user writes one, and for the resolvers
  /// that offer no encrypted service at all (they carry [plain] instead).
  final String url;

  /// Known addresses of [url]'s own host, so resolving it needs no DNS.
  final List<String> bootstrap;

  /// Servers that answer plain, unencrypted DNS on port 53.
  final List<String> plain;

  /// One line under the name in Settings.
  final String note;

  /// True when this entry actually names a server.
  bool get usable => url.isNotEmpty || plain.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is DnsProvider &&
      other.key == key &&
      other.url == url &&
      other.label == label;

  @override
  int get hashCode => Object.hash(key, url, label);
}

/// The provider list and the user's choice, ported from
/// Hikari's `net/DnsProviders.kt` and `NetTuning.activeDns()`.
class DnsProviders {
  const DnsProviders._();

  /// Ask the phone's own resolver first — the app's behaviour before this
  /// setting existed, and still the default.
  static const String system = 'system';

  /// A URL the user typed.
  static const String custom = 'custom';

  static const String boxName = 'dns_prefs';
  static const String _choiceKey = 'dnsProvider';
  static const String _customKey = 'customDns';

  /// Bumped when the choice changes, so the resolver drops its caches.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const List<DnsProvider> all = [
    DnsProvider(
      system,
      'Automatic (this phone)',
      note: "Use the phone's own DNS, with the built-in encrypted fallback "
          "for names it can't answer.",
    ),
    DnsProvider(
      'cloudflare',
      'Cloudflare',
      url: 'https://cloudflare-dns.com/dns-query',
      bootstrap: ['1.1.1.1', '1.0.0.1'],
      note: 'Fast, no filtering, logs dropped after 24 hours.',
    ),
    DnsProvider(
      'google',
      'Google',
      url: 'https://dns.google/dns-query',
      bootstrap: ['8.8.8.8', '8.8.4.4'],
      note: 'Google Public DNS — very fast, no filtering.',
    ),
    DnsProvider(
      'adguard',
      'AdGuard',
      url: 'https://dns.adguard-dns.com/dns-query',
      bootstrap: ['94.140.14.14', '94.140.15.15'],
      note: 'Blocks ads and trackers at the DNS level.',
    ),
    DnsProvider(
      'quad9',
      'Quad9',
      url: 'https://dns.quad9.net/dns-query',
      bootstrap: ['9.9.9.9', '149.112.112.112'],
      note: 'Blocks known malicious domains.',
    ),
    DnsProvider(
      'dnssb',
      'DNS.SB',
      url: 'https://doh.sb/dns-query',
      bootstrap: ['185.222.222.222', '45.11.45.11'],
      note: 'No filtering, no logging.',
    ),
    DnsProvider(
      'mullvad',
      'Mullvad',
      url: 'https://doh.mullvad.net/dns-query',
      note: 'Privacy-first, no logging.',
    ),
    DnsProvider(
      'canadianshield',
      'Canadian Shield',
      url: 'https://private.canadianshield.cira.ca/dns-query',
      note: "CIRA's resolver — blocks malware, not content.",
    ),
    DnsProvider(
      'cleanbrowsing',
      'CleanBrowsing (family)',
      url: 'https://doh.cleanbrowsing.org/doh/family-filter/',
      note: 'Filters adult content.',
    ),
    DnsProvider(
      'dnswatch',
      'DNS.WATCH',
      plain: ['84.200.69.80', '84.200.70.40'],
      note: 'Plain DNS only — free, no filtering, no logging, but the answers '
          'travel unencrypted. Pick an encrypted option instead if you can.',
    ),
    DnsProvider(
      custom,
      'Custom',
      note: 'Point the app at any DNS-over-HTTPS address you like.',
    ),
  ];

  static String _choice = system;
  static String _custom = '';

  static String get choice => _choice;
  static String get customUrl => _custom;

  /// The entry a stored key refers to, falling back to [system] so a key from
  /// a newer build can never leave the app without a resolver.
  static DnsProvider byKey(String? key) =>
      all.firstWhere((p) => p.key == key, orElse: () => all.first);

  /// The provider actually in force: [byKey] with the typed URL filled in for
  /// [custom], or null when the phone's own resolver should be used.
  static DnsProvider? get active {
    final chosen = byKey(_choice);
    if (chosen.key == system) return null;
    if (chosen.key == custom) return customEndpoint(_custom);
    return chosen;
  }

  /// The endpoint a user-typed string means, or null if it isn't usable.
  ///
  /// Bare hosts get `https://` and a `/dns-query` path so "1.1.1.1" or
  /// "dns.example.com" both work, and anything pasted from a browser (a
  /// `?dns=…` query, a fragment) is stripped rather than sent.
  static DnsProvider? customEndpoint(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'https://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final path = uri.path.isEmpty || uri.path == '/' ? '/dns-query' : uri.path;
    // Rebuilt rather than `replace`d: `replace(query: null)` keeps the old
    // query and `replace(query: '')` prints a bare '?#', so neither strips.
    final clean = Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    );
    return DnsProvider(custom, 'Custom', url: clean.toString());
  }

  static Future<void> load() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<dynamic>(boxName);
    final box = Hive.box<dynamic>(boxName);
    _choice = box.get(_choiceKey, defaultValue: system) as String? ?? system;
    _custom = box.get(_customKey, defaultValue: '') as String? ?? '';
  }

  static Future<void> setChoice(String key, {String? customUrl}) async {
    _choice = byKey(key).key;
    if (customUrl != null) _custom = customUrl.trim();
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<dynamic>(boxName);
    final box = Hive.box<dynamic>(boxName);
    await box.put(_choiceKey, _choice);
    await box.put(_customKey, _custom);
    revision.value++;
  }

  @visibleForTesting
  static void resetForTest() {
    _choice = system;
    _custom = '';
  }
}
