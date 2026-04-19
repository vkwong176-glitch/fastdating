import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';
import '../services/ad_coop_billing_service.dart';
import '../models/event_proposal_models.dart';
import '../services/admin_backend_service.dart';
import '../services/feed_firestore_service.dart';
import '../services/manual_subscription_billing_service.dart';
import '../services/subscription_order_service.dart';
import '../services/admin_firebase_session.dart';
import '../services/event_proposal_service.dart';
import '../services/firestore_paths.dart';
import '../utils/activity_cms_payment.dart';
import '../utils/avatar_field.dart';
import '../utils/firestore_image_data_url.dart';
import '../utils/image_upload_compress.dart'
    show prepareEventCmsPosterForUpload;
import '../utils/admin_password_hash.dart';
import '../utils/constants.dart';
import '../widgets/allow_admin_screenshot.dart';
import '../widgets/admin_pagination.dart';
import '../widgets/storage_network_image.dart';
export 'admin_section_d_page.dart';
export 'admin_payment_settings_page.dart';

// —— 共用 ——

String _streamErrorMessage(LanguageProvider lang, Object? err) {
  final s = err.toString();
  if (s.contains('admin_firebase_auth_required')) {
    return lang.getString('admin_firebase_required');
  }
  return s;
}

/// 會員登記日期：優先 [createdAt]，否則 [updatedAt]（舊資料尚未有建立時間時）。
String _formatMemberRegisteredDate(Map<String, dynamic> m) {
  Timestamp? ts;
  final c = m['createdAt'];
  if (c is Timestamp) {
    ts = c;
  } else {
    final u = m['updatedAt'];
    if (u is Timestamp) ts = u;
  }
  if (ts == null) return '—';
  final d = ts.toDate();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// —— A ——

class AdminSectionAPage extends StatefulWidget {
  const AdminSectionAPage({super.key});

  @override
  State<AdminSectionAPage> createState() => _AdminSectionAPageState();
}

class _AdminSectionAPageState extends State<AdminSectionAPage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetToEmail(
    BuildContext context,
    LanguageProvider lang,
    String email,
  ) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(lang.getString('admin_sec_a_recovery_required'))),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: trimmed);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lang.getString('admin_sec_a_reset_sent'))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${lang.getString('admin_sec_a_reset_fail')}: $e')),
        );
      }
    }
  }

  Future<void> _submitNew(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
  ) async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final pwd = _passwordCtrl.text;
    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_sec_a_required_fields'))),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      String? passwordHash;
      if (pwd.isNotEmpty) {
        passwordHash = hashAdminLoginPassword(name, pwd);
      }
      await svc.addAdminAccount(
        displayName: name,
        recoveryEmail: email,
        note: '',
        passwordHash: passwordHash,
      );
      if (context.mounted) {
        _nameCtrl.clear();
        _emailCtrl.clear();
        _passwordCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pwd.isEmpty
                  ? lang.getString('admin_sec_a_added_no_password')
                  : lang.getString('admin_sec_a_added'),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${lang.getString('admin_sec_a_add_fail')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _editRecoveryEmail(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
    String docId,
    String current,
  ) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('admin_sec_a_edit_recovery')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: lang.getString('admin_sec_a_recovery_email'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.getString('close')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.getString('btn_save')),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await svc.updateAdminAccount(docId: docId, recoveryEmail: ctrl.text);
      ctrl.dispose();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lang.getString('admin_sec_saved'))),
        );
      }
    } else {
      ctrl.dispose();
    }
  }

  Future<void> _showManualResetPasswordDialog(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    String displayName,
  ) async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('admin_sec_a_manual_reset_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                lang.getString('admin_sec_a_manual_reset_hint'),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: p1,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: lang.getString('admin_sec_a_new_password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: p2,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: lang.getString('admin_sec_a_confirm_password'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.getString('close')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.getString('admin_sec_a_manual_reset_submit')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) {
      p1.dispose();
      p2.dispose();
      return;
    }
    final a = p1.text;
    final b = p2.text;
    p1.dispose();
    p2.dispose();
    if (a != b) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(lang.getString('admin_sec_a_password_mismatch'))),
        );
      }
      return;
    }
    if (a.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(lang.getString('admin_sec_a_required_fields'))),
        );
      }
      return;
    }
    final hash = hashAdminLoginPassword(displayName, a);
    await svc.updateAdminAccount(docId: d.id, passwordHash: hash);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_sec_a_manual_reset_ok'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final svc = AdminBackendService.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_a')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpansionTile(
            initiallyExpanded: true,
            title: Text(lang.getString('admin_sec_a_new_expand')),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: lang.getString('admin_sec_a_account_name'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: lang.getString('admin_sec_a_recovery_email'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: lang.getString('admin_sec_a_set_password'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed:
                      _submitting ? null : () => _submitNew(context, lang, svc),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(lang.getString('admin_sec_a_submit')),
                ),
              ),
            ],
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: svc.watchAdminAccounts(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_streamErrorMessage(lang, snap.error)),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(child: Text(lang.getString('admin_sec_empty')));
                }
                return AdminPagedDocumentsFrame(
                  docs: docs,
                  childBuilder: (context, pageDocs) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowHeight: 48,
                          dataRowMinHeight: 52,
                          columns: [
                            DataColumn(
                              label:
                                  Text(lang.getString('admin_sec_a_col_name')),
                            ),
                            DataColumn(
                              label:
                                  Text(lang.getString('admin_sec_a_col_reset')),
                            ),
                            DataColumn(
                              label: Text(lang
                                  .getString('admin_sec_a_col_manual_reset')),
                            ),
                            DataColumn(
                              label: Text(
                                  lang.getString('admin_sec_a_col_recovery')),
                            ),
                            DataColumn(
                              label: Text(
                                  lang.getString('admin_sec_a_col_delete')),
                            ),
                          ],
                          rows: [
                            for (final d in pageDocs)
                              _buildRow(context, lang, svc, d),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildRow(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final m = d.data();
    final name = (m['displayName'] as String?) ?? '—';
    final recovery = (m['recoveryEmail'] as String?) ?? '';
    return DataRow(
      cells: [
        DataCell(Text(name)),
        DataCell(
          TextButton(
            onPressed: recovery.isEmpty
                ? null
                : () => _sendResetToEmail(context, lang, recovery),
            child: Text(lang.getString('admin_sec_a_change_password')),
          ),
        ),
        DataCell(
          TextButton(
            onPressed: () => _showManualResetPasswordDialog(
              context,
              lang,
              svc,
              d,
              name,
            ),
            child: Text(lang.getString('admin_sec_a_col_manual_reset')),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  recovery.isEmpty ? '—' : recovery,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _editRecoveryEmail(
                  context,
                  lang,
                  svc,
                  d.id,
                  recovery,
                ),
              ),
            ],
          ),
        ),
        DataCell(
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await svc.deleteAdminAccount(d.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(lang.getString('admin_sec_deleted'))),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

// —— B（會員 + B2 黑名單）——

class AdminSectionBPage extends StatefulWidget {
  const AdminSectionBPage({super.key});

  @override
  State<AdminSectionBPage> createState() => _AdminSectionBPageState();
}

class _AdminSectionBPageState extends State<AdminSectionBPage>
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
    final svc = AdminBackendService.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_b')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: lang.getString('admin_sec_b_tab_members')),
            Tab(text: lang.getString('admin_sec_b_tab_blacklist')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _MembersTab(lang: lang, svc: svc),
          _BlacklistTab(lang: lang, svc: svc),
        ],
      ),
    );
  }
}

class _MembersTab extends StatefulWidget {
  const _MembersTab({required this.lang, required this.svc});
  final LanguageProvider lang;
  final AdminBackendService svc;

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  int? _count;
  bool _cleanupBusy = false;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final n = await widget.svc.fetchUserCount();
    if (mounted) setState(() => _count = n);
  }

  Future<void> _onCleanupIncomplete(BuildContext context) async {
    final lang = widget.lang;
    final svc = widget.svc;
    setState(() => _cleanupBusy = true);
    final exclude = FirebaseAuth.instance.currentUser?.uid;
    final ids = await svc.findIncompletePlaceholderUserIds(excludeUid: exclude);
    if (!mounted) return;
    setState(() => _cleanupBusy = false);
    if (!context.mounted) return;
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_sec_b_cleanup_none'))),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('admin_sec_b_cleanup_title')),
        content: SingleChildScrollView(
          child: Text(
            '${lang.getString('admin_sec_b_cleanup_body')}\n\n'
            '${lang.getString('admin_sec_b_cleanup_found')}: ${ids.length} '
            '${lang.getString('admin_sec_b_cleanup_unit')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.getString('close')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.getString('admin_sec_b_cleanup_confirm')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    setState(() => _cleanupBusy = true);
    final n =
        await svc.deleteIncompletePlaceholderProfiles(excludeUid: exclude);
    if (!mounted) return;
    setState(() => _cleanupBusy = false);
    await _loadCount();
    if (context.mounted) {
      final unit = lang.getString('admin_sec_b_cleanup_unit');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unit.isEmpty
                ? '${lang.getString('admin_sec_b_cleanup_done')}: $n'
                : '${lang.getString('admin_sec_b_cleanup_done')} $n $unit',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppConstants.primaryColor.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  lang.getString('admin_sec_b_total'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  _count == null ? '…' : '$_count',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: OutlinedButton.icon(
            onPressed:
                _cleanupBusy ? null : () => _onCleanupIncomplete(context),
            icon: _cleanupBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined),
            label: Text(lang.getString('admin_sec_b_cleanup_scan')),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.svc.watchUsersPreview(),
            builder: (context, userSnap) {
              if (userSnap.hasError) {
                return Center(
                    child: Text(_streamErrorMessage(lang, userSnap.error)));
              }
              if (!userSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: widget.svc.watchBlacklist(),
                builder: (context, blSnap) {
                  if (blSnap.hasError) {
                    return Center(
                        child: Text(_streamErrorMessage(lang, blSnap.error)));
                  }
                  if (!blSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = userSnap.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                        child: Text(lang.getString('admin_sec_empty')));
                  }
                  final blackIds = <String>{
                    for (final x in blSnap.data!.docs) x.id,
                  };
                  return AdminPagedDocumentsFrame(
                    docs: docs,
                    childBuilder: (context, pageDocs) {
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: pageDocs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final d = pageDocs[i];
                          final m = d.data();
                          final name = (m['displayName'] as String?) ?? '—';
                          final email = (m['email'] as String?) ?? '';
                          final gender = (m['gender'] as String?) ?? '—';
                          final sub = m['subscriptionActive'] == true;
                          final subLabel = sub
                              ? lang.getString('admin_sec_subscribed')
                              : '—';
                          final regStr = _formatMemberRegisteredDate(m);
                          final onBlack = blackIds.contains(d.id);
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(name),
                                  subtitle: Text(
                                    '${lang.getString('admin_sec_b_reg_date')}: $regStr\n'
                                    '$gender · $subLabel\n$email',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: onBlack,
                                      onChanged: (v) async {
                                        if (v == true) {
                                          await widget.svc.addToBlacklist(
                                            d.id,
                                            lang.getString(
                                                'admin_sec_b2_checkbox_reason'),
                                          );
                                        } else {
                                          await widget.svc
                                              .removeFromBlacklist(d.id);
                                        }
                                      },
                                    ),
                                    SizedBox(
                                      width: 72,
                                      child: Text(
                                        lang.getString(
                                            'admin_sec_b_add_blacklist'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BlacklistTab extends StatelessWidget {
  const _BlacklistTab({required this.lang, required this.svc});
  final LanguageProvider lang;
  final AdminBackendService svc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddBlacklist(context),
        icon: const Icon(Icons.block),
        label: Text(lang.getString('admin_sec_b2_add')),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: svc.watchBlacklist(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(_streamErrorMessage(lang, snap.error)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(child: Text(lang.getString('admin_sec_empty')));
          }
          final sorted =
              List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs)
                ..sort((a, b) {
                  final ta = a.data()['createdAt'];
                  final tb = b.data()['createdAt'];
                  if (ta is Timestamp && tb is Timestamp) {
                    return tb.compareTo(ta);
                  }
                  return 0;
                });
          return AdminPagedDocumentsFrame(
            docs: sorted,
            childBuilder: (context, pageDocs) {
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: pageDocs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = pageDocs[i];
                  final m = d.data();
                  final reason = (m['reason'] as String?) ?? '';
                  return ListTile(
                    title: Text(d.id),
                    subtitle: reason.isNotEmpty ? Text(reason) : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () async {
                        await svc.removeFromBlacklist(d.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text(lang.getString('admin_sec_deleted'))),
                          );
                        }
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showAddBlacklist(BuildContext context) async {
    final uidCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('admin_sec_b2_add')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: uidCtrl,
              decoration:
                  InputDecoration(labelText: lang.getString('admin_field_uid')),
            ),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                  labelText: lang.getString('admin_field_reason')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(lang.getString('close'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(lang.getString('btn_save'))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await svc.addToBlacklist(uidCtrl.text, reasonCtrl.text);
      uidCtrl.dispose();
      reasonCtrl.dispose();
    } else {
      uidCtrl.dispose();
      reasonCtrl.dispose();
    }
  }
}

// —— C ——

bool _subscriptionOrderAutoPaid(Map<String, dynamic> m) {
  final s = (m['status'] as String?) ?? '';

  /// [demo_local] 為示範訂單，不視為已成交；其餘成交與否依管理員核實或真實付款狀態。
  /// 與 [SubscriptionProvider._orderPaidFromFirestore] 之 `paid` 等狀態對齊。
  return s == 'paid_iap' ||
      s == 'upgraded' ||
      // 保留舊資料相容，待遷移後可移除。
      s == 'paid_stripe' ||
      s == SubscriptionOrderService.statusPaidManual ||
      s == 'paid';
}

bool _subscriptionOrderDisplayPaid(Map<String, dynamic> m) {
  return m['adminPaid'] == true || _subscriptionOrderAutoPaid(m);
}

bool _subscriptionOrderCanConfirmNextManualCycle(Map<String, dynamic> m) {
  return _orderHasManualMonthlyBilling(m) && _orderHasRemainingManualCycles(m);
}

String _subscriptionOrderManualBillingStatus(Map<String, dynamic> m) {
  final status = (m['manualBillingStatus'] as String?)?.trim() ?? '';
  switch (status) {
    case ManualSubscriptionBillingService.statusPendingFirstPayment:
      return '待首期付款';
    case ManualSubscriptionBillingService.statusPastDueSuspended:
      return '逾期待付款';
    case ManualSubscriptionBillingService.statusCompleted:
      return '已完成';
    case ManualSubscriptionBillingService.statusActive:
      return '生效中';
    default:
      return '—';
  }
}

bool _orderHasManualMonthlyBilling(Map<String, dynamic> m) {
  return ManualSubscriptionBillingService.isManualMonthlySubscriptionOrder(m) ||
      AdCoopBillingService.isManualMonthlyAdCoopOrder(m);
}

int _orderManualBillingPaidMonths(Map<String, dynamic> m) {
  if (ManualSubscriptionBillingService.isManualMonthlySubscriptionOrder(m)) {
    return ManualSubscriptionBillingService.paidMonthsFor(m);
  }
  if (AdCoopBillingService.isManualMonthlyAdCoopOrder(m)) {
    return AdCoopBillingService.paidMonthsFor(m);
  }
  final raw = m['manualBillingPaidMonths'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return 0;
}

int _orderManualBillingTotalMonths(Map<String, dynamic> m) {
  if (ManualSubscriptionBillingService.isManualMonthlySubscriptionOrder(m)) {
    return ManualSubscriptionBillingService.totalMonthsFor(m);
  }
  if (AdCoopBillingService.isManualMonthlyAdCoopOrder(m)) {
    return AdCoopBillingService.totalMonthsFor(m);
  }
  final raw = m['manualBillingTotalMonths'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return 1;
}

bool _orderHasRemainingManualCycles(Map<String, dynamic> m) {
  return _orderManualBillingPaidMonths(m) < _orderManualBillingTotalMonths(m);
}

/// 由訂單 [totalPrice] 字串解析數字金額（與活動報名 HKD$ 格式一致）。
double? _adminParseHkdAmountFromOrderField(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().replaceAll(',', '').trim();
  final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(s);
  if (m == null) return null;
  return double.tryParse(m.group(1)!);
}

/// 活動報名訂單：依 [createdAt] 篩選**當月**，統計筆數與已付款合計銀碼。
({int monthCount, double monthPaidHkd}) _activityOrdersThisMonthStats(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> activityDocs,
) {
  final now = DateTime.now();
  var monthCount = 0;
  var monthPaidHkd = 0.0;
  for (final d in activityDocs) {
    final m = d.data();
    final c = m['createdAt'];
    if (c is! Timestamp) continue;
    final dt = c.toDate();
    if (dt.year != now.year || dt.month != now.month) continue;
    monthCount++;
    if (_subscriptionOrderDisplayPaid(m)) {
      monthPaidHkd += _adminParseHkdAmountFromOrderField(m['totalPrice']) ?? 0;
    }
  }
  return (monthCount: monthCount, monthPaidHkd: monthPaidHkd);
}

String _adminFormatHkdStat(double v) {
  if (v == v.roundToDouble()) {
    return v.round().toString();
  }
  return v.toStringAsFixed(2);
}

/// 訂閱方案訂單（區塊 C）：本月內且視為已付款之 [totalPrice] 合計。
double _subscriptionPlanMonthlyPaidHkd(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> monthlyDocs,
) {
  var sum = 0.0;
  for (final d in monthlyDocs) {
    final m = d.data();
    if (!_subscriptionOrderDisplayPaid(m)) continue;
    sum += _adminParseHkdAmountFromOrderField(m['totalPrice']) ?? 0;
  }
  return sum;
}

/// 訂閱方案訂單：已開啟自動續約（[autoRenewal]）之筆數。
int _subscriptionPlanAutoRenewalCount(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  return docs.where((d) => d.data()['autoRenewal'] == true).length;
}

bool _subscriptionOrderIsAdCoop(Map<String, dynamic> m) {
  return (m['purchaseKind']?.toString().trim() ?? '') ==
      SubscriptionOrderService.purchaseKindAdCoop;
}

bool _subscriptionOrderHasAdCoopContent(Map<String, dynamic> m) {
  final adTitle =
      ((m['adPostTitle'] ?? m['ad_post_title']) ?? '').toString().trim();
  final adBody =
      ((m['adPostText'] ?? m['ad_post_text']) ?? '').toString().trim();
  final adLink =
      ((m['adPostLink'] ?? m['ad_post_link']) ?? '').toString().trim();
  final adImageUrl =
      ((m['adPostImageUrl'] ?? m['adPostImageURL'] ?? m['ad_post_image_url']) ??
              '')
          .toString()
          .trim();
  return adTitle.isNotEmpty ||
      adBody.isNotEmpty ||
      adLink.isNotEmpty ||
      adImageUrl.isNotEmpty;
}

int _adCoopOrderSortMs(Map<String, dynamic> m) {
  final updatedAt = m['updatedAt'];
  if (updatedAt is Timestamp) return updatedAt.millisecondsSinceEpoch;
  final createdAt = m['createdAt'];
  if (createdAt is Timestamp) return createdAt.millisecondsSinceEpoch;
  return 0;
}

String _subscriptionPaymentMethodLabel(LanguageProvider lang, String? raw) {
  final r = (raw ?? '').trim();
  if (r.isEmpty) return '—';
  switch (r) {
    case 'manual_fps_wechat_bank':
      return lang.getString('admin_pay_manual_fps_wechat_bank');
    case 'iap_unavailable_web':
    case 'iap_unavailable':
      return lang.getString('admin_pay_other');
    case 'stripe':
    case 'pending_stripe':
      return lang.getString('payment_method_legacy_removed');
    case 'iap_app_store':
      return lang.getString('admin_pay_iap_ios');
    case 'iap_google_play':
      return lang.getString('admin_pay_iap_android');
    default:
      if (r.startsWith('iap_')) {
        return lang.getString('admin_pay_iap_ios');
      }
      return r;
  }
}

String _adminAdCoopReviewStatusLine(
    LanguageProvider lang, Map<String, dynamic> m) {
  final s = (m['adContentReviewStatus'] as String?)?.trim() ?? '';
  if (s == AdminBackendService.adContentReviewApproved) {
    return lang.getString('admin_ad_coop_review_passed');
  }
  if (s == AdminBackendService.adContentReviewNeedsRevision) {
    return lang.getString('admin_ad_coop_review_revision');
  }
  if (s == 'pending') {
    return lang.getString('admin_ad_coop_review_pending');
  }
  return lang.getString('admin_ad_coop_review_none');
}

bool _adminEnsureFirebaseWrite(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc,
) {
  if (svc.hasFirebaseWriteSession) return true;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lang.getString('admin_firebase_required'))),
    );
  }
  return false;
}

Future<void> _confirmDeleteSubscriptionOrder(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc, {
  required String orderDocId,
  String? memberUid,
}) async {
  if (!_adminEnsureFirebaseWrite(context, lang, svc)) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(lang.getString('btn_delete')),
      content: Text(lang.getString('admin_delete_order_confirm')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(lang.getString('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(lang.getString('btn_delete')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await svc.deleteSubscriptionOrder(orderDocId, memberUserId: memberUid);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_sec_deleted'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> _markSubscriptionOrderAdminPaid(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc, {
  required String orderDocId,
}) async {
  if (!_adminEnsureFirebaseWrite(context, lang, svc)) return;
  try {
    await svc.setSubscriptionOrderAdminPaid(orderDocId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_sec_saved'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}

Future<void> _submitAdCoopContentApprove(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc,
  String orderDocId,
  String memberUid,
) async {
  if (!_adminEnsureFirebaseWrite(context, lang, svc)) return;
  try {
    await svc.setAdCoopContentReview(
      orderDocId: orderDocId,
      memberUserId: memberUid,
      status: AdminBackendService.adContentReviewApproved,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_sec_saved'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> _publishAdCoopPromotion(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc, {
  required String memberUid,
  required String displayName,
  required String adTitle,
  required String adText,
  required String adLink,
  required String adImageUrl,
  required int durationMonths,
  required String existingPostId,
  String linkedOrderId = '',
}) async {
  if (!_adminEnsureFirebaseWrite(context, lang, svc)) return;
  if (adText.trim().isEmpty &&
      adLink.trim().isEmpty &&
      adImageUrl.trim().isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此廣告沒有可發佈的文字、連結或圖片。')),
      );
    }
    return;
  }
  try {
    final nowUtc = DateTime.now().toUtc();
    var expiresAtUtc = _addMonthsUtc(nowUtc, durationMonths);
    final trimmedLinkedOrderId = linkedOrderId.trim();
    if (trimmedLinkedOrderId.isNotEmpty) {
      final orderSnap = await FirebaseFirestore.instance
          .collection(FirestorePaths.subscriptionOrders)
          .doc(trimmedLinkedOrderId)
          .get();
      final orderData = orderSnap.data();
      if (orderData != null) {
        if (!_subscriptionOrderDisplayPaid(orderData)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('請先確認此廣告訂單已付款，再發佈宣傳貼文。')),
            );
          }
          return;
        }
        if (AdCoopBillingService.isManualMonthlyAdCoopOrder(orderData)) {
          final manualExpiry = AdCoopBillingService.expirationFor(orderData);
          if (manualExpiry != null) {
            expiresAtUtc = manualExpiry.toUtc();
          }
        }
      }
    }
    final postId = await FeedFirestoreService.instance.publishAdminAdPromotion(
      displayName: adTitle.trim().isNotEmpty ? adTitle : displayName,
      content: adText,
      externalLink: adLink,
      imageUrl: adImageUrl,
      promotionSourceMemberUid: memberUid,
      existingPostId: existingPostId,
      durationMonths: durationMonths,
      explicitExpiresAtUtc: expiresAtUtc,
    );
    if (postId == null || postId.isEmpty) return;
    await svc.updateAdCoopPromotionMetadata(
      memberUserId: memberUid,
      postId: postId,
      status: FeedFirestoreService.adPromotionStatusActive,
      durationMonths: durationMonths,
      startedAtUtc: nowUtc,
      expiresAtUtc: expiresAtUtc,
      adTitle: adTitle,
      adText: adText,
      adLink: adLink,
      adImageUrl: adImageUrl,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已發佈宣傳貼文（$durationMonths個月）。')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}

Future<void> _saveAdCoopPromotionDuration(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc, {
  required String memberUid,
  required int months,
}) async {
  if (!_adminEnsureFirebaseWrite(context, lang, svc)) return;
  try {
    await svc.setAdCoopPromotionDuration(
      memberUserId: memberUid,
      months: months,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已設定有效期為$months個月。')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}

Future<void> _pauseAdCoopPromotion(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc, {
  required String memberUid,
  required String postId,
}) async {
  if (!_adminEnsureFirebaseWrite(context, lang, svc)) return;
  final trimmedPostId = postId.trim();
  if (trimmedPostId.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此會員尚未發佈宣傳貼文。')),
      );
    }
    return;
  }
  try {
    await FeedFirestoreService.instance.pauseAdminAdPromotion(trimmedPostId);
    await svc.pauseAdCoopPromotion(memberUserId: memberUid);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已暫停宣傳貼文。')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}

Future<void> _submitAdCoopStandaloneApprove(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc,
  String memberUid,
) async {
  if (!_adminEnsureFirebaseWrite(context, lang, svc)) return;
  try {
    await svc.setAdCoopStandaloneContentReview(
      memberUserId: memberUid,
      status: AdminBackendService.adContentReviewApproved,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_sec_saved'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> _submitAdCoopContentIssue(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc,
  String orderDocId,
  String memberUid,
) async {
  if (!_adminEnsureFirebaseWrite(context, lang, svc)) return;
  final ctrl = TextEditingController();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(lang.getString('admin_ad_coop_issue_title')),
      content: TextField(
        controller: ctrl,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: lang.getString('admin_ad_coop_issue_reason'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(lang.getString('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(lang.getString('submit')),
        ),
      ],
    ),
  );
  final reason = ctrl.text.trim();
  ctrl.dispose();
  if (go != true || !context.mounted) return;
  if (reason.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lang.getString('admin_ad_coop_issue_required'))),
    );
    return;
  }
  try {
    await svc.setAdCoopContentReview(
      orderDocId: orderDocId,
      memberUserId: memberUid,
      status: AdminBackendService.adContentReviewNeedsRevision,
      note: reason,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_sec_saved'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> _submitAdCoopStandaloneIssue(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc,
  String memberUid,
) async {
  if (!_adminEnsureFirebaseWrite(context, lang, svc)) return;
  final ctrl = TextEditingController();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(lang.getString('admin_ad_coop_issue_title')),
      content: TextField(
        controller: ctrl,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: lang.getString('admin_ad_coop_issue_reason'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(lang.getString('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(lang.getString('submit')),
        ),
      ],
    ),
  );
  final reason = ctrl.text.trim();
  ctrl.dispose();
  if (go != true || !context.mounted) return;
  if (reason.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lang.getString('admin_ad_coop_issue_required'))),
    );
    return;
  }
  try {
    await svc.setAdCoopStandaloneContentReview(
      memberUserId: memberUid,
      status: AdminBackendService.adContentReviewNeedsRevision,
      note: reason,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_sec_saved'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> _confirmDeleteAdCoopSubmission(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc, {
  required String memberUid,
  required bool hasLinkedOrder,
  String? orderDocId,
}) async {
  if (!_adminEnsureFirebaseWrite(context, lang, svc)) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(lang.getString('btn_delete')),
      content: Text(lang.getString('admin_ad_coop_delete_submission_confirm')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(lang.getString('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(lang.getString('btn_delete')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    if (hasLinkedOrder && orderDocId != null && orderDocId.trim().isNotEmpty) {
      await svc.deleteAdCoopSubmissionForOrder(
        orderDocId: orderDocId.trim(),
        memberUserId: memberUid,
      );
    } else {
      await svc.deleteAdCoopStandaloneSubmission(memberUserId: memberUid);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('admin_sec_saved'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

DateTime? _adCoopPostedAtFromOrder(Map<String, dynamic> m) {
  final u = m['updatedAt'];
  if (u is Timestamp) return u.toDate();
  final c = m['createdAt'];
  if (c is Timestamp) return c.toDate();
  return null;
}

DateTime? _adCoopPostedAtFromStandalone(
  Map<String, dynamic> userData,
  Map<String, dynamic>? sub,
) {
  final s = sub?['submittedAt'];
  if (s is Timestamp) return s.toDate();
  final upd = userData['updatedAt'];
  if (upd is Timestamp) return upd.toDate();
  return null;
}

DateTime _addMonthsUtc(DateTime baseUtc, int months) {
  final utc = baseUtc.toUtc();
  final totalMonths = utc.month - 1 + months;
  final year = utc.year + (totalMonths ~/ 12);
  final month = (totalMonths % 12) + 1;
  final nextMonth = month == 12
      ? DateTime.utc(year + 1, 1, 1)
      : DateTime.utc(year, month + 1, 1);
  final lastDay = nextMonth.subtract(const Duration(days: 1)).day;
  final day = utc.day > lastDay ? lastDay : utc.day;
  return DateTime.utc(
    year,
    month,
    day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
    utc.microsecond,
  );
}

int _adCoopPromotionDurationMonths(Map<String, dynamic> data) {
  final raw = data['adCoopPromotionDurationMonths'];
  if (raw is int && raw > 0) return raw;
  if (raw is num && raw.toInt() > 0) return raw.toInt();
  return 1;
}

DateTime? _adCoopPromotionExpiresAt(Map<String, dynamic> data) {
  final raw = data['adCoopPromotionExpiresAt'];
  if (raw is Timestamp) return raw.toDate();
  return null;
}

String _adCoopPromotionStatus(Map<String, dynamic> data) {
  final expiresAt = _adCoopPromotionExpiresAt(data);
  if (expiresAt != null && !expiresAt.toUtc().isAfter(DateTime.now().toUtc())) {
    return FeedFirestoreService.adPromotionStatusPausedExpired;
  }
  return (data['adCoopPromotionStatus'] as String?)?.trim() ?? '';
}

String _adCoopPromotionStatusLabel(String status) {
  switch (status) {
    case FeedFirestoreService.adPromotionStatusActive:
      return '發佈中';
    case FeedFirestoreService.adPromotionStatusPausedManual:
      return '已暫停';
    case FeedFirestoreService.adPromotionStatusPausedExpired:
      return '已到期暫停';
    default:
      return '未發佈';
  }
}

/// 廣告審批：合併多來源 [users] 快照，依最新貼文日期新到舊。
List<DocumentSnapshot<Map<String, dynamic>>> _mergeAdCoopApprovalUserDocs(
  List<DocumentSnapshot<Map<String, dynamic>>> a,
  List<DocumentSnapshot<Map<String, dynamic>>> b,
) {
  final map = <String, DocumentSnapshot<Map<String, dynamic>>>{};
  for (final d in a) {
    map[d.id] = d;
  }
  for (final d in b) {
    map[d.id] = d;
  }
  final list = map.values.toList();
  int sortMs(Map<String, dynamic> data) {
    final sub = data['adCoopLatestSubmission'];
    if (sub is Map) {
      final t = sub['submittedAt'];
      if (t is Timestamp) return t.millisecondsSinceEpoch;
    }
    final u = data['updatedAt'];
    if (u is Timestamp) return u.millisecondsSinceEpoch;
    return 0;
  }

  list.sort(
    (x, y) => sortMs(y.data() ?? {}).compareTo(sortMs(x.data() ?? {})),
  );
  return list;
}

List<DocumentSnapshot<Map<String, dynamic>>>
    _filterStandaloneApprovalDocsWithoutLinkedOrders(
  List<DocumentSnapshot<Map<String, dynamic>>> docs,
) {
  return docs.where((d) {
    final m = d.data() ?? {};
    final raw = m['adCoopLatestSubmission'];
    if (raw is! Map) return true;
    final linkedOrderId = (raw['linkedOrderId'] ?? '').toString().trim();
    return linkedOrderId.isEmpty;
  }).toList();
}

/// 廣告審批頁：已合併之 [users] 列表（不含訂單付款區塊）。
Widget _adCoopApprovalMergedListBody(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
    List<DocumentSnapshot<Map<String, dynamic>>> merged,
    {bool showEmptyState = true,
    bool wrapWithScrollView = true}) {
  final body = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (merged.isEmpty && showEmptyState)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(lang.getString('admin_sec_empty')),
        ),
      if (merged.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            lang.getString('admin_sec_ad_approval_records_section'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdminPagedGenericFrame<DocumentSnapshot<Map<String, dynamic>>>(
            expand: false,
            shrinkWrap: true,
            items: merged,
            itemBuilder: (context, index, d) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _adminStandaloneAdCoopCard(
                context,
                lang,
                svc,
                d,
                showAdPostContentBlock: true,
                adPostContentUseInline: true,
                showAdCoopReviewControls: true,
                useAdPublicationSectionHeading: true,
              ),
            ),
          ),
        ),
      ],
    ],
  );
  if (!wrapWithScrollView) return body;
  return SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: 24),
    child: body,
  );
}

Widget _adCoopApprovalOrderListBody(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (docs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(lang.getString('admin_sec_empty')),
        ),
      if (docs.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            lang.getString('admin_sec_ad_approval_records_section'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdminPagedDocumentsFrame(
            expand: false,
            docs: docs,
            childBuilder: (context, pageDocs) {
              return ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pageDocs.length,
                itemBuilder: (context, i) => _adminSubscriptionOrderCard(
                  context,
                  lang,
                  svc,
                  pageDocs[i],
                  showAdPostContentBlock: true,
                  adPostContentUseInline: true,
                  hideAdOrderPaymentMeta: true,
                  showAdCoopReviewControls: true,
                ),
              );
            },
          ),
        ),
      ],
    ],
  );
}

Future<void> _showAdCoopNetworkImageZoom(
  BuildContext context,
  String imageUrl,
) async {
  final trimmed = imageUrl.trim();
  if (trimmed.isEmpty) return;
  final dataBytes = decodeAvatarFieldToBytes(trimmed);
  String? resolvedNet;
  if (dataBytes == null && trimmed.startsWith('http')) {
    resolvedNet = await resolveFirebaseStorageDisplayUrl(trimmed);
  }
  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    builder: (zoomCtx) => Dialog(
      backgroundColor: Colors.black87,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child: dataBytes != null
                  ? Image.memory(
                      dataBytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                    )
                  : Image.network(
                      resolvedNet ?? trimmed,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(zoomCtx).top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(zoomCtx),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 與會員端「廣告貼文記錄」卡片一致：左縮圖、文字／連結、灰字日期時間；點圖可放大。
Widget _buildAdCoopPostContentMemberStyle(
  BuildContext context,
  LanguageProvider lang, {
  required String adTitle,
  required String adText,
  required String adLink,
  required String adImageUrl,
  DateTime? postedAt,

  /// 為 false 時，無文字／圖／連結不顯示佔位說明（廣告審批列表用）。
  bool showEmptyPlaceholder = true,
}) {
  final title = adTitle.trim();
  final t = adText.trim();
  final link = adLink.trim();
  final img = adImageUrl.trim();
  final hasAny =
      title.isNotEmpty || t.isNotEmpty || link.isNotEmpty || img.isNotEmpty;

  if (!hasAny) {
    if (!showEmptyPlaceholder) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        lang.getString('admin_ad_coop_content_empty'),
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[700],
          height: 1.4,
        ),
      ),
    );
  }

  final timeLine = postedAt != null
      ? '${postedAt.year}/${postedAt.month}/${postedAt.day} '
          '${postedAt.hour.toString().padLeft(2, '0')}:'
          '${postedAt.minute.toString().padLeft(2, '0')}'
      : null;

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GestureDetector(
        onTap: img.isNotEmpty
            ? () async {
                await _showAdCoopNetworkImageZoom(context, img);
              }
            : null,
        child: img.isNotEmpty
            ? StorageNetworkImage(
                url: img,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                borderRadius: 8,
              )
            : Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.image_not_supported, color: Colors.grey[500]),
              ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              SelectableText(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            if (title.isNotEmpty &&
                (t.isNotEmpty || link.isNotEmpty || timeLine != null))
              const SizedBox(height: 6),
            if (t.isNotEmpty)
              SelectableText(
                t,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                ),
              )
            else if (img.isNotEmpty)
              Text(
                lang.getString('admin_ad_coop_image_only_hint'),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                  height: 1.4,
                ),
              ),
            if (link.isNotEmpty) ...[
              const SizedBox(height: 4),
              InkWell(
                enableFeedback: false,
                onTap: () async {
                  final u = Uri.tryParse(link);
                  if (u != null && await canLaunchUrl(u)) {
                    await launchUrl(
                      u,
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                child: Text(
                  link,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue[700],
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (timeLine != null) ...[
              const SizedBox(height: 6),
              Text(
                timeLine,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

/// 彈窗檢視會員於廣告合作提交的完整內容（與訂單／[users.adCoopLatestSubmission] 同步之資料）。
Future<void> _showAdCoopPostContentViewer(
  BuildContext context,
  LanguageProvider lang, {
  required String memberUid,
  required String adTitle,
  required String adText,
  required String adLink,
  required String adImageUrl,
  DateTime? postedAt,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      final screen = MediaQuery.sizeOf(dialogCtx);
      final w = math.min(480.0, screen.width - 32);
      final h = math.min(620.0, screen.height * 0.78);
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SizedBox(
          width: w,
          height: h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        lang.getString('admin_ad_coop_content_dialog_title'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(dialogCtx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildMemberRegistrationBlock(
                        dialogCtx,
                        lang,
                        memberUid,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        lang.getString('ad_post_content_heading'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildAdCoopPostContentMemberStyle(
                        dialogCtx,
                        lang,
                        adTitle: adTitle,
                        adText: adText,
                        adLink: adLink,
                        adImageUrl: adImageUrl,
                        postedAt: postedAt,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 卡片內直接顯示廣告貼文（與 [_showAdCoopPostContentViewer] 版面一致）。
Widget _buildAdCoopPostContentInline(
  BuildContext context,
  LanguageProvider lang, {
  required String adTitle,
  required String adText,
  required String adLink,
  required String adImageUrl,
  DateTime? postedAt,
  bool showEmptyPlaceholder = true,
}) {
  return _buildAdCoopPostContentMemberStyle(
    context,
    lang,
    adTitle: adTitle,
    adText: adText,
    adLink: adLink,
    adImageUrl: adImageUrl,
    postedAt: postedAt,
    showEmptyPlaceholder: showEmptyPlaceholder,
  );
}

/// 無廣告訂單、僅 [users.adCoopLatestSubmission] 待審時顯示。
Widget _adminStandaloneAdCoopCard(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc,
  DocumentSnapshot<Map<String, dynamic>> userDoc, {
  /// 為 false 時不顯示「廣告貼文內容」標題與內容（廣告貼文訂單列表頁）。
  bool showAdPostContentBlock = true,

  /// 僅在 [showAdPostContentBlock] 為 true 時：true 為直接顯示；false 為「查看」按鈕。
  bool adPostContentUseInline = false,
  bool showAdCoopReviewControls = false,

  /// `true`：區塊標題用「廣告刊登內容」（廣告審批頁）。
  bool useAdPublicationSectionHeading = false,
}) {
  final uid = userDoc.id;
  final m = userDoc.data() ?? {};
  final raw = m['adCoopLatestSubmission'];
  Map<String, dynamic>? sub;
  if (raw is Map<String, dynamic>) {
    sub = raw;
  } else if (raw is Map) {
    sub = Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
  }
  final adTitle =
      ((sub?['title'] ?? m['adCoopPromotionTitle']) ?? '').toString().trim();
  final adBody =
      ((sub?['text'] ?? m['adCoopPromotionText']) ?? '').toString().trim();
  final linkLine =
      ((sub?['link'] ?? m['adCoopPromotionLink']) ?? '').toString().trim();
  final adImgUrl = (((sub?['imageUrl'] ?? sub?['imageURL']) ??
              m['adCoopPromotionImageUrl']) ??
          '')
      .toString()
      .trim();
  final postedAt = _adCoopPostedAtFromStandalone(m, sub);
  final linkedOrderId = (sub?['linkedOrderId'] ?? '').toString().trim();
  final memberDisplayName = (m['displayName'] as String?)?.trim() ?? '';
  final promotionDurationMonths = _adCoopPromotionDurationMonths(m);
  final promotionStatus = _adCoopPromotionStatus(m);
  final promotionExpiresAt = _adCoopPromotionExpiresAt(m);
  final promotionPostId = (m['adCoopPromotionPostId'] as String?)?.trim() ?? '';

  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            linkedOrderId.isNotEmpty
                ? lang.getString('admin_sec_ad_approval_linked_note')
                : lang.getString('admin_sec_i_standalone_note'),
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.brown[800],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildMemberRegistrationBlock(context, lang, uid),
          const Divider(height: 20),
          if (showAdPostContentBlock) ...[
            Text(
              lang.getString(
                useAdPublicationSectionHeading
                    ? 'admin_ad_approval_publication_heading'
                    : 'ad_post_content_heading',
              ),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (showAdCoopReviewControls && postedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                '${lang.getString('admin_ad_coop_submitted_at')}: '
                '${DateFormat('yyyy/MM/dd HH:mm').format(postedAt)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
            const SizedBox(height: 8),
            if (adPostContentUseInline)
              _buildAdCoopPostContentInline(
                context,
                lang,
                adTitle: adTitle,
                adText: adBody,
                adLink: linkLine,
                adImageUrl: adImgUrl,
                postedAt: postedAt,
                showEmptyPlaceholder: !showAdCoopReviewControls,
              )
            else
              FilledButton.tonal(
                onPressed: () => _showAdCoopPostContentViewer(
                  context,
                  lang,
                  memberUid: uid,
                  adTitle: adTitle,
                  adText: adBody,
                  adLink: linkLine,
                  adImageUrl: adImgUrl,
                  postedAt: postedAt,
                ),
                child: Text(lang.getString('admin_ad_coop_view_content_btn')),
              ),
          ],
          if (showAdCoopReviewControls) ...[
            const SizedBox(height: 8),
            Text(
              lang.getString('admin_ad_coop_review_pending'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    promotionStatus.isEmpty
                        ? '有效期：$promotionDurationMonths個月'
                        : promotionExpiresAt != null
                            ? '宣傳狀態：${_adCoopPromotionStatusLabel(promotionStatus)} · 到期：${DateFormat('yyyy/MM/dd HH:mm').format(promotionExpiresAt)}'
                            : '宣傳狀態：${_adCoopPromotionStatusLabel(promotionStatus)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [1, 3, 6, 12]
                      .map(
                        (months) => OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: promotionDurationMonths == months
                                ? Colors.blue.shade50
                                : null,
                            foregroundColor: Colors.blue[800],
                            side: BorderSide(color: Colors.blue.shade300),
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: () => _saveAdCoopPromotionDuration(
                            context,
                            lang,
                            svc,
                            memberUid: uid,
                            months: months,
                          ),
                          child: Text('$months個月'),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          if (linkedOrderId.isNotEmpty) {
                            _submitAdCoopContentApprove(
                              context,
                              lang,
                              svc,
                              linkedOrderId,
                              uid,
                            );
                          } else {
                            _submitAdCoopStandaloneApprove(
                              context,
                              lang,
                              svc,
                              uid,
                            );
                          }
                        },
                        child: Text(lang.getString('admin_ad_coop_pass')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange[800],
                          side: BorderSide(color: Colors.deepOrange.shade400),
                        ),
                        onPressed: () {
                          if (linkedOrderId.isNotEmpty) {
                            _submitAdCoopContentIssue(
                              context,
                              lang,
                              svc,
                              linkedOrderId,
                              uid,
                            );
                          } else {
                            _submitAdCoopStandaloneIssue(
                              context,
                              lang,
                              svc,
                              uid,
                            );
                          }
                        },
                        child: Text(lang.getString('admin_ad_coop_issue')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue[800],
                          side: BorderSide(color: Colors.blue.shade400),
                        ),
                        onPressed: () => _publishAdCoopPromotion(
                          context,
                          lang,
                          svc,
                          memberUid: uid,
                          displayName: memberDisplayName,
                          adTitle: adTitle,
                          adText: adBody,
                          adLink: linkLine,
                          adImageUrl: adImgUrl,
                          durationMonths: promotionDurationMonths,
                          existingPostId: promotionPostId,
                          linkedOrderId: linkedOrderId,
                        ),
                        child: const Text('宣傳貼文'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange[800],
                          side: BorderSide(color: Colors.orange.shade400),
                        ),
                        onPressed: () => _pauseAdCoopPromotion(
                          context,
                          lang,
                          svc,
                          memberUid: uid,
                          postId: promotionPostId,
                        ),
                        child: const Text('暫停'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[800],
                          side: BorderSide(color: Colors.red.shade400),
                        ),
                        onPressed: () => _confirmDeleteAdCoopSubmission(
                          context,
                          lang,
                          svc,
                          memberUid: uid,
                          hasLinkedOrder: linkedOrderId.isNotEmpty,
                          orderDocId:
                              linkedOrderId.isEmpty ? null : linkedOrderId,
                        ),
                        child: Text(lang.getString('btn_delete')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _adminSubscriptionOrderCard(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc,
  QueryDocumentSnapshot<Map<String, dynamic>> d, {
  /// 為 false 時不顯示「廣告貼文內容」區塊（廣告貼文訂單頁）。
  bool showAdPostContentBlock = true,

  /// 僅在 [showAdPostContentBlock] 為 true 時：true 為直接顯示貼文；false 為「查看」按鈕（訂閱訂單列表等）。
  bool adPostContentUseInline = false,

  /// 為 true 且為廣告單時，不顯示訂單狀態／期數／金額／付款等（僅廣告審批頁）。
  bool hideAdOrderPaymentMeta = false,

  /// 通過／有問題等；僅廣告審批面板為 true，「廣告貼文訂單」頁為 false。
  bool showAdCoopReviewControls = false,
}) {
  final m = d.data();
  final uid = (m['userId'] as String?) ?? '';
  final plan = (m['planName'] ?? m['planId'] ?? '—').toString();
  final monthsRaw = (m['months'] ?? '').toString().trim();
  /// 與會員「購買記錄」一致：方案名 · N（個月／months）
  final planDetail = monthsRaw.isEmpty
      ? plan
      : '$plan · $monthsRaw${lang.getString('months')}';
  /// 會員端 [recordOrder] 寫入 [totalPrice]；後台 [upsertSubscriptionOrder] 可能僅有 [amount]。
  final priceShown = () {
    final t = m['totalPrice'];
    if (t != null && t.toString().trim().isNotEmpty) return t.toString();
    final a = m['amount'];
    if (a == null) return '—';
    if (a is num) return a.toString();
    final s = a.toString().trim();
    return s.isEmpty ? '—' : s;
  }();
  final pmRaw = (m['paymentMethod'] as String?) ?? '';
  final pmLabel = _subscriptionPaymentMethodLabel(lang, pmRaw);
  final exp = m['expiresAt'];
  var expStr = '—';
  if (exp is Timestamp) {
    expStr = exp.toDate().toString().split(' ').first;
  }
  final created = m['createdAt'];
  var timeStr = '—';
  if (created is Timestamp) {
    timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(created.toDate());
  }
  final paidShown = _subscriptionOrderDisplayPaid(m);
  final canConfirmNextManualCycle = _subscriptionOrderCanConfirmNextManualCycle(m);
  final dealDone = paidShown;
  final isAd = _subscriptionOrderIsAdCoop(m);
  final reviewSt = (m['adContentReviewStatus'] as String?)?.trim() ?? '';
  final reviewNote = (m['adContentReviewNote'] as String?)?.trim() ?? '';
  final adTitle =
      ((m['adPostTitle'] ?? m['ad_post_title']) ?? '').toString().trim();
  final linkLine =
      ((m['adPostLink'] ?? m['ad_post_link']) ?? '').toString().trim();
  final adImgUrl =
      ((m['adPostImageUrl'] ?? m['adPostImageURL'] ?? m['ad_post_image_url']) ??
              '')
          .toString()
          .trim();
  final adBody =
      ((m['adPostText'] ?? m['ad_post_text']) ?? '').toString().trim();

  Widget cardForUserDoc(Map<String, dynamic>? userDocData) {
    Map<String, dynamic>? mirrorSub;
    final raw = userDocData?['adCoopLatestSubmission'];
    if (raw is Map<String, dynamic>) {
      mirrorSub = raw;
    } else if (raw is Map) {
      mirrorSub = Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    final mirrorText = (mirrorSub?['text'] ?? '').toString().trim();
    final mirrorTitle = (mirrorSub?['title'] ?? '').toString().trim();
    final mirrorLink = (mirrorSub?['link'] ?? '').toString().trim();
    final mirrorImg = ((mirrorSub?['imageUrl'] ?? mirrorSub?['imageURL']) ?? '')
        .toString()
        .trim();
    final adTitleDisp = adTitle.isNotEmpty ? adTitle : mirrorTitle;
    final adBodyDisp = adBody.isNotEmpty ? adBody : mirrorText;
    final linkDisp = linkLine.isNotEmpty ? linkLine : mirrorLink;
    final adImgDisp = adImgUrl.isNotEmpty ? adImgUrl : mirrorImg;
    var postedAt = _adCoopPostedAtFromOrder(m);
    if (postedAt == null && userDocData != null) {
      postedAt = _adCoopPostedAtFromStandalone(
        userDocData,
        mirrorSub,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMemberRegistrationBlock(context, lang, uid),
            const Divider(height: 20),
            if (isAd &&
                (showAdPostContentBlock || showAdCoopReviewControls)) ...[
              if (showAdPostContentBlock) ...[
                Text(
                  lang.getString('ad_post_content_heading'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (showAdCoopReviewControls && postedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${lang.getString('admin_ad_coop_submitted_at')}: '
                    '${DateFormat('yyyy/MM/dd HH:mm').format(postedAt)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
                const SizedBox(height: 8),
                if (adPostContentUseInline)
                  _buildAdCoopPostContentInline(
                    context,
                    lang,
                    adTitle: adTitleDisp,
                    adText: adBodyDisp,
                    adLink: linkDisp,
                    adImageUrl: adImgDisp,
                    postedAt: postedAt,
                    showEmptyPlaceholder: !showAdCoopReviewControls,
                  )
                else
                  FilledButton.tonal(
                    onPressed: uid.isEmpty
                        ? null
                        : () => _showAdCoopPostContentViewer(
                              context,
                              lang,
                              memberUid: uid,
                              adTitle: adTitleDisp,
                              adText: adBodyDisp,
                              adLink: linkDisp,
                              adImageUrl: adImgDisp,
                              postedAt: postedAt,
                            ),
                    child:
                        Text(lang.getString('admin_ad_coop_view_content_btn')),
                  ),
              ],
              if (showAdCoopReviewControls) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _adminAdCoopReviewStatusLine(lang, m),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (reviewSt ==
                        AdminBackendService.adContentReviewNeedsRevision &&
                    reviewNote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    reviewNote,
                    style: TextStyle(
                        fontSize: 13, color: Colors.orange[900], height: 1.35),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: uid.isEmpty
                            ? null
                            : () => _submitAdCoopContentApprove(
                                  context,
                                  lang,
                                  svc,
                                  d.id,
                                  uid,
                                ),
                        child: Text(lang.getString('admin_ad_coop_pass')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange[800],
                          side: BorderSide(color: Colors.deepOrange.shade400),
                        ),
                        onPressed: uid.isEmpty
                            ? null
                            : () => _submitAdCoopContentIssue(
                                  context,
                                  lang,
                                  svc,
                                  d.id,
                                  uid,
                                ),
                        child: Text(lang.getString('admin_ad_coop_issue')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[800],
                          side: BorderSide(color: Colors.red.shade400),
                        ),
                        onPressed: uid.isEmpty
                            ? null
                            : () => _confirmDeleteAdCoopSubmission(
                                  context,
                                  lang,
                                  svc,
                                  memberUid: uid,
                                  hasLinkedOrder: true,
                                  orderDocId: d.id,
                                ),
                        child: Text(lang.getString('btn_delete')),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ],
            if (!(hideAdOrderPaymentMeta && isAd)) ...[
              Text(
                '${lang.getString('admin_sec_c_order_status')}: ${dealDone ? lang.getString('admin_sec_c_deal_done') : lang.getString('admin_sec_c_deal_pending')}',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (!isAd) ...[
                Text(
                  '${lang.getString('admin_sec_c_plan')}: $planDetail',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '${lang.getString('payment_amount')}: $priceShown',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (isAd) ...[
                const SizedBox(height: 4),
                Text(
                  '${lang.getString('admin_sec_i_months')}: ${(m['months'] ?? '—').toString()}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '${lang.getString('admin_sec_i_amount')}: $priceShown',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '${lang.getString('admin_sec_c_pay_method')}: $pmLabel',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '${lang.getString('admin_sec_c_order_time')}: $timeStr',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '${lang.getString('admin_sec_c_expires')}: $expStr',
                style: const TextStyle(fontSize: 14),
              ),
              if (_orderHasManualMonthlyBilling(m)) ...[
                const SizedBox(height: 4),
                Text(
                  '月繳進度: '
                  '${_orderManualBillingPaidMonths(m)}/'
                  '${_orderManualBillingTotalMonths(m)}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '月繳狀態: ${_subscriptionOrderManualBillingStatus(m)}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${lang.getString('admin_sec_c_pay_state')}: ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    paidShown
                        ? lang.getString('admin_sec_c_paid')
                        : lang.getString('admin_sec_c_unpaid'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: paidShown ? Colors.green[700] : Colors.orange[800],
                    ),
                  ),
                  const Spacer(),
                  if (!paidShown || canConfirmNextManualCycle) ...[
                    FilledButton.tonal(
                      onPressed: () => _markSubscriptionOrderAdminPaid(
                        context,
                        lang,
                        svc,
                        orderDocId: d.id,
                      ),
                      style: FilledButton.styleFrom(
                        foregroundColor: Colors.green.shade800,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      child: Text(lang.getString('admin_sec_c_btn_mark_paid')),
                    ),
                    const SizedBox(width: 8),
                  ],
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[800],
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () => _confirmDeleteSubscriptionOrder(
                      context,
                      lang,
                      svc,
                      orderDocId: d.id,
                      memberUid: uid.isEmpty ? null : uid,
                    ),
                    child: Text(lang.getString('btn_delete')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  if (!isAd || uid.isEmpty) {
    return cardForUserDoc(null);
  }
  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection(FirestorePaths.users)
        .doc(uid)
        .snapshots(),
    builder: (context, userSnap) {
      return cardForUserDoc(userSnap.data?.data());
    },
  );
}

Widget _buildMemberRegistrationBlock(
  BuildContext context,
  LanguageProvider lang,
  String uid,
) {
  if (uid.isEmpty) {
    return Text(
      '${lang.getString('admin_field_uid')}：—',
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }
  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    future: FirebaseFirestore.instance
        .collection(FirestorePaths.users)
        .doc(uid)
        .get(),
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(minHeight: 2),
        );
      }
      if (!snap.hasData || !snap.data!.exists) {
        return Text(
          '${lang.getString('admin_field_uid')}：$uid',
          style: const TextStyle(fontSize: 13),
        );
      }
      final u = snap.data!.data()!;
      final memberNo = (u['memberNo'] as String?)?.trim() ?? '';
      final name = (u['displayName'] as String?)?.trim() ?? '';
      final email = (u['email'] as String?)?.trim() ?? '';
      final phone = (u['phone'] as String?)?.trim() ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lang.getString('admin_sec_c_member'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          if (memberNo.isNotEmpty)
            Text(
              '${lang.getString('admin_sec_member_no')}: $memberNo',
              style: const TextStyle(fontSize: 14),
            ),
          if (name.isNotEmpty)
            Text(
              '${lang.getString('admin_sec_display_name')}: $name',
              style: const TextStyle(fontSize: 14),
            ),
          if (email.isNotEmpty)
            Text('Email：$email', style: const TextStyle(fontSize: 14)),
          if (phone.isNotEmpty)
            Text(
              '${lang.getString('phone')}: $phone',
              style: const TextStyle(fontSize: 14),
            ),
        ],
      );
    },
  );
}

class AdminSectionCPage extends StatelessWidget {
  const AdminSectionCPage({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final svc = AdminBackendService.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_c')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: svc.watchSubscriptionOrders(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(_streamErrorMessage(lang, snap.error)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs
              .where(
                (d) => SubscriptionOrderService
                    .isSubscriptionPlanOrderForAdminList(
                  d.data(),
                ),
              )
              .toList();
          final monthly = svc.filterOrdersThisMonth(docs);
          final expiring = svc.ordersExpiringWithinDays(docs, 30);
          final monthPaidHkd = _subscriptionPlanMonthlyPaidHkd(monthly);
          final paidAmtStr = _adminFormatHkdStat(monthPaidHkd);
          final monthPaidLine = lang
              .getString('admin_sec_c_monthly_paid_line')
              .replaceAll('{amount}', 'HKD\$$paidAmtStr');
          final renewalCount = _subscriptionPlanAutoRenewalCount(docs);
          final renewalLine = lang
              .getString('admin_sec_c_renewal_total')
              .replaceAll('{n}', '$renewalCount');

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${lang.getString('admin_sec_c_monthly')}: ${monthly.length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              monthPaidLine,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${lang.getString('admin_sec_c_expiry_hint')}: ${expiring.length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              renewalLine,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                if (docs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(lang.getString('admin_sec_empty')),
                  )
                else
                  AdminPagedDocumentsFrame(
                    expand: false,
                    docs: docs,
                    childBuilder: (context, pageDocs) {
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pageDocs.length,
                        itemBuilder: (context, i) {
                          final d = pageDocs[i];
                          return _adminSubscriptionOrderCard(
                            context,
                            lang,
                            svc,
                            d,
                          );
                        },
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// —— D：見 [admin_section_d_page.dart] ——

// —— E ——

Widget _adminActivityRegistrationOrderCard(
  BuildContext context,
  LanguageProvider lang,
  AdminBackendService svc,
  QueryDocumentSnapshot<Map<String, dynamic>> d,
) {
  final m = d.data();
  final uid = (m['userId'] as String?) ?? '';
  final title = (m['planName'] ?? '—').toString();
  final headcount = (m['months'] ?? '—').toString();
  final total = (m['totalPrice'] ?? '—').toString();
  final pmLabel = _subscriptionPaymentMethodLabel(
      lang, (m['paymentMethod'] as String?) ?? '');
  final summary = (m['activitySummary'] as String?)?.trim() ?? '';
  final created = m['createdAt'];
  var timeStr = '—';
  if (created is Timestamp) {
    timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(created.toDate());
  }
  final paidShown = _subscriptionOrderDisplayPaid(m);

  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              lang.getString('payment_type_activity'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.teal.shade900,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildMemberRegistrationBlock(context, lang, uid),
          const Divider(height: 20),
          Text(
            '${lang.getString('event_name')}: $title',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '${lang.getString('activity_reg_headcount')}: $headcount',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            '${lang.getString('payment_amount')}: $total',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            '${lang.getString('admin_sec_c_pay_method')}: $pmLabel',
            style: const TextStyle(fontSize: 14),
          ),
          if (summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${lang.getString('admin_activity_summary')}\n$summary',
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${lang.getString('admin_sec_c_order_time')}: $timeStr',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${lang.getString('admin_sec_c_pay_state')}: ',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              Text(
                paidShown
                    ? lang.getString('admin_sec_c_paid')
                    : lang.getString('admin_sec_c_unpaid'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: paidShown ? Colors.green[700] : Colors.orange[800],
                ),
              ),
              const Spacer(),
              if (!paidShown) ...[
                FilledButton.tonal(
                  onPressed: () => _markSubscriptionOrderAdminPaid(
                    context,
                    lang,
                    svc,
                    orderDocId: d.id,
                  ),
                  style: FilledButton.styleFrom(
                    foregroundColor: Colors.green.shade800,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  child: Text(lang.getString('admin_sec_c_btn_mark_paid')),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[800],
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                onPressed: () => _confirmDeleteSubscriptionOrder(
                  context,
                  lang,
                  svc,
                  orderDocId: d.id,
                  memberUid: uid.isEmpty ? null : uid,
                ),
                child: Text(lang.getString('btn_delete')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AdminSectionEPage extends StatefulWidget {
  const AdminSectionEPage({super.key});

  @override
  State<AdminSectionEPage> createState() => _AdminSectionEPageState();
}

class _AdminSectionEPageState extends State<AdminSectionEPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _purgeStaleUnpaid());
  }

  Future<void> _purgeStaleUnpaid() async {
    await ensureFirebaseIdentityForAdminBackend();
    if (!mounted) return;
    final n = await AdminBackendService.instance
        .purgeAllUnpaidSubscriptionOrdersOlderThanRepeated(
      const Duration(days: 30),
    );
    if (!mounted || n <= 0) return;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lang
              .getString('admin_purge_unpaid_orders_snackbar')
              .replaceAll('{n}', '$n'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final svc = AdminBackendService.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_e')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: svc.watchSubscriptionOrders(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(_streamErrorMessage(lang, snap.error)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final activityDocs = snap.data!.docs.where((d) {
            final k = d.data()['purchaseKind'] as String?;
            return k ==
                SubscriptionOrderService.purchaseKindActivityRegistration;
          }).toList();
          final stats = _activityOrdersThisMonthStats(activityDocs);
          final paidAmtStr = _adminFormatHkdStat(stats.monthPaidHkd);
          final paidLine = lang
              .getString('admin_sec_e_monthly_paid_total')
              .replaceAll('{amount}', 'HKD\$$paidAmtStr');

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang
                                  .getString('admin_sec_e_monthly_count')
                                  .replaceAll('{n}', '${stats.monthCount}'),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[800],
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              lang.getString('admin_sec_e_monthly_paid_label'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              paidLine,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (activityDocs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      lang.getString('admin_sec_e_activity_empty'),
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  )
                else
                  AdminPagedDocumentsFrame(
                    expand: false,
                    docs: activityDocs,
                    childBuilder: (context, pageDocs) {
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pageDocs.length,
                        itemBuilder: (context, i) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _adminActivityRegistrationOrderCard(
                              context,
                              lang,
                              svc,
                              pageDocs[i],
                            ),
                          );
                        },
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// —— F ——

void _showAdminEventCmsDetailPreview(
  BuildContext context,
  LanguageProvider lang,
  Map<String, dynamic> m,
) {
  final detail = (m['activityDetail'] as String?)?.trim() ?? '';
  final poster = (m['registrationPosterUrl'] ?? '').toString().trim();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(lang.getString('admin_sec_f_activity_detail')),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (poster.isNotEmpty) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  enableFeedback: false,
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog<void>(
                      context: context,
                      builder: (zoomCtx) => Dialog(
                        backgroundColor: Colors.black87,
                        insetPadding: EdgeInsets.zero,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4,
                              child: Center(
                                child: StorageNetworkImage(
                                  url: poster,
                                  width: MediaQuery.sizeOf(zoomCtx).width,
                                  height:
                                      MediaQuery.sizeOf(zoomCtx).height * 0.88,
                                  fit: BoxFit.contain,
                                  borderRadius: 0,
                                ),
                              ),
                            ),
                            Positioned(
                              top: MediaQuery.paddingOf(zoomCtx).top + 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white),
                                onPressed: () => Navigator.pop(zoomCtx),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: StorageNetworkImage(
                      url: poster,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      borderRadius: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                lang.getString('activity_details_label'),
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              const SizedBox(height: 8),
            ],
            if (detail.isNotEmpty)
              SelectableText(detail, style: const TextStyle(height: 1.45))
            else if (poster.isEmpty)
              Text(
                lang.getString('admin_sec_empty'),
                style: TextStyle(color: Colors.grey[700]),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
}

/// 活動 CMS 列表：進入時先 [ensureFirebaseIdentityForAdminBackend]，並在 Firebase 登入身分就緒後
/// 重新訂閱 [watchEventCms]（避免初次建立串流時尚未登入而一直停留在錯誤／空狀態）。
class _AdminSectionFEventList extends StatefulWidget {
  const _AdminSectionFEventList({
    required this.lang,
    required this.svc,
    required this.onEdit,
    required this.listEpoch,
  });

  final LanguageProvider lang;
  final AdminBackendService svc;
  final void Function(String docId) onEdit;

  /// 儲存成功後遞增，強制重新訂閱 [watchEventCms] 以確保列表與伺服器一致。
  final int listEpoch;

  @override
  State<_AdminSectionFEventList> createState() =>
      _AdminSectionFEventListState();
}

class _AdminSectionFEventListState extends State<_AdminSectionFEventList> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await ensureFirebaseIdentityForAdminBackend();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final svc = widget.svc;

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, authSnap) {
        final authKey = authSnap.data?.uid ??
            FirebaseAuth.instance.currentUser?.uid ??
            'none';
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          key: ValueKey<String>(
            'event_cms_${authKey}_${widget.listEpoch}',
          ),
          stream: svc.watchEventCms(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _streamErrorMessage(lang, snap.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () async {
                          await ensureFirebaseIdentityForAdminBackend();
                          if (context.mounted) setState(() {});
                        },
                        child: Text(lang.getString('admin_firebase_retry')),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs.toList()
              ..sort((a, b) {
                final ta = a.data()['updatedAt'];
                final tb = b.data()['updatedAt'];
                final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
                final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
                return db.compareTo(da);
              });
            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        lang.getString('admin_sec_empty'),
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        lang.getString('admin_sec_f_empty_hint'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return AdminPagedDocumentsFrame(
              docs: docs,
              childBuilder: (context, pageDocs) {
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: pageDocs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = pageDocs[i];
                    final m = d.data();
                    final title = (m['title'] as String?) ?? '—';
                    final price = (m['price'] as String?)?.trim();
                    final poster =
                        (m['registrationPosterUrl'] ?? '').toString().trim();
                    var thumb = poster;
                    if (thumb.isEmpty) {
                      final urls = m['imageUrls'];
                      if (urls is List) {
                        for (final e in urls) {
                          final s = e.toString().trim();
                          if (s.isNotEmpty) {
                            thumb = s;
                            break;
                          }
                        }
                      }
                    }
                    final subStyle = TextStyle(
                      fontSize: 13,
                      color: Colors.grey[800],
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                if (price != null && price.isNotEmpty)
                                  Text(
                                    '${lang.getString('admin_sec_f_price')}: $price',
                                    style: subStyle,
                                  ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () =>
                                      _showAdminEventCmsDetailPreview(
                                    context,
                                    lang,
                                    m,
                                  ),
                                  child: Text(
                                    lang.getString(
                                      'admin_sec_f_view_activity_detail',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8, right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 72,
                                height: 72,
                                child: thumb.isNotEmpty
                                    ? StorageNetworkImage(
                                        url: thumb,
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                        borderRadius: 8,
                                      )
                                    : Container(
                                        width: 72,
                                        height: 72,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          border: Border.all(
                                            color: Colors.blue.shade300,
                                            width: 1.5,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          lang.getString(
                                            'admin_sec_f_list_poster_placeholder',
                                          ),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.blue[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => widget.onEdit(d.id),
                                child: Text(lang.getString('btn_edit')),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red[700],
                                ),
                                onPressed: () async {
                                  final identityOk =
                                      await ensureFirebaseIdentityForAdminBackend();
                                  if (!context.mounted) return;
                                  if (!identityOk) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          lang.getString(
                                            'admin_firebase_required',
                                          ),
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (dialogCtx) => AlertDialog(
                                      title: Text(lang.getString('btn_delete')),
                                      content: Text(
                                        lang.getString(
                                          'admin_sec_f_delete_confirm',
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogCtx, false),
                                          child: Text(lang.getString('cancel')),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red[700],
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(dialogCtx, true),
                                          child: Text(
                                            lang.getString('btn_delete'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true || !context.mounted) return;
                                  try {
                                    await svc.deleteEventCms(d.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            lang.getString('admin_sec_deleted'),
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                    }
                                  }
                                },
                                child: Text(lang.getString('btn_delete')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class AdminSectionFPage extends StatefulWidget {
  const AdminSectionFPage({super.key});

  @override
  State<AdminSectionFPage> createState() => _AdminSectionFPageState();
}

class _AdminSectionFPageState extends State<AdminSectionFPage> {
  int _listEpoch = 0;

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final svc = AdminBackendService.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_f_editor')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editEvent(context, lang, svc, null),
        icon: const Icon(Icons.add),
        label: Text(lang.getString('admin_sec_f_add')),
      ),
      body: _AdminSectionFEventList(
        lang: lang,
        svc: svc,
        listEpoch: _listEpoch,
        onEdit: (docId) => _editEvent(context, lang, svc, docId),
      ),
    );
  }

  Future<void> _editEvent(
    BuildContext context,
    LanguageProvider lang,
    AdminBackendService svc,
    String? docId,
  ) async {
    final identityPre = await ensureFirebaseIdentityForAdminBackend();
    if (!identityPre) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lang.getString('admin_firebase_required'))),
        );
      }
      return;
    }

    final titleCtrl = TextEditingController();
    var bodyPersisted = '';
    final activityDetailCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final existingUrls = <String>[];
    var selectedPayment = ActivityCmsPaymentCodes.iapStores;
    var selectedMaxReg = 10;
    final effectiveDocId = docId ??
        FirebaseFirestore.instance.collection(FirestorePaths.eventCms).doc().id;
    var registrationPosterUrl = '';

    if (docId != null) {
      final doc = await FirebaseFirestore.instance
          .collection(FirestorePaths.eventCms)
          .doc(docId)
          .get();
      final m = doc.data();
      if (m != null) {
        titleCtrl.text = (m['title'] as String?) ?? '';
        bodyPersisted = (m['body'] as String?) ?? '';
        activityDetailCtrl.text = (m['activityDetail'] as String?) ?? '';
        priceCtrl.text = (m['price'] as String?)?.trim() ?? '';
        final capRaw = m['maxParticipants'];
        if (capRaw is int) {
          selectedMaxReg = capRaw.clamp(1, 10);
        } else if (capRaw is num) {
          selectedMaxReg = capRaw.toInt().clamp(1, 10);
        }
        final pm = (m['paymentMethod'] as String?)?.trim();
        if (pm != null &&
            pm.isNotEmpty &&
            ActivityCmsPaymentCodes.orderedChoices.contains(pm)) {
          selectedPayment = pm;
        }
        final urls = m['imageUrls'];
        if (urls is List) {
          for (final e in urls) {
            final s = e.toString().trim();
            if (s.isNotEmpty) existingUrls.add(s);
          }
        }
        registrationPosterUrl =
            (m['registrationPosterUrl'] ?? '').toString().trim();
      }
    }

    if (!context.mounted) return;

    var posterUploadBusy = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: Text(lang.getString('admin_sec_f_editor')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: lang.getString('event_name'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      lang.getString('admin_sec_f_event_poster_upload'),
                      style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      enableFeedback: false,
                      onTap: posterUploadBusy
                          ? null
                          : () async {
                              final picker = ImagePicker();
                              final x = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1920,
                                imageQuality: 82,
                              );
                              if (x == null) return;
                              posterUploadBusy = true;
                              setSt(() {});
                              try {
                                final bytes = await x.readAsBytes();
                                final raw = Uint8List.fromList(bytes);
                                final prepared =
                                    prepareEventCmsPosterForUpload(raw);
                                if (!ctx.mounted) return;
                                if (prepared == null) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        lang.getString(
                                          'admin_sec_f_poster_invalid_format',
                                        ),
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final url = await svc
                                    .uploadPreparedEventCmsRegistrationPoster(
                                  eventDocId: effectiveDocId,
                                  prepared: prepared,
                                );
                                if (!ctx.mounted) return;
                                if (url != null) {
                                  setSt(() => registrationPosterUrl = url);
                                } else {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        lang.getString(
                                          'event_proposal_image_failed',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              } catch (e, st) {
                                debugPrint('poster upload: $e\n$st');
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${lang.getString('event_proposal_image_failed')} ($e)',
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                posterUploadBusy = false;
                                if (ctx.mounted) setSt(() {});
                              }
                            },
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 160,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.blue.shade300,
                                width: 1.5,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: registrationPosterUrl.isNotEmpty
                                ? StorageNetworkImage(
                                    url: registrationPosterUrl,
                                    width: double.infinity,
                                    height: 160,
                                    fit: BoxFit.contain,
                                    borderRadius: 12,
                                  )
                                : Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 56,
                                    color: Colors.grey[500],
                                  ),
                          ),
                          if (posterUploadBusy)
                            Container(
                              height: 160,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lang.getString('admin_sec_f_tap_area_to_upload'),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lang.getString('admin_sec_f_poster_rules'),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  if (registrationPosterUrl.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            setSt(() => registrationPosterUrl = ''),
                        child: Text(
                          lang.getString('admin_sec_f_remove_event_poster'),
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: activityDetailCtrl,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: lang.getString('admin_sec_f_activity_detail'),
                      hintText:
                          lang.getString('admin_sec_f_activity_detail_hint'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: selectedMaxReg,
                    decoration: InputDecoration(
                      labelText: lang.getString('admin_sec_f_registration_cap'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: List.generate(
                      10,
                      (i) => DropdownMenuItem<int>(
                        value: i + 1,
                        child: Text('${i + 1}'),
                      ),
                    ),
                    onChanged: (v) {
                      if (v != null) {
                        setSt(() => selectedMaxReg = v);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    decoration: InputDecoration(
                      labelText: lang.getString('admin_sec_f_price'),
                      hintText: 'HKD\$…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (docId != null)
                TextButton(
                  onPressed: () async {
                    await svc.deleteEventCms(docId);
                    if (ctx.mounted) Navigator.pop(ctx, false);
                  },
                  child: Text(lang.getString('btn_delete')),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(lang.getString('close')),
              ),
              FilledButton(
                onPressed: () {
                  if (titleCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          lang.getString('admin_sec_f_title_required'),
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(lang.getString('btn_save')),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && context.mounted) {
      if (titleCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lang.getString('admin_sec_f_title_required'))),
        );
        titleCtrl.dispose();
        activityDetailCtrl.dispose();
        priceCtrl.dispose();
        return;
      }
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(lang.getString('admin_sec_f_saving')),
                ),
              ],
            ),
          ),
        ),
      );
      try {
        await ensureFirebaseIdentityForAdminBackend();
        var urls = <String>[];
        if (docId != null && existingUrls.isNotEmpty) {
          urls = List<String>.from(existingUrls);
        }
        final result = await svc.saveEventCms(
          docId: docId ?? effectiveDocId,
          title: titleCtrl.text,
          body: bodyPersisted,
          imageUrls: urls,
          paymentNote: '',
          gmailNotify: false,
          price: priceCtrl.text,
          paymentMethod: selectedPayment,
          maxParticipants: selectedMaxReg,
          activityDetail: activityDetailCtrl.text,
          registrationPosterUrl: registrationPosterUrl,
        );
        if (!context.mounted) return;
        if (!result.wrote) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(lang.getString('admin_firebase_required'))),
          );
        } else {
          setState(() => _listEpoch++);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(lang.getString('admin_sec_saved'))),
          );
          if (result.frontendSyncError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  lang
                      .getString('admin_sec_f_sync_failed')
                      .replaceAll('{error}', result.frontendSyncError!),
                ),
              ),
            );
          }
        }
      } catch (e, st) {
        debugPrint('saveEventCms: $e\n$st');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${lang.getString('admin_save_failed')}: $e',
              ),
            ),
          );
        }
      } finally {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    }
    titleCtrl.dispose();
    activityDetailCtrl.dispose();
    priceCtrl.dispose();
  }
}

// —— G ——

class AdminSectionGPage extends StatefulWidget {
  const AdminSectionGPage({super.key});

  @override
  State<AdminSectionGPage> createState() => _AdminSectionGPageState();
}

class _AdminSectionGPageState extends State<AdminSectionGPage> {
  String _statusLabel(LanguageProvider lang, EventProposalRecord r) {
    switch (r.status) {
      case EventProposalStatus.approved:
        return lang.getString('event_proposal_status_passed');
      case EventProposalStatus.rejected:
        return lang.getString('event_proposal_status_rejected');
      case EventProposalStatus.pending:
        return lang.getString('pending_review');
    }
  }

  Color _statusColor(EventProposalRecord r) {
    switch (r.status) {
      case EventProposalStatus.approved:
        return Colors.green;
      case EventProposalStatus.rejected:
        return Colors.red;
      case EventProposalStatus.pending:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_g')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
      ),
      body: StreamBuilder<List<EventProposalRecord>>(
        stream: EventProposalService.watchAllForAdmin(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(_streamErrorMessage(lang, snap.error)),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return Center(child: Text(lang.getString('admin_sec_empty')));
          }
          return AdminPagedGenericFrame<EventProposalRecord>(
            items: list,
            itemBuilder: (context, i, r) {
              final email = r.userEmail ?? '—';
              final detail = [
                if (r.content.isNotEmpty) r.content,
                if (r.venue.isNotEmpty)
                  '${lang.getString('event_venue')}: ${r.venue}',
                if (r.date.isNotEmpty)
                  '${lang.getString('event_date')}: ${r.date}',
                if (r.time.isNotEmpty)
                  '${lang.getString('event_time')}: ${r.time}',
                if (r.costPrice.isNotEmpty)
                  '${lang.getString('event_cost')}: ${r.costPrice}',
              ].join(' · ');
              final stColor = _statusColor(r);
              return Material(
                color: AppConstants.white,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.eventName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                if (detail.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    detail,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('yyyy/MM/dd HH:mm')
                                      .format(r.createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: stColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: stColor),
                            ),
                            child: Text(
                              _statusLabel(lang, r),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: stColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (r.status == EventProposalStatus.pending) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () async {
                                await EventProposalService.setAdminStatus(
                                  r.id,
                                  EventProposalStatus.rejected,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        lang.getString(
                                            'event_proposal_status_rejected'),
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Text(lang
                                  .getString('event_proposal_status_rejected')),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () async {
                                await EventProposalService.setAdminStatus(
                                  r.id,
                                  EventProposalStatus.approved,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        lang.getString(
                                            'event_proposal_status_passed'),
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Text(
                                lang.getString('event_proposal_status_passed'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// —— H —— 見 [admin_payment_settings_page.dart]

// —— I ——

/// 廣告貼文訂單／廣告審批共用。
///
/// [includeAdSubscriptionOrders]：`false` 時僅顯示會員「廣告貼文記錄」同步之待審資料（[users]），
/// 不含 [subscription_orders] 廣告貼文訂單（供 [AdminSectionAdApprovalPage]）。
class _AdCoopReviewPanel extends StatelessWidget {
  const _AdCoopReviewPanel({
    required this.embedMonthlySummary,
    this.includeAdSubscriptionOrders = true,
    this.includeStandaloneMirrorRecords = false,
  });

  /// `true`：「廣告貼文訂單」頁（頂部僅本月統計；卡片僅會員＋訂單／付款；不顯示貼文與審核）。`false`：廣告審批頁（貼文＋審核，不顯示訂單／付款欄）。
  final bool embedMonthlySummary;

  /// `false`：廣告審批頁只列出與會員端「廣告貼文記錄」一致之待審貼文，不混入廣告訂單列表。
  final bool includeAdSubscriptionOrders;

  /// `true`：額外顯示來自 `users.adCoopLatestSubmission` 的無訂單／備援審批資料。
  final bool includeStandaloneMirrorRecords;

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final svc = AdminBackendService.instance;

    if (includeAdSubscriptionOrders && includeStandaloneMirrorRecords) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: svc.watchSubscriptionOrders(),
        builder: (context, orderSnap) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: svc.watchUsersWithStandaloneAdCoopPending(),
            builder: (context, standSnap) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: svc.watchUsersWithAdCoopAdminReviewPending(),
                builder: (context, adminSnap) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: svc.watchUsersWithManagedAdCoopPromotions(),
                    builder: (context, promoSnap) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream:
                            svc.watchUsersWithAdCoopApprovalArchiveVisible(),
                        builder: (context, archiveSnap) {
                          final err = orderSnap.error ??
                              standSnap.error ??
                              adminSnap.error ??
                              promoSnap.error ??
                              archiveSnap.error;
                          if (err != null) {
                            return Center(
                              child: Text(_streamErrorMessage(lang, err)),
                            );
                          }
                          if (!orderSnap.hasData ||
                              !standSnap.hasData ||
                              !adminSnap.hasData ||
                              !promoSnap.hasData ||
                              !archiveSnap.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final orderDocs = orderSnap.data!.docs
                              .where(
                                (d) =>
                                    _subscriptionOrderIsAdCoop(d.data()) &&
                                    _subscriptionOrderHasAdCoopContent(
                                        d.data()),
                              )
                              .toList()
                            ..sort(
                              (a, b) => _adCoopOrderSortMs(b.data())
                                  .compareTo(_adCoopOrderSortMs(a.data())),
                            );
                          final standDocs = standSnap.data!.docs
                              .map((d) =>
                                  d as DocumentSnapshot<Map<String, dynamic>>)
                              .toList();
                          final adminDocs = adminSnap.data!.docs
                              .map((d) =>
                                  d as DocumentSnapshot<Map<String, dynamic>>)
                              .toList();
                          final promoDocs = promoSnap.data!.docs
                              .map((d) =>
                                  d as DocumentSnapshot<Map<String, dynamic>>)
                              .toList();
                          final archiveDocs = archiveSnap.data!.docs
                              .map((d) =>
                                  d as DocumentSnapshot<Map<String, dynamic>>)
                              .toList();

                          final mergedUserDocs =
                              _filterStandaloneApprovalDocsWithoutLinkedOrders(
                            _mergeAdCoopApprovalUserDocs(
                              _mergeAdCoopApprovalUserDocs(
                                _mergeAdCoopApprovalUserDocs(
                                    standDocs, adminDocs),
                                promoDocs,
                              ),
                              archiveDocs,
                            ),
                          );

                          if (orderDocs.isEmpty && mergedUserDocs.isEmpty) {
                            return Center(
                              child: Text(lang.getString('admin_sec_empty')),
                            );
                          }

                          return SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (orderDocs.isNotEmpty)
                                  _adCoopApprovalOrderListBody(
                                    context,
                                    lang,
                                    svc,
                                    orderDocs,
                                  ),
                                if (mergedUserDocs.isNotEmpty)
                                  _adCoopApprovalMergedListBody(
                                    context,
                                    lang,
                                    svc,
                                    mergedUserDocs,
                                    showEmptyState: false,
                                    wrapWithScrollView: false,
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    }

    if (!includeAdSubscriptionOrders) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: svc.watchUsersWithStandaloneAdCoopPending(),
        builder: (context, standSnap) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: svc.watchUsersWithAdCoopAdminReviewPending(),
            builder: (context, adminSnap) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: svc.watchUsersWithManagedAdCoopPromotions(),
                builder: (context, promoSnap) {
                  final err =
                      standSnap.error ?? adminSnap.error ?? promoSnap.error;
                  if (err != null) {
                    return Center(
                      child: Text(_streamErrorMessage(lang, err)),
                    );
                  }
                  if (!standSnap.hasData ||
                      !adminSnap.hasData ||
                      !promoSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final standDocs = standSnap.data!.docs
                      .map((d) => d as DocumentSnapshot<Map<String, dynamic>>)
                      .toList();
                  final adminDocs = adminSnap.data!.docs
                      .map((d) => d as DocumentSnapshot<Map<String, dynamic>>)
                      .toList();
                  final promoDocs = promoSnap.data!.docs
                      .map((d) => d as DocumentSnapshot<Map<String, dynamic>>)
                      .toList();
                  final mergedAb = _mergeAdCoopApprovalUserDocs(
                    _mergeAdCoopApprovalUserDocs(standDocs, adminDocs),
                    promoDocs,
                  );
                  return _adCoopApprovalMergedListBody(
                    context,
                    lang,
                    svc,
                    mergedAb,
                  );
                },
              );
            },
          );
        },
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: svc.watchSubscriptionOrders(),
      builder: (context, orderSnap) {
        if (orderSnap.hasError) {
          return Center(
            child: Text(_streamErrorMessage(lang, orderSnap.error)),
          );
        }
        if (!orderSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = orderSnap.data!.docs
            .where((d) => _subscriptionOrderIsAdCoop(d.data()))
            .toList();
        final monthlyAd = svc.filterOrdersThisMonth(docs);
        final monthPaidHkd = _subscriptionPlanMonthlyPaidHkd(monthlyAd);
        final paidAmtStr = _adminFormatHkdStat(monthPaidHkd);

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (embedMonthlySummary) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${lang.getString('admin_sec_i_monthly_orders')}：${monthlyAd.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${lang.getString('admin_sec_i_monthly_paid_total')}：HKD\$$paidAmtStr',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
              ],
              if (docs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(lang.getString('admin_sec_empty')),
                ),
              if (docs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AdminPagedDocumentsFrame(
                    expand: false,
                    docs: docs,
                    childBuilder: (context, pageDocs) {
                      return ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pageDocs.length,
                        itemBuilder: (context, i) {
                          return _adminSubscriptionOrderCard(
                            context,
                            lang,
                            svc,
                            pageDocs[i],
                            showAdPostContentBlock: !embedMonthlySummary,
                            adPostContentUseInline: !embedMonthlySummary,
                            hideAdOrderPaymentMeta: !embedMonthlySummary,
                            showAdCoopReviewControls: !embedMonthlySummary,
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class AdminSectionIPage extends StatelessWidget {
  const AdminSectionIPage({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_i')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
      ),
      body: const _AdCoopReviewPanel(embedMonthlySummary: true),
    );
  }
}

/// 廣告審批：與 [AdminSectionIPage] 相同資料來源；顯示會員資料、廣告貼文內容、提交時間與審核操作。
class AdminSectionAdApprovalPage extends StatelessWidget {
  const AdminSectionAdApprovalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_ad_approval_title')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: const _AdCoopReviewPanel(
        embedMonthlySummary: false,
        includeAdSubscriptionOrders: true,
        includeStandaloneMirrorRecords: true,
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AllowAdminScreenshot(
                    child: AdminSectionPromotionPostPage()),
              ),
            );
          },
          icon: const Icon(Icons.campaign_outlined),
          label: Text(lang.getString('admin_sec_ad_promotion')),
        ),
      ),
    );
  }
}

class AdminSectionPromotionPostPage extends StatefulWidget {
  const AdminSectionPromotionPostPage({super.key});

  @override
  State<AdminSectionPromotionPostPage> createState() =>
      _AdminSectionPromotionPostPageState();
}

class _AdminSectionPromotionPostPageState
    extends State<AdminSectionPromotionPostPage> {
  static const int _defaultPromotionMonths = 12;
  static const List<int> _promotionMonthOptions = [1, 3, 6, 12];

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _linkCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();
  final ScrollController _promotionScrollController = ScrollController();

  Uint8List? _pickedImageBytes;
  String _pickedImageDataUrl = '';
  /// 編輯既有貼文時，沿用 Firestore 內既有圖片 URL（未重選圖時）。
  String _editingRemoteImageUrl = '';
  String? _editingPostId;
  int _selectedPromotionMonths = _defaultPromotionMonths;
  bool _imageBusy = false;
  bool _publishing = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _linkCtrl.dispose();
    _contentCtrl.dispose();
    _promotionScrollController.dispose();
    super.dispose();
  }

  void _cancelEditingPromotion() {
    setState(() {
      _editingPostId = null;
      _editingRemoteImageUrl = '';
      _titleCtrl.clear();
      _linkCtrl.clear();
      _contentCtrl.clear();
      _pickedImageBytes = null;
      _pickedImageDataUrl = '';
      _selectedPromotionMonths = _defaultPromotionMonths;
    });
  }

  void _loadPostForEditing(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    final savedMonths = m['promotionDurationMonths'];
    final durationMonths = savedMonths is int
        ? savedMonths
        : savedMonths is num
            ? savedMonths.toInt()
            : _defaultPromotionMonths;
    setState(() {
      _editingPostId = doc.id;
      _titleCtrl.text = (m['authorName'] as String?)?.trim() ?? '';
      _linkCtrl.text = (m['externalLink'] as String?)?.trim() ?? '';
      _contentCtrl.text = (m['content'] as String?)?.trim() ?? '';
      _selectedPromotionMonths =
          durationMonths < 1 ? _defaultPromotionMonths : durationMonths;
      _pickedImageBytes = null;
      _pickedImageDataUrl = '';
      _editingRemoteImageUrl = (m['imageUrl'] as String?)?.trim() ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_promotionScrollController.hasClients) {
        _promotionScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickPromotionImage(LanguageProvider lang) async {
    if (_imageBusy) return;
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 82,
    );
    if (x == null || !mounted) return;
    setState(() => _imageBusy = true);
    try {
      final raw = Uint8List.fromList(await x.readAsBytes());
      final prepared = prepareEventCmsPosterForUpload(raw);
      if (prepared == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lang.getString('admin_ad_promotion_invalid_image'),
            ),
          ),
        );
        return;
      }
      final dataUrl = imageBytesToFirestoreDataUrl(prepared.bytes);
      if (!mounted) return;
      if (dataUrl == null || dataUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lang.getString('event_proposal_image_failed'),
            ),
          ),
        );
        return;
      }
      setState(() {
        _pickedImageBytes = prepared.bytes;
        _pickedImageDataUrl = dataUrl;
        _editingRemoteImageUrl = '';
      });
    } catch (e, st) {
      debugPrint('admin promotion pick image: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('${lang.getString('event_proposal_image_failed')} ($e)')),
      );
    } finally {
      if (mounted) setState(() => _imageBusy = false);
    }
  }

  void _clearPickedImage() {
    setState(() {
      _pickedImageBytes = null;
      _pickedImageDataUrl = '';
      _editingRemoteImageUrl = '';
    });
  }

  Future<void> _publishPromotion(LanguageProvider lang) async {
    final svc = AdminBackendService.instance;
    if (!_adminEnsureFirebaseWrite(context, lang, svc) || _publishing) return;
    final title = _titleCtrl.text.trim();
    final link = _linkCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(lang.getString('admin_ad_promotion_title_required'))),
      );
      return;
    }
    if (content.isEmpty &&
        link.isEmpty &&
        _pickedImageDataUrl.isEmpty &&
        _editingRemoteImageUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(lang.getString('admin_ad_promotion_content_required'))),
      );
      return;
    }
    setState(() => _publishing = true);
    try {
      final existingId = _editingPostId?.trim() ?? '';
      final imagePayload = _pickedImageDataUrl.trim().isNotEmpty
          ? _pickedImageDataUrl.trim()
          : _editingRemoteImageUrl.trim();
      final postId =
          await FeedFirestoreService.instance.publishAdminAdPromotion(
        displayName: title,
        content: content,
        externalLink: link,
        imageUrl: imagePayload,
        existingPostId: existingId,
        durationMonths: _selectedPromotionMonths,
        promotionOrigin: FeedFirestoreService.adPromotionOriginAdminManual,
      );
      if (!mounted) return;
      if (postId == null || postId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(lang.getString('admin_ad_promotion_publish_failed'))),
        );
        return;
      }
      final wasEditing = existingId.isNotEmpty;
      _titleCtrl.clear();
      _linkCtrl.clear();
      _contentCtrl.clear();
      _clearPickedImage();
      setState(() {
        _selectedPromotionMonths = _defaultPromotionMonths;
        _editingPostId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasEditing
                ? lang.getString('admin_ad_promotion_updated_ok')
                : lang.getString('admin_ad_promotion_publish_ok'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _republishPromotion(
    LanguageProvider lang,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final m = doc.data();
    final savedMonths = m['promotionDurationMonths'];
    final durationMonths = savedMonths is int
        ? savedMonths
        : savedMonths is num
            ? savedMonths.toInt()
            : _defaultPromotionMonths;
    try {
      await FeedFirestoreService.instance.publishAdminAdPromotion(
        displayName: (m['authorName'] as String?)?.trim() ?? '宣傳貼文',
        content: (m['content'] as String?)?.trim() ?? '',
        externalLink: (m['externalLink'] as String?)?.trim() ?? '',
        imageUrl: (m['imageUrl'] as String?)?.trim() ?? '',
        existingPostId: doc.id,
        durationMonths:
            durationMonths < 1 ? _defaultPromotionMonths : durationMonths,
        promotionOrigin: FeedFirestoreService.adPromotionOriginAdminManual,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(lang.getString('admin_ad_promotion_republish_ok'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _promotionStatusLabel(String status) {
    switch (status) {
      case FeedFirestoreService.adPromotionStatusActive:
        return '發佈中';
      case FeedFirestoreService.adPromotionStatusPausedManual:
        return '已暫停';
      case FeedFirestoreService.adPromotionStatusPausedExpired:
        return '已到期';
      default:
        return '未發佈';
    }
  }

  Widget _buildImageBox(LanguageProvider lang) {
    final hasLocal =
        _pickedImageBytes != null && _pickedImageBytes!.isNotEmpty;
    final hasRemote = _editingRemoteImageUrl.trim().isNotEmpty;
    final showPreview = hasLocal || hasRemote;
    return Stack(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            enableFeedback: false,
            onTap: _imageBusy ? null : () => _pickPromotionImage(lang),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black87, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasLocal
                  ? Image.memory(
                      _pickedImageBytes!,
                      fit: BoxFit.cover,
                    )
                  : hasRemote
                      ? StorageNetworkImage(
                          url: _editingRemoteImageUrl,
                          width: double.infinity,
                          height: 220,
                          fit: BoxFit.cover,
                          borderRadius: 0,
                        )
                      : Center(
                          child: Text(
                            lang.getString('admin_ad_promotion_upload'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
            ),
          ),
        ),
        if (_imageBusy)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
              ),
            ),
          ),
        if (showPreview)
          Positioned(
            top: 10,
            right: 10,
            child: IconButton.filledTonal(
              onPressed: _clearPickedImage,
              icon: const Icon(Icons.close),
            ),
          ),
      ],
    );
  }

  Widget _buildPromotionCard(
    LanguageProvider lang,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data();
    final title = (m['authorName'] as String?)?.trim() ?? '宣傳貼文';
    final content = (m['content'] as String?)?.trim() ?? '';
    final link = (m['externalLink'] as String?)?.trim() ?? '';
    final imageUrl = (m['imageUrl'] as String?)?.trim() ?? '';
    final status = (m['promotionStatus'] as String?)?.trim() ?? '';
    final createdAt = m['createdAt'];
    final expiresAt = m['promotionExpiresAt'];
    final durationMonths = m['promotionDurationMonths'];
    final createdLine = createdAt is Timestamp
        ? DateFormat('yyyy/MM/dd HH:mm').format(createdAt.toDate())
        : '—';
    final expiresLine = expiresAt is Timestamp
        ? DateFormat('yyyy/MM/dd HH:mm').format(expiresAt.toDate())
        : '—';
    final isActive = status == FeedFirestoreService.adPromotionStatusActive;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: imageUrl.isNotEmpty
                        ? StorageNetworkImage(
                            url: imageUrl,
                            width: 92,
                            height: 92,
                            fit: BoxFit.cover,
                            borderRadius: 12,
                          )
                        : Container(
                            color: Colors.orange.shade50,
                            child: const Icon(Icons.campaign, size: 34),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '狀態：${_promotionStatusLabel(status)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                      Text(
                        '期限：${durationMonths is num ? durationMonths.toInt() : _defaultPromotionMonths}個月',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                      Text(
                        '發佈：$createdLine',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                      Text(
                        '到期：$expiresLine',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                content,
                style: const TextStyle(fontSize: 15, height: 1.45),
              ),
            ],
            if (link.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                enableFeedback: false,
                onTap: () async {
                  final u = Uri.tryParse(link);
                  if (u != null && await canLaunchUrl(u)) {
                    await launchUrl(u, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  link,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue[700],
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _loadPostForEditing(doc),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(lang.getString('admin_ad_promotion_edit')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isActive
                        ? () async {
                            try {
                              await FeedFirestoreService.instance
                                  .pauseAdminAdPromotion(doc.id);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    lang.getString(
                                        'admin_ad_promotion_paused_ok'),
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          }
                        : () => _republishPromotion(lang, doc),
                    icon: Icon(
                      isActive
                          ? Icons.pause_circle_outline
                          : Icons.publish_outlined,
                    ),
                    label: Text(
                      isActive
                          ? lang.getString('admin_ad_promotion_pause')
                          : lang.getString('admin_ad_promotion_republish'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final editing = _editingPostId != null && _editingPostId!.isNotEmpty;
    final formFields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editing) ...[
          Material(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.edit_note, color: Colors.amber.shade900, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      lang.getString('admin_ad_promotion_editing_banner'),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: Colors.brown.shade800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelEditingPromotion,
                    child: Text(
                      lang.getString('admin_ad_promotion_cancel_edit'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _titleCtrl,
          decoration: InputDecoration(
            labelText: lang.getString('admin_ad_promotion_title'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _linkCtrl,
          decoration: InputDecoration(
            labelText: lang.getString('admin_ad_promotion_link'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _contentCtrl,
          minLines: 4,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: lang.getString('admin_ad_promotion_content'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          lang.getString('admin_ad_promotion_duration'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _promotionMonthOptions
              .map(
                (months) => OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _selectedPromotionMonths == months
                        ? Colors.blue.shade50
                        : null,
                    foregroundColor: Colors.blue[800],
                    side: BorderSide(color: Colors.blue.shade300),
                  ),
                  onPressed: () =>
                      setState(() => _selectedPromotionMonths = months),
                  child: Text('$months個月'),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _publishing ? null : () => _publishPromotion(lang),
            child: _publishing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    editing
                        ? lang.getString('admin_ad_promotion_save_publish')
                        : lang.getString('admin_ad_promotion_publish'),
                  ),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.getString('admin_sec_ad_promotion')),
        backgroundColor: AppConstants.appBarBackground.withValues(alpha: 0.92),
        toolbarHeight: AppConstants.appBarToolbarHeight,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(FirestorePaths.publicFeedPosts)
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs.where((d) {
                final m = d.data();
                return m['isAdPromotion'] == true &&
                    (m['promotionOrigin'] as String?) ==
                        FeedFirestoreService.adPromotionOriginAdminManual;
              }).toList() ??
              const [];

          return SingleChildScrollView(
            controller: _promotionScrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildImageBox(lang),
                          const SizedBox(height: 16),
                          formFields,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: _buildImageBox(lang)),
                        const SizedBox(width: 20),
                        Expanded(flex: 5, child: formFields),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  lang.getString('admin_ad_promotion_published'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (snap.hasError)
                  Text(_streamErrorMessage(lang, snap.error))
                else if (!snap.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (docs.isEmpty)
                  Text(
                    lang.getString('admin_ad_promotion_empty'),
                    style: TextStyle(color: Colors.grey[700]),
                  )
                else
                  ...docs.map((d) => _buildPromotionCard(lang, d)),
              ],
            ),
          );
        },
      ),
    );
  }
}
