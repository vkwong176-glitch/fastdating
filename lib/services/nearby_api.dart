import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/constants.dart';
import '../utils/mock_data.dart';

/// 附近的人 API：連接後端取得附近用戶列表
/// 若 [AppConstants.nearbyApiBaseUrl] 為空或請求失敗，則回傳 mock 資料
class NearbyApi {
  static const String _path = '/api/nearby';

  /// 取得附近用戶列表（可傳經緯度或半徑，依後端 API 規格）
  static Future<List<Map<String, dynamic>>> getNearbyUsers({
    double? lat,
    double? lng,
    int? radiusKm,
    bool allowMockFallback = true,
  }) async {
    final baseUrl = AppConstants.nearbyApiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      return allowMockFallback ? getMockUserList() : <Map<String, dynamic>>[];
    }

    try {
      final query = <String, String>{};
      if (lat != null) query['lat'] = '$lat';
      if (lng != null) query['lng'] = '$lng';
      if (radiusKm != null) query['radius_km'] = '$radiusKm';
      final uri = Uri.parse('$baseUrl$_path').replace(queryParameters: query.isNotEmpty ? query : null);
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('請求逾時'),
      );

      if (response.statusCode != 200) {
        return allowMockFallback ? getMockUserList() : <Map<String, dynamic>>[];
      }

      final decoded = jsonDecode(response.body);
      final list = _parseUserList(decoded);
      if (list.isNotEmpty) return list;
      return allowMockFallback ? getMockUserList() : <Map<String, dynamic>>[];
    } catch (_) {
      return allowMockFallback ? getMockUserList() : <Map<String, dynamic>>[];
    }
  }

  /// 解析後端回傳：支援 { data: [] }、{ users: [] } 或直接 []
  static List<Map<String, dynamic>> _parseUserList(dynamic decoded) {
    List<dynamic> raw = const [];
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map) {
      raw = decoded['data'] ?? decoded['users'] ?? decoded['list'] ?? [];
    }
    final List<Map<String, dynamic>> result = [];
    for (final e in raw) {
      if (e is! Map) continue;
      final map = Map<String, dynamic>.from(e);
      if (map['id'] == null && map['name'] == null) continue;
      final rawGender = map['gender']?.toString().trim().toLowerCase() ?? '';
      final gender = rawGender == 'female' ? 'female' : 'male';
      result.add({
        'id': map['id']?.toString() ?? '',
        'name': map['name']?.toString() ?? '',
        'age': map['age'] is int ? map['age'] : int.tryParse(map['age']?.toString() ?? '') ?? 0,
        'gender': gender,
        'job': map['job']?.toString() ?? '',
        'distance': map['distance']?.toString() ?? '',
        'avatar': map['avatar']?.toString() ?? '',
        'tags': map['tags'] is List ? List<String>.from(map['tags']!) : <String>[],
        'sentence': map['sentence']?.toString() ?? '',
      });
    }
    return result;
  }
}
