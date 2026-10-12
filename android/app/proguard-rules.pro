# Razorpay Checkout (razorpay_flutter): keep its classes and callbacks in the
# shrunk release build (rules from Razorpay's Android integration guide).
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/
-keepclasseswithmembers class * {
  public void onPayment*(...);
}
# Google Pay / UPI intent classes Razorpay may reference.
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.**
-dontwarn proguard.annotation.Keep
-dontwarn proguard.annotation.KeepClassMembers
