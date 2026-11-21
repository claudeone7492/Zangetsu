import 'package:flutter/material.dart';

class StreamChoice {
  const StreamChoice({required this.label, required this.url, this.quality});
  final String label;
  final String url;
  final String? quality;
}

/// Dedicated stream/server picker, usable from the player or a poster menu.
class ServerStreamsPage extends StatelessWidget {
  const ServerStreamsPage({
    super.key,
    required this.title,
    required this.streams,
    required this.onPick,
    this.currentUrl,
  });

  final String title;
  final List<StreamChoice> streams;
  final void Function(StreamChoice) onPick;
  final String? currentUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        itemCount: streams.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final stream = streams[index];
          final selected = stream.url == currentUrl;
          return ListTile(
            leading: Icon(selected ? Icons.check_circle : Icons.dns_outlined),
            title: Text(stream.label),
            subtitle: stream.quality == null ? null : Text(stream.quality!),
            onTap: () {
              onPick(stream);
              Navigator.of(context).maybePop();
            },
          );
        },
      ),
    );
  }
}
