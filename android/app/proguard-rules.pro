# Keep the app's own Android entry points / platform-channel code.
-keep class com.nox1020.invest.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-dontwarn io.flutter.embedding.**

# shared_preferences_android 2.5.x is called from Dart through JNI (package:jni)
# by exact method descriptors, e.g.
#   SharedPreferencesApiRegistrar.getAll(String, List, kotlin.coroutines.Continuation)
# R8 renamed kotlin.coroutines.Continuation (to E2/d), so the JNI lookup failed:
#   NoSuchMethodError: no non-static method ...getAll(...Lkotlin/coroutines/Continuation;)
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep interface kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-dontwarn kotlinx.coroutines.**

# Also looked up by name from Dart (package:jni generated bindings): results
# and errors of suspend calls. These were renamed in 1.0.221 (audit).
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
