import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import 'app_toast.dart';

/// Copies a playback URL to the clipboard and confirms it with a toast.
///
/// Used by the player's source sheets and the Stremio link sheet, so a
/// long-press on any stream copies the exact URL to paste elsewhere.
Future<void> copyPlaybackLink(BuildContext context, String url) async {
  if (url.isEmpty) return;
  try {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) showAppToast(context, context.l10n.playbackLinkCopied);
  } on PlatformException {
    if (context.mounted) showAppToast(context, context.l10n.couldNotCopyLink);
  }
}
