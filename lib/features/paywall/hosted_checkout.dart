import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/environment.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';

/// What the hosted checkout's return URL says happened. The paywall keeps
/// polling for the webhook on [paid] and [pending]; only [cancelled] ends the
/// wait immediately.
enum CheckoutOutcome { paid, pending, cancelled }

/// Reads a gateway return URL. Returns null when [url] is not one of the
/// configured return URLs.
///
/// The scheme, host and path must match exactly (a trailing slash is
/// tolerated); the query carries the gateway's verdict. Flutterwave reuses
/// `redirect_url` for failures too, and labels a bank transfer `pending`, so
/// the status is what separates "paid" from "come back later" and "cancelled".
///
/// Several URLs are accepted because the app and the edge function can be
/// deployed in either order: the server reports the URL it used, while
/// [Environment.paymentReturnUrl] and [Environment.legacyPaymentReturnUrl]
/// cover an older function and an older build.
CheckoutOutcome? checkoutOutcomeForUrl(
  String url, {
  required List<String> returnUrls,
}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  String trim(String path) => path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;

  for (final returnUrl in returnUrls) {
    final target = Uri.tryParse(returnUrl);
    if (target == null) continue;
    if (uri.scheme != target.scheme ||
        uri.host != target.host ||
        uri.port != target.port) {
      continue;
    }
    if (trim(uri.path) != trim(target.path)) continue;

    final status =
        (uri.queryParameters['status'] ??
                uri.queryParameters['payment_status'] ??
                '')
            .toLowerCase();
    if (const {
      'cancelled',
      'canceled',
      'failed',
      'error',
      'declined',
    }.contains(status)) {
      return CheckoutOutcome.cancelled;
    }
    if (const {
      'pending',
      'processing',
      'initiated',
      'queued',
    }.contains(status)) {
      return CheckoutOutcome.pending;
    }
    return CheckoutOutcome.paid;
  }
  return null;
}

/// Embedded hosted checkout for whichever gateway the server selected:
/// KoraPay where its live account has the local currency, Flutterwave
/// everywhere else.
///
/// The card flow deliberately stays inside the app: a browser tab loses the
/// callback and leaves the user unsure whether they paid. We load the checkout
/// URL, watch for the return URL, and pop the gateway's outcome.
///
/// Callers must treat the pop as "the user came back having paid" and verify
/// server-side before unlocking anything durable — the WebView cannot be
/// trusted for entitlement.
class HostedCheckout extends StatefulWidget {
  const HostedCheckout({
    super.key,
    required this.checkoutUrl,
    this.provider,
    this.returnUrl,
  });

  final String checkoutUrl;

  /// `korapay` or `flutterwave`, used only for the title. The URL is already
  /// the server's choice, so this never changes routing.
  final String? provider;

  /// The exact return URL the server passed to the gateway, when it reported
  /// one. The known defaults are always watched as well.
  final String? returnUrl;

  @override
  State<HostedCheckout> createState() => _HostedCheckoutState();
}

class _HostedCheckoutState extends State<HostedCheckout> {
  late final WebViewController _controller;
  late final List<String> _returnUrls = {
    if (widget.returnUrl != null) widget.returnUrl!,
    Environment.paymentReturnUrl,
    Environment.legacyPaymentReturnUrl,
  }.toList(growable: false);
  bool _loading = true;
  bool _finished = false;

  String? get _providerName => switch (widget.provider) {
    'korapay' => 'KoraPay',
    'flutterwave' => 'Flutterwave',
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (request) {
            final url = request.url;
            final outcome = checkoutOutcomeForUrl(url, returnUrls: _returnUrls);
            if (outcome != null) {
              if (!_finished) {
                _finished = true;
                Navigator.of(context).pop(outcome);
              }
              return NavigationDecision.prevent;
            }
            // Stay embedded: a scheme handoff (intent://, a bank app, tel:)
            // leaves the payment sheet with the callback lost, which is exactly
            // the "did my card go through?" dead end this screen exists to
            // avoid. Only ordinary web navigation is followed.
            final uri = Uri.tryParse(url);
            if (uri == null ||
                !(uri.isScheme('https') || uri.isScheme('http'))) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(
      backgroundColor: AppColors.bg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        _providerName == null
            ? context.l10n.paywallCheckout
            : '${context.l10n.paywallCheckout} · $_providerName',
        style: AppText.title,
      ),
    ),
    body: Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
      ],
    ),
  );
}
