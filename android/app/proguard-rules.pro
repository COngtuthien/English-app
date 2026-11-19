# Flutter / plugin keep rules for release minification.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.dexterous.** { *; }
-keep class com.tundralabs.fluttertts.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.google.android.play.core.**
# flutter_local_notifications uses Gson with generic types
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
