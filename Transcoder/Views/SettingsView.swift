import SwiftUI
import UniformTypeIdentifiers

/// The settings pane, in the sibling apps' style: a narrow material column of
/// ALL-CAPS labelled rows, each with a caption where the choice needs one.
struct SettingsView: View {
    @Environment(ContentViewModel.self) private var vm
    @State private var isDroppingFolder = false

    var body: some View {
        @Bindable var vm = vm
        let format = vm.settings.format

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if vm.isRunning {
                    Text("Locked during conversion")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 8)
                }

                row("Format", caption: Self.summary(of: format)) {
                    Picker("Format", selection: $vm.settings.format) {
                        ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                sectionDivider

                if format.isLossy {
                    row("Bitrate") {
                        Picker("Bitrate", selection: optional(\.bitrateKbps, default: format.bitrates.last!)) {
                            ForEach(format.bitrates, id: \.self) { Text("\($0) kbps").tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    row("Bit Depth") {
                        Picker("Bit depth", selection: optional(\.bitDepth, default: 24)) {
                            ForEach(format.bitDepths, id: \.self) { Text($0 == 32 ? "32-bit float" : "\($0)-bit").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                row("Sample Rate", caption: format.sampleRates.isEmpty ? "Opus is always 48 kHz." : nil) {
                    if format.sampleRates.isEmpty {
                        Text("48 kHz")
                            .font(AppFont.value)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Sample rate", selection: $vm.preset.sampleRate) {
                            Text("Same as source").tag(Int?.none)
                            Divider()
                            ForEach(format.sampleRates, id: \.self) { Text(Self.khz($0)).tag(Int?.some($0)) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                row("Channels") {
                    Picker("Channels", selection: $vm.preset.channels) {
                        Text("Source").tag(Int?.none)
                        Text("Mono").tag(Int?.some(1))
                        Text("Stereo").tag(Int?.some(2))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Source keeps the channels the file already has.")
                }

                HStack {
                    Spacer()
                    Button("Reset to Defaults") { vm.preset = .defaults(for: format) }
                        .controlSize(.small)
                        .disabled(vm.preset == .defaults(for: format))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)

                sectionDivider

                outputFolder

                sectionDivider

                row("Tags & Cover Art",
                    caption: format.carriesArtwork
                        ? "Tags and cover art are carried over."
                        : "Tags are carried over. \(format.displayName) keeps no cover art.") {
                    EmptyView()
                }
            }
            .padding(12)
        }
        .background(.thinMaterial)
        .disabled(vm.isRunning)
    }

    // MARK: - Output folder

    private var outputFolder: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("OUTPUT FOLDER").panelLabel()

            if let folder = vm.outputFolder {
                Label(folder.lastPathComponent, systemImage: "folder")
                    .font(AppFont.value)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(isDroppingFolder ? Color.accentColor : .secondary)
                    .help(folder.path(percentEncoded: false))
            } else {
                Text("Beside each source file")
                    .font(AppFont.value)
                    .foregroundStyle(isDroppingFolder ? Color.accentColor : .secondary)
            }

            HStack(spacing: 6) {
                Button("Choose…") { vm.chooseOutputFolder() }
                    .controlSize(.small)
                if vm.outputFolder != nil {
                    Button("Reset") { vm.settings.outputFolderPath = nil }
                        .controlSize(.small)
                        .help("Write each output file beside its source file")
                }
            }

            Text("Drop a folder here to choose it.")
                .font(AppFont.help)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isDroppingFolder) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
                Task { @MainActor in vm.settings.outputFolderPath = url.path }
            }
            return true
        }
    }

    // MARK: - Building blocks

    private var sectionDivider: some View {
        Divider().padding(.vertical, 6)
    }

    @ViewBuilder
    private func row<Content: View>(_ label: String, caption: String? = nil,
                                    @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased()).panelLabel()
            content()
            if let caption {
                Text(caption)
                    .font(AppFont.help)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }

    private func optional(_ keyPath: WritableKeyPath<Preset, Int?>, default value: Int) -> Binding<Int> {
        Binding(get: { vm.preset[keyPath: keyPath] ?? value },
                set: { vm.preset[keyPath: keyPath] = $0 })
    }

    static func khz(_ rate: Int) -> String {
        rate % 1000 == 0 ? "\(rate / 1000) kHz" : String(format: "%.1f kHz", Double(rate) / 1000)
    }

    /// One line on what each format is for, from the manual's format table.
    static func summary(of format: OutputFormat) -> String {
        switch format {
        case .mp3: "Lossy. Almost all players can play it."
        case .aac: "Lossy. Smaller than MP3 at the same quality."
        case .alac: "Lossless. About half the size of WAV."
        case .flac: "Lossless and open."
        case .wav: "Uncompressed PCM, for audio editors."
        case .aiff: "Uncompressed PCM, Apple's equivalent of WAV."
        case .opus: "Lossy. The best quality at a low bitrate."
        }
    }
}
