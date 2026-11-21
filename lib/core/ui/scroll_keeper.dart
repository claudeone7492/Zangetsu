import 'package:flutter/widgets.dart';

/// Stable scroll keys for rows that rebuild.
class ScrollKeeper {
  const ScrollKeeper._();

  static PageStorageKey<String> keyFor(String id) => PageStorageKey<String>('scroll:$id');
}
