import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/episode.dart';
import '../models/home_section.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../models/provider_info.dart';
import '../models/video_source.dart';
import '../provider/base_provider.dart';
import 'hikari_mapping.dart';

/// Native MethodChannel for `.hiki` extensions. Android-only; every call is
/// guarded so a non-Android platform or a broken extension degrades to an empty
/// result rather than throwing into the UI.
const MethodChannel hikariChannel = MethodChannel('zangetsu/hikari');

/// Metadata the native host reports after loading a `.hiki` file.
class HikariLoadedInfo {
  const HikariLoadedInfo({
    required this.name,
    required this.version,
    required this.mainClass,
    required this.providerId,
    required this.providerName,
    required this.mainUrl,
    required this.description,
    required this.iconUrl,
    required this.tvTypes,
  });

  final String name;
  final int version;
  final String mainClass;
  final String providerId;
  final String providerName;
  final String mainUrl;
  final String description;
  final String? iconUrl;
  final List<String> tvTypes;

  factory HikariLoadedInfo.fromMap(Map<Object?, Object?> map) => HikariLoadedInfo(
    name: '${map['name'] ?? ''}',
    version: map['version'] is int ? map['version'] as int : 1,
    mainClass: '${map['mainClass'] ?? ''}',
    providerId: '${map['providerId'] ?? ''}',
    providerName: '${map['providerName'] ?? ''}',
    mainUrl: '${map['mainUrl'] ?? ''}',
    description: '${map['description'] ?? ''}',
    iconUrl: map['iconUrl'] is String && (map['iconUrl'] as String).isNotEmpty
        ? map['iconUrl'] as String
        : null,
    tvTypes: [
      if (map['tvTypes'] is List)
        for (final t in map['tvTypes'] as List) '$t',
    ],
  );
}

/// Loads a `.hiki` file in the native host and returns its metadata.
///
/// Throws a [PlatformException] carrying the native message when the extension
/// is malformed, so the install flow can show why instead of "failed".
Future<HikariLoadedInfo?> hikariLoad(String path) async {
  if (!Platform.isAndroid) return null;
  final result = await hikariChannel.invokeMapMethod<Object?, Object?>(
    'load',
    {'path': path},
  );
  if (result == null) return null;
  return HikariLoadedInfo.fromMap(result);
}

/// Unloads a `.hiki` from the native provider cache.
Future<void> hikariUnload(String path) async {
  if (!Platform.isAndroid) return;
  try {
    await hikariChannel.invokeMethod('unload', {'path': path});
  } catch (_) {
    // Nothing to unload is not an error.
  }
}

/// A `.hiki` extension surfaced as a normal [BaseProvider].
class HikariProviderAdapter implements BaseProvider {
  HikariProviderAdapter({
    required this.path,
    required this.info,
    required this.lang,
  });

  /// Absolute path of the installed `.hiki` file — the native cache key.
  final String path;

  final HikariLoadedInfo info;
  final String lang;

  @override
  String get sourceId => 'hiki:${info.providerId.isEmpty ? info.name : info.providerId}';

  @override
  String get displayName => info.providerName.isEmpty ? info.name : info.providerName;

  /// The extension's own site, used for the Cloudflare/browser actions. Item
  /// urls from a Hikari provider are already absolute, so this never turns a
  /// relative url absolute.
  String get mainUrl => info.mainUrl;

  /// What this extension scrapes. A series-scraper reads as anime, a
  /// film-scraper as movie — the same distinction [hikariMediaItem] makes per
  /// row, applied to the whole source for the mode buckets.
  ProviderType get providerType =>
      info.tvTypes.any((t) => t.toLowerCase() != 'movie')
      ? ProviderType.anime
      : ProviderType.movie;

  Map<String, dynamic> get _base => {'path': path};

  @override
  Future<ProviderInfo> getInfo() async => ProviderInfo(
    name: displayName,
    lang: lang,
    baseUrl: info.mainUrl,
    logo: info.iconUrl,
    type: providerType,
    version: '${info.version}',
  );

  /// Hikari catalogues are the extension's own Home rows.
  @override
  Future<List<HomeSection>?> getHome({String category = 'sub'}) async {
    final catalogs = await _callList('catalogs');
    if (catalogs.isEmpty) return null;
    final sections = <HomeSection>[];
    for (final catalog in catalogs) {
      final items = await _callList('catalog', {
        ..._base,
        'catalog': jsonEncode(catalog),
        'page': 1,
      });
      final mapped = _mapItems(items);
      if (mapped.isEmpty) continue;
      sections.add(
        HomeSection(
          title: '${catalog['name'] ?? 'Untitled'}',
          items: mapped,
          more: BrowseMore(
            sourceId: sourceId,
            kind: 'hiki_catalog',
            categoryId: '${catalog['id']}',
          ),
        ),
      );
    }
    return sections.isEmpty ? null : sections;
  }

  /// One page of a named catalogue — the `hiki_catalog` "See all" target.
  ///
  /// [catalogJson] is the encoded [HikariCatalog] the Home row was built from,
  /// so a row keeps browsing the same catalogue rather than falling back to
  /// the provider's first one.
  Future<List<MediaItem>> catalogPage(String catalogJson, int page) async {
    final items = await _callList('catalog', {
      ..._base,
      'catalog': catalogJson,
      'page': page,
    });
    return _mapItems(items);
  }

  @override
  Future<List<MediaItem>> popular({
    String category = 'sub',
    int dateRange = 7,
    int page = 1,
  }) async {
    final catalogs = await _callList('catalogs');
    if (catalogs.isEmpty) return const [];
    final items = await _callList('catalog', {
      ..._base,
      'catalog': jsonEncode(catalogs.first),
      'page': page,
    });
    return _mapItems(items);
  }

  @override
  Future<List<MediaItem>> search(
    String query,
    int page, {
    String category = '',
  }) async {
    final items = await _callList('search', {
      ..._base,
      'query': query,
      'page': page,
    });
    return _mapItems(items);
  }

  @override
  Future<MediaDetail> getDetail(String url, {String category = 'sub'}) async {
    final media = hikariMediaFromDetailUrl(url) ?? <String, dynamic>{};
    final full = await _callMap('meta', {..._base, 'media': jsonEncode(media)});
    final resolved = full ?? media;
    final episodes = await getEpisodes(url, category: category);
    return hikariMediaDetail(resolved, sourceId: sourceId, episodes: episodes);
  }

  @override
  Future<List<Episode>> getEpisodes(String url, {String category = 'sub'}) async {
    final media = hikariMediaFromDetailUrl(url);
    if (media == null) return const [];
    final raw = await _callList('episodes', {..._base, 'media': jsonEncode(media)});
    if (raw.isEmpty) {
      // A movie: Hikari models no episodes, so expose one tappable entry.
      return [hikariEpisode(media, null, sourceId: sourceId)];
    }
    return [
      for (final e in raw) hikariEpisode(media, e, sourceId: sourceId),
    ];
  }

  @override
  Future<List<VideoSource>> getVideoSources(
    String episodeUrl, {
    bool fast = false,
  }) async {
    final packed = hikariEpisodeFromUrl(episodeUrl);
    if (packed == null) return const [];
    final raw = await _callList('streams', {
      ..._base,
      'media': jsonEncode(packed.media),
      'episode': packed.episode == null ? null : jsonEncode(packed.episode),
    });
    return [
      for (final s in raw) ?hikariVideoSource(s),
    ];
  }

  List<MediaItem> _mapItems(List<Map<String, dynamic>> raw) => [
    for (final json in raw)
      hikariMediaItem(json, sourceId: sourceId, providerName: displayName),
  ];

  /// Invokes [method] and normalises the result to a list of maps. A failed
  /// extension call is reported as "no results" rather than an exception: one
  /// broken extension must not break Home.
  Future<List<Map<String, dynamic>>> _callList(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    if (!Platform.isAndroid) return const [];
    try {
      final result = await hikariChannel.invokeMethod<Object?>(method, args);
      if (result is! List) return const [];
      return [
        for (final e in result)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } on PlatformException {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> _callMap(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await hikariChannel.invokeMapMethod<Object?, Object?>(
        method,
        args,
      );
      return result == null ? null : Map<String, dynamic>.from(result);
    } on PlatformException {
      return null;
    }
  }
}
