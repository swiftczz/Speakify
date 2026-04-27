# Eleven Listening

A SwiftPM macOS 26 text-to-speech app for English listening practice.

## Run

```bash
swift run --scratch-path build Eleven
```

## Build an app bundle

```bash
Scripts/package-app.sh
open build/release/Eleven.app
```

## Configure

Open Settings in the app, paste your ElevenLabs API key, choose a download directory, then load voices. The default download directory is the current user's Downloads folder.

The TTS integration is isolated behind `TTSProvider`, so another provider can be added without replacing the UI or playback flow.
