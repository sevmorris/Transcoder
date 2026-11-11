import SwiftUI

struct SettingsView: View {
    @Environment(ContentViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let format = vm.settings.format
        Form {
            Section("Output") {
                Picker("Format", selection: $vm.settings.format) {
                    ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
                }
                if format.isLossy {
                    Picker("Bitrate", selection: optional(\.bitrateKbps, default: format.bitrates.last!)) {
                        ForEach(format.bitrates, id: \.self) { Text("\($0) kbps").tag($0) }
                    }
                } else {
                    Picker("Bit depth", selection: optional(\.bitDepth, default: 24)) {
                        ForEach(format.bitDepths, id: \.self) { Text($0 == 32 ? "32-bit float" : "\($0)-bit").tag($0) }
                    }
                }
                if format.sampleRates.isEmpty {
                    LabeledContent("Sample rate", value: "48 kHz")
                } else {
                    Picker("Sample rate", selection: $vm.preset.sampleRate) {
                        Text("Same as source").tag(Int?.none)
                        ForEach(format.sampleRates, id: \.self) { Text(Self.khz($0)).tag(Int?.some($0)) }
                    }
                }
                Picker("Channels", selection: $vm.preset.channels) {
                    Text("Same as source").tag(Int?.none)
                    Text("Mono").tag(Int?.some(1))
                    Text("Stereo").tag(Int?.some(2))
                }
                Button("Reset to Defaults") { vm.preset = .defaults(for: format) }
                    .disabled(vm.preset == .defaults(for: format))
            }
            Section("Save To") {
                Text(vm.outputFolder?.path(percentEncoded: false) ?? "Beside each source file")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                HStack {
                    Button("Choose…") { vm.chooseOutputFolder() }
                    Button("Beside Source") { vm.settings.outputFolderPath = nil }
                        .disabled(vm.outputFolder == nil)
                }
            }
            Section {
                Text(format.carriesArtwork
                     ? "Tags and cover art are carried over."
                     : "Tags are carried over; \(format.displayName) keeps no cover art.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(vm.isRunning)
    }

    private func optional(_ keyPath: WritableKeyPath<Preset, Int?>, default value: Int) -> Binding<Int> {
        Binding(get: { vm.preset[keyPath: keyPath] ?? value },
                set: { vm.preset[keyPath: keyPath] = $0 })
    }

    static func khz(_ rate: Int) -> String {
        rate % 1000 == 0 ? "\(rate / 1000) kHz" : String(format: "%.1f kHz", Double(rate) / 1000)
    }
}
