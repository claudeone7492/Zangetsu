/// Single source of truth for the product name. Final rename = one
/// find/replace on the token `WATCH_APP` across the repo, plus a bundle-id
/// rename (`flutter pub run rename` or manual android/ios edits).
const String kAppName = 'Zangetsu';

/// Short brand line shown under the app name in notifications and about-style
/// copy. Kept beside [kAppName] so the two never drift.
const String kAppTagline = 'Streaming, manga & light novels';

/// Running app version shown in Settings/About. Populated from the real build
/// (PackageInfo) at boot so it never goes stale; this literal is just the
/// pre-boot fallback.
String kAppVersion = '1.0.0';

/// Build number behind [kAppVersion], e.g. `13108`. Kept separate because
/// [kAppVersion] is user-facing (Settings shows `v2.0.0`) and goes out as the
/// Simkl `app-version` header, and neither wants a build number. A log report
/// does: "2.0.0" spans every build of a release, and knowing which one a
/// report came from is the whole point.
String kAppBuild = '';

/// Stable application id embedded in default provider-repo manifests and
/// checked by the repo guard so a manga-only (Sozo) repo can't be added.
const String kAppId = 'watch_app';

/// Default provider repos, installed on first launch via onboarding. The app
/// ships with NO built-in providers — every source comes from these manifests.
///
/// Order matters: the first repo is the streaming pack the default source is
/// drawn from. Only sources that resolve fully (browse, search, detail, and
/// playback/reader) ship here — dead upstreams are dropped rather than handed
/// to a new user as an empty Home. Each repo installs independently — a repo
/// that is unreachable is skipped rather than failing the whole run.
///
/// The curated first-party pack carries the verified anime, movie, manga and
/// novel sources (it vendors the working subset of the community packs). The
/// Spyou repos stay reachable through the community directory
/// ([kSourceDirectoryUrl]) so a user can still add anything we dropped.
const List<String> kDefaultRepoUrls = [
  // First-party pack — every source here is verified end-to-end.
  'https://raw.githubusercontent.com/claudeone7492/Zangetsu/main/provider-repo/index.json',
];

/// Content source activated for a NEW user at the end of first-run onboarding.
/// Must be an id present in one of [kDefaultRepoUrls]' manifests. Existing
/// users are never affected — onboarding runs once and their pick is already
/// persisted; if this source fails to install, onboarding falls back to the
/// first source that did.
const String kDefaultSourceId = 'anikoto';

/// Preferred first source when entering Manga mode with no remembered pick.
/// MangaPill's catalogue is the most complete of the bundled manga pack; the
/// remaining manga sources stay selectable and act as fallbacks.
const String kDefaultMangaSourceId = 'mangapill';

/// Source the vertical Shorts feed draws from first. MovieBox carries a
/// dedicated short-drama catalogue ("Hot Short TV" / "Trending Short Drama"
/// rails), so it leads the feed's source list; the remaining installed video
/// sources fill in behind it. A missing/uninstalled id is simply skipped.
const String kShortsDefaultSourceId = 'moviebox';

/// The short-drama catalogues — the ONLY sources the Reels feed and the Shorts
/// page draw from. Each is built end to end around serialized vertical short
/// dramas (see their `getShorts`), so their output is dramas and nothing else.
///
/// The Reels feed ("drama shorts") and the Shorts page ("AI shorts") are both
/// meant to be a pure short-drama surface, but the aggregate used to walk EVERY
/// installed video source and fold each one's ordinary home rows in behind the
/// dramas. That is how feature films and TV episodes leaked into both pages:
/// MovieBox's own home carries two dozen movie/TV rails and only two short-drama
/// ones, so its `getShorts` feed is used and its home is ignored; the generic
/// movie sources (frameXTV, NetMirror, VidSrc, VidLink …) have no `getShorts`
/// at all, so their whole movie catalogue came through the home-row fallback.
/// Restricting the aggregate to these ids is what makes both pages short dramas
/// "and nothing more".
const List<String> kShortDramaSourceIds = <String>[
  'moviebox',
  'goodshort',
  'reelshort',
  'netshort',
];

/// Short-drama catalogues whose OWN home rows are short dramas end to end, so
/// they are safe as a fallback when `getShorts` answers nothing.
///
/// MovieBox is deliberately absent: it is the one drama catalogue that ALSO
/// aggregates movies and TV, so its home is two dozen movie/TV rails with only
/// two short-drama ones. Falling back to its home rows when its `getShorts`
/// came back empty would re-introduce exactly the feature films a drama page
/// must not show, so MovieBox is served by `getShorts` alone.
const List<String> kDramaOnlyHomeSourceIds = <String>[
  'goodshort',
  'reelshort',
  'netshort',
];

/// The sports sources the Live TV rail merges, in the order their fixtures
/// read. MovieBox carries a full fixture list (a `PlayTypeText` match centre
/// plus live broadcasts), CDNLive/TimStreams publish a broadcaster schedule,
/// StreamFree adds per-sport fixtures (24/7 channels plus matches), and
/// StreamSports99 is the VIP tenant of the CDNLive API with its own
/// domain-bound player pages. All are asked and merged so an installed-but-empty
/// source simply contributes nothing; a source that isn't installed is skipped
/// before the call.
///
/// Shared with the source repository's cross-provider live resolution: a
/// fixture's own provider may no longer mint a URL for it, so the same fixture
/// is looked up on the others.
const List<String> kLiveSportsSourceIds = <String>[
  'nuviotv',
  'moviebox',
  'cdnlivetv',
  'streamsports99',
  'timstreams',
  'streamfree',
];

/// The two providers that carry the fullest, most reliable live-stream lists.
/// Playback resolves through these first even when the tapped fixture came from
/// a lower-priority source; the rest stay as fallbacks for matches only they
/// index.
const List<String> kPriorityLiveSportsSourceIds = <String>[
  'nuviotv',
  'moviebox',
];

/// Public directory of community source repos (Sozo Read format:
/// `{entries:[{name,author,repoUrl,description,tags,verified}]}`). Browsed from
/// Providers → Add repo so a user can discover community packs in one tap.
/// Optional: a fetch failure simply hides the discovery list.
const String kSourceDirectoryUrl =
    'https://raw.githubusercontent.com/Spyou/sozoread-directory/main/index.json';

/// Manifest schema version this app speaks. Repos below this are rejected.
const int kManifestSchemaVersion = 2;

/// Community Discord invite. Lived in two places (the launch community sheet
/// and Settings → About) and drifted — the sheet's copy went stale and expired.
/// One const now, so refreshing the invite is a single edit here.
const String kDiscordInviteUrl = 'https://discord.gg/hey6vz9kg6';

/// Where "Send report" posts the diagnostic log — the Cloudflare Worker in
/// `cloudflare/log-intake/` (see its README to deploy). No path, no trailing
/// slash.
///
/// Empty means "not set up" — the report button falls back to the share sheet
/// rather than failing, so a fork with no Worker of its own still works.
///
/// Only the public URL lives here. The Discord webhook stays on the Worker:
/// this app is open source and its APK is public, so anything put in the app
/// can be read straight back out of it.
const String kLogIntakeUrl = 'https://zangetsu-logs.log-intake.workers.dev';

/// Public R2 manifest for the rotating profile-picker backdrops. The manifest
/// contains up to three image filenames stored beside it in this bucket.
const String kProfilePickerArtworkManifestUrl =
    'https://avatars.zangetsu.online/profile-picker/manifest.json';

/// Developer announcements feed (a plain JSON file in the public app repo).
/// The app READS this on launch to show in-app announcements — never writes.
/// Edit + push that file to broadcast a message to every user.
const String kAnnouncementsUrl =
    'https://raw.githubusercontent.com/claudeone7492/Zangetsu/main/announcements.json';

/// TMDB API key for movie/TV trailer lookups (TrailerService). Anime trailers
/// use AniList and need no key. Supply via `--dart-define=TMDB_API_KEY=...`,
/// or paste a literal default below. When empty, movie/TV trailers are
/// gracefully disabled (the Trailer button simply never appears for them).
const String kTmdbApiKey = String.fromEnvironment(
  'TMDB_API_KEY',
  defaultValue: '',
);
