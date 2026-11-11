import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ContentViewModel.self) private var vm
    @State private var isTargeted = false

    var body: some View {
        @Bindable var vm = vm
        HSplitView {
            queuePane.frame(minWidth: 420)
            SettingsView().frame(width: 280)
        }
        .toolbar { toolbar }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in vm.add([url]) } }
                }
            }
            return true
        }
        .alert("Error", isPresented: Binding(get: { vm.errorMessage != nil },
                                             set: { if !$0 { vm.errorMessage = nil } })) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
        .sheet(isPresented: $vm.showHelp) { HelpView() }
    }

    @ViewBuilder private var queuePane: some View {
        if vm.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text("Drop audio or video files here").font(.title3)
                Text("Transcoder converts the audio, keeping tags and cover art.")
                    .foregroundStyle(.secondary)
                Button("Choose Files…") { vm.chooseInputs() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isTargeted ? Color.accentColor.opacity(0.08) : .clear)
        } else {
            List {
                ForEach(vm.items) { item in
                    QueueRow(item: item)
                        .contextMenu {
                            Button("Reveal in Finder") { vm.reveal(item) }.disabled(item.outputURL == nil)
                            Button("Remove") { vm.remove(item) }
                        }
                }
            }
            .overlay { if isTargeted { Color.accentColor.opacity(0.08).allowsHitTesting(false) } }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { vm.chooseInputs() } label: { Label("Add Files", systemImage: "plus") }
            Button { vm.clearFinished() } label: { Label("Clear Finished", systemImage: "xmark.circle") }
                .disabled(vm.isRunning || !vm.items.contains(where: \.isFinished))
            Button { vm.revealAll() } label: { Label("Reveal in Finder", systemImage: "folder") }
                .disabled(!vm.items.contains { $0.outputURL != nil })
            if vm.isRunning {
                Button { vm.cancel() } label: { Label("Cancel", systemImage: "stop.fill") }
            } else {
                Button { vm.start() } label: { Label("Convert", systemImage: "play.fill") }
                    .disabled(!vm.hasPending)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

private struct QueueRow: View {
    @Environment(ContentViewModel.self) private var vm
    let item: QueueItem

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.source.lastPathComponent).lineLimit(1).truncationMode(.middle)
                detail
            }
            Spacer()
            if item.outputURL != nil {
                Button { vm.reveal(item) } label: { Image(systemName: "magnifyingglass.circle") }
                    .buttonStyle(.borderless).help("Reveal in Finder")
            } else if !vm.isRunning || item.status == .pending {
                Button { vm.remove(item) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("Remove from queue")
                    .disabled(vm.isRunning)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var icon: some View {
        switch item.status {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .converting: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .cancelled: Image(systemName: "slash.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var detail: some View {
        switch item.status {
        case .pending: Text("Waiting").font(.caption).foregroundStyle(.secondary)
        case .converting(let fraction): ProgressView(value: fraction).progressViewStyle(.linear)
        case .done(let url): Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
        case .failed(let message): Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
        case .cancelled: Text("Cancelled").font(.caption).foregroundStyle(.secondary)
        }
    }
}
