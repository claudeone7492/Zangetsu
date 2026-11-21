import 'package:flutter/material.dart';

import '../../core/telegram/telegram_prefs.dart';
import '../../core/telegram/telegram_service.dart';
import '../../core/telegram/telegram_source.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';

/// The TDLib sign-in card on the Telegram screen.
///
/// Telegram's own client model is a phone number and a code, so that is what
/// this asks for. The `api_id`/`api_hash` pair comes from my.telegram.org —
/// they identify the app, not the viewer, and Telegram refuses a client
/// without them.
///
/// The card is a state machine over [TelegramService.authState]: each step
/// shows exactly one field, and a step that fails says why instead of leaving
/// the viewer on a spinner.
class TelegramSignInCard extends StatefulWidget {
  const TelegramSignInCard({
    super.key,
    required this.service,
    required this.prefs,
    required this.onSignedIn,
  });

  final TelegramService service;
  final TelegramPrefs prefs;

  /// Called once the state reaches `ready`, so the screen can reload a channel
  /// through the now-usable native path.
  final VoidCallback onSignedIn;

  @override
  State<TelegramSignInCard> createState() => _TelegramSignInCardState();
}

class _TelegramSignInCardState extends State<TelegramSignInCard> {
  final TextEditingController _apiId = TextEditingController();
  final TextEditingController _apiHash = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();

  String _state = 'idle';
  String? _reason;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _apiId.text = widget.prefs.apiId;
    _apiHash.text = widget.prefs.apiHash;
    _refresh();
  }

  @override
  void dispose() {
    _apiId.dispose();
    _apiHash.dispose();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = await widget.service.authState();
    final reason = state == 'unavailable'
        ? await widget.service.unavailableReason()
        : null;
    if (!mounted) return;
    setState(() {
      _state = state;
      _reason = reason;
    });
  }

  Future<void> _run(Future<String> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await step();
      if (!mounted) return;
      setState(() {
        _state = state;
        _busy = state == 'starting';
      });
      if (state == 'starting') await _awaitSettled();
    } on TelegramException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.telegramFailed;
        _busy = false;
      });
    }
  }

  /// TDLib answers a login step asynchronously, so a step that returns
  /// `starting` is not a state to draw — it is a state to wait out. Poll until
  /// TDLib names the next step, or give up and let the viewer retry.
  Future<void> _awaitSettled() async {
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final state = await widget.service.authState();
      if (!mounted) return;
      if (state == 'starting') continue;
      setState(() {
        _state = state;
        _busy = false;
      });
      if (state == 'ready') widget.onSignedIn();
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = context.l10n.telegramFailed;
    });
  }

  Future<void> _saveCredentials() async {
    await widget.prefs.saveCredentials(_apiId.text, _apiHash.text);
    await _run(() => widget.service.setCredentials(_apiId.text, _apiHash.text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_state == 'unavailable') {
      return _Card(
        child: Text(
          _reason == null
              ? l10n.telegramTdlibUnavailable
              : '${l10n.telegramTdlibUnavailable}\n$_reason',
          style: AppText.caption.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.telegramSignInTitle, style: AppText.title),
          const SizedBox(height: 6),
          Text(
            l10n.telegramSignInBody,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          ..._fields(l10n),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: AppText.caption.copyWith(color: AppColors.accent),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  List<Widget> _fields(AppLocalizations l10n) {
    switch (_state) {
      case 'ready':
        return [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(l10n.telegramSignedIn)),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await widget.service.signOut();
                        await _refresh();
                      },
                child: Text(l10n.telegramSignOut),
              ),
            ],
          ),
        ];
      case 'waitCode':
        return [
          _field(_code, l10n.telegramCode, TextInputType.number),
          _action(l10n.save, () => _run(() => widget.service.submitCode(_code.text))),
        ];
      case 'waitPassword':
        return [
          _field(_password, l10n.telegramPassword, TextInputType.text, obscure: true),
          _action(
            l10n.save,
            () => _run(() => widget.service.submitPassword(_password.text)),
          ),
        ];
      case 'waitPhone':
        return [
          _field(_phone, l10n.telegramPhone, TextInputType.phone),
          _action(
            l10n.save,
            () => _run(() => widget.service.submitPhone(_phone.text)),
          ),
        ];
      case 'starting':
        return [
          Text(
            l10n.telegramSignInTitle,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
        ];
      default:
        // idle or closed: the credentials step, then the phone step.
        return [
          _field(_apiId, 'api_id', TextInputType.number),
          _field(_apiHash, 'api_hash', TextInputType.text),
          _action(l10n.save, _saveCredentials),
          const SizedBox(height: 8),
          _field(_phone, l10n.telegramPhone, TextInputType.phone),
          _action(
            l10n.signIn,
            () => _run(() => widget.service.submitPhone(_phone.text)),
          ),
        ];
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    TextInputType keyboard, {
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label, isDense: true),
    ),
  );

  Widget _action(String label, VoidCallback onPressed) => Align(
    alignment: Alignment.centerRight,
    child: FilledButton(
      onPressed: _busy ? null : onPressed,
      child: Text(label),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}
