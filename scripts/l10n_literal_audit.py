#!/usr/bin/env python3
"""Report user-visible string literals that have no matching ARB key.

This is the inventory used to close the l10n migration: it scans `lib/` for
`label:`/`tooltip:`/`hintText:`/`helperText:`/`title:`/`subtitle:` assignments
whose literal value is not a value in `app_en.arb`, so a string that was never
wired shows up here.

Files in `DATA` are excluded on purpose. They hold values that must stay
identical across locales — ISO codes, HTTP header names, font names, provider
row names, brand names, style names and sample data. Translating them would
corrupt matching or mislabel a proper noun.

Exit code is 0 only when the audit finds no non-data literal, so it can be
used as a check in CI or in a definition-of-done verification.

Usage: python3 scripts/l10n_literal_audit.py
"""
import collections
import io
import json
import pathlib
import re
import sys

DATA = {
    # Original data catalogues.
    'lib/core/i18n/source_languages.dart',
    'lib/core/reading/manga_translation/manga_translation_languages.dart',
    'lib/core/zmode/metadata_filters.dart',
    'lib/core/brand/zangetsu_mark.dart',
    'lib/core/subscription/geo_pricing.dart',
    'lib/features/player/shader_presets.dart',
    'lib/core/zmode/movie_regions.dart',
    'lib/core/playback/subtitle_language.dart',
    'lib/core/playback/tv_track_helpers.dart',
    'lib/core/anilist/anilist_api.dart',
    # Brand names, provider-supplied row names, style names and sample data.
    'lib/core/provider/js_pack_engine.dart',
    'lib/features/sources/providers_hub_screen.dart',
    'lib/core/repository/source_repository.dart',
    'lib/core/ui/banner_style.dart',
    'lib/features/settings/poster_card_settings_screen.dart',
    'lib/core/ui/splash_style.dart',
    'lib/features/live/xtream_accounts_screen.dart',
    'lib/core/aniyomi/aniyomi_provider.dart',
    'lib/core/app_icon/app_icon_service.dart',
    'lib/core/hikari/hikari_mapping.dart',
    'lib/core/mangayomi/mangayomi_provider.dart',
    'lib/core/metadata/people_service.dart',
    'lib/core/mihon/mihon_provider.dart',
    'lib/core/stremio/stremio_library_badge.dart',
    'lib/core/ui/source_switcher.dart',
    'lib/core/ui/tracker_badge.dart',
    'lib/features/community/community_sheet.dart',
    'lib/features/settings/connections_screen_tv.dart',
    'lib/features/settings/discord_settings_screen.dart',
    'lib/features/settings/settings_about.dart',
    'lib/features/sources/hikari_sources_screen.dart',
    'lib/features/sources/js_pack_sources_screen.dart',
}

PATTERN = re.compile(
    r"""(?:label|tooltip|hintText|helperText|title|subtitle)\s*[:=]\s*"""
    r"""(?:const\s+)?['"]([^'"$]{3,})['"]"""
)


def main():
    en = json.load(io.open('lib/l10n/app_en.arb', encoding='utf-8'))
    known = {v for k, v in en.items() if not k.startswith('@')}

    need = collections.defaultdict(set)
    for path in pathlib.Path('lib').rglob('*.dart'):
        name = str(path)
        if 'l10n' in name or path.name.startswith('app_localizations'):
            continue
        if name in DATA:
            continue
        for number, line in enumerate(
                path.read_text(encoding='utf-8').splitlines(), 1):
            if line.strip().startswith('//'):
                continue
            for match in PATTERN.finditer(line):
                value = match.group(1)
                if value not in known:
                    need[name].add((number, value))

    total = sum(len(v) for v in need.values())
    print(f'{total} non-data literal(s)')
    for name, values in sorted(need.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        print(f'\n## {name} ({len(values)})')
        for number, value in sorted(values):
            print(f'  {number}: {value!r}')
    return 0 if total == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
