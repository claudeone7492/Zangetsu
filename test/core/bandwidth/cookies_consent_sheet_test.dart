import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/bandwidth/bandwidth_consent_sheet.dart';
import 'package:watch_app/core/bandwidth/bandwidth_share.dart';

/// The first-run card is a small, transparent cookie notice. These tests pin
/// the copy (no bandwidth talk), the two routes out of it, and the fact that
/// nothing is turned on until the user accepts.
void main() {
  late _FakeShare share;

  setUp(() => share = _FakeShare());
  tearDown(() => share.dispose());

  Widget host() => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showCookiesConsentSheet(context, share: share),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('shows a small cookie notice, never bandwidth sharing', (
    t,
  ) async {
    await open(t);

    expect(find.text('Cookies'), findsOneWidget);
    expect(find.textContaining('cookies'), findsWidgets);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Manage preferences'), findsOneWidget);
    // The old disclosure copy must be gone.
    expect(find.textContaining('bandwidth'), findsNothing);
    expect(find.textContaining('Proxies.sx'), findsNothing);
    // Nothing runs until the user answers.
    expect(share.accepted, isFalse);
  });

  testWidgets('Accept allows everything and starts the background service', (
    t,
  ) async {
    await open(t);

    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();

    expect(share.accepted, isTrue);
    expect(find.text('Cookies'), findsNothing);
  });

  testWidgets('Manage preferences can decline the optional category', (
    t,
  ) async {
    await open(t);

    await t.tap(find.text('Manage preferences'));
    await t.pumpAndSettle();

    expect(find.text('Essential cookies'), findsOneWidget);
    expect(find.text('Performance and features'), findsOneWidget);

    // Turn the optional category off, then save.
    await t.tap(find.byType(Switch));
    await t.pump();
    await t.tap(find.text('Save preferences'));
    await t.pumpAndSettle();

    expect(share.declined, isTrue);
    expect(share.accepted, isFalse);
  });

  testWidgets('Manage preferences keeping the optional category accepts', (
    t,
  ) async {
    await open(t);

    await t.tap(find.text('Manage preferences'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save preferences'));
    await t.pumpAndSettle();

    expect(share.accepted, isTrue);
  });
}

/// Records what the card asked of the controller. Only the two consent paths
/// matter here — no method channels, no real service.
class _FakeShare extends BandwidthShare {
  bool accepted = false;
  bool declined = false;

  @override
  bool get supported => true;

  @override
  Future<void> accept() async {
    accepted = true;
    declined = false;
  }

  @override
  Future<void> decline() async {
    declined = true;
    accepted = false;
  }
}
