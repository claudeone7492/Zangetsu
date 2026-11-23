import 'dart:io';
import 'package:hive/hive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/backup/settings_backup.dart';

void main() {
  _driftGuard();
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp();
    Hive.init(dir.path);
    await Hive.openBox('playback_prefs');
    await Hive.openBox('viewer_profiles');
    // A typed Box<Map> — the codec must read/write it without a type-mismatch.
    await Hive.openBox<Map>('title_prefs');
  });
  tearDown(() async {
    await Hive.deleteFromDisk();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('build dumps open boxes and merge overwrites them', () async {
    Hive.box('playback_prefs').put('defaultSpeed', 1.5);
    final data = SettingsBackup().build();
    await Hive.box('playback_prefs').clear();
    await SettingsBackup().merge(data);
    expect(Hive.box('playback_prefs').get('defaultSpeed'), 1.5);
  });

  test('merge skips boxes that are not open (no throw)', () async {
    await SettingsBackup().merge({
      'not_open_box': {'x': 1},
    });
  });

  test(
    'restores the last tracker view without backing up sign-in data',
    () async {
      final selection = await Hive.openBox('tracker_switch_prefs');
      await selection.put('lastTracker', 'AniList');
      final auth = await Hive.openBox('anilist');
      await auth.put('token', 'test-only-token');

      final backup = SettingsBackup().build();
      expect(backup['tracker_switch_prefs'], {'lastTracker': 'AniList'});
      expect(backup.containsKey('anilist'), isFalse);
      await selection.clear();
      await SettingsBackup().merge(backup);
      expect(selection.get('lastTracker'), 'AniList');
      expect(auth.get('token'), 'test-only-token');
    },
  );

  test('backs up viewer profile metadata', () async {
    final profile = {
      'id': 'default',
      'name': 'Home',
      'avatar': 0,
      'isKids': false,
    };
    Hive.box('viewer_profiles').put('profiles:local', [profile]);

    final data = SettingsBackup().build();
    await Hive.box('viewer_profiles').clear();
    await SettingsBackup().merge(data);

    expect(Hive.box('viewer_profiles').get('profiles:local'), [profile]);
  });

  // Regression: title_prefs is opened as Box<Map>; an untyped Hive.box() throws.
  test('handles a Box<Map>-typed box without a type mismatch', () async {
    Hive.box<Map>('title_prefs').put('src::1', {'quality': '720p'});
    final data = SettingsBackup().build(); // must NOT throw
    expect(data['title_prefs'], {
      'src::1': {'quality': '720p'},
    });
    await Hive.box<Map>('title_prefs').clear();
    await SettingsBackup().merge(data);
    expect(Hive.box<Map>('title_prefs').get('src::1'), {'quality': '720p'});
  });
}

// The real bug wasn't any one missing box — it was drift. The list was written
// once and never revisited, so every settings box added afterwards silently
// fell out of backup (nav_prefs was missing the same day it was created).
// This fails when a new `boxName` appears in lib/ and nobody has decided
// whether it belongs in a backup.
void _driftGuard() {
  group('settings backup coverage', () {
    /// Boxes deliberately left out, each with the reason it must stay out.
    /// Adding one here is a decision; leaving a box in neither list is a bug.
    const excluded = <String, String>{
      // Secrets / tokens — must never leave the device in a backup file.
      'anilist': 'oauth token',
      'mal': 'oauth token',
      'simkl': 'oauth token',
      'mangabaka': 'oauth token',
      'discord': 'rpc token',
      'auth_cache': 'session cache',
      'stremio_installations': 'requires device-local secure addon URLs',
      // Device-specific: holds a SAF content:// URI that is meaningless (and
      // unwritable) on another device.
      'download_prefs': 'device-specific download location',
      // The device fingerprint is the app's account. Restoring it onto another
      // device would collapse two devices onto one identity — and hand the
      // second device the first one's trial and entitlement.
      'device_identity': 'device-specific identity',
      // Local FX rate + currency for the approximate price. Re-resolved on the
      // restoring device, where the currency is almost certainly different.
      'geo_pricing': 'device-specific FX cache',
      // Reference source ids the restoring device may not have installed.
      'pinned_sources': 'source ids',
      'subscriptions': 'source ids',
      'zmode_matches': 'source ids',
      // Installed sources — carried by the separate Sources bundle.
      'provider_settings': 'sources bundle',
      'provider_registry': 'sources bundle',
      'provider_repos': 'sources bundle',
      'cs_repos': 'sources bundle',
      'aniyomi_installed': 'sources bundle',
      'aniyomi_repos': 'sources bundle',
      'mihon_installed': 'sources bundle',
      'mihon_repos': 'sources bundle',
      'hikari_installed': 'sources bundle',
      'hikari_repos': 'sources bundle',
      'lnreader_repos': 'sources bundle',
      // A one-shot "community sheet already shown" flag. Device-local by
      // nature — a restore must not suppress it on a device that never saw it.
      'app_flags': 'device-local one-shot UI flags',
      // Last cloud-pull timestamps for the library sync throttle. Restoring
      // another device's timestamps would stall this device's first pull.
      'library_sync_meta': 'device-local sync throttle',
      'lnreader_plugins': 'sources bundle',
      'universal_scrapers': 'sources bundle',
      // The TV guide cache — refetched from its XMLTV feeds on any device.
      'epg_guides': 'cache',
      // The DVR schedule — device-local recordings; a restored booking on
      // another device would point at a file that isn't there.
      'dvr_entries': 'device-specific recordings',
      // JS plugin-pack families — carried by the Sources bundle (see
      // `SourcesBackup`, which round-trips them as `jsPacks`).
      'nuvio_packs': 'sources bundle',
      'vega_packs': 'sources bundle',
      'sora_packs': 'sources bundle',
      'skystream_packs': 'sources bundle',
      'kotatsu_packs': 'sources bundle',
      // User data — carried by the library backup, not settings.
      'my_list': 'library backup',
      'watch_history': 'library backup',
      'read_history': 'library backup',
      'resume_positions': 'library backup',
      'read_positions': 'library backup',
      'list_status': 'library backup',
      'list_categories': 'library backup',
      'collections': 'library backup',
      'tracker_bindings': 'library backup',
      'my_list_series_groups': 'library backup',
      'reader_overrides': 'per-title, library-shaped',
      'reader_highlights': 'per-chapter, library-shaped',
      'chapter_downloads': 'downloads, not settings',
      'downloads': 'downloads, not settings',
      // Caches and transient state — regenerated, never restored.
      'logo_cache': 'cache',
      'stremio_home_cache': 'cache',
      'tmdb_banner_cache_v3': 'cache',
      'provider_js_cache': 'cache',
      'episode_meta': 'cache',
      'cf_clearance': 'cache',
      'genre_catalog': 'cache',
      'entitlement_cache': 'cached entitlement verdict, re-read from server',
      // Icon URLs picked back up the next time a repo index is read.
      'source_icons': 'cache',
      'source_health': 'transient',
      'zmode_source_score': 'derived play counts, rebuilt from use',
      'updates': 'transient',
      'announcements': 'transient',
      'search_history': 'transient',
      'content_mode': 'restored per device',
      'home_cache': 'cache',
      // IPTV marks point at channel ids from a playlist the restoring device
      // may not have, so a restore would leave dangling favourites.
      'iptv_marks': 'channel ids',
      // Playlist URLs can embed provider credentials (Xtream-style user/pass).
      'live_playlists': 'playlist URLs may carry credentials',
      'trakt': 'oauth token',
      // Endpoint URL plus its API key; a restore onto another device would
      // carry the credential with it.
      'lossless_endpoint': 'endpoint URL and API key',
      // Signing-cert digests pinned on this install. Restoring them elsewhere
      // would vouch for extensions this device never verified.
      'extension_signers': 'per-install extension pins',
    };

    test('every settings box is either backed up or explicitly excluded', () {
      final declared = <String>{};
      // Matches every declaration shape in lib/, not just `boxName = '…'`:
      // families also use `installedBoxName`, `kFooReposBox`, `_flagsBox`,
      // `syncMetaBox`. The narrower pattern silently skipped them, which made
      // this guard pass by not looking.
      final re = RegExp(r"[A-Za-z_]*[Bb]ox(?:Name)?\s*=\s*'([a-z0-9_]+)'");
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final m in re.allMatches(f.readAsStringSync())) {
          declared.add(m.group(1)!);
        }
      }
      expect(declared, isNotEmpty, reason: 'the scan itself must find boxes');

      final unclassified =
          declared
              .where((b) => !SettingsBackup.boxNames.contains(b))
              .where((b) => !excluded.containsKey(b))
              .toList()
            ..sort();

      expect(
        unclassified,
        isEmpty,
        reason:
            'These Hive boxes are neither backed up nor listed as excluded.\n'
            'Add each to SettingsBackup.boxNames if it holds user settings, or\n'
            'to this test\'s `excluded` map with the reason it should not be\n'
            'restored: $unclassified',
      );
    });

    test('no backed-up box is also on the excluded list', () {
      for (final b in SettingsBackup.boxNames) {
        expect(excluded.containsKey(b), isFalse, reason: '$b is in both lists');
      }
    });
  });
}
