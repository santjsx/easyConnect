# Ignore missing Google Play Core classes (used by Flutter deferred components engine)
-dontwarn com.google.android.play.core.**

# Flutter wrapper classes and engines
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Hive adapters, generated adapter files, and model classes intact
-keep class com.easyconnect.app.features.contacts.models.Contact { *; }
-keep class com.easyconnect.app.features.settings.models.AppSettings { *; }
-keep class com.easyconnect.app.features.calling.models.CallLog { *; }

# Keep annotations and signature metadata for type serialization
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Keep native JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep androidx libraries intact
-keep class androidx.annotation.** { *; }
