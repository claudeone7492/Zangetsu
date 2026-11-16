import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/subscription/geo_pricing.dart';

void main() {
  group('GeoQuote.format', () {
    test('shows whole units in the local currency', () {
      const quote = GeoQuote(currency: 'NGN', rate: 1352.11);
      expect(quote.format(2.97), '₦4,016');
    });

    test('USD quotes render with a dollar sign', () {
      const quote = GeoQuote(currency: 'USD', rate: 1);
      expect(quote.format(5.09), r'$5');
    });
  });

  group('currency lookup', () {
    test('resolves the main African timezones', () {
      expect(currencyForTimezone('Africa/Lagos'), 'NGN');
      expect(currencyForTimezone('Africa/Nairobi'), 'KES');
      expect(currencyForTimezone('Africa/Johannesburg'), 'ZAR');
      expect(currencyForTimezone('Africa/Cairo'), 'EGP');
      expect(currencyForTimezone('Africa/Dar_es_Salaam'), 'TZS');
    });

    test('ignores non-African timezones', () {
      expect(currencyForTimezone('Europe/London'), isNull);
      expect(currencyForTimezone('America/New_York'), isNull);
      // Reunion is African but uses the euro, so it is deliberately unlisted.
      expect(currencyForTimezone('Indian/Reunion'), isNull);
    });

    test('matches a linked zone by its city tail', () {
      expect(currencyForTimezone('Africa/Asmera'), 'ERN');
    });

    test('falls back to the country code', () {
      expect(currencyForCountry('NG'), 'NGN');
      expect(currencyForCountry('ng'), 'NGN');
      expect(currencyForCountry('GB'), isNull);
    });
  });
}
