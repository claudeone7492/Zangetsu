import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../core/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/provider/provider_registry.dart';
import '../../core/provider/provider_repo_registry.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_focusable.dart';
import '../home/cubit/home_cubit.dart';
import 'how_it_works.dart';
import '../../l10n/l10n.dart';

Future<void> _markOnboarded() =>
    Hive.box(ActiveSourceCubit.boxName).put('onboarded', true);

/// TV-adapted first-run onboarding. Reuses the exact same state machine and
/// source-install logic as the phone [OnboardingScreen] — only the interaction
/// model changes: every action button is a [TvFocusable] so the D-pad reaches
/// it and OK activates it. [HowItWorksView] is reused unchanged for the tips
/// step.
class OnboardingScreenTv extends StatefulWidget {
  const OnboardingScreenTv({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreenTv> createState() => _OnboardingScreenTvState();
}

class _OnboardingScreenTvState extends State<OnboardingScreenTv> {
  bool _busy = false;
  String? _error;
  String _status = '';
  bool _showTips = false;

  /// Downloads the official Zangetsu provider repo and installs every source,
  /// then activates a well-populated default so Home is useful on first open.
  /// A single source that fails is skipped rather than failing the whole run.
  Future<void> _setup() async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
      _status = l10n.downloadingSourceCatalog;
    });
    try {
      final repos = sl<ProviderReposRegistry>();
      final registry = sl<ProviderRegistry>();
      final repo = await repos.fetchAndCache(kZangetsuRepoUrl);
      final total = repo.sources.length;
      var installed = 0;
      final installedIds = <String>[];
      for (final s in repo.sources) {
        if (!mounted) return;
        setState(
          () => _status = l10n.installingSource(s.name, installed + 1, total),
        );
        try {
          await registry.install(
            sourceId: s.id,
            fileUrl: repos.resolveFileUrl(repo, s),
            repoUrl: repo.url,
            displayName: s.name,
            version: s.version,
            force: true,
          );
          installed++;
          installedIds.add(s.id);
        } catch (_) {
          // Skip a single failed source; keep installing the rest.
        }
      }
      if (installed == 0) {
        throw Exception('No sources could be installed');
      }
      // New TV users default to AniKoto; fall back to the first installed source
      // if it didn't install. Runs only on first-run onboarding — existing users
      // keep their saved pick.
      sl<ActiveSourceCubit>().setSource(
        installedIds.contains(kDefaultSourceId)
            ? kDefaultSourceId
            : installedIds.first,
      );
      sl<HomeCubit>().load();
      await _markOnboarded();
      if (mounted) {
        setState(() {
          _busy = false;
          _showTips = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.setupFailedCheckConnection;
      });
    }
  }

  Future<void> _skip() async {
    await _markOnboarded();
    if (mounted) widget.onDone();
  }

  Widget _bullet(IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, color: AppColors.accent, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: AppText.body.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    ),
  );

  /// Post-setup "how it works" guide — same content as the phone, button is
  /// [TvFocusable] with autofocus so the D-pad lands on it immediately.
  Widget _buildTips() => Scaffold(
    backgroundColor: AppColors.bg,
    body: SafeArea(
      child: Center(
        child: SizedBox(
          width: 680,
          child: Column(
            children: [
              const SizedBox(height: 40),
              Text(
                context.l10n.allSet,
                style: AppText.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Expanded(child: HowItWorksView()),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
                child: TvFocusable(
                  autofocus: true,
                  onTap: widget.onDone,
                  child: ExcludeFocus(
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        onPressed: widget.onDone,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          context.l10n.startWatching,
                          style: AppText.button.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_showTips) return _buildTips();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Text(
                  context.l10n.welcomeToApp(kAppName),
                  style: AppText.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.onboardingTvSubtitle(kAppName),
                  style: AppText.body.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 26),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bullet(
                      Icons.dns_rounded,
                      context.l10n.multipleStreamingSources,
                    ),
                    _bullet(
                      Icons.high_quality_rounded,
                      context.l10n.upTo4kHdrStreams,
                    ),
                    _bullet(
                      Icons.cloud_download_outlined,
                      context.l10n.autoUpdatingNoAppUpdate,
                    ),
                  ],
                ),
                const Spacer(flex: 3),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: AppText.caption.copyWith(color: AppColors.accent),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                ],
                if (_busy)
                  Column(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _status,
                        style: AppText.caption,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                else ...[
                  TvFocusable(
                    autofocus: true,
                    onTap: _setup,
                    child: ExcludeFocus(
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: _setup,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _error == null
                                ? context.l10n.getStarted
                                : context.l10n.retry,
                            style: AppText.button.copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TvFocusable(
                    autofocus: false,
                    onTap: _skip,
                    child: ExcludeFocus(
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: TextButton(
                          onPressed: _skip,
                          child: Text(
                            context.l10n.skipForNow,
                            style: AppText.caption.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
