import 'package:flutter/material.dart';

class ScraperPage {
  const ScraperPage({required this.url, this.headers = const {}});
  final String url;
  final Map<String, String> headers;
}

/// Image-list reader for pages a scraper returns as bare image URLs.
class ScraperReaderScreen extends StatefulWidget {
  const ScraperReaderScreen({super.key, required this.title, required this.pages, this.onLoadMore});

  final String title;
  final List<ScraperPage> pages;
  final Future<List<ScraperPage>> Function()? onLoadMore;

  @override
  State<ScraperReaderScreen> createState() => _ScraperReaderScreenState();
}

class _ScraperReaderScreenState extends State<ScraperReaderScreen> {
  final ScrollController _controller = ScrollController();
  late List<ScraperPage> _pages = widget.pages;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _controller.removeListener(_maybeLoadMore);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _maybeLoadMore() async {
    final load = widget.onLoadMore;
    if (load == null || _loading) return;
    if (_controller.position.pixels < _controller.position.maxScrollExtent - 600) return;
    _loading = true;
    final more = await load();
    if (mounted) setState(() => _pages = [..._pages, ...more]);
    _loading = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView.builder(
        controller: _controller,
        itemCount: _pages.length,
        itemBuilder: (context, index) {
          final page = _pages[index];
          return InteractiveViewer(
            maxScale: 4,
            child: Image.network(
              page.url,
              headers: page.headers.isEmpty ? null : page.headers,
              fit: BoxFit.fitWidth,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, _, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Page ${index + 1} failed to load'),
              ),
            ),
          );
        },
      ),
    );
  }
}
