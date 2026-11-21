import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/models/episode.dart';
import '../../core/models/video_source.dart';
import '../../core/playback/resume_store.dart';
import '../../core/telegram/telegram_prefs.dart';
import '../../core/telegram/telegram_service.dart';
import '../../core/telegram/telegram_source.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';
import '../player/player_screen.dart';
import 'telegram_sign_in.dart';

/// Browses public Telegram channels.
///
/// Public channels work with no login and no native library: the Dart web
/// client reads the preview page. A channel added here is saved, and the
/// native bridge takes over automatically on a build that links TDLib.
class TelegramScreen extends StatefulWidget {
  const TelegramScreen({super.key});

  @override
  State<TelegramScreen> createState() => _TelegramScreenState();
}

class _TelegramScreenState extends State<TelegramScreen> {
  final TextEditingController _controller = TextEditingController();
  final TelegramService _service = sl<TelegramService>();
  TelegramChannelPage? _page;
  bool _loading = false;
  String? _error;

  /// The channel on screen, so signing in can reload it through the native
  /// path without the viewer typing the name again.
  String? _current;

  /// Whether this build has the TDLib client, and what state it is in. Both
  /// come from the bridge; on a build without it the card is not drawn at all.
  bool _native = false;

  TelegramPrefs get _prefs => sl<TelegramPrefs>();

  @override
  void initState() {
    super.initState();
    _loadNative();
  }

  Future<void> _loadNative() async {
    final available = await _service.nativeAvailable();
    if (!mounted) return;
    setState(() => _native = available);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(String raw) async {
    final key = await _prefs.addChannel(raw);
    if (!mounted) return;
    if (key == null) {
      setState(() => _error = context.l10n.telegramInvalidChannel);
      return;
    }
    _controller.text = key;
    setState(() {
      _loading = true;
      _error = null;
      _page = null;
      _current = key;
    });
    try {
      final page = await _service.browse(key);
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } on TelegramException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.telegramFailed;
        _loading = false;
      });
    }
  }

  Future<void> _remove(String channel) async {
    await _prefs.removeChannel(channel);
    if (mounted) setState(() {});
  }

  void _play(TelegramStream stream) {
    final title = stream.title.isEmpty
        ? context.l10n.telegramVideoFallback
        : stream.title;
    final source = VideoSource(url: stream.url, container: stream.container);
    final episode = Episode(
      id: 'telegram:${stream.url}',
      title: title,
      number: 1,
      url: stream.url,
      thumbnail: stream.thumbnailUrl,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          sourceId: 'telegram',
          resume: sl<ResumeStore>(),
          resolveSources: (url) async => [source],
          episodes: [episode],
          initialSource: source,
          showTitle: title,
          cover: stream.thumbnailUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final channels = _prefs.allChannels;
    final page = _page;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.telegram)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            l10n.telegramSubtitle,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (_native)
            TelegramSignInCard(
              service: _service,
              prefs: _prefs,
              onSignedIn: () {
                final channel = _current;
                if (channel != null) _open(channel);
              },
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: l10n.telegramChannelHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.go,
                  onSubmitted: _open,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _open(_controller.text),
                child: Text(l10n.telegramAddChannel),
              ),
            ],
          ),
          if (channels.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final channel in channels)
                  InputChip(
                    label: Text(channel),
                    onPressed: () => _open(channel),
                    onDeleted: _prefs.channels.contains(channel)
                        ? () => _remove(channel)
                        : null,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            _Notice(icon: Icons.error_outline_rounded, message: _error!)
          else if (page != null)
            if (page.streams.isEmpty)
              _Notice(
                icon: Icons.video_library_outlined,
                message: l10n.telegramNoStreams,
              )
            else
              for (final stream in page.streams)
                _StreamTile(stream: stream, onTap: () => _play(stream)),
          const SizedBox(height: 16),
          Text(
            l10n.telegramPrivateHint,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StreamTile extends StatelessWidget {
  const _StreamTile({required this.stream, required this.onTap});

  final TelegramStream stream;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = stream.title.isEmpty
        ? context.l10n.telegramVideoFallback
        : stream.title;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 72,
        height: 48,
        child: stream.thumbnailUrl == null
            ? const Icon(Icons.play_circle_outline_rounded)
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  stream.thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.play_circle_outline_rounded),
                ),
              ),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.body,
      ),
      subtitle: stream.publishedAt == null
          ? null
          : Text(
              _date(stream.publishedAt!),
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
      trailing: const Icon(Icons.play_arrow_rounded),
      onTap: onTap,
    );
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Icon(icon, color: AppColors.textSecondary),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}
