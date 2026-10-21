# Keep rules shipped with EVERY release build (standing rule, 2026-10-20).
# The Google Mobile Ads SDK pulls in WorkManager + Room transitively; if
# R8 shrinking is ever enabled, it strips Room's generated *_Impl classes
# and the app crashes at startup inside
# androidx.startup.InitializationProvider — before Flutter starts.
# (Device-verified on Pawzzle Shelter, Galaxy A16.)

# WorkManager / Room (transitive via Google Mobile Ads SDK)
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class **_Impl { *; }
-keep class androidx.startup.** { *; }

# Google Mobile Ads / Play services ads
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }

# Flutter embedding
-keep class io.flutter.** { *; }
