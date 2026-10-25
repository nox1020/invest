# Keep the app's own Android entry points / platform-channel code.
-keep class com.nox1020.invest.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-dontwarn io.flutter.embedding.**
