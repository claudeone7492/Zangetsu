// The parental screen's Cancel/Remove buttons used to be English literals.
// They now read from l10n, and this test proves the wiring reaches the
// translation rather than just compiling: it renders the screen in German and
// asserts the German word is on screen and the English one is not. A test that
// only checked "a Remove button exists" would pass even with the literal back.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/live/live_parental.dart';
import 'package:watch_app/features/live/live_parental_screen.dart';
import 'package:watch_app/l10n/app_localizations.dart';

/// In-memory secure storage so the real parental store runs without a platform
/// channel.
class _MemoryStorage implements FlutterSecureStorage {
  _MemoryStorage([Map<String, String>? seed]) : data = {...?seed};
  final Map<String, String> data;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Locale locale) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const LiveParentalScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _MemoryStorage storage;

  setUp(() async {
    await sl.reset();
    storage = _MemoryStorage();
    sl.registerSingleton<LiveParental>(LiveParental(storage: storage));
  });

  tearDown(() async {
    await sl.reset();
  });

  testWidgets('Remove reads German on a German phone', (tester) async {
    await sl<LiveParental>().setPin('1234');

    await _pump(tester, const Locale('de'));

    // Only rendered once a PIN exists, so this also confirms we reached the
    // state the button lives in.
    expect(find.text('Entfernen'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('the same button is English on an English phone', (tester) async {
    await sl<LiveParental>().setPin('1234');

    await _pump(tester, const Locale('en'));

    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('Entfernen'), findsNothing);
  });

  testWidgets('the PIN dialog Cancel is translated too', (tester) async {
    await _pump(tester, const Locale('de'));

    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();

    expect(find.text('Abbrechen'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });
}
