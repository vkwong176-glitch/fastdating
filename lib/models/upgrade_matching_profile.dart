import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 升級配對表單資料（與 [FirestorePaths.upgradeMatchingPool] 內 `profile` 欄位對應）
class UpgradeMatchingProfileData {
  UpgradeMatchingProfileData({
    required this.text,
    this.gender,
    this.hasProperty,
    this.marriedBefore,
    this.wantMarriageSoon,
    this.wantChildren,
    this.urgentMarriage,
    this.hasDriverLicense,
    this.personalPhotoBytes,
  });

  static const List<String> textKeys = [
    'nationality',
    'name',
    'age',
    'dob',
    'heightWeight',
    'phone',
    'residence',
    'education',
    'occupationIncome',
    'partnerReq',
    'debt',
    'health',
    'marriageDetail',
    'pets',
    'hobbies',
    'selfReflection',
    'partnerFlaws',
    'languages',
    'sideBusiness',
    'political',
    'religion',
    'diet',
    'alcohol',
    'smokingFreq',
    'gambling',
  ];

  final Map<String, String> text;
  final String? gender;
  final bool? hasProperty;
  final bool? marriedBefore;
  final bool? wantMarriageSoon;
  final bool? wantChildren;
  final bool? urgentMarriage;
  final bool? hasDriverLicense;
  final Uint8List? personalPhotoBytes;

  String get displayName => (text['name'] ?? '').trim();

  Map<String, dynamic> toProfileFirestoreMap() {
    final textMap = <String, String>{};
    for (final k in textKeys) {
      textMap[k] = text[k] ?? '';
    }
    return {
      'text': textMap,
      'gender': gender,
      'hasProperty': hasProperty,
      'marriedBefore': marriedBefore,
      'wantMarriageSoon': wantMarriageSoon,
      'wantChildren': wantChildren,
      'urgentMarriage': urgentMarriage,
      'hasDriverLicense': hasDriverLicense,
      if (personalPhotoBytes != null && personalPhotoBytes!.isNotEmpty)
        'personalPhotoBase64': base64Encode(personalPhotoBytes!),
    };
  }

  static UpgradeMatchingProfileData? fromFirestoreDoc(Map<String, dynamic> doc) {
    final raw = doc['profile'];
    if (raw is! Map) return null;
    final p = Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
    final textRaw = p['text'];
    final text = <String, String>{};
    final byLower = <String, String>{};
    if (textRaw is Map) {
      for (final e in textRaw.entries) {
        final lk = e.key.toString().toLowerCase();
        byLower[lk] = e.value?.toString() ?? '';
      }
    }
    for (final k in textKeys) {
      text[k] = byLower[k] ?? '';
    }
    Uint8List? photo;
    final b64 = p['personalPhotoBase64']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      try {
        photo = base64Decode(b64);
      } catch (_) {}
    }
    bool? readBool(String k) {
      final v = p[k];
      if (v is bool) return v;
      return null;
    }
    return UpgradeMatchingProfileData(
      text: text,
      gender: p['gender']?.toString(),
      hasProperty: readBool('hasProperty'),
      marriedBefore: readBool('marriedBefore'),
      wantMarriageSoon: readBool('wantMarriageSoon'),
      wantChildren: readBool('wantChildren'),
      urgentMarriage: readBool('urgentMarriage'),
      hasDriverLicense: readBool('hasDriverLicense'),
      personalPhotoBytes: photo,
    );
  }

  static Map<String, TextEditingController> createControllers() {
    return {for (final k in textKeys) k: TextEditingController()};
  }

  void applyToControllers(Map<String, TextEditingController> c) {
    for (final k in textKeys) {
      final ctrl = c[k];
      if (ctrl != null) {
        ctrl.text = text[k] ?? '';
      }
    }
  }

  static UpgradeMatchingProfileData fromControllers({
    required Map<String, TextEditingController> c,
    String? gender,
    bool? hasProperty,
    bool? marriedBefore,
    bool? wantMarriageSoon,
    bool? wantChildren,
    bool? urgentMarriage,
    bool? hasDriverLicense,
    Uint8List? personalPhotoBytes,
  }) {
    final text = <String, String>{};
    for (final k in textKeys) {
      text[k] = c[k]?.text.trim() ?? '';
    }
    return UpgradeMatchingProfileData(
      text: text,
      gender: gender,
      hasProperty: hasProperty,
      marriedBefore: marriedBefore,
      wantMarriageSoon: wantMarriageSoon,
      wantChildren: wantChildren,
      urgentMarriage: urgentMarriage,
      hasDriverLicense: hasDriverLicense,
      personalPhotoBytes: personalPhotoBytes,
    );
  }
}
