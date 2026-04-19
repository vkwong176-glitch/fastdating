// ignore_for_file: lines_longer_than_80_chars
//
// Web 與 Android 已填入目前 Firebase Console 設定；iOS／macOS 仍請用 flutterfire configure 或手動補齊。
//
// 自訂網域上線後：Firebase Console → Authentication → 設定 →「已授權網域」必須加入你的網域，
// 否則網頁版 Email／第三方登入會被拒。
//
// Web [authDomain] 使用預設 *.firebaseapp.com，Google OAuth 的 redirect 會與 Firebase 自動建立的
// 網路用戶端一致，可避免 redirect_uri_mismatch。若改回自訂網域，須在 Google Cloud Console 憑證
// 加入 https://你的網域/__/auth/handler。
//
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// 由 FlutterFire CLI 產生；手動維護時請與 Firebase Console 專案一致。
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBYRWyMQmnLgTP7moRIRPxL2EObrxBo5cM',
    appId: '1:780058794247:web:deaca7455344856a6b0da2',
    messagingSenderId: '780058794247',
    projectId: 'fast-dating-vk',
    authDomain: 'fast-dating-vk.firebaseapp.com',
    storageBucket: 'fast-dating-vk.firebasestorage.app',
    measurementId: 'G-RWNCRS3EYV',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBJAz8vN5smHhkgu9qHnAsuknHMRWq1U5Q',
    appId: '1:780058794247:android:e1d62f3e5832a8946b0da2',
    messagingSenderId: '780058794247',
    projectId: 'fast-dating-vk',
    storageBucket: 'fast-dating-vk.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_WITH_IOS_API_KEY',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'fastdating-placeholder',
    storageBucket: 'fastdating-placeholder.appspot.com',
    iosBundleId: 'com.example.fastdating',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'REPLACE_WITH_MACOS_API_KEY',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'fastdating-placeholder',
    storageBucket: 'fastdating-placeholder.appspot.com',
    iosBundleId: 'com.example.fastdating',
  );
}
