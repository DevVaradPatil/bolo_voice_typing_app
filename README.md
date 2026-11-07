# Bolo

Voice typing for Android in 22 Indian languages + English, in any app. A floating bubble appears with the
keyboard: **hold to talk**, **slide up to lock**, **tap stop** to finish. Speech goes to Sarvam AI's streaming
speech-to-text (`saaras:v4`), and each phrase is typed into the focused text box as soon as it comes back.

## Setup

1. Put your Sarvam key in `.env` at the repo root (gitignored):
   ```
   SARVAM_API_KEY=your_key_here
   ```
   It's read at build time into `BuildConfig`. Note it ends up inside the APK, so don't share builds publicly.
2. Build:
   ```bash
   flutter build apk --release --split-per-abi --target-platform android-arm64
   ```
3. On the phone: install, allow the mic, then turn on **Accessibility → Bolo bubble**. For sideloaded APKs on
   Android 13+, first allow **App info → ⋮ → Allow restricted settings**.

## Where things are

| | |
|---|---|
| `lib/main.dart` | Settings app UI (Flutter): setup, language, output style, recent dictations |
| `android/.../BoloService.kt` | Accessibility service: bubble, gestures, typing into other apps, history |
| `android/.../Dictation.kt` | Mic → Sarvam WebSocket → text |
| `brand/` | Logo and design tokens |

## Testing without a voice

Debug builds stream `test.wav` (16 kHz mono PCM16) instead of the mic if it exists:
```bash
adb push test.wav /sdcard/Android/data/com.varad.bolo/files/test.wav
```

After reinstalling over an existing install, toggle the accessibility service off and on if the bubble doesn't appear.
