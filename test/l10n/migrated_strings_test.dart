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
  // settings, appearance and nav tabs
  'settingsGroupLanguage': 'Language',
  'settingsGroupLayout': 'Layout',
  'settingsGroupLook': 'Look',
  'searchStyle': 'Search style',
  'settingsSearchStyleSubtitle': 'Choose Classic or New for search',
  'settingsTheme': 'Theme & colour',
  'settingsThemeSubtitle': 'Accent colour, dark mode and font',
  'settingsBranding': 'Icon, splash & banner',
  'settingsBrandingSubtitle': 'How the app looks before you open it',
  'settingsPosterCards': 'Poster cards',
  'settingsPosterCardsSubtitle': 'Shape and labels for title cards',
  'settingsHomeRowsSubtitle': 'Which rows show on Home, and their order',
  'settingsSearchLayoutSubtitle': 'How results from different sources line up',
  'settingsBatchDownloadSubtitle': 'How the sheet looks when you grab a batch of episodes',
  'settingsCollectionsSubtitle': 'Your own rows on Home',
  'collections': 'Collections',
  'settingsProfilesAccount': 'Profiles & account',
  'settingsSubscription': 'Subscription',
  'settingsSubscriptionSubtitle': 'Manage your plan, apply a promo code',
  'adminConsole': 'Admin console',
  'settingsAdminSubtitle': 'Devices, promo codes and subscriptions',
  'settingsDebrid': 'Debrid',
  'settingsDebridSubtitle': 'Real-Debrid & TorBox for torrents',
  'sourcePriority': 'Source Priority',
  'settingsSourcePrioritySubtitle': 'Order Auto Resolve tries sources in',
  'appearanceAdaptiveColour': 'Adaptive colour',
  'appearanceTintSubtitle': 'Tints the background of Home and Detail from the poster colour',
  'appearanceTitleArtwork': 'Title artwork',
  'appearanceTitleArtworkSubtitle': 'Show the official title logo instead of plain text on Detail',
  'appearanceEpisodeOrderSubtitle': 'Every detail screen opens newest-first; the list button still flips it for that visit',
  'appearanceReverseEpisodeOrder': 'Reverse episode list always on',
  'appearanceEverythingDrawn': 'Everything in the app is drawn in this',
  'navBlurBackground': 'Blur background',
  'navBlurSubtitle': 'Softens artwork behind the liquid navbar',
  'navChangeContentMode': 'Change content mode',
  // final batch: admin, filters, source switcher, reader, profiles
  'adminTitle': 'Admin',
  'adminChangeExpiry': 'Change expiry',
  'statusActive': 'ACTIVE',
  'statusFinished': 'FINISHED',
  'statusKids': 'KIDS',
  'commonInclude': 'Include',
  'commonExclude': 'Exclude',
  'commonAscending': 'Ascending',
  'commonViewDetails': 'View Details',
  'sourceSwitcherAutoResolve': 'Auto Resolve',
  'sourceSwitcherTryAll': 'Try every installed source until one matches',
  'sourceSwitcherHoldSelectToPin': 'Hold Select to pin a source to the top',
  'sourceSwitcherAppleTvUnavailable': 'Could not load that source on Apple TV',
  'mangaUpNext': 'UP NEXT',
  'mangaChapterCloudflare': 'This Mangayomi chapter is protected by Cloudflare.',
  'mangayomiFilterUnsupported': 'This filter type is not supported yet',
  'stremioNoLinks': 'No links',
  'stremioNoPlayableLinks': 'No playable links found',
  'stremioAddonsTitle': 'Stremio Addons',
  'profilesAddProfile': 'Add profile',
  'profilesChooseWhoIsWatching': 'Choose who is watching. Each profile keeps its own list and progress.',
  'profileLockRecoveryCodeHint': 'Use the private recovery code saved when this profile’s PIN was set.',
  'profileLockOtherDevicesUnaffected': 'Your PIN still works. Other devices keep their own setting.',
  'homeTvSourcePrefix': 'Source ·',
  'trackerChooseList': 'Choose list',
  'authGifTooLarge': 'This GIF is too large to optimize safely. Try a smaller file.',
  'authGifUnreadable': 'Could not read that GIF file.',
  'profileMoreComingSoon': 'More features are on their way with Zoro… he just got lost again.',
  // remaining hard-coded UI strings
  'adminCreatePasscode': 'Create admin passcode',
  'adminEnterPasscode': 'Enter admin passcode',
  'adminPasscode': 'Passcode',
  'adminDevices': 'Devices',
  'adminActiveNow': 'Active now',
  'adminActiveSubs': 'Active subs',
  'adminMrr': 'MRR',
  'freeAccess': 'Free access',
  'readerCustomColorFilter': 'Custom color filter',
  'readerBlendMode': 'Color filter blend mode',
  'readerBlendMultiply': 'Multiply',
  'readerBlendScreen': 'Screen',
  'readerBlendOverlay': 'Overlay',
  'readerBlendDodge': 'Dodge',
  'readerBlendLighten': 'Lighten',
  'stremioPasteAddonUrl': 'Paste the URL from the addon settings page',
  'stremioAddonUrl': 'Addon URL',
  'moveUp': 'Move up',
  'moveDown': 'Move down',
  'stremioConfigureAddon': 'Configure addon',
  'stremioUpdateUrl': 'Update URL',
  'pairSendTitle': 'Send from this device',
  'pairSendSubtitle': 'Shows a code the other device types in',
  'pairReceiveTitle': 'Receive on this device',
  'pairReceiveSubtitle': 'Finds senders on your Wi-Fi',
  'pairCodeExample': '123456',
  'collectionsRename': 'Rename collection',
  'collectionsNewFolder': 'New folder',
  'collectionsNewLiveFolder': 'New live folder',
  'collectionsSearchText': 'Search text',
  'collectionsDeleteTitle': 'Delete "{name}"?',
  'liveParentalConfirmOldPin': 'Confirm the old PIN',
  'liveParentalCurrentPin': 'Current PIN',
  'liveParentalRemovePin': 'Remove PIN',
  'liveParentalRemovePinBody': 'Enter the current PIN to remove the lock',
  'liveParentalUnlockBody': 'Enter the PIN to reveal restricted channels',
  'paywallPromoHint': 'Have a promo code?',
  'paywallPlan': 'Plan',
  'paywallPrice': 'Price',
  'paywallTotal': 'Total',
  'paywallYouSave': 'You save',
  'tvErrorCouldNotLoadEpisode': 'Couldn\'t load this episode',
  'tvErrorCouldNotCheckSources': 'Couldn\'t check every source',
  'tvErrorGenericBody': 'There was an issue loading this content. If this continues, try changing sources.',
  'tvErrorCouldNotPlaySource': 'Couldn\'t play this source',
  'tvErrorPlaySourceBody': '{showTitle} failed to play. The stream was found but the player couldn\'t decode it{code}. Try another source, or pick one manually.',
  'tvErrorTryNextSource': 'Try Next Source',
  'episodeWhereToWatch': 'Where to watch',
  'episodeWhereToWatchSubtitle': 'See which of your sources has this episode',
  'episodeReadOnSourceSite': 'Read it on the source\'s own site',
  'sourcesNoneAvailable': 'No sources available',
  'sourcesCouldNotLoadCatalogue': 'Could not load this catalogue',
  'sourcesNoTitlesToShow': 'No titles to show',
  'liveRefreshGuide': 'Refresh guide',
  'liveSetReminder': 'Set reminder',
  'liveRecord': 'Record',
  'profileRemoveLock': 'Remove profile lock',
  'profileEnableFingerprint': 'Enable fingerprint',
  'profileRecoverPin': 'Recover profile PIN',
  'profileRemoveAvatar': 'Remove avatar',
  'profileBio': 'Bio',
  'profileHideAdultTitles': 'Hide adult-rated catalogue titles',
  'profileEditProfile': 'Edit profile',
  'profileMenu': 'Profile menu',
  'debridTokenSaved': 'API token saved on this device',
  'debridApiToken': 'API token',
  'debridGetApiToken': 'Get an API token',
  'checkOtherSources': 'Check other sources',
  'goBack': 'Go back',
  'backupPairSyncTitle': 'Pair & sync over Wi-Fi',
  'backupPairSyncSubtitle': 'Move a backup between two devices, no cloud',
  'liveXtreamAccounts': 'Xtream accounts',
  'tvGuide': 'TV guide',
  'repositoryActions': 'Repository actions',
  'sourceHealthDeepTest': 'Deep test (opens a title from each source)',
  'gifSearchKlipy': 'Search KLIPY',
  'profilesAskOnLaunch': 'Ask who is watching on launch',
  'dubAsWritten': 'As written',
  'dubReadAloudSubtitle': 'Read the subtitle line aloud',
  'playerProvider': 'Provider',
  'stop': 'Stop',
};

/// Words that are genuinely spelled the same in the target language, so the
/// "differs from English" check would flag a correct translation.
const _legitCognates = <String, Set<String>>{
  'de': {
    'adminTitle', // German UIs say "Admin", not "Administrator"
    'settingsGroupLayout', // "Layout" is the standard German UI word
    'profileBio', // "Bio" is the standard German abbreviation
  },
  'es': {
    'paywallPlan', // Spanish uses "Plan"
    'paywallTotal', // Spanish uses "Total"
  },
  'fr': {
    'posterLayoutPortrait', // French "Portrait" is correct French
    'adminTitle', // French UIs say "Admin" too
    'homeTvSourcePrefix', // French "Source" is the French word
    'collections', // "Collections" is a French word
    'paywallTotal', // French uses "Total"
    'profileBio', // French uses "Bio"
  },
  'id': {
    'adminTitle', // Indonesian uses "Admin" natively
    'paywallTotal', // Indonesian uses "Total"
    'profileBio', // Indonesian uses "Bio"
  },
  'it': {
    'profileAccount', // Italian "Account" is correct Italian
    'settingsGroupLayout', // Italian borrows "Layout" for this
    'profileBio', // Italian uses "Bio"
    'playerProvider', // Italian uses "Provider"
  },
  'pt': {
    'settingsGroupLayout', // Portuguese borrows "Layout" too
    'paywallTotal', // Portuguese uses "Total"
    'profileBio', // Portuguese uses "Bio"
  },
  'tr': {
    'paywallPlan', // Turkish uses "Plan"
  },
};

/// Keys that are acronyms or universal loanwords, so the same text in every
/// locale is the correct translation rather than a missed one. Listing them
/// keeps the "differs from English" rule strict for real prose.
const _universalTokens = <String>{
  'liveParentalPin', // PIN is the word in every one of these languages
  'settingsDebrid', // "Debrid" is the Real-Debrid brand, kept as-is everywhere
  'adminMrr', // MRR is a finance acronym, kept as-is everywhere
  'pairCodeExample', // A sample numeric code, not prose
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
  'settingsGroupLanguage' => l.settingsGroupLanguage,
  'settingsGroupLayout' => l.settingsGroupLayout,
  'settingsGroupLook' => l.settingsGroupLook,
  'searchStyle' => l.searchStyle,
  'settingsSearchStyleSubtitle' => l.settingsSearchStyleSubtitle,
  'settingsTheme' => l.settingsTheme,
  'settingsThemeSubtitle' => l.settingsThemeSubtitle,
  'settingsBranding' => l.settingsBranding,
  'settingsBrandingSubtitle' => l.settingsBrandingSubtitle,
  'settingsPosterCards' => l.settingsPosterCards,
  'settingsPosterCardsSubtitle' => l.settingsPosterCardsSubtitle,
  'settingsHomeRowsSubtitle' => l.settingsHomeRowsSubtitle,
  'settingsSearchLayoutSubtitle' => l.settingsSearchLayoutSubtitle,
  'settingsBatchDownloadSubtitle' => l.settingsBatchDownloadSubtitle,
  'settingsCollectionsSubtitle' => l.settingsCollectionsSubtitle,
  'collections' => l.collections,
  'settingsProfilesAccount' => l.settingsProfilesAccount,
  'settingsSubscription' => l.settingsSubscription,
  'settingsSubscriptionSubtitle' => l.settingsSubscriptionSubtitle,
  'adminConsole' => l.adminConsole,
  'settingsAdminSubtitle' => l.settingsAdminSubtitle,
  'settingsDebrid' => l.settingsDebrid,
  'settingsDebridSubtitle' => l.settingsDebridSubtitle,
  'sourcePriority' => l.sourcePriority,
  'settingsSourcePrioritySubtitle' => l.settingsSourcePrioritySubtitle,
  'appearanceAdaptiveColour' => l.appearanceAdaptiveColour,
  'appearanceTintSubtitle' => l.appearanceTintSubtitle,
  'appearanceTitleArtwork' => l.appearanceTitleArtwork,
  'appearanceTitleArtworkSubtitle' => l.appearanceTitleArtworkSubtitle,
  'appearanceEpisodeOrderSubtitle' => l.appearanceEpisodeOrderSubtitle,
  'appearanceReverseEpisodeOrder' => l.appearanceReverseEpisodeOrder,
  'appearanceEverythingDrawn' => l.appearanceEverythingDrawn,
  'navBlurBackground' => l.navBlurBackground,
  'navBlurSubtitle' => l.navBlurSubtitle,
  'navChangeContentMode' => l.navChangeContentMode,
  'adminTitle' => l.adminTitle,
  'adminChangeExpiry' => l.adminChangeExpiry,
  'statusActive' => l.statusActive,
  'statusFinished' => l.statusFinished,
  'statusKids' => l.statusKids,
  'commonInclude' => l.commonInclude,
  'commonExclude' => l.commonExclude,
  'commonAscending' => l.commonAscending,
  'commonViewDetails' => l.commonViewDetails,
  'sourceSwitcherAutoResolve' => l.sourceSwitcherAutoResolve,
  'sourceSwitcherTryAll' => l.sourceSwitcherTryAll,
  'sourceSwitcherHoldSelectToPin' => l.sourceSwitcherHoldSelectToPin,
  'sourceSwitcherAppleTvUnavailable' => l.sourceSwitcherAppleTvUnavailable,
  'mangaUpNext' => l.mangaUpNext,
  'mangaChapterCloudflare' => l.mangaChapterCloudflare,
  'mangayomiFilterUnsupported' => l.mangayomiFilterUnsupported,
  'stremioNoLinks' => l.stremioNoLinks,
  'stremioNoPlayableLinks' => l.stremioNoPlayableLinks,
  'stremioAddonsTitle' => l.stremioAddonsTitle,
  'profilesAddProfile' => l.profilesAddProfile,
  'profilesChooseWhoIsWatching' => l.profilesChooseWhoIsWatching,
  'profileLockRecoveryCodeHint' => l.profileLockRecoveryCodeHint,
  'profileLockOtherDevicesUnaffected' => l.profileLockOtherDevicesUnaffected,
  'homeTvSourcePrefix' => l.homeTvSourcePrefix,
  'trackerChooseList' => l.trackerChooseList,
  'authGifTooLarge' => l.authGifTooLarge,
  'authGifUnreadable' => l.authGifUnreadable,
  'profileMoreComingSoon' => l.profileMoreComingSoon,
  'adminCreatePasscode' => l.adminCreatePasscode,
  'adminEnterPasscode' => l.adminEnterPasscode,
  'adminPasscode' => l.adminPasscode,
  'adminDevices' => l.adminDevices,
  'adminActiveNow' => l.adminActiveNow,
  'adminActiveSubs' => l.adminActiveSubs,
  'adminMrr' => l.adminMrr,
  'freeAccess' => l.freeAccess,
  'readerCustomColorFilter' => l.readerCustomColorFilter,
  'readerBlendMode' => l.readerBlendMode,
  'readerBlendMultiply' => l.readerBlendMultiply,
  'readerBlendScreen' => l.readerBlendScreen,
  'readerBlendOverlay' => l.readerBlendOverlay,
  'readerBlendDodge' => l.readerBlendDodge,
  'readerBlendLighten' => l.readerBlendLighten,
  'stremioPasteAddonUrl' => l.stremioPasteAddonUrl,
  'stremioAddonUrl' => l.stremioAddonUrl,
  'moveUp' => l.moveUp,
  'moveDown' => l.moveDown,
  'stremioConfigureAddon' => l.stremioConfigureAddon,
  'stremioUpdateUrl' => l.stremioUpdateUrl,
  'pairSendTitle' => l.pairSendTitle,
  'pairSendSubtitle' => l.pairSendSubtitle,
  'pairReceiveTitle' => l.pairReceiveTitle,
  'pairReceiveSubtitle' => l.pairReceiveSubtitle,
  'pairCodeExample' => l.pairCodeExample,
  'collectionsRename' => l.collectionsRename,
  'collectionsNewFolder' => l.collectionsNewFolder,
  'collectionsNewLiveFolder' => l.collectionsNewLiveFolder,
  'collectionsSearchText' => l.collectionsSearchText,
  'collectionsDeleteTitle' => l.collectionsDeleteTitle('X'),
  'liveParentalConfirmOldPin' => l.liveParentalConfirmOldPin,
  'liveParentalCurrentPin' => l.liveParentalCurrentPin,
  'liveParentalRemovePin' => l.liveParentalRemovePin,
  'liveParentalRemovePinBody' => l.liveParentalRemovePinBody,
  'liveParentalUnlockBody' => l.liveParentalUnlockBody,
  'paywallPromoHint' => l.paywallPromoHint,
  'paywallPlan' => l.paywallPlan,
  'paywallPrice' => l.paywallPrice,
  'paywallTotal' => l.paywallTotal,
  'paywallYouSave' => l.paywallYouSave,
  'tvErrorCouldNotLoadEpisode' => l.tvErrorCouldNotLoadEpisode,
  'tvErrorCouldNotCheckSources' => l.tvErrorCouldNotCheckSources,
  'tvErrorGenericBody' => l.tvErrorGenericBody,
  'tvErrorCouldNotPlaySource' => l.tvErrorCouldNotPlaySource,
  'tvErrorPlaySourceBody' => l.tvErrorPlaySourceBody('X', ' (E)'),
  'tvErrorTryNextSource' => l.tvErrorTryNextSource,
  'episodeWhereToWatch' => l.episodeWhereToWatch,
  'episodeWhereToWatchSubtitle' => l.episodeWhereToWatchSubtitle,
  'episodeReadOnSourceSite' => l.episodeReadOnSourceSite,
  'sourcesNoneAvailable' => l.sourcesNoneAvailable,
  'sourcesCouldNotLoadCatalogue' => l.sourcesCouldNotLoadCatalogue,
  'sourcesNoTitlesToShow' => l.sourcesNoTitlesToShow,
  'liveRefreshGuide' => l.liveRefreshGuide,
  'liveSetReminder' => l.liveSetReminder,
  'liveRecord' => l.liveRecord,
  'profileRemoveLock' => l.profileRemoveLock,
  'profileEnableFingerprint' => l.profileEnableFingerprint,
  'profileRecoverPin' => l.profileRecoverPin,
  'profileRemoveAvatar' => l.profileRemoveAvatar,
  'profileBio' => l.profileBio,
  'profileHideAdultTitles' => l.profileHideAdultTitles,
  'profileEditProfile' => l.profileEditProfile,
  'profileMenu' => l.profileMenu,
  'debridTokenSaved' => l.debridTokenSaved,
  'debridApiToken' => l.debridApiToken,
  'debridGetApiToken' => l.debridGetApiToken,
  'checkOtherSources' => l.checkOtherSources,
  'goBack' => l.goBack,
  'backupPairSyncTitle' => l.backupPairSyncTitle,
  'backupPairSyncSubtitle' => l.backupPairSyncSubtitle,
  'liveXtreamAccounts' => l.liveXtreamAccounts,
  'tvGuide' => l.tvGuide,
  'repositoryActions' => l.repositoryActions,
  'sourceHealthDeepTest' => l.sourceHealthDeepTest,
  'gifSearchKlipy' => l.gifSearchKlipy,
  'profilesAskOnLaunch' => l.profilesAskOnLaunch,
  'dubAsWritten' => l.dubAsWritten,
  'dubReadAloudSubtitle' => l.dubReadAloudSubtitle,
  'playerProvider' => l.playerProvider,
  'stop' => l.stop,

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
