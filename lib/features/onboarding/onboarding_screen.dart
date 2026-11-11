import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/ui/splash_style.dart';
import 'bankai_splash.dart';
import 'package:hive/hive.dart';

import '../../core/app_config.dart';
import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/provider/provider_registry.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../home/cubit/home_cubit.dart';
import 'onboarding_screen_tv.dart';
import '../../l10n/l10n.dart';

/// First-run flag, stored in the shared 'app_prefs' Hive box (opened during
/// [initDependencies]). True once the user has completed onboarding.
bool isOnboarded() {
  if (!Hive.isBoxOpen(ActiveSourceCubit.boxName)) return false;
  return Hive.box(
        ActiveSourceCubit.boxName,
      ).get('onboarded', defaultValue: false)
      as bool;
}

Future<void> _markOnboarded() =>
    Hive.box(ActiveSourceCubit.boxName).put('onboarded', true);

// ─────────────────────────────────────────────────────────────────────────────
// Splash — shown while initDependencies() runs.
// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  // Glow eases in; the wordmark fades in and "draws" left→right (wipe reveal)
  // while settling up to full scale; the loader appears last.
  late final Animation<double> _glow = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.12, 0.5, curve: Curves.easeOut),
  );
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Read once, at the start of the animation — the picker writes the box, and
  /// re-reading mid-build would let a change take effect halfway through a run.
  late final bool _bankai = SplashStyle.selectedId == 'bankai';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // The mark being cut in, driven by the same controller — one ticker
          // either way, so picking it costs nothing the wordmark did not.
          if (_bankai) {
            return Center(
              child: LayoutBuilder(
                builder: (context, box) => BankaiSplash(
                  progress: _c.value,
                  size: math.min(box.maxWidth * 0.62, 320),
                ),
              ),
            );
          }
          final r = _reveal.value;
          return Stack(
            children: [
              // Soft coral glow behind the wordmark — echoes the logo's circle.
              Center(
                child: Opacity(
                  opacity: _glow.value,
                  child: Container(
                    width: 460,
                    height: 460,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0.18),
                          AppColors.accent.withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Wordmark — wipe reveal (left→right) + fade + slight scale settle.
              Center(
                child: FractionallySizedBox(
                  widthFactor: 0.62,
                  child: Opacity(
                    opacity: _fade.value,
                    child: Transform.scale(
                      scale: 0.94 + 0.06 * r,
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: const [
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [
                            0.0,
                            (r - 0.07).clamp(0.0, 1.0),
                            r.clamp(0.0001, 1.0),
                          ],
                        ).createShader(rect),
                        child: Image.asset(
                          'assets/icon/wordmark.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding — first launch. Every source the app uses is bundled and installed
// during boot, so there is nothing here for the user to set up. This screen is
// a single automatic step: it activates the default source, loads Home, then
// hands off to the app via [onDone]. On the rare chance the bundled pack did
// not land (a truncated install), it retries once, then simply lets the user in.
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called once setup completes — the boot gate then shows the app shell.
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String _status = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  /// Activates a well-populated default so Home is useful on first open. The
  /// sources themselves are already installed by the boot pass; this only picks
  /// which one is active and primes Home. Best-effort: any failure still marks
  /// onboarding done so the user is never trapped on this screen.
  Future<void> _setup() async {
    if (mounted) {
      setState(() => _status = context.l10n.downloadingSourceCatalog);
    }
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

  @override
  Widget build(BuildContext context) {
    if (sl<AppMode>().isTv) return OnboardingScreenTv(onDone: widget.onDone);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            const _Logo(),
            const SizedBox(height: 18),
            Text(
              context.l10n.goodToHaveYouHere,
              style: AppText.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                context.l10n.onboardingIntro,
                style: AppText.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(flex: 3),
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
                const SizedBox(height: 12),
                Text(
                  _status,
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

/// The app mark in a soft accent tile.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Container(
    width: 84,
    height: 84,
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(22),
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.play_circle_fill_rounded,
      color: AppColors.accent,
      size: 46,
    ),
  );
}
