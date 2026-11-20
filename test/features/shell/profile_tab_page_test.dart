import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/settings/settings_screen.dart';
import 'package:watch_app/features/shell/root_shell.dart';

void main() {
  test('shared TV rail pages keep Settings at index three', () {
    final pages = buildShellPages(null);

    expect(pages, hasLength(4));
    expect(pages[3], isA<SettingsScreen>());
    expect(pages.last, isA<SettingsScreen>());
  });

  test('describing the pages needs no DI registration', () {
    // The Search page picks between song and title search by the active mode,
    // but that lookup belongs to build time — assembling the list must not
    // reach into GetIt, or every caller (and every test) has to register the
    // mode cubit first. No registration here on purpose.
    expect(() => buildShellPages(null), returnsNormally);
  });
}
