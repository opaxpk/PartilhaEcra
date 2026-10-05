# WebRTC usa reflexão/JNI — não pode ser removido pelo R8.
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn org.webrtc.**
