# SPDX-License-Identifier: GPL-3.0-or-later
# minifyEnabled is false, but keep SDL's JNI entry points untouched if a
# release build ever turns it on.
-keep class org.libsdl.app.** { *; }
-keep class com.silenthill.android.** { *; }
-keepclasseswithmembernames class * { native <methods>; }
