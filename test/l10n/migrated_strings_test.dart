// Guards the keys added during the l10n migration.
//
// Two failure modes matter here and neither shows up in a passing widget test:
// a key added to app_en.arb but never translated (so 11 locales silently fall
// back to English), and a key whose value in a non-English locale is the
// English text copied across (same user-visible result, harder to spot in a
// diff). Both are checked against the generated catalogue rather than the .arb
// files, so this also fails when the generated output is stale.
//
// New keys are registered in [_strings] with their English text and, where the
// word is genuinely the same in the target language, an entry in
// [_legitCognates].
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/l10n/app_localizations.dart';

/// key -> English text, for every key added by the migration batches.
const _strings = <String, String>{
  // profile surface
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
  // poster card and appearance settings
  'posterLayoutPortrait': 'Portrait',
  'posterLayoutLandscape': 'Landscape',
  'posterTitlePlacement': 'Title placement',
  'posterTitleAutomatic': 'Automatic',
  'posterTitleInsideImage': 'Inside image',
  'posterTitleBelowImage': 'Below image',
  'posterSizeSmall': 'Small',
  'posterSizeLarge': 'Large',
  'posterCardSizeDescription':
      'Card size applies to poster rows and grids throughout the app.',
  'settingsAppFont': 'App font',
  'settingsNavbarVisibility': 'Navbar visibility',
  'settingsNavbarGlassDescription':
      'Darkens the whole glass background for clearer icons.',
  'settingsGlassTint': 'Glass tint',
  'settingsTabBarDescription': 'Adjust the tab bar and mode button together.',
  'settingsUnpinAll': 'Unpin all',
  'settingsSourceCatalogue': 'Source Catalogue',
  'settingsShowSourceListsInHome': 'Show installed source lists in Home',
  // source and addon screens
  'sourcesInstallDefaultRepos': 'Install default repos',
  'sourcesMangayomiUpdatesAvailable': 'Mangayomi extension updates available',
  'sourcesPasteIndexLink':
      'Paste the matching index link. Each category is saved separately.',
  'sourcesUninstallSourceTitle': 'Uninstall source?',
  'sourcesCouldNotLoadRepository': 'Could not load repository',
  'sourcesRemoveAddonTitle': 'Remove addon?',
  'sourcesAddonNoSettingsPage': 'This addon has no settings page',
  'sourcesCouldNotOpenSettingsPage': 'Could not open the settings page',
  'sourcesAddonSyncPending': 'Addon sync pending',
  'sourcesRetrySync': 'Retry sync',
  'sourcesNoAddonsYet': 'No addons yet. Add an addon to get started.',
  'sourcesHomeRows': 'Home rows',
  'sourcesHideRowsKeepMetadata': 'Hide rows while keeping metadata available',
  'sourcesAddAccount': 'Add account',
  'sourcesAddXtreamAccount': 'Add Xtream account',
  // collections and live TV
  'collectionsNewCollection': 'New collection',
  'collectionsAddFolder': 'Add folder',
  'collectionsAddLiveFolder': 'Add live folder',
  'collectionsEmpty': 'No collections yet.',
  'collectionsNoFolders': 'No folders yet. Add one to start filling it.',
  'liveNoGuideData': 'No guide data',
  'liveRecordingsAndReminders': 'Recordings & reminders',
  'liveRecordings': 'Recordings',
  'liveReminders': 'Reminders',
  'liveNoStreamResolved':
      'No stream resolved yet — open the channel to record it',
  'liveParentalPin': 'PIN',
  'liveParentalConfirm': 'Confirm',
  'liveParentalShowUpTo': 'Show up to',
  'liveParentalEverything': 'Everything — no rating filtering',
  // dub sheet, GIF picker, Stremio discover, paywall, community, pairing
  'dubVoice': 'Voice',
  'dubNarrateIn': 'Narrate in',
  'dubNarrateSubtitles': 'Narrate subtitles',
  'dubSkipSoundEffects': 'Skip sound effects',
  'dubDoNotNarrateCues': 'Do not narrate lines like [CROWD CHEERING].',
  'gifChooseGif': 'Choose a GIF',
  'gifCouldNotLoad': 'Could not load GIFs. Check your connection.',
  'gifSearchUnavailable': 'GIF search is unavailable right now.',
  'gifSignInToSearch': 'Sign in to search for GIFs.',
  'gifPoweredByKlipy': 'Powered by KLIPY',
  'stremioBrowse': 'Browse',
  'stremioBrowseCatalogues': 'Browse catalogues',
  'stremioChooseCatalogueHint':
      'Choose an addon catalogue to browse. Search filters are separate.',
  'stremioNoBrowseableCatalogues': 'No browseable addon catalogues are available.',
  'stremioSearchResultFilters': 'Search result filters',
  'paywallCheckout': 'Checkout',
  'paywallCheckoutUnavailable': 'Checkout is unavailable right now.',
  'paywallPayWithKorapay': 'Pay with KoraPay · card, transfer, USSD',
  'paywallSecuredInApp': 'Secured in-app · no redirect',
  'communityJoinTitle': 'Join the Zangetsu community',
  'communityJoinBody': 'Updates, requests, and help — come say hi.',
  'communityMaybeLater': 'Maybe later',
  'pairTypeCodeOnOtherDevice': 'Type this code on the other device.',
  'pairLookingForDevice': 'Looking for a device that is sending…',
  'pairRestoreFromThisDevice': 'Restore from this device',
  'profileOptionalImage': 'Optional image for your profile',
  'profileAvatarLabel': 'Profile avatar',
  'commonCloudflareProtected': 'This source is protected by Cloudflare',
  'commonBackupSaveFailed':
      'Could not save the backup. Your current data is unchanged.',
};

/// Words that are genuinely spelled the same in the target language, so the
/// "differs from English" check would flag a correct translation.
const _legitCognates = <String, Set<String>>{
  'fr': {'posterLayoutPortrait'}, // French "Portrait" is correct French
  'it': {'profileAccount'}, // Italian "Account" is correct Italian
};

/// Keys that are acronyms or universal loanwords, so the same text in every
/// locale is the correct translation rather than a missed one. Listing them
/// keeps the "differs from English" rule strict for real prose.
const _universalTokens = <String>{
  'liveParentalPin', // PIN is the word in every one of these languages
};

/// Pulls one key's value out of a catalogue.
///
/// Generated localizations expose typed getters, not a map, so the key has to
/// be resolved somehow. Keeping the switch in one place means adding a key
/// costs one line here plus one line in [_strings], and a key that is
/// registered but not reachable fails loudly rather than being skipped.
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
  'posterLayoutPortrait' => l.posterLayoutPortrait,
  'posterLayoutLandscape' => l.posterLayoutLandscape,
  'posterTitlePlacement' => l.posterTitlePlacement,
  'posterTitleAutomatic' => l.posterTitleAutomatic,
  'posterTitleInsideImage' => l.posterTitleInsideImage,
  'posterTitleBelowImage' => l.posterTitleBelowImage,
  'posterSizeSmall' => l.posterSizeSmall,
  'posterSizeLarge' => l.posterSizeLarge,
  'posterCardSizeDescription' => l.posterCardSizeDescription,
  'settingsAppFont' => l.settingsAppFont,
  'settingsNavbarVisibility' => l.settingsNavbarVisibility,
  'settingsNavbarGlassDescription' => l.settingsNavbarGlassDescription,
  'settingsGlassTint' => l.settingsGlassTint,
  'settingsTabBarDescription' => l.settingsTabBarDescription,
  'settingsUnpinAll' => l.settingsUnpinAll,
  'settingsSourceCatalogue' => l.settingsSourceCatalogue,
  'settingsShowSourceListsInHome' => l.settingsShowSourceListsInHome,
  'sourcesInstallDefaultRepos' => l.sourcesInstallDefaultRepos,
  'sourcesMangayomiUpdatesAvailable' => l.sourcesMangayomiUpdatesAvailable,
  'sourcesPasteIndexLink' => l.sourcesPasteIndexLink,
  'sourcesUninstallSourceTitle' => l.sourcesUninstallSourceTitle,
  'sourcesCouldNotLoadRepository' => l.sourcesCouldNotLoadRepository,
  'sourcesRemoveAddonTitle' => l.sourcesRemoveAddonTitle,
  'sourcesAddonNoSettingsPage' => l.sourcesAddonNoSettingsPage,
  'sourcesCouldNotOpenSettingsPage' => l.sourcesCouldNotOpenSettingsPage,
  'sourcesAddonSyncPending' => l.sourcesAddonSyncPending,
  'sourcesRetrySync' => l.sourcesRetrySync,
  'sourcesNoAddonsYet' => l.sourcesNoAddonsYet,
  'sourcesHomeRows' => l.sourcesHomeRows,
  'sourcesHideRowsKeepMetadata' => l.sourcesHideRowsKeepMetadata,
  'sourcesAddAccount' => l.sourcesAddAccount,
  'sourcesAddXtreamAccount' => l.sourcesAddXtreamAccount,
  'collectionsNewCollection' => l.collectionsNewCollection,
  'collectionsAddFolder' => l.collectionsAddFolder,
  'collectionsAddLiveFolder' => l.collectionsAddLiveFolder,
  'collectionsEmpty' => l.collectionsEmpty,
  'collectionsNoFolders' => l.collectionsNoFolders,
  'liveNoGuideData' => l.liveNoGuideData,
  'liveRecordingsAndReminders' => l.liveRecordingsAndReminders,
  'liveRecordings' => l.liveRecordings,
  'liveReminders' => l.liveReminders,
  'liveNoStreamResolved' => l.liveNoStreamResolved,
  'liveParentalPin' => l.liveParentalPin,
  'liveParentalConfirm' => l.liveParentalConfirm,
  'liveParentalShowUpTo' => l.liveParentalShowUpTo,
  'liveParentalEverything' => l.liveParentalEverything,
  'dubVoice' => l.dubVoice,
  'dubNarrateIn' => l.dubNarrateIn,
  'dubNarrateSubtitles' => l.dubNarrateSubtitles,
  'dubSkipSoundEffects' => l.dubSkipSoundEffects,
  'dubDoNotNarrateCues' => l.dubDoNotNarrateCues,
  'gifChooseGif' => l.gifChooseGif,
  'gifCouldNotLoad' => l.gifCouldNotLoad,
  'gifSearchUnavailable' => l.gifSearchUnavailable,
  'gifSignInToSearch' => l.gifSignInToSearch,
  'gifPoweredByKlipy' => l.gifPoweredByKlipy,
  'stremioBrowse' => l.stremioBrowse,
  'stremioBrowseCatalogues' => l.stremioBrowseCatalogues,
  'stremioChooseCatalogueHint' => l.stremioChooseCatalogueHint,
  'stremioNoBrowseableCatalogues' => l.stremioNoBrowseableCatalogues,
  'stremioSearchResultFilters' => l.stremioSearchResultFilters,
  'paywallCheckout' => l.paywallCheckout,
  'paywallCheckoutUnavailable' => l.paywallCheckoutUnavailable,
  'paywallPayWithKorapay' => l.paywallPayWithKorapay,
  'paywallSecuredInApp' => l.paywallSecuredInApp,
  'communityJoinTitle' => l.communityJoinTitle,
  'communityJoinBody' => l.communityJoinBody,
  'communityMaybeLater' => l.communityMaybeLater,
  'pairTypeCodeOnOtherDevice' => l.pairTypeCodeOnOtherDevice,
  'pairLookingForDevice' => l.pairLookingForDevice,
  'pairRestoreFromThisDevice' => l.pairRestoreFromThisDevice,
  'profileOptionalImage' => l.profileOptionalImage,
  'profileAvatarLabel' => l.profileAvatarLabel,
  'commonCloudflareProtected' => l.commonCloudflareProtected,
  'commonBackupSaveFailed' => l.commonBackupSaveFailed,
  _ => throw ArgumentError('key $key is registered but not mapped in _value'),
};

void main() {
  test('every migrated string is translated in all 12 locales', () {
    expect(AppLocalizations.supportedLocales, hasLength(12));

    for (final locale in AppLocalizations.supportedLocales) {
      final l = lookupAppLocalizations(locale);
      final allowed = _legitCognates[locale.languageCode] ?? const <String>{};

      for (final entry in _strings.entries) {
        final key = entry.key;
        final value = _value(l, key);

        expect(
          value.trim(),
          isNotEmpty,
          reason: '$key is empty in ${locale.languageCode}',
        );

        final isUniversal = _universalTokens.contains(key);
        if (locale.languageCode != 'en' && !allowed.contains(key) && !isUniversal) {
          expect(
            value,
            isNot(entry.value),
            reason:
                '$key still holds the English text in ${locale.languageCode} '
                '— it was added to app_en.arb but never translated',
          );
        }
      }
    }
  });

  test('German and Japanese read their own language, not English', () {
    final de = lookupAppLocalizations(const Locale('de'));
    expect(de.profileManageProfiles, 'Profile verwalten');
    expect(de.posterLayoutPortrait, 'Hochformat');
    expect(de.settingsUnpinAll, 'Alle lösen');

    final ja = lookupAppLocalizations(const Locale('ja'));
    expect(ja.profileKidsProfile, 'キッズプロフィール');
    expect(ja.settingsGlassTint, 'ガラスの色合い');
  });
}
