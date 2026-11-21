import 'package:flutter/material.dart';

import '../../core/net/dns_providers.dart';
import '../../core/net/doh_dns.dart';
import '../../l10n/l10n.dart';

/// DNS mode, the settings half of Hikari's `net/DnsProviders.kt` +
/// `NetTuning.activeDns()`.
///
/// The list is exactly [DnsProviders.all]; picking one re-resolves the app's
/// own traffic through it (see DohDns.applyTo) and "Test" answers with what
/// that provider said about example.com.
class DnsModeScreen extends StatefulWidget {
  const DnsModeScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const DnsModeScreen());

  @override
  State<DnsModeScreen> createState() => _DnsModeScreenState();
}

class _DnsModeScreenState extends State<DnsModeScreen> {
  late final TextEditingController _custom = TextEditingController(
    text: DnsProviders.customUrl,
  );
  String? _result;
  bool _testing = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final failure = await DohDns.probe(DnsProviders.active);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = failure ?? '${context.l10n.ok} — example.com resolved';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dnsMode)),
      body: ValueListenableBuilder<int>(
        valueListenable: DnsProviders.revision,
        builder: (context, _, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l10n.interfaceScaleBody,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            RadioGroup<String>(
              groupValue: DnsProviders.choice,
              onChanged: (value) async {
                if (value == null) return;
                if (value == DnsProviders.custom &&
                    _custom.text.trim().isEmpty) {
                  return;
                }
                await DnsProviders.setChoice(value, customUrl: _custom.text);
                DohDns.invalidate();
                if (mounted) setState(() => _result = null);
              },
              child: Column(
                children: [
                  for (final provider in DnsProviders.all)
                    RadioListTile<String>(
                      value: provider.key,
                      title: Text(provider.label),
                      subtitle: Text(
                        provider.key == DnsProviders.custom &&
                                DnsProviders.customUrl.isNotEmpty
                            ? DnsProviders.customUrl
                            : provider.note,
                      ),
                    ),
                ],
              ),
            ),
            if (DnsProviders.choice == DnsProviders.custom)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _custom,
                  decoration: InputDecoration(
                    labelText: l10n.dnsCustomAddress,
                    hintText: 'https://dns.example.com/dns-query',
                  ),
                  onSubmitted: (value) async {
                    await DnsProviders.setChoice(
                      DnsProviders.custom,
                      customUrl: value,
                    );
                    DohDns.invalidate();
                    if (mounted) setState(() {});
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  FilledButton(
                    onPressed: _testing ? null : _test,
                    child: Text(_testing ? '…' : l10n.dnsTest),
                  ),
                  const SizedBox(width: 12),
                  if (_result != null)
                    Expanded(
                      child: Text(
                        _result!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
