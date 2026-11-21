import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/states.dart';
import '../../core/web/userscript_store.dart';
import '../../l10n/l10n.dart';

/// The installed userscripts, with an add sheet that accepts either a pasted
/// `==UserScript==` file or a hand-written name + match list + body.
class UserscriptsScreen extends StatefulWidget {
  const UserscriptsScreen({super.key});

  @override
  State<UserscriptsScreen> createState() => _UserscriptsScreenState();
}

class _UserscriptsScreenState extends State<UserscriptsScreen> {
  List<Userscript> _scripts = UserscriptStore.instance.all;

  void _reload() {
    if (mounted) setState(() => _scripts = UserscriptStore.instance.all);
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<_NewScript>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const _AddScriptSheet(),
    );
    if (result == null || !mounted) return;
    try {
      await UserscriptStore.instance.add(
        name: result.name,
        matches: result.matches,
        code: result.code,
      );
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.userscriptAdded)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.userscriptInvalid)),
      );
    }
  }

  Future<void> _remove(Userscript script) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(context.l10n.delete),
        content: Text(script.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await UserscriptStore.instance.remove(script.id);
    _reload();
  }

  Future<void> _toggle(Userscript script, bool value) async {
    await UserscriptStore.instance.setEnabled(script.id, value);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(context.l10n.userscripts),
        actions: [
          IconButton(
            tooltip: context.l10n.addUserscript,
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _scripts.isEmpty
          ? EmptyState(
              icon: Icons.code_rounded,
              message: context.l10n.userscriptsEmpty,
              actionLabel: context.l10n.addUserscript,
              onAction: _add,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                for (final script in _scripts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(script.name, style: AppText.body),
                              Text(
                                script.matches.join(', '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: script.enabled,
                          activeThumbColor: AppColors.accent,
                          onChanged: (value) => _toggle(script, value),
                        ),
                        IconButton(
                          tooltip: context.l10n.delete,
                          onPressed: () => _remove(script),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NewScript {
  const _NewScript({
    required this.name,
    required this.matches,
    required this.code,
  });

  final String name;
  final List<String> matches;
  final String code;
}

class _AddScriptSheet extends StatefulWidget {
  const _AddScriptSheet();

  @override
  State<_AddScriptSheet> createState() => _AddScriptSheetState();
}

class _AddScriptSheetState extends State<_AddScriptSheet> {
  final _name = TextEditingController();
  final _matches = TextEditingController();
  final _code = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _name.dispose();
    _matches.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = true);
      return;
    }
    var name = _name.text.trim();
    var matches = _matches.text
        .split(RegExp(r'[\n,]'))
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
    // A pasted Tampermonkey file carries its own name and @match list; use
    // them when the fields above were left blank.
    final parsed = UserscriptStore.parse(code);
    if (parsed != null) {
      if (name.isEmpty) name = parsed.name;
      if (matches.isEmpty) matches = parsed.matches;
    }
    if (name.isEmpty && matches.isEmpty) {
      setState(() => _error = true);
      return;
    }
    Navigator.of(context).pop(
      _NewScript(name: name, matches: matches, code: code),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.addUserscript, style: AppText.headline),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.l10n.userscriptName,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _matches,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.l10n.userscriptMatches,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              minLines: 6,
              maxLines: 14,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.l10n.userscriptCode,
                alignLabelWithHint: true,
              ),
            ),
            if (_error) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.userscriptInvalid,
                style: AppText.caption.copyWith(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                  ),
                  onPressed: _submit,
                  child: Text(context.l10n.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
