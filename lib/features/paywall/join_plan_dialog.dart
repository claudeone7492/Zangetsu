import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';

/// Asks for the 8-character code the paying device shows in
/// Settings → Devices on this plan. Resolves the normalised code, or null when
/// the user backs out.
Future<String?> showJoinPlanDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _JoinPlanDialog(),
  );
}

class _JoinPlanDialog extends StatefulWidget {
  const _JoinPlanDialog();

  @override
  State<_JoinPlanDialog> createState() => _JoinPlanDialogState();
}

class _JoinPlanDialogState extends State<_JoinPlanDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _code =>
      _controller.text.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();

  void _submit() {
    if (_code.length < 6) return;
    Navigator.of(context).pop(_code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface2,
      title: const Text('Join a plan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'On the device that pays, open Settings → Devices on this plan and '
            'type the code it shows.',
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(8),
            ],
            style: AppText.title.copyWith(
              color: Colors.white,
              letterSpacing: 6,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              hintText: 'ABCD2345',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _code.length >= 6 ? _submit : null,
          child: const Text('Join'),
        ),
      ],
    );
  }
}
