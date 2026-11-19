import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/hive/safe_box.dart';

import '../models/home_section.dart';
import '../models/media_item.dart';

/// A hand-made Home row: a name the user chose, filled with titles they picked.
///
/// Three levels, as CloudStream's personal catalogues have:
///   collection → folder → source
/// A collection is the row itself. A folder groups titles inside it (a season,
/// a mood, "rewatch someday"); the folder is also what a catalogue source
/// answers with. A folder with a `query` refills itself from the active source
/// instead of holding fixed titles, which is how a collection stays useful
/// without being maintained by hand.
///
/// Stored flat: one JSON-ish map per collection in a Hive box, so a corrupt
/// entry costs that collection and nothing else.
@immutable
class Collection {
  const Collection({
    required this.id,
    required this.name,
    this.folders = const [],
    this.position = 0,
    this.hidden = false,
  });

  final String id;
  final String name;
  final List<CollectionFolder> folders;
  final int position;

  /// Hidden collections keep their contents but leave Home — deleting the row
  /// is destructive and irreversible, hiding is not.
  final bool hidden;

  bool get isEmpty => folders.every((f) => f.items.isEmpty && f.query == null);

  Collection copyWith({
    String? name,
    List<CollectionFolder>? folders,
    int? position,
    bool? hidden,
  }) => Collection(
    id: id,
    name: name ?? this.name,
    folders: folders ?? this.folders,
    position: position ?? this.position,
    hidden: hidden ?? this.hidden,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'position': position,
    'hidden': hidden,
    'folders': [for (final f in folders) f.toMap()],
  };

  /// Parse a stored collection, or null when the entry is unusable.
  ///
  /// Tolerant by design: a folder that fails to parse is dropped rather than
  /// taking the whole collection with it, because a single bad record should
  /// not read as "all my collections are gone".
  static Collection? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;
    final folders = <CollectionFolder>[];
    final rawFolders = raw['folders'];
    if (rawFolders is List) {
      for (final f in rawFolders) {
        final folder = CollectionFolder.fromMap(f);
        if (folder != null) folders.add(folder);
      }
    }
    return Collection(
      id: id,
      name: name,
      folders: folders,
      position: (raw['position'] as num?)?.toInt() ?? 0,
      hidden: raw['hidden'] == true,
    );
  }

  /// The collection as a Home row. A collection with nothing in it is still a
  /// row (the UI shows it as empty rather than silently vanishing, so the user
  /// can see what they made).
  HomeSection toSection() => HomeSection(
    title: name,
    items: [
      for (final folder in folders)
        for (final item in folder.items) item,
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is Collection &&
      other.id == id &&
      other.name == name &&
      other.position == position &&
      other.hidden == hidden &&
      listEquals(other.folders, folders);

  @override
  int get hashCode => Object.hash(id, name, position, hidden, folders.length);
}

/// A group of titles inside a collection. Either fixed ([items]) or live
/// ([query] against the active source), never both meaningfully — a query
/// folder refills on load and keeps whatever it last fetched as its items.
@immutable
class CollectionFolder {
  const CollectionFolder({
    required this.id,
    required this.name,
    this.items = const [],
    this.query,
  });

  final String id;
  final String name;
  final List<MediaItem> items;

  /// When set, the folder is a saved search: the store asks the source for
  /// this text and replaces [items] with the result. Null means the folder
  /// holds exactly the titles the user put in it.
  final String? query;

  bool get isLive => query != null && query!.trim().isNotEmpty;

  CollectionFolder copyWith({
    String? name,
    List<MediaItem>? items,
    String? query,
  }) => CollectionFolder(
    id: id,
    name: name ?? this.name,
    items: items ?? this.items,
    query: query ?? this.query,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    if (query != null) 'query': query,
    'items': [for (final i in items) i.toJson()],
  };

  static CollectionFolder? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;
    final items = <MediaItem>[];
    final rawItems = raw['items'];
    if (rawItems is List) {
      for (final i in rawItems) {
        if (i is! Map) continue;
        try {
          items.add(MediaItem.fromJson(Map<String, dynamic>.from(i)));
        } catch (_) {
          // One unreadable title drops itself, not the folder.
        }
      }
    }
    final query = raw['query'];
    return CollectionFolder(
      id: id,
      name: name,
      items: items,
      query: query is String && query.trim().isNotEmpty ? query : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CollectionFolder &&
      other.id == id &&
      other.name == name &&
      other.query == query &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(id, name, query, items.length);
}

/// Persists collections and turns live folders into titles.
///
/// Lives in its own Hive box so a corrupt collection never costs the library,
/// and never blocks boot: every read is best-effort and yields an empty list
/// rather than throwing into the Home build.
class CollectionStore {
  CollectionStore({Future<List<MediaItem>> Function(String query)? search})
    : _search = search;

  static const String boxName = 'collections';
  static const String _key = 'collections';

  /// Injected so the store doesn't depend on the repository directly: the
  /// Home feature hands in the active source's `search`.
  final Future<List<MediaItem>> Function(String query)? _search;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely(boxName);
  }

  Box get _box => Hive.box(boxName);

  /// All collections, in display order. Never throws.
  List<Collection> all() {
    if (!Hive.isBoxOpen(boxName)) return const [];
    final raw = _box.get(_key);
    if (raw is! List) return const [];
    final out = <Collection>[];
    for (final r in raw) {
      final c = Collection.fromMap(r);
      if (c != null) out.add(c);
    }
    out.sort((a, b) => a.position.compareTo(b.position));
    return out;
  }

  /// The collections Home should draw: hidden ones excluded.
  List<Collection> visible() => [for (final c in all()) if (!c.hidden) c];

  Future<void> _write(List<Collection> collections) async {
    await _box.put(_key, [for (final c in collections) c.toMap()]);
    revision.value++;
  }

  /// Create a collection with a generated id, at the end of the list.
  Future<Collection> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('A collection needs a name');
    final existing = all();
    final collection = Collection(
      id: _uuidV4(),
      name: trimmed,
      position: existing.length,
    );
    await _write([...existing, collection]);
    return collection;
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _replace(id, (c) => c.copyWith(name: trimmed));
  }

  Future<void> setHidden(String id, bool hidden) =>
      _replace(id, (c) => c.copyWith(hidden: hidden));

  Future<void> delete(String id) async {
    final remaining = [for (final c in all()) if (c.id != id) c];
    await _write(remaining);
  }

  /// Move a collection to [position], closing the gap it left behind.
  Future<void> move(String id, int position) async {
    final list = all();
    final from = list.indexWhere((c) => c.id == id);
    if (from < 0) return;
    final moved = list.removeAt(from);
    final to = position.clamp(0, list.length);
    list.insert(to, moved);
    await _write([
      for (var i = 0; i < list.length; i++) list[i].copyWith(position: i),
    ]);
  }

  Future<CollectionFolder> addFolder(String collectionId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('A folder needs a name');
    final folder = CollectionFolder(id: _uuidV4(), name: trimmed);
    await _replace(
      collectionId,
      (c) => c.copyWith(folders: [...c.folders, folder]),
    );
    return folder;
  }

  /// Add a folder that refills itself from a saved search of [query].
  Future<CollectionFolder> addLiveFolder(
    String collectionId,
    String name,
    String query,
  ) async {
    final trimmed = name.trim();
    final spec = query.trim();
    if (trimmed.isEmpty) throw ArgumentError('A folder needs a name');
    if (spec.isEmpty) throw ArgumentError('A live folder needs a search');
    final folder = CollectionFolder(
      id: _uuidV4(),
      name: trimmed,
      query: spec,
    );
    await _replace(
      collectionId,
      (c) => c.copyWith(folders: [...c.folders, folder]),
    );
    return folder;
  }

  /// Add a title to a folder. Idempotent on `sourceId:id`, because tapping the
  /// same bookmark twice should not create a duplicate the user can't see.
  Future<void> addItem(String collectionId, String folderId, MediaItem item) =>
      _replace(
        collectionId,
        (c) => c.copyWith(
          folders: [
            for (final f in c.folders)
              if (f.id != folderId)
                f
              else
                f.copyWith(
                  items: [
                    for (final i in f.items)
                      if (i.sourceId != item.sourceId || i.id != item.id) i,
                    item,
                  ],
                ),
          ],
        ),
      );

  Future<void> removeItem(
    String collectionId,
    String folderId,
    MediaItem item,
  ) => _replace(
    collectionId,
    (c) => c.copyWith(
      folders: [
        for (final f in c.folders)
          if (f.id != folderId)
            f
          else
            f.copyWith(
              items: [
                for (final i in f.items)
                  if (i.sourceId != item.sourceId || i.id != item.id) i,
              ],
            ),
      ],
    ),
  );

  /// Refresh every live folder by re-running its saved search. A folder whose
  /// search fails keeps its previous titles rather than emptying itself.
  Future<void> refreshLive() async {
    final search = _search;
    if (search == null) return;
    final collections = all();
    var changed = false;
    final updated = <Collection>[];
    for (final c in collections) {
      final folders = <CollectionFolder>[];
      for (final f in c.folders) {
        if (!f.isLive) {
          folders.add(f);
          continue;
        }
        try {
          final items = await search(f.query!.trim());
          if (!listEquals(items, f.items)) changed = true;
          folders.add(f.copyWith(items: items));
        } catch (_) {
          folders.add(f);
        }
      }
      updated.add(c.copyWith(folders: folders));
    }
    if (changed) await _write(updated);
  }

  Future<void> _replace(
    String id,
    Collection Function(Collection) transform,
  ) async {
    final list = all();
    final at = list.indexWhere((c) => c.id == id);
    if (at < 0) return;
    list[at] = transform(list[at]);
    await _write(list);
  }
}

/// Random v4 UUID. Hand-rolled to avoid a package for one string.
String _uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int i, int j) =>
      b.sublist(i, j).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
