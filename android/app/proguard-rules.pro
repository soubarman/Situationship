# Situationship ProGuard / R8 Rules for Release Shrinking & Obfuscation

# Flutter Engine & Framework
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Flutter Deferred Components / Play Core (when play-core library is not included)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Situationship Native LLM JNI Bridge
-keep class com.example.situationship.CupidNativeLlm { *; }
-keep class com.example.situationship.CupidNativeLlm$Companion { *; }
-keep class com.example.situationship.CupidNativeLlm$TokenCallback { *; }
-keep class com.example.situationship.MainActivity { *; }

# Keep native methods and JNI bindings
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve attributes for Firebase and Reflection
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Firebase & Google Play Services
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# OkHttp & Coroutines
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
