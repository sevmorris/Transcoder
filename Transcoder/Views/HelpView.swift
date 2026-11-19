import SwiftUI

/// A short summary of how to use Transcoder, in the sibling apps' Help shape:
/// a title, then one headed section to a subject. The manual has the rest.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Transcoder Help")
                        .font(.largeTitle.bold())

                    section("Getting Started",
                            "Drag audio files, video files or folders onto the window, or click Add Files (⌘O). Select the output format and its settings in the settings pane. Then click Convert (⌘↩).")
                    section("Audio Only",
                            "Transcoder writes only audio. From a video file, it writes the first audio track.")
                    section("Format Settings",
                            "Each format keeps its own bitrate, bit depth, sample rate and channels. \"Same as source\" keeps the value of the source file. Reset to Defaults sets the values of the selected format again.")
                    section("Tags & Cover Art",
                            "Transcoder copies the tags and the cover art. WAV and Opus keep the tags, but FFmpeg has no location for a cover in them.")
                    section("Output Folder",
                            "Transcoder writes each output file beside its source file. To use one folder for all output files, click Choose… or drop a folder on the Output Folder section. Click Reset to write beside each source file again. Transcoder does not write over a file: a name already taken gets a number.")
                    section("The Queue",
                            "Transcoder converts the waiting rows one at a time, from the top. Cancel (⌘.) stops the batch and deletes the incomplete file. If a conversion fails, the row shows the cause. Hold the pointer on the message to read all of it, or right-click the row and select Copy Error Message.")
                    section("Convert Again",
                            "To convert a finished file again, right-click its row and select Convert Again. To do this for all finished rows, click Convert Again in the toolbar. Then click Convert.")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Manual").font(.headline)
                        Link("sevmorris.github.io/Transcoder/manual",
                             destination: URL(string: "https://sevmorris.github.io/Transcoder/manual/")!)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 560)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    HelpView()
}
