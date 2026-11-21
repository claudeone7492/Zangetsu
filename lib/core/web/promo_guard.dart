import 'ad_block.dart';

/// Filters donation / membership links out of the in-app browser.
///
/// A provider's page often carries a "support us" button that opens a tip jar;
/// the same page is also where a stream plays, so a host-only filter is not
/// enough. [blocks] follows Hikari's rules: a donation host, a donation word
/// in the path or query, but never a media URL (a stream can live on any host).
class PromoGuard {
  const PromoGuard._();

  static const Set<String> donationHosts = {
    'ko-fi.com',
    'kofi.com',
    'kofiwidget2.com',
    'buymeacoffee.com',
    'buymeacoff.ee',
    'bmc.link',
    'patreon.com',
    'patron.com',
    'membership.io',
    'subscribestar.com',
    'boosty.to',
    'dona.to',
    'liberapay.com',
    'opencollective.com',
    'trakteer.id',
    'saweria.co',
    'sociabuzz.com',
    'karyakarsa.com',
    'tipme.in',
    'tipsme.in',
    'donationalerts.com',
    'donatepay.ru',
    'tipeeestream.com',
    'streamlabs.com',
    'streamelements.com',
    'streamtip.com',
    'tipanddonation.com',
    'paypal.com',
    'paypal.me',
    'cash.app',
    'venmo.com',
    'wise.com',
    'revolut.me',
    'razorpay.com',
    'instamojo.com',
    'paytm.me',
    'phonepe.com',
    'paystack.com',
    'gumroad.com',
    'buymeacoffees.com',
    'gofundme.com',
    'fundrazr.com',
    'kickstarter.com',
    'indiegogo.com',
    'fundly.com',
    'patreon-payments.com',
    'sponsor.ajay.app',
    'githubsponsors.org',
  };

  static const List<String> donationPathWords = [
    'donate',
    'donation',
    'donations',
    'donar',
    'spenden',
    'donate-us',
    'support-us',
    'supportus',
    'tipjar',
    'tip-jar',
    'buymeacoffee',
    'buy-me-a-coffee',
    'become-a-sponsor',
    'sponsors',
    'fundraiser',
    'fundraise',
    'fund-us',
    'fundus',
    'kofi',
    'ko-fi',
    'patreon',
    'paypal',
  ];

  static final RegExp _media = RegExp(
    r'\.(m3u8|mpd|mp4|mkv|webm|ts|m4v|mov)([?#]|$)',
    caseSensitive: false,
  );

  static bool blocks(Uri uri) {
    if (!AdBlock.instance.promosEnabled) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (_media.hasMatch(uri.toString())) return false;
    final host = uri.host
        .toLowerCase()
        .replaceFirst(RegExp(r'^www\.'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    if (donationHosts.any((h) => host == h || host.endsWith('.$h'))) {
      return true;
    }
    final path = uri.path.toLowerCase();
    if (path.isNotEmpty &&
        donationPathWords.any((word) => path.contains(word))) {
      return true;
    }
    final query = uri.query.toLowerCase();
    if (query.isNotEmpty &&
        const ['donate', 'buymeacoffee', 'patreon', 'ko-fi', 'paypal'].any(
          query.contains,
        )) {
      return true;
    }
    return false;
  }
}
