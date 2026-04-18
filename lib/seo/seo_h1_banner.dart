import 'package:flutter/material.dart';

import 'seo_metadata.dart';

/// 公開頁頂部語意化主標（利於搜尋引擎理解主題）。
class SeoH1Banner extends StatelessWidget {
  const SeoH1Banner({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final h1 = SeoMetadata.forPath(path).h1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          header: true,
          child: SelectableText(
            h1,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  height: 1.25,
                ),
          ),
        ),
      ),
    );
  }
}
