# Changelog

All notable changes to Transcoder are documented here. Version numbers match GitHub releases (`v*` tags).

## [Unreleased]

**Added**
- **Convert Again.** Right-click a completed, failed or cancelled row and choose **Convert Again**, or click the new **Convert Again** toolbar button for every such row. The rows go back to Waiting, ready for the next Convert, with whatever format and settings you choose. The new output gets the next free name, so nothing is overwritten. Until now, the only way was to remove the row and add the file again.
- **More files are accepted:** `.dsf` and `.dff` (DSD), `.weba`, `.tak`, `.shn` and `.rf64`, which macOS has no audio type for, and `.wv`, `.ape`, `.tta`, `.mpc`, `.mka` and `.mkv`, which it recognises only when another app (such as VLC) is installed. Transcoder ignored all of these without a word, although its FFmpeg reads every one.

**Fixed**
- **A WAV file larger than 4 GB is no longer written broken.** FFmpeg wrote it with a header that cannot describe its size and reported success, so the row showed done for a file that players read as shorter than it is (699 s of a 720 s recording). Past 4 GB, Transcoder now writes RF64, the extension of WAV for large files. Smaller WAV files are as before.
- **An AIFF file larger than 4 GB now fails with a clear message instead of showing done.** AIFF cannot hold more than 4 GB, and FFmpeg wrote such a file with a broken header and reported success (a 960 s file read as 28 s). Transcoder now refuses it before it starts, with *Too large for AIFF*. If the source does not give its length, it checks the file afterwards and deletes it.
- **Remove no longer lets a batch convert a file you removed.** The row's context menu offered Remove during a batch, and the batch then converted the removed file out of sight. No row can be removed while a batch runs now, as the row's own button already said.
- **Settings saved by another version of Transcoder now load.** A setting added by a later version, or one this version does not know, made every setting go back to its default. Now each setting is read on its own, and settings saved by 0.1.0 load unchanged.
- **Cancel no longer marks files that you added during the batch as cancelled.** They wait for the next batch, as the manual says.
- **A file added twice in one drop, or through a symbolic link, is now queued once.**
- **A file that cannot be read now says why**, with ffprobe's own reason (for example *Invalid data found when processing input*), not only "ffprobe exit 1".
- **A missing output folder now fails with a plain message that names it.** When the chosen folder is on a drive that is disconnected, each row said only what FFmpeg could not write.
- **A long source whose container gives no length is no longer stopped after 10 minutes.** The limit for such a file is now 24 hours.

**Documentation**
- The manual says that MP3, like Opus, folds a surround source to stereo at *Same as source*. It describes Convert Again, the files Transcoder accepts, and what Transcoder does during a batch, and its Troubleshooting lists the new messages. The Theory of Operation describes the WAV and AIFF size limits, the probe, the time limit, the queue rules and how settings are read.

## [0.1.0] — 2026-11-10

The first release of Transcoder, an audio-only converter for macOS.

**New**
- Converts to MP3, AAC (M4A), Apple Lossless (M4A), FLAC, WAV, AIFF and Opus (OGG).
- Takes audio files, folders, and the first audio track of video files.
- Each format remembers its own bitrate, bit depth, sample rate and channels.
- A batch queue with progress for each file, Cancel, and Reveal in Finder.
- Tags and cover art come across. WAV and Opus keep the tags; neither has a place for a cover.
- Never overwrites: a name already taken gets a number.

**Documentation**
- A manual and a Theory of Operation at [sevmorris.github.io/Transcoder](https://sevmorris.github.io/Transcoder/).
