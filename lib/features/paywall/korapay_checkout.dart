import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';

/// Embedded KoraPay checkout.
///
/// The card flow deliberately stays inside the app: a browser tab loses the
/// callback and leaves the user unsure whether they paid. We load the checkout
/// URL, watch for the return URL, and pop `true` on success.
///
/// Callers must treat the pop as "the user came back having paid" and verify
/// server-side before unlocking anything durable — the WebView cannot be
/// trusted for entitlement.
class KoraPayCheckout extends StatefulWidget {
  const KoraPayCheckout({
    super.key,
    required this.checkoutUrl,
    this.successUrlPrefix = 'https://zangetsu.online/payment/success',
    this.cancelUrlPrefix = 'https://zangetsu.online/payment/cancel',
  });

  final String checkoutUrl;
  final String successUrlPrefix;
  final String cancelUrlPrefix;

  @override
  State<KoraPayCheckout> createState() => _KoraPayCheckoutState();
}

class _KoraPayCheckoutState extends State<KoraPayCheckout> {
  late final WebViewController _controller;
  bool _loading = true;

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
            if (url.startsWith(widget.successUrlPrefix)) {
              Navigator.of(context).pop(true);
              return NavigationDecision.prevent;
            }
            if (url.startsWith(widget.cancelUrlPrefix)) {
              Navigator.of(context).pop(false);
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
      title: Text(context.l10n.paywallCheckout, style: AppText.title),
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
