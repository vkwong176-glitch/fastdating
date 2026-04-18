import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/constants.dart';
import '../widgets/upgrade_matching_form.dart';

/// 升級配對：詳細資料表單（多區塊、淺黃卡片、淺灰格線底）
class UpgradeMatchingPage extends StatelessWidget {
  const UpgradeMatchingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F0F0),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.go('/home'),
        ),
        automaticallyImplyLeading: false,
        title: Text(
          '升級配對',
          style: TextStyle(
            fontSize: AppConstants.appBarTitleResolvedSize(context, base: 20),
            color: Colors.black87,
          ),
        ),
        backgroundColor: AppConstants.appBarBackground,
        toolbarHeight: AppConstants.appBarToolbarHeight,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: const UpgradeMatchingForm(
        submitLabel: '提交',
        embedded: false,
      ),
    );
  }
}
