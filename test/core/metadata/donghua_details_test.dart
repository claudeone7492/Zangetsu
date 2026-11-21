import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/donghua_details.dart';

void main() {
  test('reads studio, country and year', () {
    final details = DonghuaDetails.fromTmdb({
      'production_companies': [
        {'name': 'Studio A'},
      ],
      'production_countries': [
        {'iso_3166_1': 'CN'},
      ],
      'first_air_date': '2021-07-08',
      'status': 'Ended',
      'number_of_episodes': 12,
    });
    expect(details.studio, 'Studio A');
    expect(details.country, 'CN');
    expect(details.year, 2021);
    expect(details.episodeCount, 12);
    expect(details.isEmpty, isFalse);
  });

  test('empty payload is empty', () {
    expect(DonghuaDetails.fromTmdb(const {}).isEmpty, isTrue);
  });
}
