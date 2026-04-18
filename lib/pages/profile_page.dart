import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../utils/responsive_layout.dart';
import '../providers/language_provider.dart';
import '../widgets/pressable_opacity.dart';
import 'settings_page.dart';
import 'profile_preference_page.dart';

/// 我的頁面（檔案 tab）
/// 頂部大頭照、暱稱、簽名；編輯資料、設定、我的配對；寬版面時 [ResponsiveLayout.profileMaxWidth] 置中
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<LanguageProvider>(context);
    final maxW = ResponsiveLayout.profileMaxWidth(context);

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.padding),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  // 頂部：大頭照
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppConstants.primaryColor, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppConstants.grey.withOpacity(0.2),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.network(
                        'https://picsum.photos/seed/profile_me/160/160',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '我',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '享受生活，認識新朋友',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppConstants.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 白色卡片區
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppConstants.padding),
                    decoration: BoxDecoration(
                      color: AppConstants.white,
                      borderRadius:
                          BorderRadius.circular(AppConstants.cardRadius),
                      boxShadow: [
                        BoxShadow(
                          color: AppConstants.grey.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        PressableOpacity(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ProfilePreferencePage(),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: AppConstants.primaryColor),
                              borderRadius: BorderRadius.circular(
                                  AppConstants.borderRadius),
                            ),
                            child: Center(
                              child: Text(
                                '編輯資料',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppConstants.primaryColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SettingRow(
                          icon: Icons.settings,
                          title: langProvider.getString('settings'),
                          onTap: () {
                            context.go('/setting');
                          },
                        ),
                        const SizedBox(height: 16),
                        _SettingRow(
                          icon: Icons.favorite,
                          title: '我的配對列表',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      enableFeedback: false,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: AppConstants.primaryColor, size: 22),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 16)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: AppConstants.grey),
          ],
        ),
      ),
    );
  }
}
