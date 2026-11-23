import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watch_app/core/mangayomi/mangayomi_defaults.dart';
import 'package:watch_app/core/mangayomi/mangayomi_manager.dart';
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

/// Serves a canned body per URL and records what was fetched, so the real
/// service (parse, validate, persist) runs against a deterministic network.
class _StubClient extends http.BaseClient {
  _StubClient(this.bodies);

  final Map<String, String> bodies;
  final List<String> requested = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    requested.add(url);
    final body = bodies[url];
    if (body == null) {
      return http.StreamedResponse(
        Stream.value(const []),
        404,
        request: request,
      );
    }
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
      request: request,
    );
  }
}

String _indexFor(int count, {int itemType = 0, int codeLang = 1}) =>
    jsonEncode([
      for (var i = 1; i <= count; i++)
        {
          'id': i,
          'name': 'Source $i',
          'baseUrl': 'https://source$i.example.com',
          'sourceCodeUrl': 'https://cdn.example.com/$i.dart',
          'version': '1.0.0',
          'itemType': itemType,
          'sourceCodeLanguage': codeLang,
          'lang': 'en',
        },
    ]);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mg_defaults_test');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  MangayomiManager managerFor(http.Client client) =>
      MangayomiManager(MangayomiExtensionService(dir, client: client));

  test('seeds every default repo on a fresh install', () async {
    final client = _StubClient({
      kDefaultMangayomiRepoUrls[0]: _indexFor(2),
      kDefaultMangayomiRepoUrls[1]: _indexFor(3, itemType: 1),
      kDefaultMangayomiRepoUrls[2]: _indexFor(1),
    });
    final manager = managerFor(client);
    await manager.init();

    final added = await seedDefaultMangayomiRepos(manager);

    expect(added, kDefaultMangayomiRepoUrls.length);
    expect(
      manager.repositories.map((u) => u.toString()),
      containsAll(kDefaultMangayomiRepoUrls),
    );
  });

  test('a second pass adds nothing (idempotent across boots)', () async {
    final client = _StubClient({
      kDefaultMangayomiRepoUrls[0]: _indexFor(2),
      kDefaultMangayomiRepoUrls[1]: _indexFor(3, itemType: 1),
      kDefaultMangayomiRepoUrls[2]: _indexFor(1),
    });
    final manager = managerFor(client);
    await manager.init();

    expect(
      await seedDefaultMangayomiRepos(manager),
      kDefaultMangayomiRepoUrls.length,
    );
    expect(await seedDefaultMangayomiRepos(manager), 0);
  });

  test('an unreachable repo is skipped, the rest still land', () async {
    // Only the manga index answers; the anime one 404s.
    final client = _StubClient({kDefaultMangayomiRepoUrls[0]: _indexFor(1)});
    final manager = managerFor(client);
    await manager.init();

    final added = await seedDefaultMangayomiRepos(manager);

    expect(added, 1);
    expect(manager.repositories.map((u) => u.toString()), [
      kDefaultMangayomiRepoUrls[0],
    ]);
  });

  test('a repo already added by the user is left untouched', () async {
    final client = _StubClient({
      kDefaultMangayomiRepoUrls[0]: _indexFor(1),
      kDefaultMangayomiRepoUrls[1]: _indexFor(1, itemType: 1),
      kDefaultMangayomiRepoUrls[2]: _indexFor(1),
    });
    final manager = managerFor(client);
    await manager.init();
    await manager.addRepository(Uri.parse(kDefaultMangayomiRepoUrls[0]));
    final before = client.requested.length;

    final added = await seedDefaultMangayomiRepos(manager);

    expect(added, 2);
    // Only the missing repos were fetched again.
    expect(client.requested.length - before, 2);
    expect(client.requested.last, kDefaultMangayomiRepoUrls[2]);
  });

  test('the seeded list survives a restart', () async {
    final client = _StubClient({
      kDefaultMangayomiRepoUrls[0]: _indexFor(1),
      kDefaultMangayomiRepoUrls[1]: _indexFor(1, itemType: 1),
      kDefaultMangayomiRepoUrls[2]: _indexFor(1),
    });
    final first = managerFor(client);
    await first.init();
    await seedDefaultMangayomiRepos(first);

    // A fresh manager over the same directory: the repos are on disk, so
    // boot must not re-fetch or duplicate them.
    final second = managerFor(client);
    await second.init();
    final before = client.requested.length;

    expect(await seedDefaultMangayomiRepos(second), 0);
    expect(client.requested.length, before);
    expect(
      second.repositories.map((u) => u.toString()),
      containsAll(kDefaultMangayomiRepoUrls),
    );
  });

  test('provisioning installs English manga and novel sources', () async {
    final client = _StubClient({
      kDefaultMangayomiRepoUrls[0]: _indexFor(2),
      kDefaultMangayomiRepoUrls[1]: _indexFor(1, itemType: 1),
      kDefaultMangayomiRepoUrls[2]: _indexFor(1, itemType: 2),
      'https://cdn.example.com/1.dart': 'class Source {}',
      'https://cdn.example.com/2.dart': 'class Source {}',
    });
    final manager = managerFor(client);
    await manager.init();
    await seedDefaultMangayomiRepos(manager);

    final added = await provisionDefaultMangayomiSources(manager);

    expect(added, 3);
    expect(manager.installed, hasLength(3));
  });

  test('a malformed index does not stop the other repo', () async {
    final client = _StubClient({
      kDefaultMangayomiRepoUrls[0]: '{"not":"a list"}',
      kDefaultMangayomiRepoUrls[1]: _indexFor(2, itemType: 1),
    });
    final manager = managerFor(client);
    await manager.init();

    final added = await seedDefaultMangayomiRepos(manager);

    expect(added, 1);
    expect(manager.repositories.map((u) => u.toString()), [
      kDefaultMangayomiRepoUrls[1],
    ]);
  });
}
