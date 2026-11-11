import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcoder Help").font(.title2.bold())
            Group {
                Text("Drop audio files, video files or folders into the window, or choose Add Files. Pick an output format and its settings on the right, then Convert (⌘↩).")
                Text("Only audio is written. From a video file Transcoder takes the first audio track.")
                Text("Each format remembers its own bitrate, sample rate, channels and bit depth. \"Same as source\" keeps what the file already has.")
                Text("Tags and cover art come across. WAV and Opus keep the tags but have no place FFmpeg can put a cover.")
                Text("Outputs go beside each source unless you choose a folder. Nothing is overwritten: a name already taken gets a number.")
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 460)
    }
}
