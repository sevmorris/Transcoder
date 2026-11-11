# Vendor dependencies

## FFmpeg / ffprobe (bundled binaries)

Transcoder bundles a **static, audio-only, LGPL FFmpeg 9.0.2** with LAME 4.0, for macOS **arm64**. The binaries are not in git:

| Artifact | Location |
|----------|----------|
| Binary checksums & release tag | `Vendor/ffmpeg-manifest.env` |
| Download script | `scripts/fetch-ffmpeg.sh` |
| Build recipe (Corresponding Source) | FilmStrip's `scripts/build-ffmpeg.sh`, recipe r5 |
| Upstream source | URLs in the manifest |

Xcode runs `scripts/fetch-ffmpeg.sh` as a build phase. `Transcoder/` is a synchronized group, so the project also lists `ffmpeg` and `ffprobe` explicitly in Copy Bundle Resources (the "Vendored Binaries" group) and takes them out of the synced folder with an exception set; that way a fresh clone's first build ships them too. Running `./scripts/fetch-ffmpeg.sh` before `xcodebuild` is still the second guard.

**Borrowed pin.** The manifest currently points at FilmStrip's `ffmpeg-deps-9.0.2-audio-arm64-r5` release, because Transcoder has no GitHub repository yet to host its own. Before the first release, Transcoder should carry its own `scripts/build-ffmpeg.sh`, build with it and host the result as a prerelease here; the borrowed pin is then recorded as superseded, never deleted.

### Encoders used

`libmp3lame` (MP3), and FFmpeg's own `aac`, `alac`, `flac`, `pcm_s16le/s24le/f32le` (WAV), `pcm_s16be/s24be` (AIFF) and `opus`. FFmpeg's Opus encoder is marked experimental, so Transcoder passes `-strict -2`, and it runs at 48 kHz only. A libopus build would be better quality at low bitrates; it is LGPL-compatible (BSD) and a candidate for Transcoder's own recipe.
