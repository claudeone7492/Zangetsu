import 'package:flutter/material.dart';

/// Horizontal rail of backdrops for a detail page.
class StillsRail extends StatelessWidget {
  const StillsRail({super.key, required this.urls, this.headers, this.height = 140, this.onTap});

  final List<String> urls;
  final Map<String, String>? headers;
  final double height;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => GestureDetector(
          onTap: onTap == null ? null : () => onTap!(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              urls[index],
              headers: headers,
              width: height * 16 / 9,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
