import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../services/feed_firestore_service.dart';
import '../services/firebase_bootstrap.dart';
import '../utils/constants.dart';
import '../widgets/admin_pagination.dart';

/// 懷疑違規：待審貼文批准／拒絕；會員舉報之刪除、不理、警告、黑名單。
class AdminSectionKPage extends StatefulWidget {
  const AdminSectionKPage({super.key});

  @override
  State<AdminSectionKPage> createState() => _AdminSectionKPageState();
}

class _AdminSectionKPageState extends State<AdminSectionKPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_k')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: lang.getString('admin_sec_k_tab_pending')),
            Tab(text: lang.getString('admin_sec_k_tab_reports')),
          ],
        ),
      ),
      body: !FirebaseBootstrap.isReady
          ? Center(child: Text(lang.getString('admin_sec_empty')))
          : TabBarView(
              controller: _tab,
              children: [
                _PendingModerationTab(lang: lang),
                _MemberReportsTab(lang: lang),
              ],
            ),
    );
  }
}

class _PendingModerationTab extends StatelessWidget {
  const _PendingModerationTab({required this.lang});

  final LanguageProvider lang;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FeedFirestoreService.instance.watchPendingFeedPosts(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('${snap.error}'));
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(child: Text(lang.getString('admin_sec_k_empty')));
        }
        return AdminPagedDocumentsFrame(
          docs: docs,
          childBuilder: (context, pageDocs) {
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pageDocs.length,
              itemBuilder: (context, i) {
            final d = pageDocs[i];
            final m = d.data();
            final name = (m['authorName'] as String?) ?? '—';
            final content = (m['content'] as String?) ?? '';
            final tag = (m['tag'] as String?) ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (tag.isNotEmpty)
                          Chip(
                            label: Text(tag, style: const TextStyle(fontSize: 12)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(content),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            await FeedFirestoreService.instance
                                .rejectPendingFeedPost(d.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(lang.getString('admin_sec_k_rejected')),
                                ),
                              );
                            }
                          },
                          child: Text(lang.getString('admin_sec_reject')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            try {
                              await FeedFirestoreService.instance
                                  .approvePendingFeedPost(d.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      lang.getString('admin_sec_k_approved'),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$e')),
                                );
                              }
                            }
                          },
                          child: Text(lang.getString('admin_sec_approve')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
              },
            );
          },
        );
      },
    );
  }
}

class _MemberReportsTab extends StatelessWidget {
  const _MemberReportsTab({required this.lang});

  final LanguageProvider lang;

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _sorted(
    QuerySnapshot<Map<String, dynamic>>? snap,
  ) {
    final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
      snap?.docs ?? const [],
    );
    docs.sort((a, b) {
      final ta = a.data()['createdAt'];
      final tb = b.data()['createdAt'];
      final ia = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
      final ib = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
      return ib.compareTo(ia);
    });
    return docs;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FeedFirestoreService.instance.watchPendingFeedPostReports(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('${snap.error}'));
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = _sorted(snap.data);
        if (docs.isEmpty) {
          return Center(child: Text(lang.getString('admin_sec_k_reports_empty')));
        }
        return AdminPagedDocumentsFrame(
          docs: docs,
          childBuilder: (context, pageDocs) {
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pageDocs.length,
              itemBuilder: (context, i) {
            final d = pageDocs[i];
            final m = d.data();
            final postId = (m['postId'] as String?) ?? '';
            final authorUid = (m['postAuthorUid'] as String?) ?? '';
            final detail = (m['detail'] as String?) ?? '';
            final preview = (m['contentPreview'] as String?) ?? '';
            final authorName = (m['postAuthorDisplayName'] as String?) ?? '—';
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${lang.getString('admin_report_post_label')}: $postId',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${lang.getString('admin_report_author_label')}: $authorName',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        preview,
                        style: const TextStyle(fontSize: 14, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${lang.getString('admin_report_reason_label')}:',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(detail),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            await FeedFirestoreService.instance
                                .resolveFeedReportIgnore(d.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(lang.getString('admin_report_ignored')),
                                ),
                              );
                            }
                          },
                          child: Text(lang.getString('admin_report_ignore')),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: Colors.red.shade800),
                          onPressed: postId.isEmpty
                              ? null
                              : () async {
                                  try {
                                    await FeedFirestoreService.instance
                                        .resolveFeedReportDeletePost(
                                      reportDocId: d.id,
                                      postId: postId,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            lang.getString('admin_report_deleted'),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                    }
                                  }
                                },
                          child: Text(lang.getString('admin_report_delete_post')),
                        ),
                        TextButton(
                          onPressed: authorUid.isEmpty
                              ? null
                              : () async {
                                  try {
                                    await FeedFirestoreService.instance
                                        .warnAuthorForFeedReport(
                                      reportDocId: d.id,
                                      authorUid: authorUid,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            lang.getString('admin_report_warned'),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                    }
                                  }
                                },
                          child: Text(lang.getString('admin_report_warn')),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.grey.shade800,
                          ),
                          onPressed: authorUid.isEmpty
                              ? null
                              : () async {
                                  try {
                                    await FeedFirestoreService.instance
                                        .blacklistAuthorFromFeedReport(
                                      reportDocId: d.id,
                                      authorUid: authorUid,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            lang.getString('admin_report_blacklisted'),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                    }
                                  }
                                },
                          child: Text(lang.getString('admin_report_blacklist')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
              },
            );
          },
        );
      },
    );
  }
}
