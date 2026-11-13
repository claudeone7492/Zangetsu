// The per-source filter icon (search_screen.dart's control row +
// section headers) must route `ani:` ids (Aniyomi) and `mihon:` ids (Mihon)
// to their sheets, route unprefixed ids to the Zangetsu JS sheet, and stay
// hidden for the other ecosystems (CloudStream, LNReader, Mangayomi) that have
// no per-source sheet here. sourceFilterEcosystemOf is pulled out as its own
// top-level function (same pattern as searchFilterSections /
// searchTypeAudioGroupsVisible) so the routing decision is testable without
// pumping the sheet.
//
// Note the two layers: sourceFilterEcosystemOf decides WHICH sheet an id would
// open. Whether a Zangetsu source actually has filters is a separate, async
// question (its declared `getFilters` schema) answered in
// _SearchViewState._sourceFilterFor — so an unprefixed id routing here does not
// by itself mean a button appears.

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/home/search_screen.dart';

void main() {
  group('sourceFilterEcosystemOf', () {
    test('ani: sources route to Aniyomi', () {
      expect(sourceFilterEcosystemOf('ani:1'), SourceFilterEcosystem.aniyomi);
    });

    test('mihon: sources route to Mihon', () {
      expect(sourceFilterEcosystemOf('mihon:1'), SourceFilterEcosystem.mihon);
    });

    test('unprefixed (Zangetsu) sources route to the JS filter sheet', () {
      expect(
        sourceFilterEcosystemOf('some-js-source'),
        SourceFilterEcosystem.zangetsu,
      );
      expect(
        sourceFilterEcosystemOf('moviebox'),
        SourceFilterEcosystem.zangetsu,
      );
    });

    test('cs: (CloudStream) sources have no per-source filter sheet', () {
      expect(sourceFilterEcosystemOf('cs:1'), isNull);
    });

    test('lnr: (LNReader) sources have no per-source filter sheet', () {
      expect(sourceFilterEcosystemOf('lnr:novelbin'), isNull);
    });
  });
}
