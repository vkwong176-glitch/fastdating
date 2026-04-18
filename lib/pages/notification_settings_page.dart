import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../providers/notification_provider.dart';

/// APP 內通知設定頁（如左下圖）
/// 項目：App 內音效、App 內震動、對話內音效、顯示通知
class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<NotificationProvider>(context);

    final theme = Theme.of(context);
    final titleFs = AppConstants.appBarTitleResolvedSize(context, base: 20);
    return Scaffold(
      appBar: AppBar(
        title: const Text('APP 內通知'),
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontSize: titleFs,
            ) ??
            theme.textTheme.titleLarge?.copyWith(fontSize: titleFs),
        backgroundColor: AppConstants.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      backgroundColor: AppConstants.backgroundColor,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildSection(
            context,
            '提示',
            [
              _switchRow('App 內音效', provider.inAppSound,
                  (v) => provider.inAppSound = v),
              _switchRow('App 內震動', provider.inAppVibration,
                  (v) => provider.inAppVibration = v),
              _switchRow(
                  '對話內音效', provider.chatSound, (v) => provider.chatSound = v),
            ],
          ),
          const SizedBox(height: 20),
          _buildSection(
            context,
            '背景通知',
            [
              _switchRow('顯示通知', provider.showNotification,
                  (v) => provider.showNotification = v),
              _switchRow('按心通知', provider.heartNotification,
                  (v) => provider.heartNotification = v),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String sectionTitle, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            sectionTitle,
            style: TextStyle(
              fontSize: 13,
              color: AppConstants.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppConstants.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppConstants.grey.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _switchRow(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF26A69A),
    );
  }
}
