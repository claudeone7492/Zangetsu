import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/lnreader/lnreader_defaults.dart';
import 'package:watch_app/core/lnreader/lnreader_extension_service.dart';

class _FakeLnReaderService extends LnReaderExtensionService {
  _FakeLnReaderService(this.index) : super(httpGet: (_) async => '');

  final List<LnReaderPluginMeta> index;
  final List<String> installedIds = [];
  final List<String> installedLog = [];

  @override
  Future<List<LnReaderPluginMeta>> fetchIndex(String indexUrl) async => index;

  @override
  List<LnReaderPluginMeta> installed() => [
    for (final id in installedIds) index.firstWhere((m) => m.id == id),
  ];

  @override
  Future<void> install(LnReaderPluginMeta meta) async {
    installedLog.add(meta.id);
    installedIds.add(meta.id);
  }
}

LnReaderPluginMeta _meta(String id, String lang) => LnReaderPluginMeta(
  id: id,
  name: id,
  site: 'https://$id.test/',
  lang: lang,
  version: '1.0.0',
  url: 'https://cdn.test/$id.js',
  iconUrl: 'https://cdn.test/$id.png',
);

void main() {
  test('installs only missing plugins in the requested language', () async {
    final service = _FakeLnReaderService([
      _meta('a', 'English'),
      _meta('b', 'English'),
      _meta('c', 'Spanish'),
    ])..installedIds.add('a');

    final added = await seedDefaultLnReaderPlugins(service, concurrency: 2);

    expect(added, 1);
    expect(service.installedLog, ['b']);
  });

  test('a second pass installs nothing new', () async {
    final service = _FakeLnReaderService([_meta('a', 'English')]);

    expect(await seedDefaultLnReaderPlugins(service), 1);
    expect(await seedDefaultLnReaderPlugins(service), 0);
  });
}
