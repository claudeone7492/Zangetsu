import 'package:flutter/material.dart';

import '../../core/music/music_models.dart';

/// Leanback music home: one focusable rail per section.
class MusicScreenTv extends StatelessWidget {
  const MusicScreenTv({
    super.key,
    required this.sections,
    required this.onPlay,
    this.onOpenTrack,
  });

  final List<MusicSection> sections;
  final void Function(MusicTrack track, List<MusicTrack> queue) onPlay;
  final void Function(MusicTrack track)? onOpenTrack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Music')),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final section = sections[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Text(section.title, style: Theme.of(context).textTheme.titleMedium),
              ),
              SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: section.tracks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    final track = section.tracks[i];
                    return _TvTrackTile(
                      track: track,
                      onSelect: () => onPlay(track, section.tracks),
                      onLongSelect: onOpenTrack == null ? null : () => onOpenTrack!(track),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TvTrackTile extends StatefulWidget {
  const _TvTrackTile({required this.track, required this.onSelect, this.onLongSelect});
  final MusicTrack track;
  final VoidCallback onSelect;
  final VoidCallback? onLongSelect;

  @override
  State<_TvTrackTile> createState() => _TvTrackTileState();
}

class _TvTrackTileState extends State<_TvTrackTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (value) => setState(() => _focused = value),
      child: GestureDetector(
        onTap: widget.onSelect,
        onLongPress: widget.onLongSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 150,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _focused ? Colors.white12 : Colors.transparent,
            border: Border.all(color: _focused ? Colors.white54 : Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: widget.track.artwork == null
                      ? const ColoredBox(color: Colors.black26)
                      : Image.network(widget.track.artwork!, fit: BoxFit.cover, width: double.infinity),
                ),
              ),
              const SizedBox(height: 6),
              Text(widget.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                widget.track.artist ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
