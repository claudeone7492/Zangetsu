import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';

Future<List<Map<String, dynamic>>?> showMangayomiFilterSheet(
  BuildContext context,
  List<Map<String, dynamic>> filters,
) {
  final selected = (jsonDecode(jsonEncode(filters)) as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  return showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Source filters',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, selected),
                      child: Text(context.l10n.apply),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final filter in selected)
                      _filterRow(context, filter, update),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _filterRow(
  BuildContext context,
  Map<String, dynamic> filter,
  StateSetter update,
) {
  final name = filter['name']?.toString() ?? '';
  final kind = filter['type_name']?.toString() ?? '';
  switch (kind) {
    case 'SelectFilter':
      final values = filter['values'] is List
          ? filter['values'] as List
          : const [];
      if (values.isEmpty) return const SizedBox.shrink();
      final current =
          filter['state'] is int &&
              (filter['state'] as int) >= 0 &&
              (filter['state'] as int) < values.length
          ? filter['state'] as int
          : 0;
      return ListTile(
        title: Text(name),
        trailing: DropdownButton<int>(
          value: current,
          items: [
            for (var i = 0; i < values.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text((values[i] as Map)['name']?.toString() ?? '$i'),
              ),
          ],
          onChanged: (value) => update(() => filter['state'] = value),
        ),
      );
    case 'CheckBoxFilter':
      return SwitchListTile(
        title: Text(name),
        value: filter['state'] == true,
        onChanged: (value) => update(() => filter['state'] = value),
      );
    case 'TriStateFilter':
      final state = filter['state'] is int ? filter['state'] as int : 0;
      return ListTile(
        title: Text(name),
        trailing: DropdownButton<int>(
          value: state.clamp(0, 2),
          items: [
            DropdownMenuItem(value: 0, child: Text(context.l10n.any)),
            const DropdownMenuItem(value: 1, child: Text('Include')),
            const DropdownMenuItem(value: 2, child: Text('Exclude')),
          ],
          onChanged: (value) => update(() => filter['state'] = value),
        ),
      );
    case 'TextFilter':
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: TextFormField(
          initialValue: filter['state']?.toString() ?? '',
          decoration: InputDecoration(labelText: name),
          onChanged: (value) => filter['state'] = value,
        ),
      );
    case 'GroupFilter':
      final children = filter['state'] is List
          ? filter['state'] as List
          : const [];
      return ExpansionTile(
        title: Text(name),
        children: [
          for (final child in children)
            if (child is Map)
              _filterRow(context, child.cast<String, dynamic>(), update),
        ],
      );
    case 'SortFilter':
      final values = filter['values'] is List
          ? filter['values'] as List
          : const [];
      final state = filter['state'] is Map
          ? (filter['state'] as Map).cast<String, dynamic>()
          : <String, dynamic>{'index': 0, 'ascending': true};
      if (values.isEmpty) return const SizedBox.shrink();
      final index =
          state['index'] is int &&
              (state['index'] as int) >= 0 &&
              (state['index'] as int) < values.length
          ? state['index'] as int
          : 0;
      return Column(
        children: [
          ListTile(
            title: Text(name),
            trailing: DropdownButton<int>(
              value: index,
              items: [
                for (var i = 0; i < values.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text((values[i] as Map)['name']?.toString() ?? '$i'),
                  ),
              ],
              onChanged: (value) => update(() => state['index'] = value),
            ),
          ),
          SwitchListTile(
            title: const Text('Ascending'),
            value: state['ascending'] == true,
            onChanged: (value) => update(() => state['ascending'] = value),
          ),
        ],
      );
    case 'HeaderFilter':
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    case 'SeparatorFilter':
      return const Divider();
    default:
      return ListTile(
        title: Text(name.isEmpty ? 'Source filter' : name),
        subtitle: const Text('This filter type is not supported yet'),
      );
  }
}
