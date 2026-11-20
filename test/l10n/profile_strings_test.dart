// Guards the profile strings added for the l10n migration.
//
// Two failure modes are worth catching and neither is visible from a passing
// widget test: a key that exists in English only (so 11 locales silently fall
// back to English), and a key that exists but holds the English text in a
// non-English locale (same result, harder to spot in a diff). Both are checked
// against the generated catalogue rather than the .arb files, so this also
// fails if the generated output is stale.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/l10n/app_localizations.dart';

const _profileKeys = <String, String>{
  'profileCouldNotUpdateAccountName': 'Could not update account name',
  'profileChooseAvatar': 'Choose avatar',
  'profilePhotoFromGallery': 'Photo from gallery',
  'profileAnimatedGifFile': 'Animated GIF file',
  'profileSearchGifs': 'Search GIFs',
  'profileCover': 'Profile cover',
  'profileRemoveCover': 'Remove cover',
  'profileDeleteTitle': 'Delete profile?',
  'profileRestoreToCloud': 'Restore to cloud',
  'profileAccount': 'Account',
  'profileManageProfiles': 'Manage profiles',
  'profileSaveRecoveryCode': 'Save your recovery code',
  'profileISavedIt': 'I saved it',
  'profileSetNumericPin': 'Set a numeric PIN',
  'profileForgotPin': 'Forgot PIN?',
  'profileChooseNewPin': 'Choose a new 4 or 6 digit PIN',
  'profileUseFingerprint': 'Use fingerprint on this phone',
  'profileDonate': 'Donate',
  'profileKidsProfile': 'Kids profile',
};

String _value(AppLocalizations l, String key) => switch (key) {
  'profileCouldNotUpdateAccountName' => l.profileCouldNotUpdateAccountName,
  'profileChooseAvatar' => l.profileChooseAvatar,
  'profilePhotoFromGallery' => l.profilePhotoFromGallery,
  'profileAnimatedGifFile' => l.profileAnimatedGifFile,
  'profileSearchGifs' => l.profileSearchGifs,
  'profileCover' => l.profileCover,
  'profileRemoveCover' => l.profileRemoveCover,
  'profileDeleteTitle' => l.profileDeleteTitle,
  'profileRestoreToCloud' => l.profileRestoreToCloud,
  'profileAccount' => l.profileAccount,
  'profileManageProfiles' => l.profileManageProfiles,
  'profileSaveRecoveryCode' => l.profileSaveRecoveryCode,
  'profileISavedIt' => l.profileISavedIt,
  'profileSetNumericPin' => l.profileSetNumericPin,
  'profileForgotPin' => l.profileForgotPin,
  'profileChooseNewPin' => l.profileChooseNewPin,
  'profileUseFingerprint' => l.profileUseFingerprint,
  'profileDonate' => l.profileDonate,
  'profileKidsProfile' => l.profileKidsProfile,
  _ => throw ArgumentError('unmapped key $key'),
};

/// Words that are genuinely spelled the same in the target language, so the
/// "differs from English" check would flag correct translations.
const _legitCognates = <String, Set<String>>{
  'it': {'profileAccount'}, // Italian "Account" is correct Italian
};

void main() {
  test('every profile string is translated in all 12 locales', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = lookupAppLocalizations(locale);
      for (final key in _profileKeys.keys) {
        expect(
          _value(l, key).trim(),
          isNotEmpty,
          reason: '$key is empty in ${locale.languageCode}',
        );
        final allowed = _legitCognates[locale.languageCode] ?? const <String>{};
        if (locale.languageCode != 'en' && !allowed.contains(key)) {
          expect(
            _value(l, key),
            isNot(_profileKeys[key]),
            reason:
                '$key still holds the English text in ${locale.languageCode} '
                '— it was added to app_en.arb but not translated',
          );
        }
      }
    }
  });

  test('German reads German, not English', () {
    final de = lookupAppLocalizations(const Locale('de'));
    expect(de.profileManageProfiles, 'Profile verwalten');
    expect(de.profileDeleteTitle, 'Profil löschen?');
    expect(de.profileKidsProfile, 'Kinderprofil');
  });
}
