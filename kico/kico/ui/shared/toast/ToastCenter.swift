import SwiftUI
import Combine

enum ToastStyle {
    case error
}

enum ToastSource: String {
    case auth
    case camera
    case `import`
    case general
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: ToastStyle
    let source: ToastSource
}

@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var currentMessage: ToastMessage?

    private var queue: [ToastMessage] = []
    private var dismissTask: Task<Void, Never>?
    private var lastShownAtByKey: [String: Date] = [:]

    func showError(_ message: String, source: ToastSource = .general, dedupeKey: String? = nil) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let key = dedupeKey ?? "\(source.rawValue):\(text)"
        let now = Date()
        if let last = lastShownAtByKey[key], now.timeIntervalSince(last) < 1.2 {
            return
        }
        lastShownAtByKey[key] = now

        enqueue(ToastMessage(text: text, style: .error, source: source))
    }

    private func enqueue(_ message: ToastMessage) {
        if currentMessage == nil {
            present(message)
            return
        }

        queue.append(message)
    }

    private func present(_ message: ToastMessage) {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            currentMessage = message
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            self?.dismissCurrent(messageID: message.id)
        }
    }

    private func dismissCurrent(messageID: UUID) {
        guard currentMessage?.id == messageID else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            currentMessage = nil
        }

        if !queue.isEmpty {
            let next = queue.removeFirst()
            present(next)
        }
    }
}
