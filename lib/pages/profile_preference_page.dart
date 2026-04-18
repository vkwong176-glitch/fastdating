import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../utils/responsive_layout.dart';
import '../providers/language_provider.dart';
import '../providers/profile_preference_provider.dart';

/// 個人設定頁（編輯資料進入）
/// 地區開關、顯示性別開關、平台顯示開關、標籤、篩選（年齡範圍、對方性別）
class ProfilePreferencePage extends StatelessWidget {
  const ProfilePreferencePage({super.key});

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final pref = Provider.of<ProfilePreferenceProvider>(context);
    final maxW = ResponsiveLayout.settingsFormMaxWidth(context);

    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/home'),
        ),
        automaticallyImplyLeading: false,
        title: Text(langProvider.getString('profile')),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontSize: titleFs,
            ) ??
            theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.white,
        elevation: 0,
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: ListView(
            padding: const EdgeInsets.all(AppConstants.padding),
            children: [
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _switchRow(
                      context,
                      title: langProvider.getString('region'),
                      value: pref.regionEnabled,
                      onChanged: (v) => pref.regionEnabled = v,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 48, top: 4),
                      child: Text(
                        '打開讓其他用戶看見你的地區...',
                        style:
                            TextStyle(fontSize: 12, color: AppConstants.grey),
                      ),
                    ),
                    const Divider(height: 24),
                    _switchRow(
                      context,
                      title: langProvider.getString('show_gender'),
                      value: pref.showMyGender,
                      onChanged: (v) => pref.showMyGender = v,
                      activeColor: const Color(0xFF00BCD4),
                    ),
                    const Divider(height: 24),
                    _switchRow(
                      context,
                      title: langProvider.getString('show_on_platform'),
                      value: pref.showOnPlatform,
                      onChanged: (v) => pref.showOnPlatform = v,
                      activeColor: const Color(0xFF00BCD4),
                    ),
                    const Divider(height: 24),
                    _rowWithArrow(
                      title: langProvider.getString('tags'),
                      trailing: Text(
                        '#識朋友 #分享日常',
                        style:
                            TextStyle(color: AppConstants.grey, fontSize: 14),
                      ),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                langProvider.getString('filter'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _switchRow(
                      context,
                      title:
                          '${langProvider.getString('age_range')} ${pref.ageRange.start.toInt()} - ${pref.ageRange.end.toInt()}',
                      value: pref.ageRangeEnabled,
                      onChanged: (v) => pref.ageRangeEnabled = v,
                      activeColor: const Color(0xFF00BCD4),
                    ),
                    if (pref.ageRangeEnabled) ...[
                      RangeSlider(
                        values: pref.ageRange,
                        min: AppConstants.discoverAgeFilterMin,
                        max: AppConstants.discoverAgeFilterMax,
                        divisions: AppConstants.discoverAgeFilterDivisions,
                        activeColor: const Color(0xFF00BCD4),
                        onChanged: (v) => pref.ageRange = v,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 8),
                        child: Text(
                          '如你關閉年齡範圍，你將無法查看...',
                          style:
                              TextStyle(fontSize: 12, color: AppConstants.grey),
                        ),
                      ),
                    ],
                    const Divider(height: 24),
                    _rowWithArrow(
                      title: langProvider.getString('show_other_gender'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            pref.displayOtherGender == 'male'
                                ? '💙 ${langProvider.getString('male')}'
                                : '💗 ${langProvider.getString('female')}',
                            style: TextStyle(
                                color: AppConstants.grey, fontSize: 14),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              color: AppConstants.grey, size: 20),
                        ],
                      ),
                      onTap: () {
                        _showGenderPicker(context, pref, langProvider);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.padding),
      decoration: BoxDecoration(
        color: AppConstants.white,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: [
          BoxShadow(
            color: AppConstants.grey.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _switchRow(
    BuildContext context, {
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? activeColor,
  }) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 16)),
        const Spacer(),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: activeColor ?? AppConstants.primaryColor,
        ),
      ],
    );
  }

  Widget _rowWithArrow({
    required String title,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      enableFeedback: false,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            const Spacer(),
            trailing,
          ],
        ),
      ),
    );
  }

  void _showGenderPicker(
    BuildContext context,
    ProfilePreferenceProvider pref,
    LanguageProvider langProvider,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(langProvider.getString('male')),
                onTap: () {
                  pref.displayOtherGender = 'male';
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text(langProvider.getString('female')),
                onTap: () {
                  pref.displayOtherGender = 'female';
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
