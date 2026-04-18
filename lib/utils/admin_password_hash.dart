import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'constants.dart';

/// 名冊登入密碼雜湊（與 [AppConstants.adminLoginPasswordPepper] 一併使用）。
String hashAdminLoginPassword(String login, String password) {
  final l = login.trim();
  final key = '${AppConstants.adminLoginPasswordPepper}|$l|$password';
  return sha256.convert(utf8.encode(key)).toString();
}
