import 'package:flutter/material.dart';

/// One shared help surface, used by settings rows and empty states.
Future<void> showHelpSheet(
  BuildContext context, {
  required String title,
  required String body,
  List<({String label, String text})> sections = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
          for (final section in sections) ...[
            const SizedBox(height: 20),
            Text(section.label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(section.text, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    ),
  );
}
