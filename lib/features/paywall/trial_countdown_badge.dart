import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/subscription/trial_countdown.dart';
import '../../core/theme/app_colors.dart';

/// Top-left glass pill showing the remaining free-trial time.
///
/// It reads [TrialCountdownController.countdown], which is null for paid
/// subscribers and when no trial is running, so the badge disappears rather
/// than showing a misleading "0s" or a paid-plan countdown.
class TrialCountdownBadge extends StatelessWidget {
  const TrialCountdownBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TrialCountdown?>(
      valueListenable: TrialCountdownController.instance.countdown,
      builder: (context, value, _) {
        if (value == null) return const SizedBox.shrink();
        final urgent = value.remaining <= const Duration(hours: 24);
        final iconColor = urgent ? AppColors.accent : Colors.white70;

        return Semantics(
          label: 'Free trial: ${value.compactLabel} remaining',
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  key: const ValueKey('trial-countdown-badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.17),
                        AppColors.bg.withValues(alpha: 0.42),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 14, color: iconColor),
                      const SizedBox(width: 6),
                      Text(
                        'Free trial',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        value.compactLabel,
                        style: TextStyle(
                          color: urgent ? AppColors.accent : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
