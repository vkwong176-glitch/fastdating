import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../providers/interest_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/language_provider.dart';
import '../providers/nav_provider.dart';
import '../router/app_router.dart';
import '../services/firebase_bootstrap.dart';
import '../services/firestore_paths.dart';
import '../services/feed_firestore_service.dart';
import '../utils/hk_time_format.dart';
import '../services/user_firestore_service.dart';
import '../utils/interests_parse.dart';
import '../services/screen_capture_platform.dart';
import '../utils/content_moderation.dart';
import '../utils/avatar_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'settings_page.dart';
import 'activity_page.dart';

/// 發布頁：選圖、一句話、標籤、顯示性別、顯示在 Fast Dating
class OneSentencePage extends StatefulWidget {
  const OneSentencePage({super.key});

  @override
  State<OneSentencePage> createState() => _OneSentencePageState();
}

class _OneSentencePageState extends State<OneSentencePage>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;
  final _callNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _jobController = TextEditingController();
  final _sentenceController = TextEditingController();
  final _interestController = TextEditingController();
  final _tagController = TextEditingController();
  final List<String> _tags = [];
  bool _loadingImage = false;
  String? _interestError;
  bool _showGenderOn = true;
  bool _showInHkLoveEasyOn = true;

  /// Firestore `avatar`（data URL）解碼後預覽；與新選圖 [_pickedImage] 二擇一顯示
  Uint8List? _avatarBytesFromFirestore;

  bool _savingAvatar = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScreenCapturePlatform.allowScreenshots();
      _loadUserFieldsFromFirestore();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ScreenCapturePlatform.allowScreenshots();
    }
  }

  Future<void> _loadUserFieldsFromFirestore() async {
    if (!FirebaseBootstrap.isReady) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(FirestorePaths.users)
          .doc(u.uid)
          .get();
      if (!mounted) return;
      final d = doc.data();
      if (d == null) return;
      setState(() {
        final dn = (d['displayName'] as String?)?.trim();
        if (dn != null && dn.isNotEmpty) {
          _callNameController.text = dn;
        }
        final rawAge = d['age'];
        if (rawAge != null) {
          final a = rawAge is int ? rawAge : int.tryParse(rawAge.toString());
          if (a != null && a >= 1 && a <= 120) {
            _ageController.text = '$a';
          }
        }
        final j = (d['job'] as String?)?.trim();
        if (j != null && j.isNotEmpty && j != '未填寫') {
          _jobController.text = j;
        }
        final s = (d['sentence'] as String?)?.trim();
        if (s != null && s.isNotEmpty && s != kDiscoverDefaultSentence) {
          _sentenceController.text = s;
        }
        final av = (d['avatar'] as String?)?.trim();
        if (av != null && avatarFieldIsDataUrl(av)) {
          _avatarBytesFromFirestore = decodeAvatarFieldToBytes(av);
        }
      });
    } catch (_) {}
  }

  Future<void> _saveProfileImageOnly() async {
    if (_pickedImage == null) return;
    setState(() => _savingAvatar = true);
    try {
      final bytes = await _pickedImage!.readAsBytes();
      await UserFirestoreService.instance
          .saveProfileAvatarFromImageBytes(bytes);
      if (!mounted) return;
      setState(() {
        _avatarBytesFromFirestore = Uint8List.fromList(bytes);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存大頭照，訊息列表將同步顯示')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callNameController.dispose();
    _ageController.dispose();
    _jobController.dispose();
    _sentenceController.dispose();
    _interestController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  /// 同步興趣到首頁篩選：逗號分隔，每項至多 10 字（逾長自動截斷）；與篩選既有選項重複者不加入。
  void _syncInterestsToFilter() {
    final parts = parseCommaSeparatedInterests(_interestController.text);
    if (parts.isEmpty) return;
    setState(() => _interestError = null);
    Provider.of<InterestProvider>(context, listen: false).addInterests(parts);
  }

  /// 一句話鍵按入顯示圖功能：從相簿選圖並顯示
  Future<void> _pickAndShowImage() async {
    setState(() => _loadingImage = true);
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (file != null) {
        setState(() {
          _pickedImage = file;
          _loadingImage = false;
        });
      } else {
        setState(() => _loadingImage = false);
      }
    } catch (e) {
      setState(() => _loadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法選取圖片：$e')),
        );
      }
    }
  }

  void _addTag() {
    final t = _tagController.text.trim();
    if (t.isNotEmpty && !_tags.contains(t)) {
      setState(() {
        _tags.add(t);
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Widget _buildToggleRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
    double titleFontSize = 16,
    double subtitleFontSize = 13,
    bool loading = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: subtitleFontSize,
                    color: Colors.black,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(right: 8, top: 8),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Switch(
          value: value,
          onChanged: loading ? null : onChanged,
          activeColor: const Color(0xFF26A69A),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    /// 手機版藍圈區（興趣～標籤輸入）字級 +0.1cm；白框樣式不變
    final isMobile =
        MediaQuery.sizeOf(context).width < AppConstants.layoutWideBreakpoint;
    final isWide =
        MediaQuery.sizeOf(context).width >= AppConstants.layoutWideBreakpoint;
    const mobileBlueSectionBoost = 0.1 * AppConstants.logicalPxPerCm;
    final mb = isMobile ? mobileBlueSectionBoost : 0.0;

    /// 電腦版紅圈內表單字級 +0.3cm（不含 AppBar、「開始聊天」與底部條款小字）
    final dw = isWide ? AppConstants.oneSentenceDesktopFormFontExtra3mm : 0.0;
    final interestFs = 14.0 + mb + dw;
    final sentenceFs = 16.0 + mb + dw;
    final counterFs = 12.0 + mb + dw;
    final toggleTitleFs = 16.0 + dw;
    final toggleSubtitleFs = 13.0 + dw;

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/home'),
        ),
        automaticallyImplyLeading: false,
        title: Text(
          '想講～',
          style: TextStyle(
            fontSize: AppConstants.appBarTitleResolvedSize(context, base: 20),
            color: Colors.black,
          ),
        ),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          // 設定
          IconButton(
            onPressed: () {
              context.go('/setting');
            },
            icon: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppConstants.primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.settings, color: Colors.white, size: 22),
            ),
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 40),
            ),
          ),
          const SizedBox(width: 8),
          // 活動（所有活動）
          IconButton(
            onPressed: () {
              context.go('/event');
            },
            icon: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppConstants.primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.event, color: Colors.white, size: 22),
            ),
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 40),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.padding),
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
                        '稱呼',
                        style: TextStyle(
                            fontSize: interestFs, color: Colors.black),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _callNameController,
                        maxLength: 24,
                        decoration: InputDecoration(
                          hintText: '希望別人怎麼稱呼你',
                          hintStyle: TextStyle(
                            color: Colors.red.shade400,
                            fontSize: interestFs,
                          ),
                          counterText: '',
                          filled: true,
                          fillColor: AppConstants.white,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppConstants.cardRadius),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        style: TextStyle(
                            color: Colors.black, fontSize: interestFs),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '年齡',
                        style: TextStyle(
                            fontSize: interestFs, color: Colors.black),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ageController,
                        keyboardType: TextInputType.number,
                        maxLength: 3,
                        decoration: InputDecoration(
                          hintText: '例如 24',
                          hintStyle: TextStyle(
                            color: Colors.red.shade400,
                            fontSize: interestFs,
                          ),
                          counterText: '',
                          filled: true,
                          fillColor: AppConstants.white,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppConstants.cardRadius),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        style: TextStyle(
                            color: Colors.black, fontSize: interestFs),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text(
                    '訊息大頭照',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: interestFs, color: Colors.black),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: GestureDetector(
                    onTap: _loadingImage ? null : _pickAndShowImage,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppConstants.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppConstants.grey.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _buildImageContent(desktopExtra: dw),
                      ),
                    ),
                  ),
                ),
                if (FirebaseBootstrap.isReady &&
                    FirebaseAuth.instance.currentUser != null &&
                    _pickedImage != null) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _savingAvatar ? null : _saveProfileImageOnly,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConstants.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      icon: _savingAvatar
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_alt, size: 20),
                      label: const Text('儲存圖片至大頭照'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // 興趣：自由輸入，逗號為一個選項，每項 10 字內，同步首頁篩選（重複不加入）
            Text(
              '興趣（例如: 行街, 游水, 玩等~）',
              style: TextStyle(fontSize: interestFs, color: Colors.black),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _interestController,
              maxLength: 100,
              decoration: InputDecoration(
                hintText: '輸入興趣，以逗號分隔，每個最多 10 字',
                hintStyle: TextStyle(
                  color: Colors.red.shade400,
                  fontSize: interestFs,
                ),
                counterText: '',
                errorText: _interestError,
                filled: true,
                fillColor: AppConstants.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: TextStyle(color: Colors.black, fontSize: interestFs),
              onChanged: (_) => setState(() => _interestError = null),
            ),
            const SizedBox(height: 16),
            Text(
              '職業（會顯示於配對卡）',
              style: TextStyle(fontSize: interestFs, color: Colors.black),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _jobController,
              maxLength: 40,
              decoration: InputDecoration(
                hintText: '例如：設計師',
                hintStyle: TextStyle(
                  color: Colors.red.shade400,
                  fontSize: interestFs,
                ),
                counterText: '',
                filled: true,
                fillColor: AppConstants.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: TextStyle(color: Colors.black, fontSize: interestFs),
            ),
            const SizedBox(height: 16),
            // 一句話輸入（X 不要 → 改為紅字提示）
            TextField(
              controller: _sentenceController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '你在想什麼？心情如何？在做什麼？',
                hintStyle: TextStyle(
                  color: Colors.red.shade400,
                  fontSize: sentenceFs,
                ),
                filled: true,
                fillColor: AppConstants.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              style: TextStyle(color: Colors.black, fontSize: sentenceFs),
            ),
            const SizedBox(height: 16),
            // 標籤區（X 不要 → 改為紅字提示）
            Text(
              '標籤自己',
              style: TextStyle(
                fontSize: interestFs,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tagController,
              decoration: InputDecoration(
                hintText: '標籤自己...',
                hintStyle: TextStyle(
                  color: Colors.red.shade400,
                  fontSize: interestFs,
                ),
                filled: true,
                fillColor: AppConstants.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              style: TextStyle(color: Colors.black, fontSize: interestFs),
              onSubmitted: (_) => _addTag(),
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags
                    .map((tag) => Chip(
                          label: Text(
                            tag,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: interestFs,
                            ),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () => _removeTag(tag),
                          backgroundColor: AppConstants.white,
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
            // 標籤自己下面：白框 — 顯示我的性別、將我顯示在 Fast Dating
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppConstants.white,
                borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                boxShadow: [
                  BoxShadow(
                    color: AppConstants.grey.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildToggleRow(
                    title: '顯示我的性別',
                    value: _showGenderOn,
                    onChanged: (v) => setState(() => _showGenderOn = v),
                    titleFontSize: toggleTitleFs,
                    subtitleFontSize: toggleSubtitleFs,
                  ),
                  const Divider(height: 24),
                  _buildToggleRow(
                    title: '將我顯示在 Fast Dating',
                    value: _showInHkLoveEasyOn,
                    onChanged: (v) => setState(() => _showInHkLoveEasyOn = v),
                    titleFontSize: toggleTitleFs,
                    subtitleFontSize: toggleSubtitleFs,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 開始聊天按鈕：同步興趣、發布貼文到發布頁、返回
            Material(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              child: InkWell(
                enableFeedback: false,
                onTap: () async {
                  final callName = _callNameController.text.trim();
                  final ageStr = _ageController.text.trim();
                  final ageParsed = int.tryParse(ageStr);
                  final sentence = _sentenceController.text.trim();
                  final job = _jobController.text.trim();
                  final interests = _interestController.text.trim();
                  final tags = _tags;
                  if (FirebaseBootstrap.isReady &&
                      FirebaseAuth.instance.currentUser != null) {
                    if (callName.isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('請填寫稱呼')),
                        );
                      }
                      return;
                    }
                    if (ageStr.isEmpty || ageParsed == null) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('請填寫年齡')),
                        );
                      }
                      return;
                    }
                    if (ageParsed < 18 || ageParsed > 99) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('請填寫有效年齡（18～99）'),
                          ),
                        );
                      }
                      return;
                    }
                    if (job.isEmpty || job == '未填寫') {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('請填寫職業')),
                        );
                      }
                      return;
                    }
                    if (sentence.isEmpty ||
                        sentence == kDiscoverDefaultSentence) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('請填寫一句話（不可為系統預設句）'),
                          ),
                        );
                      }
                      return;
                    }
                    _syncInterestsToFilter();
                    await UserFirestoreService.instance
                        .mergeDiscoverTagsFromCommaSeparated(interests);
                    await UserFirestoreService.instance
                        .updateJobAndSentenceFromOneSentencePage(
                      displayName: callName,
                      age: ageParsed,
                      job: job,
                      sentence: sentence,
                    );
                    if (!mounted) return;
                  }
                  List<int>? avatarBytes;
                  if (_pickedImage != null) {
                    try {
                      avatarBytes = await _pickedImage!.readAsBytes();
                    } catch (_) {}
                  }
                  if (avatarBytes != null &&
                      avatarBytes.isNotEmpty &&
                      FirebaseBootstrap.isReady &&
                      FirebaseAuth.instance.currentUser != null) {
                    await UserFirestoreService.instance
                        .saveProfileAvatarFromImageBytes(avatarBytes);
                  }
                  if (!mounted) return;
                  final hashtagsStr = [
                    if (interests.isNotEmpty) interests,
                    if (tags.isNotEmpty) tags.map((t) => '#$t').join(' '),
                  ].where((s) => s.isNotEmpty).join(' ');
                  final post = UserPostItem(
                    id: 'my_${DateTime.now().millisecondsSinceEpoch}',
                    name: callName.isNotEmpty ? callName : '我',
                    content: sentence.isNotEmpty ? sentence : '（無文字）',
                    tag: '貼文',
                    hashtags: hashtagsStr,
                    iconColor: AppConstants.primaryColor,
                    imageBytes: null,
                    authorUid: FirebaseAuth.instance.currentUser?.uid,
                    authorAge: (ageParsed != null &&
                            ageParsed >= 18 &&
                            ageParsed <= 99)
                        ? ageParsed
                        : null,
                    createdAtUtc: DateTime.now().toUtc(),
                  );
                  if (!context.mounted) return;
                  final feed =
                      Provider.of<FeedProvider>(context, listen: false);
                  if (FirebaseBootstrap.isReady &&
                      FirebaseAuth.instance.currentUser != null) {
                    try {
                      final outcome = await FeedFirestoreService.instance
                          .publishPostWithModeration(
                        displayName: callName.isNotEmpty ? callName : '我',
                        content: sentence.isNotEmpty ? sentence : '（無文字）',
                        job: job,
                        interests: interests,
                        tag: '貼文',
                        hashtags: hashtagsStr.isNotEmpty ? hashtagsStr : null,
                        iconColor: const Color(0xFF26A69A),
                        imageBytes: null,
                        authorAge: (ageParsed != null &&
                                ageParsed >= 18 &&
                                ageParsed <= 99)
                            ? ageParsed
                            : null,
                      );
                      if (!context.mounted) return;
                      final lang = Provider.of<LanguageProvider>(
                        context,
                        listen: false,
                      );
                      switch (outcome) {
                        case FeedPublishOutcome.blocked:
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text(lang.getString('moderation_blocked')),
                            ),
                          );
                          return;
                        case FeedPublishOutcome.duplicateSameDay:
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text(lang.getString('duplicate_same_day')),
                            ),
                          );
                          return;
                        case FeedPublishOutcome.imageBlocked:
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  lang.getString('image_moderation_blocked')),
                            ),
                          );
                          return;
                        case FeedPublishOutcome.contactOrLinkBlocked:
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  lang.getString('moderation_contact_blocked')),
                            ),
                          );
                          return;
                        case FeedPublishOutcome.queuedForModeration:
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text(lang.getString('moderation_queued')),
                            ),
                          );
                          break;
                        case FeedPublishOutcome.published:
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已發佈至邀聊通知（其他會員可見）'),
                            ),
                          );
                          break;
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('發佈失敗：$e')),
                      );
                    }
                  } else {
                    final lang = Provider.of<LanguageProvider>(
                      context,
                      listen: false,
                    );
                    final mod = ContentModeration.evaluateFields(
                      displayName: callName,
                      content: sentence,
                      job: job,
                      interests: interests,
                      hashtags: hashtagsStr.isNotEmpty ? hashtagsStr : null,
                    );
                    if (mod == ModerationVerdict.blocked) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(lang.getString('moderation_blocked')),
                        ),
                      );
                      return;
                    }
                    if (mod == ModerationVerdict.suspected) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            lang.getString('moderation_need_login_review'),
                          ),
                        ),
                      );
                      return;
                    }
                    if (feed.hasLocalDuplicatePostWithin24Hours(sentence)) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(lang.getString('duplicate_same_day')),
                        ),
                      );
                      return;
                    }
                    _syncInterestsToFilter();
                    feed.addLocalPost(post);
                  }
                  if (!context.mounted) return;
                  Provider.of<NavProvider>(context, listen: false)
                      .setCurrentIndex(0);
                  appRouter.go('/home');
                },
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF26A69A), Color(0xFF4DB6AC)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius:
                        BorderRadius.circular(AppConstants.borderRadius),
                  ),
                  child: const Center(
                    child: Text(
                      '開始聊天',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '開始聊天即代表同意我們的私隱與使用者條款。',
              style: const TextStyle(fontSize: 12, color: Colors.black),
              textAlign: TextAlign.center,
            ),
            Text(
              '系統會根據您的標題與個人設定，為您推薦感興趣的用戶。',
              style: const TextStyle(fontSize: 12, color: Colors.black),
              textAlign: TextAlign.center,
            ),
            _buildMyPublishedSection(context, interestFs),
          ],
        ),
      ),
    );
  }

  String _hashtagsStringForFirestore() {
    final interests = _interestController.text.trim();
    return [
      if (interests.isNotEmpty) interests,
      if (_tags.isNotEmpty) _tags.map((t) => '#$t').join(' '),
    ].where((s) => s.isNotEmpty).join(' ');
  }

  Widget _buildMyPublishedSection(BuildContext context, double interestFs) {
    if (!FirebaseBootstrap.isReady ||
        FirebaseAuth.instance.currentUser == null) {
      return const SizedBox.shrink();
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          lang.getString('my_posts_header'),
          style: TextStyle(
            fontSize: interestFs,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<UserPostItem>>(
          stream: FeedFirestoreService.instance.watchMyPublicPosts(uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final list = snapshot.data ?? [];
            if (list.isEmpty) {
              return Text(
                lang.getString('my_posts_empty'),
                style: TextStyle(
                    fontSize: interestFs - 1, color: AppConstants.grey),
              );
            }
            return Column(
              children: list
                  .map((p) => _buildMyPostRow(context, p, interestFs))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMyPostRow(
    BuildContext context,
    UserPostItem post,
    double fs,
  ) {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final timeStr = post.createdAtUtc != null
        ? formatHongKongTimeFromDateTime(post.createdAtUtc)
        : '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppConstants.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppConstants.grey.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  post.content,
                  style: TextStyle(fontSize: fs, color: Colors.black87),
                ),
              ),
              TextButton(
                onPressed: () => _onEditMyPost(context, post),
                child: Text(lang.getString('post_edit')),
              ),
              TextButton(
                onPressed: () => _onDeleteMyPost(context, post),
                child: Text(
                  lang.getString('post_delete'),
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            timeStr,
            style: TextStyle(fontSize: fs - 2, color: AppConstants.grey),
          ),
        ],
      ),
    );
  }

  Future<void> _onDeleteMyPost(BuildContext context, UserPostItem post) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('confirm_delete_post_title')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.getString('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.getString('post_delete')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final deleted =
        await FeedFirestoreService.instance.deleteMyPublicPost(post.id);
    if (!context.mounted) return;
    if (deleted) {
      Provider.of<FeedProvider>(context, listen: false)
          .onMyPublicPostRemovedFromServer(post);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('post_deleted'))),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('post_delete_failed'))),
      );
    }
  }

  Future<void> _onEditMyPost(BuildContext context, UserPostItem post) async {
    final lang = Provider.of<LanguageProvider>(context, listen: false);
    final ctrl = TextEditingController(text: post.content);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lang.getString('post_edit')),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: lang.getString('post_edit_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang.getString('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lang.getString('btn_save')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final newText = ctrl.text.trim();
    ctrl.dispose();
    if (newText.isEmpty) return;
    final tagLine = _hashtagsStringForFirestore();
    final ageEdit = int.tryParse(_ageController.text.trim());
    final err = await FeedFirestoreService.instance.updateMyPublicPost(
      docId: post.id,
      displayName: _callNameController.text.trim(),
      content: newText,
      job: _jobController.text.trim(),
      interests: _interestController.text.trim(),
      hashtags: tagLine.isEmpty ? null : tagLine,
      authorAge:
          (ageEdit != null && ageEdit >= 18 && ageEdit <= 99) ? ageEdit : null,
    );
    if (!context.mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang.getString('post_updated'))),
      );
      return;
    }
    String msg;
    switch (err) {
      case 'duplicate_same_day':
        msg = lang.getString('duplicate_same_day');
        break;
      case 'moderation_blocked':
        msg = lang.getString('moderation_blocked');
        break;
      case 'moderation_suspected':
        msg = lang.getString('moderation_suspected_edit');
        break;
      default:
        msg = err;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildImageContent({double desktopExtra = 0}) {
    if (_loadingImage) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    if (_pickedImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: _pickedImage!.readAsBytes(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                );
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
              ),
              onPressed: () => setState(() => _pickedImage = null),
            ),
          ),
        ],
      );
    }
    if (_avatarBytesFromFirestore != null &&
        _avatarBytesFromFirestore!.isNotEmpty) {
      return Image.memory(
        _avatarBytesFromFirestore!,
        fit: BoxFit.cover,
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate, size: 42, color: Colors.black54),
          const SizedBox(height: 8),
          Text(
            '點擊加入圖片',
            style: TextStyle(
              color: Colors.black,
              fontSize: 14 + desktopExtra,
            ),
          ),
        ],
      ),
    );
  }
}
