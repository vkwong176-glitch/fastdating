import 'package:flutter/material.dart';

/// 供 [MaterialApp] 與 [AuthProvider] 在 Web OAuth 回站後仍能導向 `/main`。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
