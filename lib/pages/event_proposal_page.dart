import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/event_proposal_provider.dart';
import '../providers/language_provider.dart';
import '../services/event_proposal_service.dart';
import '../utils/constants.dart';

/// 提議活動方案頁：表單提交／修改、紀錄列表（待審核／通過／落選）
/// 進入時會刪除仍為落選且自標示落選起逾 30 日未再提交修改之紀錄。
class EventProposalPage extends StatefulWidget {
  const EventProposalPage({super.key});

  @override
  State<EventProposalPage> createState() => _EventProposalPageState();
}

class _EventProposalPageState extends State<EventProposalPage> {
  EventProposalRecord? _editing;
  final ScrollController _scrollController = ScrollController();

  static String _formatDateTime(DateTime d) {
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      EventProposalService.purgeMyStaleRejectedProposalsOlderThan(
        const Duration(days: 30),
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _statusLabel(LanguageProvider lang, EventProposalRecord record) {
    switch (record.status) {
      case EventProposalStatus.approved:
        return lang.getString('event_proposal_status_passed');
      case EventProposalStatus.rejected:
        return lang.getString('event_proposal_status_rejected');
      case EventProposalStatus.pending:
        return lang.getString('pending_review');
    }
  }

  Color _statusColor(EventProposalRecord record) {
    switch (record.status) {
      case EventProposalStatus.approved:
        return Colors.green;
      case EventProposalStatus.rejected:
        return Colors.red;
      case EventProposalStatus.pending:
        return Colors.orange;
    }
  }

  Widget _buildRecordCard(
    BuildContext context,
    LanguageProvider langProvider,
    EventProposalRecord record,
  ) {
    final statusColor = _statusColor(record);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppConstants.grey.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  record.eventName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (record.content.isNotEmpty || record.venue.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (record.content.isNotEmpty) record.content,
                      if (record.venue.isNotEmpty)
                        '${langProvider.getString('event_venue')}: ${record.venue}',
                      if (record.date.isNotEmpty)
                        '${langProvider.getString('event_date')}: ${record.date}',
                      if (record.time.isNotEmpty)
                        '${langProvider.getString('event_time')}: ${record.time}',
                      if (record.costPrice.isNotEmpty)
                        '${langProvider.getString('event_cost')}: ${record.costPrice}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatDateTime(record.createdAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  _statusLabel(langProvider, record),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              if (record.status == EventProposalStatus.approved) ...[
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC0CB),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    minimumSize: const Size(72, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        content: Text(
                          langProvider
                              .getString('event_proposal_delete_confirm'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(langProvider.getString('cancel')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(langProvider.getString('btn_delete')),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await Provider.of<EventProposalProvider>(context,
                              listen: false)
                          .deleteApprovedRecord(record.id);
                    }
                  },
                  child: Text(langProvider.getString('btn_delete')),
                ),
              ],
              if (record.status == EventProposalStatus.pending) ...[
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFFFF9C4),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    minimumSize: const Size(72, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(color: Colors.amber.shade200),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    setState(() => _editing = record);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  },
                  child: Text(
                      langProvider.getString('event_proposal_record_modify')),
                ),
              ],
              if (record.status == EventProposalStatus.rejected) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFE8F5E9),
                        foregroundColor: const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFFA5D6A7)),
                        ),
                      ),
                      onPressed: () {
                        setState(() => _editing = record);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients) {
                            _scrollController.animateTo(
                              0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        });
                      },
                      child: Text(langProvider.getString('btn_edit')),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFFFCDD2),
                        foregroundColor: const Color(0xFFC62828),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            content: Text(
                              langProvider
                                  .getString('event_proposal_delete_confirm'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(langProvider.getString('cancel')),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child:
                                    Text(langProvider.getString('btn_delete')),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await Provider.of<EventProposalProvider>(context,
                                  listen: false)
                              .deleteRejectedRecord(record.id);
                        }
                      },
                      child: Text(langProvider.getString('btn_delete')),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final provider = Provider.of<EventProposalProvider>(context);
    final records = provider.records;

    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/home'),
        ),
        automaticallyImplyLeading: false,
        title: Text(langProvider.getString('event_proposal')),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontSize: titleFs,
            ) ??
            theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EventProposalForm(
              key: ValueKey(_editing?.id ?? 'new'),
              langProvider: langProvider,
              editingRecord: _editing,
              onCancelEdit: () => setState(() => _editing = null),
              onSaved: () => setState(() => _editing = null),
            ),
            const SizedBox(height: 32),
            Text(
              langProvider.getString('event_proposal_record'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  langProvider.getString('no_event_proposals'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              )
            else ...[
              ...records.map(
                (r) => _buildRecordCard(context, langProvider, r),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _EventProposalForm extends StatefulWidget {
  final LanguageProvider langProvider;
  final EventProposalRecord? editingRecord;
  final VoidCallback onCancelEdit;
  final VoidCallback onSaved;

  const _EventProposalForm({
    super.key,
    required this.langProvider,
    required this.editingRecord,
    required this.onCancelEdit,
    required this.onSaved,
  });

  @override
  State<_EventProposalForm> createState() => _EventProposalFormState();
}

class _EventProposalFormState extends State<_EventProposalForm> {
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();
  final _venueController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  final _costController = TextEditingController();
  bool _submitting = false;

  bool get _isEditing => widget.editingRecord != null;

  @override
  void initState() {
    super.initState();
    _syncFromEditing(widget.editingRecord);
  }

  @override
  void didUpdateWidget(covariant _EventProposalForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editingRecord?.id != widget.editingRecord?.id) {
      _syncFromEditing(widget.editingRecord);
    }
  }

  void _syncFromEditing(EventProposalRecord? r) {
    if (r == null) {
      _nameController.clear();
      _contentController.clear();
      _venueController.clear();
      _dateController.clear();
      _timeController.clear();
      _costController.clear();
    } else {
      _nameController.text = r.eventName;
      _contentController.text = r.content;
      _venueController.text = r.venue;
      _dateController.text = r.date;
      _timeController.text = r.time;
      _costController.text = r.costPrice;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    _venueController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _costController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final langProvider = widget.langProvider;
    final isWide =
        MediaQuery.sizeOf(context).width >= AppConstants.layoutWideBreakpoint;
    final dw = isWide ? AppConstants.eventProposalFormDesktopFontExtra2mm : 0.0;
    final titleFs = 18.0 + dw;
    final fieldFs = 16.0 + dw;
    final noteFs = 12.0 + dw;
    final btnFs = 16.0 + dw;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppConstants.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppConstants.grey.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEditing
                ? langProvider.getString('event_proposal_edit_mode')
                : langProvider.getString('event_proposal'),
            style: TextStyle(
              fontSize: titleFs,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            style: TextStyle(fontSize: fieldFs),
            decoration: InputDecoration(
              hintText: langProvider.getString('event_name'),
              hintStyle: TextStyle(fontSize: fieldFs),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dateController,
                  style: TextStyle(fontSize: fieldFs),
                  decoration: InputDecoration(
                    hintText: langProvider.getString('event_date'),
                    hintStyle: TextStyle(fontSize: fieldFs),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _timeController,
                  style: TextStyle(fontSize: fieldFs),
                  decoration: InputDecoration(
                    hintText: langProvider.getString('event_time'),
                    hintStyle: TextStyle(fontSize: fieldFs),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _venueController,
            style: TextStyle(fontSize: fieldFs),
            decoration: InputDecoration(
              hintText: langProvider.getString('event_venue'),
              hintStyle: TextStyle(fontSize: fieldFs),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _contentController,
            maxLines: 3,
            style: TextStyle(fontSize: fieldFs),
            decoration: InputDecoration(
              hintText: langProvider.getString('event_content'),
              hintStyle: TextStyle(fontSize: fieldFs),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _costController,
            style: TextStyle(fontSize: fieldFs),
            decoration: InputDecoration(
              hintText: langProvider.getString('event_cost'),
              hintStyle: TextStyle(fontSize: fieldFs),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  langProvider.getString('event_proposal_note'),
                  style: TextStyle(
                    fontSize: noteFs,
                    color: Colors.red,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_isEditing)
                    TextButton(
                      onPressed: widget.onCancelEdit,
                      child: Text(langProvider.getString('cancel')),
                    ),
                  SizedBox(
                    width: 120,
                    child: ElevatedButton(
                      onPressed: _submitting
                          ? null
                          : () async {
                              final nav = Navigator.of(context);
                              final messenger = ScaffoldMessenger.of(context);
                              final name = _nameController.text.trim().isEmpty
                                  ? '未命名活動'
                                  : _nameController.text.trim();
                              final prov = Provider.of<EventProposalProvider>(
                                  context,
                                  listen: false);
                              final c = _contentController.text.trim();
                              final v = _venueController.text.trim();
                              final d = _dateController.text.trim();
                              final t = _timeController.text.trim();
                              final p = _costController.text.trim();

                              if (prov.isDuplicateProposalContent(
                                content: c,
                                ignoreRecordId: _isEditing
                                    ? widget.editingRecord!.id
                                    : null,
                              )) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      langProvider.getString(
                                          'event_proposal_duplicate'),
                                    ),
                                  ),
                                );
                                return;
                              }

                              setState(() => _submitting = true);
                              try {
                                Future<void> submit() async {
                                  if (_isEditing) {
                                    final id = widget.editingRecord!.id;
                                    final hadImage =
                                        (widget.editingRecord!.imageUrl !=
                                                    null &&
                                                widget.editingRecord!.imageUrl!
                                                    .isNotEmpty) ||
                                            widget.editingRecord!.imageBytes !=
                                                null;
                                    await prov.updateRecord(
                                      id: id,
                                      eventName: name,
                                      newImageBytes: null,
                                      clearImage: hadImage,
                                      content: c,
                                      venue: v,
                                      date: d,
                                      time: t,
                                      costPrice: p,
                                    );
                                  } else {
                                    await prov.addRecord(
                                      eventName: name,
                                      imageBytes: null,
                                      content: c,
                                      venue: v,
                                      date: d,
                                      time: t,
                                      costPrice: p,
                                    );
                                  }
                                }

                                await submit().timeout(
                                  const Duration(seconds: 90),
                                  onTimeout: () => throw TimeoutException(
                                    'event_proposal_timeout',
                                  ),
                                );
                                if (!nav.mounted) return;
                                _nameController.clear();
                                _contentController.clear();
                                _venueController.clear();
                                _dateController.clear();
                                _timeController.clear();
                                _costController.clear();
                                widget.onSaved();
                              } on TimeoutException catch (e, st) {
                                if (!nav.mounted) return;
                                debugPrint(
                                    'Event proposal submit timeout: $e\n$st');
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      langProvider
                                          .getString('event_proposal_timeout'),
                                    ),
                                  ),
                                );
                              } catch (e, st) {
                                if (!nav.mounted) return;
                                String msg;
                                final es = e.toString();
                                if (es.contains('event_proposal_timeout')) {
                                  msg = langProvider
                                      .getString('event_proposal_timeout');
                                } else if (es.contains(
                                    'event_proposal_login_required')) {
                                  msg = langProvider.getString(
                                      'event_proposal_login_required');
                                } else if (es
                                    .contains('event_proposal_submit_failed')) {
                                  msg = langProvider.getString(
                                      'event_proposal_submit_failed');
                                } else if (e is FirebaseException &&
                                    (e.code == 'storage/unauthorized' ||
                                        e.code == 'unauthorized' ||
                                        e.code == 'permission-denied')) {
                                  msg = langProvider
                                      .getString('event_proposal_image_failed');
                                } else if (es.contains('storage') &&
                                    (es.contains('unauthorized') ||
                                        es.contains('403'))) {
                                  msg = langProvider
                                      .getString('event_proposal_image_failed');
                                } else {
                                  msg = es.length > 220
                                      ? '${es.substring(0, 220)}…'
                                      : es;
                                }
                                debugPrint('Event proposal submit: $e\n$st');
                                messenger.showSnackBar(
                                  SnackBar(content: Text(msg)),
                                );
                              } finally {
                                if (mounted)
                                  setState(() => _submitting = false);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: TextStyle(
                          fontSize: btnFs,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isEditing
                                  ? langProvider.getString('btn_save')
                                  : langProvider.getString('submit'),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
