# RiseUP

RiseUP is now a Flutter application for planning daily tasks, tracking a weekly gym schedule, and logging learning goals. The previous Capacitor and Android Studio project files have been removed. Legacy web files remain only as a migration reference and are not used by Flutter.

## Run it

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows/mobile).
2. Install the Android SDK command-line tools and add `sdkmanager`, `adb`, and the Android SDK location to your `PATH`.
3. From this folder, run `flutter pub get`.
4. Generate the platform runners you need: `flutter create --platforms=android,ios .`
5. Run with `flutter run`.

## Task reminders

When a task has a reminder time, RiseUP schedules two native Android alerts:
a five-minute heads-up and a high-priority sound/vibration alarm at the task
time. These work when the app is closed. On Android 13 and newer, allow
notifications when RiseUP asks. On Android 14 and newer, open
**Settings → Task reminders → Enable** and allow **Alarms & reminders** for
precise delivery. The Settings page also has **Send a test reminder** so you
can confirm the alert sound on the actual phone.

Android device manufacturers can apply battery restrictions that delay or block
background alarms. If reminders work in the test but not with the app closed,
allow RiseUP to run in the background / remove its battery optimisation in the
phone's settings.

## Play Store release

The Android project is configured for an Android App Bundle. Before publishing,
create and keep a private upload key (never commit it):

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\riseup-upload.jks" -alias riseup -keyalg RSA -keysize 2048 -validity 10000
```

Create `android/key.properties` with your own paths and passwords:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=riseup
storeFile=C:\\Users\\YOUR_USER\\riseup-upload.jks
```

Then build the signed bundle with `flutter build appbundle`. Upload
`build/app/outputs/bundle/release/app-release.aab` to a Play Console app. You
will still need your own Play Console account, store listing assets, a support
email, and a privacy-policy URL. Because RiseUP keeps task data only on the
device, its Data safety declaration should be based on that behaviour unless
you later add analytics, sign-in, or cloud sync.

Android Studio is not used by this project. Use Flutter and Android SDK command-line tools to build Android. iOS builds require macOS with Xcode. App data is stored locally on the device with `shared_preferences`.
