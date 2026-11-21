import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/web/website.dart';
import 'package:watch_app/core/web/website_store.dart';
import 'package:watch_app/features/web/websites_screen.dart';
import 'package:watch_app/l10n/app_localizations.dart';

/// In-memory stand-in: Hive's write queue does not drain under the widget
/// test's fake clock. The real box is covered by website_store_test.
class _FakeStore extends ChangeNotifier implements WebsiteStore {
  final _list = <Website>[];

  @override
  List<Website> get sites => List.unmodifiable(_list);

  @override
  Future<Website?> add(String name, String url) async {
    final normalised = Website.normaliseUrl(url);
    if (normalised == null) return null;
    final site = Website.fromUrl(name, normalised);
    _list.removeWhere((s) => s.id == site.id);
    _list.insert(0, site);
    notifyListeners();
    return site;
  }

  @override
  Future<void> remove(String id) async {
    _list.removeWhere((s) => s.id == id);
    notifyListeners();
  }
}

void main() {
  late _FakeStore store;

  setUp(() async {
    await sl.reset();
    store = _FakeStore();
    sl.registerSingleton<WebsiteStore>(store);
  });

  tearDown(() async {
    await sl.reset();
  });

  Widget app() => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const WebsitesScreen(),
  );

  testWidgets('empty state offers the add action', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('No websites saved yet'), findsOneWidget);
    expect(find.byTooltip('Add website'), findsOneWidget);
  });

  testWidgets('adding a site renders it and removing clears it', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add website'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // Name and host both read "example.com" on the card.
    expect(find.text('example.com'), findsNWidgets(2));
    expect(find.text('No websites saved yet'), findsNothing);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Remove website?'), findsOneWidget);

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('No websites saved yet'), findsOneWidget);
  });
}
