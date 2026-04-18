import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// 性別篩選組件
/// 支援男/女切換，點擊回調選中結果
class GenderFilter extends StatefulWidget {
  // 選中性別回調函數
  final Function(String) onSelect;
  // 初始選中性別（預設男性）
  final String initialGender;
  /// 相對於預設字級（含 [AppConstants.filterInnerFontExtra]）的增量，可為負（例如手機篩選縮字）
  final double fontSizeExtraDelta;

  const GenderFilter({
    super.key,
    required this.onSelect,
    this.initialGender = 'male',
    this.fontSizeExtraDelta = 0,
  });

  @override
  State<GenderFilter> createState() => _GenderFilterState();
}

class _GenderFilterState extends State<GenderFilter> {
  late String _selectedGender;

  @override
  void initState() {
    super.initState();
    // 初始化選中性別
    _selectedGender = widget.initialGender;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 男性按鈕
        _genderButton(
          text: '男性',
          icon: Icons.male,
          color: AppConstants.blue,
          isSelected: _selectedGender == 'male',
          onTap: () {
            setState(() => _selectedGender = 'male');
            widget.onSelect('male'); // 回調選中結果
          },
        ),
        const SizedBox(width: 16), // 按鈕間距
        // 女性按鈕
        _genderButton(
          text: '女性',
          icon: Icons.female,
          color: AppConstants.red,
          isSelected: _selectedGender == 'female',
          onTap: () {
            setState(() => _selectedGender = 'female');
            widget.onSelect('female'); // 回調選中結果
          },
        ),
      ],
    );
  }

  /// 通用性別按鈕組件
  Widget _genderButton({
    required String text,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          // 選中狀態背景淺色
          color: isSelected ? color.withOpacity(0.1) : AppConstants.white,
          border: Border.all(
            color: isSelected ? color : AppConstants.grey, // 選中狀態邊框高亮
            width: 1,
          ),
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontSize: (14 +
                        AppConstants.filterInnerFontExtra +
                        widget.fontSizeExtraDelta)
                    .clamp(11.0, 28.0),
                color: isSelected ? color : AppConstants.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}