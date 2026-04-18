import 'package:flutter/material.dart';

/// 管理後台分頁頂部：說明 Firestore 集合與 Fast Dating App 資料對應。
class AdminDataSourcePanel extends StatelessWidget {
  const AdminDataSourcePanel({
    super.key,
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.storage_outlined,
                size: 20, color: Colors.blueGrey.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Colors.blueGrey.shade900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
