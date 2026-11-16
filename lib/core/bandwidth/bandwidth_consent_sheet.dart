import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../di/injector.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../ui/buttons.dart';
import '../ui/frosted_surface.dart';
import 'bandwidth_share.dart';

/// Shows the bandwidth-sharing consent sheet, once, on the first launch where
/// it has not been answered.
///
/// Deliberately a **disclosure**, not a cookie banner: the copy says exactly
/// what the feature does — share a little idle bandwidth with the Proxies.sx
/// peer network, using data and battery — and the accept button is the only
/// thing that starts it. The sheet is skippable ([decline]) and never blocks
/// the app.
Future<void> maybeShowBandwidthConsent(BuildContext context) async {
  if (!sl.isRegistered<BandwidthShare>()) return;
  final share = sl<BandwidthShare>();
  if (!share.supported || share.answeredConsent) return;
  await showBandwidthConsentSheet(context);
}

/// Opens the consent sheet regardless of prior answer (used by "Learn more").
Future<void> showBandwidthConsentSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => const _BandwidthConsentSheet(),
  );
}

class _BandwidthConsentSheet extends StatefulWidget {
  const _BandwidthConsentSheet();

  @override
  State<_BandwidthConsentSheet> createState() => _BandwidthConsentSheetState();
}

class _BandwidthConsentSheetState extends State<_BandwidthConsentSheet> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    await sl<BandwidthShare>().accept();
    if (nav.mounted) nav.pop();
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    await sl<BandwidthShare>().decline();
    if (nav.mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FrostedSurface(
        opacity: 0.92,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.wifi_tethering_rounded,
                        color: AppColors.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.bandwidthSheetTitle,
                        style: AppText.title.copyWith(fontSize: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  l.bandwidthSheetBody,
                  style: AppText.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                _Bullet(text: l.bandwidthSheetBullet1),
                _Bullet(text: l.bandwidthSheetBullet2),
                _Bullet(text: l.bandwidthSheetBullet3),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: l.bandwidthSheetAccept,
                    icon: Icons.check_rounded,
                    onPressed: _busy ? null : _accept,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SecondaryButton(
                    label: l.bandwidthSheetDecline,
                    onPressed: _busy ? null : _decline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppText.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
