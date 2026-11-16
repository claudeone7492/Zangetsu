import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geo_currencies/geo_currencies.dart';
import 'package:intl/intl.dart';

import '../hive/safe_box.dart';

/// A device's local currency and the live USD→local rate.
class GeoQuote {
  const GeoQuote({required this.currency, required this.rate});

  /// ISO 4217 code of the local currency, e.g. `NGN`.
  final String currency;

  /// Local units per 1 USD, at the time the quote was fetched.
  final num rate;

  /// Formats a USD amount in the local currency, whole units only — this is an
  /// approximate guide, not the charged figure.
  String format(num usdAmount) {
    final symbol = NumberFormat.simpleCurrency(
      name: currency,
      locale: 'en',
    ).currencySymbol;
    return NumberFormat.currency(
      locale: 'en',
      name: currency,
      symbol: symbol,
      decimalDigits: 0,
    ).format(usdAmount * rate);
  }
}

/// Approximate local-currency pricing for the paywall.
///
/// KoraPay settles in USD over African rails, so the charged amount never
/// changes — this is a display-only guide next to the real price. It is offered
/// only when the device's currency is African, which is the only set the
/// checkout rails serve.
///
/// The country is read from the device timezone first, then the locale region —
/// both are free of any permission prompt, unlike GPS.
class GeoPricing {
  GeoPricing._();

  static const String _boxName = 'geo_pricing';
  static const String _rateKey = 'rate';
  static const String _codeKey = 'currency';
  static const String _atKey = 'fetched_at';

  /// Quotes are cached for a day: FX drift inside that window is well below the
  /// "≈" precision this is shown at, and it keeps the paywall offline-safe.
  static const Duration _ttl = Duration(hours: 24);

  static GeoQuote? _memo;
  static bool _inflight = false;

  /// The device's local currency + rate, or null when it cannot be resolved,
  /// is not African, or the network is unavailable and nothing is cached.
  static Future<GeoQuote?> quote() async {
    if (_memo != null) return _memo;

    final code = await _localCurrency();
    if (code == null) return null;

    final box = await openBoxSafely<dynamic>(_boxName);
    final cachedCode = box.get(_codeKey);
    final cachedRate = box.get(_rateKey);
    final at = box.get(_atKey);
    final fresh =
        at is int &&
        DateTime.now().millisecondsSinceEpoch - at < _ttl.inMilliseconds;

    if (fresh && cachedCode == code && cachedRate is num) {
      return _memo = GeoQuote(currency: code, rate: cachedRate);
    }

    final rate = await _fetchRate(code);
    if (rate == null) {
      // Network down: a stale rate still beats showing nothing.
      if (cachedCode == code && cachedRate is num) {
        return _memo = GeoQuote(currency: code, rate: cachedRate);
      }
      return null;
    }

    await box.put(_codeKey, code);
    await box.put(_rateKey, rate);
    await box.put(_atKey, DateTime.now().millisecondsSinceEpoch);
    return _memo = GeoQuote(currency: code, rate: rate);
  }

  /// Resolves the local ISO 4217 code from the timezone, then the locale
  /// region. Returns null for a non-African device.
  static Future<String?> _localCurrency() async {
    try {
      final tz = await FlutterTimezone.getLocalTimezone();
      final byTz = currencyForTimezone(tz.identifier);
      if (byTz != null) return byTz;
    } catch (_) {
      // No native handler (tests, unsupported platform) — fall through to the
      // locale region.
    }
    final region = PlatformDispatcher.instance.locale.countryCode;
    if (region != null) return currencyForCountry(region);
    return null;
  }

  static Future<num?> _fetchRate(String code) async {
    if (_inflight) return null;
    _inflight = true;
    try {
      final geo = GeoCurrencies(
        config: GeoCurrenciesConfig(
          geoCurrenciesType: GeoCurrenciesType.live,
        ),
      );
      final data = await geo.convertAmountWithCurrenciesCodes(
        amount: 1,
        fromCurrencyCodeIso4217: 'USD',
        toCurrencyCodeIso4217: code,
      );
      if (data == null || !data.succeeded) return null;
      return data.rate;
    } catch (_) {
      return null;
    } finally {
      _inflight = false;
    }
  }

  /// Test seam: clears the memoised quote so a test can re-resolve.
  static void resetForTest() => _memo = null;
}

/// IANA timezone → ISO 4217, covering the African zones the checkout serves.
/// Zones that use a non-African currency (e.g. `Indian/Reunion` → EUR) are
/// deliberately absent, so those devices simply see no approximate price.
const Map<String, String> _tzCurrency = {
  // North
  'Africa/Cairo': 'EGP',
  'Africa/Tripoli': 'LYD',
  'Africa/Algiers': 'DZD',
  'Africa/Casablanca': 'MAD',
  'Africa/El_Aaiun': 'MAD',
  'Africa/Khartoum': 'SDG',
  'Africa/Tunis': 'TND',
  'Africa/Nouakchott': 'MRU',
  // West
  'Africa/Lagos': 'NGN',
  'Africa/Accra': 'GHS',
  'Africa/Abidjan': 'XOF',
  'Africa/Bamako': 'XOF',
  'Africa/Banjul': 'GMD',
  'Africa/Bissau': 'XOF',
  'Africa/Conakry': 'GNF',
  'Africa/Dakar': 'XOF',
  'Africa/Freetown': 'SLE',
  'Africa/Lome': 'XOF',
  'Africa/Monrovia': 'LRD',
  'Africa/Niamey': 'XOF',
  'Africa/Ouagadougou': 'XOF',
  'Africa/Porto-Novo': 'XOF',
  'Africa/Sao_Tome': 'STN',
  'Atlantic/Cape_Verde': 'CVE',
  // Central
  'Africa/Douala': 'XAF',
  'Africa/Bangui': 'XAF',
  'Africa/Brazzaville': 'XAF',
  'Africa/Libreville': 'XAF',
  'Africa/Malabo': 'XAF',
  'Africa/Ndjamena': 'XAF',
  'Africa/Kinshasa': 'CDF',
  'Africa/Lubumbashi': 'CDF',
  'Africa/Luanda': 'AOA',
  // East
  'Africa/Nairobi': 'KES',
  'Africa/Dar_es_Salaam': 'TZS',
  'Africa/Kampala': 'UGX',
  'Africa/Kigali': 'RWF',
  'Africa/Bujumbura': 'BIF',
  'Africa/Addis_Ababa': 'ETB',
  'Africa/Asmara': 'ERN',
  'Africa/Asmera': 'ERN', // tz backward link reported by some Android builds
  'Africa/Djibouti': 'DJF',
  'Africa/Mogadishu': 'SOS',
  'Africa/Juba': 'SSP',
  'Indian/Antananarivo': 'MGA',
  'Indian/Mauritius': 'MUR',
  'Indian/Comoro': 'KMF',
  // Southern
  'Africa/Johannesburg': 'ZAR',
  'Africa/Maseru': 'LSL',
  'Africa/Mbabane': 'SZL',
  'Africa/Gaborone': 'BWP',
  'Africa/Windhoek': 'NAD',
  'Africa/Harare': 'ZWL',
  'Africa/Lusaka': 'ZMW',
  'Africa/Blantyre': 'MWK',
  'Africa/Lilongwe': 'MWK',
  'Africa/Maputo': 'MZN',
};

/// ISO 3166-1 alpha-2 → ISO 4217 for Africa, used when the timezone is unknown.
const Map<String, String> _countryCurrency = {
  'NG': 'NGN', 'GH': 'GHS', 'KE': 'KES', 'ZA': 'ZAR', 'EG': 'EGP',
  'TZ': 'TZS', 'UG': 'UGX', 'RW': 'RWF', 'BI': 'BIF', 'ET': 'ETB',
  'ER': 'ERN', 'DJ': 'DJF', 'SO': 'SOS', 'SS': 'SSP', 'MG': 'MGA',
  'MU': 'MUR', 'KM': 'KMF', 'DZ': 'DZD', 'LY': 'LYD', 'MA': 'MAD',
  'EH': 'MAD', 'SD': 'SDG', 'TN': 'TND', 'MR': 'MRU', 'CI': 'XOF',
  'ML': 'XOF', 'GM': 'GMD', 'GW': 'XOF', 'GN': 'GNF', 'SN': 'XOF',
  'SL': 'SLE', 'TG': 'XOF', 'LR': 'LRD', 'NE': 'XOF', 'BF': 'XOF',
  'BJ': 'XOF', 'ST': 'STN', 'CV': 'CVE', 'CM': 'XAF', 'CF': 'XAF',
  'CG': 'XAF', 'GA': 'XAF', 'GQ': 'XAF', 'TD': 'XAF', 'CD': 'CDF',
  'AO': 'AOA', 'LS': 'LSL', 'SZ': 'SZL', 'BW': 'BWP', 'NA': 'NAD',
  'ZW': 'ZWL', 'ZM': 'ZMW', 'MW': 'MWK', 'MZ': 'MZN',
};

@visibleForTesting
String? currencyForTimezone(String identifier) {
  final direct = _tzCurrency[identifier];
  if (direct != null) return direct;
  // Some platforms report a zone link (e.g. `Africa/Asmera`); match on the
  // city tail case-insensitively as a fallback.
  final tail = identifier.split('/').last.toLowerCase();
  for (final entry in _tzCurrency.entries) {
    if (entry.key.split('/').last.toLowerCase() == tail) return entry.value;
  }
  return null;
}

@visibleForTesting
String? currencyForCountry(String countryCode) =>
    _countryCurrency[countryCode.toUpperCase()];
