import Foundation

/// The chosen format, each format's preset and the output folder, kept in
/// `UserDefaults.app` — never `.standard`, so a test run cannot reach them.
nonisolated struct TranscoderSettings: Codable, Equatable, Sendable {
    var format: OutputFormat = .mp3
    var presets: [OutputFormat: Preset] = [:]
    /// nil writes each output beside its source.
    var outputFolderPath: String?

    static let key = "TranscoderSettings"

    enum CodingKeys: String, CodingKey { case format, presets, outputFolderPath }

    init() {}

    /// Takes each field that is there and readable, and keeps the default for
    /// the rest, so settings saved by another version still load: a field a
    /// later version adds is ignored here, one this version adds is missing
    /// from what an earlier one saved, and a format this version does not
    /// know costs only its own preset. Encoding stays synthesized, so what is
    /// written is the shape 0.1.0 reads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try? c.decodeIfPresent(String.self, forKey: .format),
           let format = OutputFormat(rawValue: raw) {
            self.format = format
        }
        if let path = try? c.decodeIfPresent(String.self, forKey: .outputFolderPath) {
            outputFolderPath = path
        }
        // OutputFormat is not CodingKeyRepresentable, so the dictionary is
        // encoded as an array of alternating keys and values:
        // ["flac", {"bitDepth": 16}, "mp3", {"bitrateKbps": 192}].
        if var list = try? c.nestedUnkeyedContainer(forKey: .presets) {
            while !list.isAtEnd {
                // The wrappers never throw, so a failure here is a malformed
                // array, not an element this version cannot read.
                guard let key = try? list.decode(LenientString.self),
                      let value = try? list.decode(LenientPreset.self) else { break }
                if let name = key.value, let format = OutputFormat(rawValue: name), let preset = value.value {
                    presets[format] = preset
                }
            }
        }
    }

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

/// One element of the presets array that always decodes, so the container
/// moves past an element it cannot read rather than stopping on it.
private nonisolated struct LenientString: Decodable {
    let value: String?
    init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(String.self) }
}

private nonisolated struct LenientPreset: Decodable {
    let value: Preset?
    init(from decoder: Decoder) throws { value = try? Preset(from: decoder) }
}
