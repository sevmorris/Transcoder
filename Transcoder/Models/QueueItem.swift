import Foundation
import Observation

@Observable
final class QueueItem: Identifiable {
    enum Status: Equatable {
        case pending
        case converting(Double)
        case done(URL)
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let source: URL
    var status: Status = .pending

    init(source: URL) { self.source = source }

    var outputURL: URL? {
        if case .done(let url) = status { return url }
        return nil
    }

    var isFinished: Bool {
        switch status {
        case .done, .failed, .cancelled: true
        default: false
        }
    }
}
