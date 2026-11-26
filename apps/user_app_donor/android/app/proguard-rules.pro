# Flutter & Android embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep MainActivity and Razorpay / Tink / Google Play Services
-keep class com.shodasha.** { *; }
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

-keepattributes *Annotation*
-dontwarn javax.annotation.**
