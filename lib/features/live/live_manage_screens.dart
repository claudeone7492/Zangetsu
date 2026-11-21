import 'package:flutter/material.dart';

/// Manage entry points that used to live only inside the Live TV screen.
class LiveManageScreen extends StatelessWidget {
  const LiveManageScreen({
    super.key,
    required this.playlistCount,
    required this.accountCount,
    required this.onOpenPlaylists,
    required this.onOpenAccounts,
    required this.onOpenGuide,
    required this.onOpenParental,
  });

  final int playlistCount;
  final int accountCount;
  final VoidCallback onOpenPlaylists;
  final VoidCallback onOpenAccounts;
  final VoidCallback onOpenGuide;
  final VoidCallback onOpenParental;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Live TV')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.playlist_play),
            title: const Text('Playlists'),
            subtitle: Text('$playlistCount imported'),
            onTap: onOpenPlaylists,
          ),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('Xtream accounts'),
            subtitle: Text('$accountCount connected'),
            onTap: onOpenAccounts,
          ),
          ListTile(
            leading: const Icon(Icons.calendar_view_day_outlined),
            title: const Text('Guide'),
            onTap: onOpenGuide,
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Parental controls'),
            onTap: onOpenParental,
          ),
        ],
      ),
    );
  }
}

class LiveVodItem {
  const LiveVodItem({required this.title, this.poster, this.year, required this.onPlay});
  final String title;
  final String? poster;
  final int? year;
  final VoidCallback onPlay;
}

/// Catch-up / on-demand catalogue.
class LiveOnDemandScreen extends StatelessWidget {
  const LiveOnDemandScreen({super.key, required this.items, this.onRefresh});
  final List<LiveVodItem> items;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('On demand')),
      body: RefreshIndicator(
        onRefresh: onRefresh ?? () async {},
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            childAspectRatio: 2 / 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return InkWell(
              onTap: item.onPlay,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: item.poster == null
                          ? const ColoredBox(color: Colors.black26)
                          : Image.network(item.poster!, fit: BoxFit.cover, width: double.infinity),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class LiveFixture {
  const LiveFixture({required this.title, required this.time, required this.onPlay, this.channel});
  final String title;
  final String time;
  final String? channel;
  final VoidCallback onPlay;
}

/// Today's fixtures.
class LiveSportsScreen extends StatelessWidget {
  const LiveSportsScreen({super.key, required this.fixtures});
  final List<LiveFixture> fixtures;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sports')),
      body: ListView.separated(
        itemCount: fixtures.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final fixture = fixtures[index];
          return ListTile(
            leading: const Icon(Icons.sports_soccer),
            title: Text(fixture.title),
            subtitle: Text([fixture.time, if (fixture.channel != null) fixture.channel!].join(' · ')),
            trailing: FilledButton(onPressed: fixture.onPlay, child: const Text('Watch')),
          );
        },
      ),
    );
  }
}
