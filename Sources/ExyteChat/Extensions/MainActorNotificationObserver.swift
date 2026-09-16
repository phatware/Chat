import Foundation

/// Owns a main-queue observer and removes it when its owner releases it.
final class MainActorNotificationObserver {
    private let token: NSObjectProtocol

    @MainActor
    convenience init(name: Notification.Name, handler: @escaping @MainActor @Sendable () -> Void) {
        self.init(name: name, value: { _ in () }, handler: { _ in handler() })
    }

    @MainActor
    init<Value: Sendable>(
        name: Notification.Name,
        value: @escaping @Sendable (Notification) -> Value,
        handler: @escaping @MainActor @Sendable (Value) -> Void
    ) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
            // Notification itself cannot cross isolation boundaries.
            let value = value(notification)
            // OperationQueue.main guarantees synchronous delivery on the main actor.
            MainActor.assumeIsolated {
                handler(value)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
