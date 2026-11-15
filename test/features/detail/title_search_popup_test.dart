import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/detail/title_search_popup.dart';
import 'package:watch_app/l10n/app_localizations.dart';

void main() {
  Future<TitleSearchChoice?> open(WidgetTester tester, {String? tap}) async {
    TitleSearchChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showTitleSearchPopup(context, 'Example Show');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Example Show'), findsOneWidget);
    expect(find.text('Search for this title?'), findsOneWidget);
    if (tap != null) {
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
    }
    return result;
  }

  testWidgets('primary action returns the plain search choice', (
    tester,
  ) async {
    expect(await open(tester, tap: 'Search'), TitleSearchChoice.search);
  });

  testWidgets('secondary action returns the all-sources choice', (
    tester,
  ) async {
    expect(
      await open(tester, tap: 'Search all sources'),
      TitleSearchChoice.searchAll,
    );
  });

  testWidgets('dismissing the popup returns null', (tester) async {
    expect(await open(tester), isNull);
  });
}
