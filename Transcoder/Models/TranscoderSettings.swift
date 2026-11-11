import Foundation

/// The chosen format, each format's preset and the output folder, kept in
/// `UserDefaults.app` — never `.standard`, so a test run cannot reach them.
nonisolated struct TranscoderSettings: Codable, Equatable, Sendable {
    var format: OutputFormat = .mp3
    var presets: [OutputFormat: Preset] = [:]
    /// nil writes each output beside its source.
    var outputFolderPath: String?

    static let key = "TranscoderSettings"

    func preset(for format: OutputFormat) -> Preset {
        presets[format] ?? .defaults(for: format)
    }

    static func load(from store: UserDefaults) -> TranscoderSettings {
        guard let data = store.data(forKey: key),
              let settings = try? JSONDecoder().decode(TranscoderSettings.self, from: data) else {
            return TranscoderSettings()
        }
        return settings
    }

    func save(to store: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { store.set(data, forKey: Self.key) }
    }
}
