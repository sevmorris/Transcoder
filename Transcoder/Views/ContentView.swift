import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ContentViewModel.self) private var vm
    @State private var isTargeted = false

    var body: some View {
        @Bindable var vm = vm

        HSplitView {
            queuePane
                .frame(minWidth: 440)

            if vm.showSettings {
                SettingsView()
                    .frame(width: 272)
            }
        }
        .toolbar { toolbar }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard !providers.isEmpty else { return false }
            vm.add(providers)
            return true
        }
        .alert("Error", isPresented: Binding(get: { vm.errorMessage != nil },
                                             set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
        .sheet(isPresented: $vm.showHelp) { HelpView() }
    }

    // MARK: - Queue

    @ViewBuilder private var queuePane: some View {
        if vm.items.isEmpty {
            EmptyQueueView(isTargeted: isTargeted)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.items) { item in
                        QueueRow(item: item)
                            .contextMenu { contextMenu(for: item) }
                        Divider()
                    }

                    Button { vm.chooseInputs() } label: {
                        Label("Add more files…", systemImage: "plus.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.06))
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
        }
    }

    @ViewBuilder private func contextMenu(for item: QueueItem) -> some View {
        Button("Reveal in Finder") { vm.reveal(item) }.disabled(item.outputURL == nil)
        Button("Convert Again") { vm.convertAgain(item) }
            .disabled(vm.isRunning || !item.isFinished)
        if case .failed = item.status {
            Button("Copy Error Message") { vm.copyFailure(item) }
        }
        Divider()
        Button("Remove") { vm.remove(item) }.disabled(vm.isRunning)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { vm.chooseInputs() } label: { Label("Add Files", systemImage: "plus") }
                .help("Add files or folders (⌘O)")

            Button { vm.resetFinished() } label: { Label("Convert Again", systemImage: "arrow.counterclockwise") }
                .help("Put every completed, failed and cancelled row back to Waiting")
                .disabled(vm.isRunning || !vm.hasFinished)

            Button { vm.clearFinished() } label: { Label("Clear Finished", systemImage: "xmark.circle") }
                .help("Remove every completed, failed and cancelled row")
                .disabled(vm.isRunning || !vm.hasFinished)

            Button { vm.revealAll() } label: { Label("Reveal in Finder", systemImage: "folder") }
                .help("Show every output file in Finder")
                .disabled(!vm.items.contains { $0.outputURL != nil })

            if vm.isRunning {
                Button { vm.cancel() } label: { Label("Cancel", systemImage: "stop.circle") }
                    .foregroundStyle(.red)
                    .help("Stop the batch (⌘.)")
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button { vm.start() } label: { Label("Convert", systemImage: "play.circle.fill") }
                    .help("Convert every waiting file (⌘↩)")
                    .disabled(!vm.hasPending)
                    .keyboardShortcut(.return, modifiers: .command)
            }

            Divider()

            Button {
                withAnimation { vm.showSettings.toggle() }
            } label: {
                Label("Settings", systemImage: "sidebar.right")
            }
            .help(vm.showSettings ? "Hide Settings" : "Show Settings")

            Button { vm.showHelp = true } label: { Label("Help", systemImage: "questionmark.circle") }
                .help("Transcoder Help")
        }
    }
}

// MARK: - Empty queue

/// The empty state, in FilmStrip's shape: the app's icon and what it does, a
/// short list of what it keeps, and a dashed drop target with the one button.
private struct EmptyQueueView: View {
    @Environment(ContentViewModel.self) private var vm
    let isTargeted: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text("Transcoder")
                        .font(.title.weight(.semibold))
                    Text("Convert audio, and keep the tags and cover art")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)
                .padding(.bottom, 20)

                VStack(spacing: 0) {
                    feature(icon: "waveform", title: "Seven formats",
                            detail: "MP3, AAC, Apple Lossless, FLAC, WAV, AIFF and Opus.")
                    Divider().padding(.leading, 44)
                    feature(icon: "slider.horizontal.3", title: "Settings for each format",
                            detail: "Each format remembers its own bitrate, bit depth, rate and channels.")
                    Divider().padding(.leading, 44)
                    feature(icon: "film", title: "Audio from video",
                            detail: "From a video file, Transcoder writes the first audio track.")
                    Divider().padding(.leading, 44)
                    feature(icon: "doc.on.doc", title: "Nothing is overwritten",
                            detail: "A name already taken gets a number.")
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 32)

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(isTargeted ? Color.accentColor.opacity(0.06) : Color.clear))

                    VStack(spacing: 10) {
                        Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                        Text("Drop audio or video files, or folders, here")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Button("Add Files…") { vm.chooseInputs() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .padding(24)
                }
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
                .padding(.horizontal, 32)
                .padding(.top, 20)

                Text("See the Help menu for details on each setting.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func feature(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.leading, 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.trailing, 12)
    }
}

// MARK: - Queue row

private struct QueueRow: View {
    @Environment(ContentViewModel.self) private var vm
    let item: QueueItem

    var body: some View {
        HStack(spacing: 10) {
            statusIcon.frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.source.lastPathComponent)
                    .font(AppFont.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail
                    .font(AppFont.rowDetail)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.outputURL != nil {
                Button { vm.reveal(item) } label: {
                    Label("Reveal", systemImage: "folder").font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help("Show the output file in Finder")
            }

            if item.outputURL == nil, !vm.isRunning || item.status == .pending {
                Button { vm.remove(item) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(vm.isRunning)
                .help("Remove from queue")
                .accessibilityLabel("Remove")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isConverting ? Color.accentColor.opacity(0.04) : .clear)
        .contentShape(Rectangle())
    }

    private var isConverting: Bool {
        if case .converting = item.status { return true }
        return false
    }

    @ViewBuilder private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
        case .converting:
            ProgressView().progressViewStyle(.circular).scaleEffect(0.6)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var detail: some View {
        switch item.status {
        case .pending:
            Text("Waiting")
        case .converting(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).progressViewStyle(.linear)
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
        case .done(let url):
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
        case .failed(let message):
            // The whole message, usually FFmpeg's last lines, is in the
            // tooltip and in the row's Copy Error Message.
            Text(message)
                .foregroundStyle(.red)
                .lineLimit(2)
                .help(message)
        case .cancelled:
            Text("Cancelled")
        }
    }
}

#Preview {
    ContentView()
        .environment(ContentViewModel())
        .frame(width: 900, height: 520)
}
