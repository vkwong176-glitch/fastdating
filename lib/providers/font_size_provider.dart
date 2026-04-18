import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

enum AppFontSizeLevel { small, medium, large }

/// 全站字體大小偏好：細字體／中字體／大字體。
class FontSizeProvider with ChangeNotifier {
  static const _prefsKey = 'app_font_size_level_v1';

  AppFontSizeLevel _level = AppFontSizeLevel.small;

  FontSizeProvider() {
    Future.microtask(_loadPersisted);
  }

  AppFontSizeLevel get level => _level;

  double get extraLogicalPx {
    switch (_level) {
      case AppFontSizeLevel.small:
        return 0.0;
      case AppFontSizeLevel.medium:
        return 0.1 * AppConstants.logicalPxPerCm;
      case AppFontSizeLevel.large:
        return 0.25 * AppConstants.logicalPxPerCm;
    }
  }

  double get sliderValue {
    switch (_level) {
      case AppFontSizeLevel.small:
        return 0;
      case AppFontSizeLevel.medium:
        return 1;
      case AppFontSizeLevel.large:
        return 2;
    }
  }

  Future<void> setLevel(AppFontSizeLevel next) async {
    if (_level == next) return;
    _level = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, next.name);
    } catch (_) {}
  }

  Future<void> setSliderValue(double rawValue) {
    final rounded = rawValue.round().clamp(0, 2);
    final next = switch (rounded) {
      1 => AppFontSizeLevel.medium,
      2 => AppFontSizeLevel.large,
      _ => AppFontSizeLevel.small,
    };
    return setLevel(next);
  }

  Future<void> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      final matched = AppFontSizeLevel.values.where((e) => e.name == raw);
      if (matched.isEmpty) return;
      _level = matched.first;
      notifyListeners();
    } catch (_) {}
  }
}
