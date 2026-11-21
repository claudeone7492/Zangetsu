import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../di/injector.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../ui/buttons.dart';
import '../ui/frosted_surface.dart';
import 'bandwidth_share.dart';

/// Shows the cookie consent card once, on the first launch where it has not
/// been answered.
///
/// A small, transparent-glass card: a short note on the cookies we use, an
/// [accept] that allows everything, and [manage] for granular control. Accepting
/// is what turns on the optional background service — nothing runs until the
/// user answers.
Future<void> maybeShowCookiesConsent(
  BuildContext context, {
  BandwidthShare? share,
}) async {
  final s = share ?? _registeredShare();
  if (s == null) return;
  // Wait for the saved answer: the shell opens this on its first frame, before
  // the channel round trip that reads native storage has finished.
  await s.ready;
  if (!s.supported || !s.available || s.answeredConsent) return;
  if (!context.mounted) return;
  await showCookiesConsentSheet(context, share: s);
}

/// Opens the cookie card regardless of prior answer (used by "Learn more").
Future<void> showCookiesConsentSheet(
  BuildContext context, {
  BandwidthShare? share,
}) {
  final s = share ?? _registeredShare();
  if (s == null) return Future<void>.value();
  // Not dismissible: the answer is what stops this card returning, so it is
  // taken here — Accept or Manage — rather than by a tap outside or the back
  // gesture that records nothing.
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => PopScope(
      canPop: false,
      child: _CookiesConsentCard(share: s),
    ),
  );
}

BandwidthShare? _registeredShare() =>
    sl.isRegistered<BandwidthShare>() ? sl<BandwidthShare>() : null;

/// The small glass card, and the preferences view it swaps to.
class _CookiesConsentCard extends StatefulWidget {
  const _CookiesConsentCard({required this.share});

  final BandwidthShare share;

  @override
  State<_CookiesConsentCard> createState() => _CookiesConsentCardState();
}

class _CookiesConsentCardState extends State<_CookiesConsentCard> {
  bool _showPrefs = false;
  bool _performance = true;
  bool _busy = false;
  bool _failed = false;

  /// Accepts, then closes only once the SDK has come up.
  ///
  /// The sheet is the user's one chance to answer, so it stays put while the
  /// peer registers: the Accept button spins, and a refused key or relay keeps
  /// the card open with the failure named instead of dismissing into a switch
  /// that reads off. Nothing is lost by retrying — the answer is already saved.
  Future<void> _accept() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    await widget.share.accept();
    if (!mounted) return;
    if (widget.share.status == BandwidthShareStatus.error) {
      setState(() {
        _busy = false;
        _failed = true;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _savePrefs() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    if (_performance) {
      await widget.share.accept();
      if (!mounted) return;
      if (widget.share.status == BandwidthShareStatus.error) {
        setState(() {
          _busy = false;
          _failed = true;
        });
        return;
      }
    } else {
      await widget.share.decline();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: FrostedSurface(
              opacity: 0.28,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _showPrefs
                      ? _prefs(context, l)
                      : _intro(context, l),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _intro(BuildContext context, AppLocalizations l) => [
    Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            Icons.cookie_outlined,
            color: AppColors.accent,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l.cookiesSheetTitle,
            style: AppText.title.copyWith(fontSize: 18),
          ),
        ),
      ],
    ),
    const SizedBox(height: 14),
    Text(
      l.cookiesSheetBody,
      style: AppText.caption.copyWith(
        color: AppColors.textSecondary,
        height: 1.45,
      ),
    ),
    if (_failed) ...[
      const SizedBox(height: 12),
      _FailureNote(text: l.bandwidthStatusError),
    ],
    const SizedBox(height: 18),
    SizedBox(
      width: double.infinity,
      child: PrimaryButton(
        label: l.cookiesSheetAccept,
        icon: Icons.check_rounded,
        loading: _busy,
        onPressed: _busy ? null : _accept,
      ),
    ),
    const SizedBox(height: 10),
    SizedBox(
      width: double.infinity,
      child: SecondaryButton(
        label: l.cookiesSheetManage,
        onPressed: _busy ? null : () => setState(() => _showPrefs = true),
      ),
    ),
  ];

  List<Widget> _prefs(BuildContext context, AppLocalizations l) => [
    Text(l.cookiesPrefsTitle, style: AppText.title.copyWith(fontSize: 18)),
    const SizedBox(height: 14),
    _PrefRow(
      title: l.cookiesPrefsEssentialTitle,
      body: l.cookiesPrefsEssentialBody,
      trailing: Text(
        l.cookiesPrefsAlwaysOn,
        style: AppText.caption.copyWith(color: AppColors.textTertiary),
      ),
    ),
    const SizedBox(height: 10),
    _PrefRow(
      title: l.cookiesPrefsPerformanceTitle,
      body: l.cookiesPrefsPerformanceBody,
      trailing: Switch.adaptive(
        value: _performance,
        activeThumbColor: AppColors.accent,
        onChanged: _busy ? null : (v) => setState(() => _performance = v),
      ),
    ),
    if (_failed) ...[
      const SizedBox(height: 12),
      _FailureNote(text: l.bandwidthStatusError),
    ],
    const SizedBox(height: 18),
    SizedBox(
      width: double.infinity,
      child: PrimaryButton(
        label: l.cookiesPrefsSave,
        icon: Icons.check_rounded,
        loading: _busy && _performance,
        onPressed: _busy ? null : _savePrefs,
      ),
    ),
  ];
}

/// One line under the buttons when the peer refused to come up.
class _FailureNote extends StatelessWidget {
  const _FailureNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _PrefRow extends StatelessWidget {
  const _PrefRow({required this.title, required this.body, this.trailing});

  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.body),
              const SizedBox(height: 2),
              Text(
                body,
                style: AppText.caption.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}
