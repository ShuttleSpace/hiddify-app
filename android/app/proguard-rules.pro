# `package:jni` (used by shared_preferences_android and the other jnigen plugins)
# reaches Kotlin from Dart through JNI, and every JNI lookup is by the literal name
# written in the binding: `JClass.forName`, `instanceMethodId` and the coroutine
# plumbing in jni/lib/src/kotlin.dart. R8 is on for release builds (FlutterPlugin.kt
# sets `releaseBuildType.isMinifyEnabled = true`) and cannot see those by-name
# lookups, so it renames the classes and they are no longer found. Startup then
# throws from `sharedPreferencesProvider` before `runApp`, leaving the app stuck on
# its splash screen. Debug builds skip R8, which is why only release was affected.
#
# These are exactly the non-`java.*` classes that package:jni resolves by name;
# `java.*` names are never obfuscated.
-keep class kotlin.coroutines.intrinsics.** { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }
