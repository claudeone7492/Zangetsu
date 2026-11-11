import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../core/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/provider/provider_registry.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../home/cubit/home_cubit.dart';
import '../../l10n/l10n.dart';

Future<void> _markOnboarded() =>
    Hive.box(ActiveSourceCubit.boxName).put('onboarded', true);

/// TV-adapted first-run onboarding. Like the phone [OnboardingScreen] it is a
/// single automatic step: the sources are bundled and installed during boot, so
/// this only activates the default source, primes Home, and hands off. There is
/// nothing for the user to configure — no buttons to press.
class OnboardingScreenTv extends StatefulWidget {
  const OnboardingScreenTv({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreenTv> createState() => _OnboardingScreenTvState();
}

class _OnboardingScreenTvState extends State<OnboardingScreenTv> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  /// Activates a well-populated default so Home is useful on first open. The
  /// sources themselves are already installed by the boot pass. Best-effort:
  /// any failure still marks onboarding done so the user is never trapped.
  Future<void> _setup() async {
    try {
      final active = sl<ActiveSourceCubit>();
      final installed = [
        for (final e in sl<ProviderRegistry>().getAll())
          if (e.enabled) e.name,
      ];
      if (installed.isNotEmpty) {
        active.setSource(
          installed.contains(kDefaultSourceId)
              ? kDefaultSourceId
              : installed.first,
        );
      }
      if (sl.isRegistered<HomeCubit>()) sl<HomeCubit>().load();
    } catch (_) {
      // Sources install during boot; a failure here is not worth blocking on.
    }
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

  @override
  Widget build(BuildContext context) {
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
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.downloadingSourceCatalog,
                  style: AppText.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
