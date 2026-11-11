# Transcoder
### Audio Converter for macOS

<p align="center">
  <strong>Version:</strong> 0.1.0
  <br />
  <a href="https://github.com/sevmorris/Transcoder/releases/latest/download/Transcoder-v0.1.0.dmg"><strong>Download Latest (DMG)</strong></a>
  ·
  <a href="https://sevmorris.github.io/Transcoder/manual/">Manual</a>
  ·
  <a href="https://sevmorris.github.io/Transcoder/theory.html">Theory of Operation</a>
</p>

A macOS app that converts audio: drop files in, pick a format, convert. Audio only — from a video file it takes the first audio track and writes nothing else.

- **Formats:** MP3, AAC (M4A), Apple Lossless (M4A), FLAC, WAV, AIFF, Opus (OGG).
- **Presets per format:** bitrate for the lossy formats, bit depth for the lossless ones, sample rate and channels for all (or "same as source"). Each format remembers its own.
- **Batch queue:** add files or whole folders; per-file progress, cancel, and Reveal in Finder.
- **Metadata:** tags and cover artwork are carried through. WAV and Opus keep the tags but have no place FFmpeg can put a cover.
- Outputs go beside each source or into a chosen folder, and never overwrite: a taken name gets a number.

Requires macOS 15.0 or later on Apple Silicon.

## Building

```bash
./scripts/fetch-ffmpeg.sh
xcodebuild -project Transcoder.xcodeproj -scheme Transcoder -configuration Release -destination 'generic/platform=macOS'
```

```bash
xcodebuild -project Transcoder.xcodeproj -scheme Transcoder test
```

The tests include an end-to-end conversion of a tagged sample with cover art to every format, run through the bundled FFmpeg in a temporary folder. A test run never touches the app's real settings: hosting tests, the app starts with no window, and `UserDefaults.app` is a scratch suite.

## Licence

MIT (see `LICENSE`). The bundled FFmpeg is LGPL; see `Vendor/README.md`.
