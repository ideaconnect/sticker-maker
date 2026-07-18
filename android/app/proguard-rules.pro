# R8/ProGuard keep rules for the release build.
#
# Release builds shrink + obfuscate Java/Kotlin. Two native libraries resolve
# their Java classes by name at runtime via JNI (FindClass/GetMethodID), so R8
# must not rename or remove those classes — otherwise inference aborts the VM.

# ONNX Runtime (flutter_onnxruntime, #28). Symptom when stripped:
#   "JNI DETECTED ERROR IN APPLICATION: java_class == null in call to
#    GetMethodID ... convertToTensorInfo ... Java_ai_onnxruntime_OrtSession_run"
# The native onnxruntime4j_jni looks up ai.onnxruntime.TensorInfo, OnnxJavaType,
# OnnxTensorLike, … by name, so keep the whole package and its members.
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Google ML Kit Subject Segmentation (#26) + its dynamically-loaded modules.
# ML Kit resolves optional model modules reflectively; keep it and the gms
# internal mlkit classes so the "Built-in AI" engine survives shrinking.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.mlkit.**
