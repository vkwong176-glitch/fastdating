import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// 年齡滑桿組件（與 [AppConstants.discoverAgeFilterMin]～[AppConstants.discoverAgeFilterMax] 一致）
/// 可選單一滑桿或範圍滑桿，回調當前值
class AgeSlider extends StatelessWidget {
  final RangeValues value;
  final ValueChanged<RangeValues> onChanged;

  const AgeSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            '年齡 ${value.start.toInt()} - ${value.end.toInt()}',
            style: TextStyle(
              fontSize: 14,
              color: AppConstants.grey,
            ),
          ),
        ),
        RangeSlider(
          values: value,
          min: AppConstants.discoverAgeFilterMin,
          max: AppConstants.discoverAgeFilterMax,
          divisions: AppConstants.discoverAgeFilterDivisions,
          activeColor: AppConstants.primaryColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
