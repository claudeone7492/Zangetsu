import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/collections/collection_store.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';

MediaItem _item(String id, {String source = 'cs:a', String? title}) =>
    MediaItem(
      id: id,
      title: title ?? 'Title $id',
      url: 'https://example.com/$id',
      type: ProviderType.movie,
      sourceId: source,
    );

void main() {
  late CollectionStore store;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('collections_test');
    Hive.init(dir.path);
  });

  setUp(() async {
    if (Hive.isBoxOpen(CollectionStore.boxName)) {
      await Hive.box(CollectionStore.boxName).clear();
    } else {
      await CollectionStore.init();
      await Hive.box(CollectionStore.boxName).clear();
    }
    store = CollectionStore();
  });

  group('model', () {
    test('a collection round-trips through storage', () {
      final collection = Collection(
        id: 'c1',
        name: 'Weekend',
        position: 2,
        folders: [
          CollectionFolder(
            id: 'f1',
            name: 'Comfort',
            items: [_item('a'), _item('b')],
          ),
        ],
      );
      final parsed = Collection.fromMap(collection.toMap());
      expect(parsed, collection);
      expect(parsed!.folders.single.items.length, 2);
    });

    test('a nameless or id-less collection is rejected', () {
      expect(Collection.fromMap({'name': 'x'}), isNull);
      expect(Collection.fromMap({'id': 'c1'}), isNull);
      expect(Collection.fromMap({'id': 'c1', 'name': '   '}), isNull);
      expect(Collection.fromMap('not a map'), isNull);
    });

    test('one bad folder does not discard its siblings', () {
      final raw = {
        'id': 'c1',
        'name': 'Mixed',
        'folders': [
          {'id': 'ok', 'name': 'Good', 'items': []},
          {'id': 'bad'}, // no name
          {'name': 'also bad'}, // no id
        ],
      };
      final parsed = Collection.fromMap(raw);
      expect(parsed, isNotNull);
      expect(parsed!.folders.map((f) => f.id), ['ok']);
    });

    test('an unreadable item drops itself, not the folder', () {
      final raw = {
        'id': 'f1',
        'name': 'Folder',
        'items': [
          _item('good').toJson(),
          {'id': 1}, // wrong types
        ],
      };
      final folder = CollectionFolder.fromMap(raw);
      expect(folder, isNotNull);
      expect(folder!.items.length, 1);
      expect(folder.items.single.id, 'good');
    });

    test('a blank query is not a live folder', () {
      const folder = CollectionFolder(id: 'f', name: 'n', query: '   ');
      expect(folder.isLive, isFalse);
      expect(
        CollectionFolder.fromMap({'id': 'f', 'name': 'n', 'query': '  '})!.query,
        isNull,
      );
    });

    test('a collection flattens its folders into one Home row', () {
      final collection = Collection(
        id: 'c1',
        name: 'Everything',
        folders: [
          CollectionFolder(id: 'f1', name: 'A', items: [_item('1')]),
          CollectionFolder(id: 'f2', name: 'B', items: [_item('2'), _item('3')]),
        ],
      );
      final section = collection.toSection();
      expect(section.title, 'Everything');
      expect(section.items.map((i) => i.id), ['1', '2', '3']);
    });
  });

  group('store', () {
    test('create appends in order and generates an id', () async {
      final a = await store.create('First');
      final b = await store.create('Second');
      expect(a.id, isNot(b.id));
      expect(store.all().map((c) => c.name), ['First', 'Second']);
      expect(store.all().map((c) => c.position), [0, 1]);
    });

    test('create refuses a blank name', () async {
      expect(() => store.create('   '), throwsArgumentError);
      expect(store.all(), isEmpty);
    });

    test('rename keeps the id and trims', () async {
      final c = await store.create('Old');
      await store.rename(c.id, '  New  ');
      expect(store.all().single.name, 'New');
      expect(store.all().single.id, c.id);
    });

    test('hide removes a collection from Home but keeps it stored', () async {
      final c = await store.create('Kept');
      await store.setHidden(c.id, true);
      expect(store.visible(), isEmpty);
      expect(store.all().length, 1);
      await store.setHidden(c.id, false);
      expect(store.visible().single.name, 'Kept');
    });

    test('delete removes only that collection', () async {
      final a = await store.create('A');
      await store.create('B');
      await store.delete(a.id);
      expect(store.all().map((c) => c.name), ['B']);
    });

    test('move reorders and renumbers positions', () async {
      await store.create('A');
      final b = await store.create('B');
      await store.create('C');
      await store.move(b.id, 0);
      expect(store.all().map((c) => c.name), ['B', 'A', 'C']);
      expect(store.all().map((c) => c.position), [0, 1, 2]);
    });

    test('move clamps an out-of-range target', () async {
      final a = await store.create('A');
      await store.create('B');
      await store.move(a.id, 99);
      expect(store.all().map((c) => c.name), ['B', 'A']);
    });

    test('adding a folder and a title', () async {
      final c = await store.create('C');
      final folder = await store.addFolder(c.id, 'Folder');
      await store.addItem(c.id, folder.id, _item('x'));
      final stored = store.all().single;
      expect(stored.folders.single.items.single.id, 'x');
    });

    test('adding the same title twice does not duplicate it', () async {
      final c = await store.create('C');
      final folder = await store.addFolder(c.id, 'F');
      await store.addItem(c.id, folder.id, _item('x'));
      await store.addItem(c.id, folder.id, _item('x'));
      expect(store.all().single.folders.single.items.length, 1);
    });

    test('the same id from a different source is a different title', () async {
      final c = await store.create('C');
      final folder = await store.addFolder(c.id, 'F');
      await store.addItem(c.id, folder.id, _item('x', source: 'cs:a'));
      await store.addItem(c.id, folder.id, _item('x', source: 'cs:b'));
      expect(store.all().single.folders.single.items.length, 2);
    });

    test('removeItem removes only the named title', () async {
      final c = await store.create('C');
      final folder = await store.addFolder(c.id, 'F');
      await store.addItem(c.id, folder.id, _item('x'));
      await store.addItem(c.id, folder.id, _item('y'));
      await store.removeItem(c.id, folder.id, _item('x'));
      expect(store.all().single.folders.single.items.map((i) => i.id), ['y']);
    });

    test('revision bumps on every write', () async {
      final before = store.revision.value;
      await store.create('A');
      expect(store.revision.value, greaterThan(before));
    });

    test('operations on an unknown id are no-ops', () async {
      await store.create('A');
      await store.rename('nope', 'X');
      await store.delete('nope');
      await store.move('nope', 0);
      expect(store.all().map((c) => c.name), ['A']);
    });
  });

  group('live folders', () {
    test('refreshLive refills a query folder from the search', () async {
      final searched = <String>[];
      final s = CollectionStore(
        search: (q) async {
          searched.add(q);
          return [_item('$q-1'), _item('$q-2')];
        },
      );
      final c = await s.create('Live');
      await s.addLiveFolder(c.id, 'Trending', 'action');
      await s.refreshLive();
      expect(searched, ['action']);
      expect(s.all().single.folders.single.items.length, 2);
    });

    test('a failing search keeps the previous titles', () async {
      var fail = false;
      final s = CollectionStore(
        search: (q) async {
          if (fail) throw StateError('offline');
          return [_item('kept')];
        },
      );
      final c = await s.create('Live');
      await s.addLiveFolder(c.id, 'Trending', 'action');
      await s.refreshLive();
      expect(s.all().single.folders.single.items.single.id, 'kept');
      fail = true;
      await s.refreshLive();
      expect(s.all().single.folders.single.items.single.id, 'kept');
    });

    test('fixed folders are never touched by a refresh', () async {
      var calls = 0;
      final s = CollectionStore(
        search: (q) async {
          calls++;
          return [_item('new')];
        },
      );
      final c = await s.create('Fixed');
      final f = await s.addFolder(c.id, 'Manual');
      await s.addItem(c.id, f.id, _item('manual'));
      await s.refreshLive();
      expect(calls, 0);
      expect(s.all().single.folders.single.items.single.id, 'manual');
    });

    test('refreshLive without a search does nothing', () async {
      await store.refreshLive();
      expect(store.all(), isEmpty);
    });
  });

  test('a corrupt stored entry costs only itself', () async {
    await store.create('Good');
    // Simulate a half-written frame: a junk entry alongside the good one.
    final box = Hive.box(CollectionStore.boxName);
    await box.put('collections', [
      {'id': 'broken'},
      ...(box.get('collections') as List),
    ]);
    expect(store.all().map((c) => c.name), ['Good']);
  });
}
