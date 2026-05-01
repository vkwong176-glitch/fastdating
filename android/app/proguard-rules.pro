# Fast Dating — Release 混淆時保留 Flutter／Firebase／商店與反射所需符號。
# https://docs.flutter.dev/deployment/android

## Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

## Plugins（google_sign_in / Firebase 等）
-keep class io.flutter.plugins.** { *; }

## Gson（部分 Firebase 相依）
-keepattributes Signature
-keepattributes *Annotation*

## Firebase
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
# Auth／Google Sign-In（Release R8）：避免類別被拔除導致本機 Session 異常或非預期 sign-out
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

## Google Play Billing／內購
-keep class com.android.vending.billing.**

## Kotlin
-dontwarn kotlin.**
