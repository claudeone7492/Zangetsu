import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/web/website.dart';
import '../../l10n/l10n.dart';

/// A saved site in the in-app browser.
///
/// Keeps http(s) navigation inside the WebView and hands every other scheme
/// (mailto:, tel:, intent:) to the platform, so a site cannot strand the
/// viewer on a blank page.
class WebsiteViewScreen extends StatefulWidget {
  const WebsiteViewScreen({super.key, required this.site});

  final Website site;

  @override
  State<WebsiteViewScreen> createState() => _WebsiteViewScreenState();
}

class _WebsiteViewScreenState extends State<WebsiteViewScreen> {
  late final WebViewController _controller;
  double _progress = 0;
  bool _canGoBack = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100);
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _error = null;
                _progress = 0;
              });
            }
          },
          onPageFinished: (_) async {
            final canBack = await _controller.canGoBack();
            if (mounted) {
              setState(() {
                _canGoBack = canBack;
                _progress = 1;
              });
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _error = context.l10n.websitesLoadFailed);
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.site.url));
  }

  Future<void> _openExternal() async {
    await launchUrl(
      Uri.parse(widget.site.url),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.site.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_canGoBack)
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => _controller.goBack(),
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _controller.reload(),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded),
              tooltip: context.l10n.websitesOpenExternal,
              onPressed: _openExternal,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_progress < 1)
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            Expanded(
              child: _error != null
                  ? _ErrorView(
                      message: _error!,
                      onRetry: () {
                        setState(() => _error = null);
                        _controller.reload();
                      },
                    )
                  : WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 44,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onRetry,
              child: Text(context.l10n.tryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
