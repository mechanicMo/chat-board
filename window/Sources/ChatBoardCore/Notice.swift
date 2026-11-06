import Combine
import Foundation

// A message at the top of the board. It closes itself after `delay` seconds, unless a newer one replaced it.
@MainActor
public final class Notice: ObservableObject {
    @Published public var text: String? {
        didSet {
            guard let shown = text else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                if self?.text == shown { self?.text = nil }
            }
        }
    }

    public let delay: TimeInterval

    public init(delay: TimeInterval = 10) { self.delay = delay }
}
