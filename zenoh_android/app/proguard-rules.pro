-keep class io.zenoh.** { *; }
-keep class io.zenoh.jni.** { *; }
-keepclassmembers class * {
    native <methods>;
}
