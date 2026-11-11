# Vendor dependencies

## FFmpeg / ffprobe (bundled binaries)

Transcoder bundles a **static, audio-only, LGPL FFmpeg 9.0.2** with LAME 4.0, for macOS **arm64**. The binaries are not in git:

| Artifact | Location |
|----------|----------|
| Binary checksums & release tag | `Vendor/ffmpeg-manifest.env` |
| Download script | `scripts/fetch-ffmpeg.sh` |
| Build recipe (Corresponding Source) | `scripts/build-ffmpeg.sh` |
| Upstream source | URLs in the manifest |

It adds libopus 1.6.1 (BSD-3-Clause) to FilmStrip's recipe r5, and is reproducible: two runs give byte-identical binaries, so the checksums in the manifest can be checked by rebuilding.

Xcode runs `scripts/fetch-ffmpeg.sh` as a build phase. `Transcoder/` is a synchronized group, so the project also lists `ffmpeg` and `ffprobe` explicitly in Copy Bundle Resources (the "Vendored Binaries" group) and takes them out of the synced folder with an exception set; that way a fresh clone's first build ships them too. Running `./scripts/fetch-ffmpeg.sh` before `xcodebuild` is still the second guard.

**Do not delete** the release named by `FFMPEG_DEPS_TAG`, nor superseded ones: older commits verify against them. Before this repo hosted its own, it borrowed FilmStrip's `ffmpeg-deps-9.0.2-audio-arm64-r5`. Deps releases stay flagged as prereleases, so `/releases/latest` stays the app.

### Encoders used

`libmp3lame` (MP3), `libopus` (Opus), and FFmpeg's own `aac`, `alac`, `flac`, `pcm_s16le/s24le/f32le` (WAV) and `pcm_s16be/s24be` (AIFF). Opus is written at 48 kHz, its native rate.
