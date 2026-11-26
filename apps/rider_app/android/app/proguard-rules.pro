# Flutter & Android embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep MainActivity and plugin registrants
-keep class com.shodasha.** { *; }

-keepattributes *Annotation*
-dontwarn javax.annotation.**
