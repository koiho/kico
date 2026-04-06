import SwiftUI

struct ToastHost: View {
    @EnvironmentObject private var toastCenter: ToastCenter

    var body: some View {
        VStack {
            if let message = toastCenter.currentMessage {
                toastCard(message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .allowsHitTesting(false)
    }

    private func toastCard(_ message: ToastMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconName(for: message.style))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Text(message.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(backgroundColor(for: message.style))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func iconName(for style: ToastStyle) -> String {
        switch style {
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private func backgroundColor(for style: ToastStyle) -> Color {
        switch style {
        case .error:
            return Color(red: 0.70, green: 0.18, blue: 0.18)
        }
    }
}
