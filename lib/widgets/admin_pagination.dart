import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';

/// 後台列表每頁筆數（與 [AdminPagedDocumentsFrame] 共用）
const int kAdminListPageSize = 20;

/// 將 [docs] 分頁顯示，底部顯示「上一頁／下一頁」（僅在超過一頁時顯示）。
class AdminPagedDocumentsFrame extends StatefulWidget {
  const AdminPagedDocumentsFrame({
    super.key,
    required this.docs,
    this.pageSize = kAdminListPageSize,
    this.expand = true,
    required this.childBuilder,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final int pageSize;
  /// 為 `false` 時不用 [Expanded]，適合放在 [SingleChildScrollView] 內（子列表請設 [shrinkWrap]: true）。
  final bool expand;
  final Widget Function(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pageDocs,
  ) childBuilder;

  @override
  State<AdminPagedDocumentsFrame> createState() =>
      _AdminPagedDocumentsFrameState();
}

class _AdminPagedDocumentsFrameState extends State<AdminPagedDocumentsFrame> {
  int _page = 0;

  @override
  void didUpdateWidget(covariant AdminPagedDocumentsFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    final n = widget.docs.length;
    if (n == 0) {
      if (_page != 0) setState(() => _page = 0);
      return;
    }
    final totalPages =
        math.max(1, (n + widget.pageSize - 1) ~/ widget.pageSize);
    if (_page >= totalPages) {
      setState(() => _page = totalPages - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final n = widget.docs.length;
    final ps = widget.pageSize;
    final totalPages = n == 0 ? 1 : math.max(1, (n + ps - 1) ~/ ps);
    final start = _page * ps;
    final end = math.min(start + ps, n);
    final pageDocs =
        start < n ? widget.docs.sublist(start, end) : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    final main = widget.childBuilder(context, pageDocs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.expand)
          Expanded(child: main)
        else
          main,
        if (n > ps)
          AdminPaginationControls(
            totalItems: n,
            currentPage: _page,
            totalPages: totalPages,
            onPrev: _page > 0 ? () => setState(() => _page--) : null,
            onNext:
                _page < totalPages - 1 ? () => setState(() => _page++) : null,
            lang: lang,
          ),
      ],
    );
  }
}

/// 泛用列表分頁（廣告貼文訂單等經篩選後的列表）。
class AdminPagedGenericFrame<T> extends StatefulWidget {
  const AdminPagedGenericFrame({
    super.key,
    required this.items,
    this.pageSize = kAdminListPageSize,
    this.expand = true,
    this.shrinkWrap = false,
    required this.itemBuilder,
  });

  final List<T> items;
  final int pageSize;
  final bool expand;
  /// 為 true 時列表 [shrinkWrap]，供放在 [SingleChildScrollView] 內。
  final bool shrinkWrap;
  final Widget Function(BuildContext context, int index, T item) itemBuilder;

  @override
  State<AdminPagedGenericFrame<T>> createState() =>
      _AdminPagedGenericFrameState<T>();
}

class _AdminPagedGenericFrameState<T> extends State<AdminPagedGenericFrame<T>> {
  int _page = 0;

  @override
  void didUpdateWidget(covariant AdminPagedGenericFrame<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final n = widget.items.length;
    if (n == 0) {
      if (_page != 0) setState(() => _page = 0);
      return;
    }
    final totalPages =
        math.max(1, (n + widget.pageSize - 1) ~/ widget.pageSize);
    if (_page >= totalPages) {
      setState(() => _page = totalPages - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final n = widget.items.length;
    final ps = widget.pageSize;
    final totalPages = n == 0 ? 1 : math.max(1, (n + ps - 1) ~/ ps);
    final start = _page * ps;
    final end = math.min(start + ps, n);
    final pageItems =
        start < n ? widget.items.sublist(start, end) : <T>[];

    final list = ListView.separated(
      padding: const EdgeInsets.all(16),
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : null,
      itemCount: pageItems.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) =>
          widget.itemBuilder(context, start + i, pageItems[i]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.expand)
          Expanded(child: list)
        else
          list,
        if (n > ps)
          AdminPaginationControls(
            totalItems: n,
            currentPage: _page,
            totalPages: totalPages,
            onPrev: _page > 0 ? () => setState(() => _page--) : null,
            onNext:
                _page < totalPages - 1 ? () => setState(() => _page++) : null,
            lang: lang,
          ),
      ],
    );
  }
}

class AdminPaginationControls extends StatelessWidget {
  const AdminPaginationControls({
    super.key,
    required this.totalItems,
    required this.currentPage,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
    required this.lang,
  });

  final int totalItems;
  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final LanguageProvider lang;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Text(
              lang
                  .getString('admin_pagination_summary')
                  .replaceAll('{count}', '$totalItems')
                  .replaceAll('{current}', '${currentPage + 1}')
                  .replaceAll('{total}', '$totalPages'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
            OutlinedButton(
              onPressed: onPrev,
              child: Text(lang.getString('admin_pagination_prev')),
            ),
            OutlinedButton(
              onPressed: onNext,
              child: Text(lang.getString('admin_pagination_next')),
            ),
          ],
        ),
      ),
    );
  }
}
