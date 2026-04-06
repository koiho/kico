import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        profileHeader
                            .padding(.top, 8)

                        openIDButton
                            .padding(.top, 20)

                        quickActions
                            .padding(.top, 18)
                            .padding(.horizontal, 16)

                        settingsRow
                            .padding(.top, 12)
                            .padding(.horizontal, 16)

                        Spacer(minLength: 60)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .top) {
            ToastHost()
        }
    }

    private var navigationBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            Text("个人中心")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var profileHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.32, green: 0.22, blue: 0.14),
                                Color(red: 0.17, green: 0.18, blue: 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 124, height: 124)

                // Show loaded avatar if available
                if let avatarImage = authManager.avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 124, height: 124)
                        .clipShape(Circle())
                } else if let userInfo = authManager.userInfo, !userInfo.avatarURI.isEmpty {
                    // Show loading indicator while avatar is being fetched
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 124, height: 124)
                } else {
                    // Show placeholder
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.92))
                }
            }

            // Show name only when logged in
            if authManager.userInfo != nil {
                Text(displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 12)
            }
        }
    }

    private var displayName: String {
        authManager.userInfo?.displayName ?? "代洒"
    }

    private var openIDButton: some View {
        Button(action: {
            if authManager.state == .signedIn {
                authManager.signOut()
            } else {
                authManager.startLogin()
            }
        }) {
            Text(openIDButtonTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.white.opacity(0.85))
                .frame(width: 156, height: 46)
                .background(Color.black)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.38), lineWidth: 1.5)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSigningIn)
        .opacity(isSigningIn ? 0.7 : 1)
    }

    private var isSigningIn: Bool {
        if case .signingIn = authManager.state {
            return true
        }
        return false
    }

    private var openIDButtonTitle: String {
        if authManager.state == .signedIn {
            return "退出登录"
        }
        if case .signingIn = authManager.state {
            return "登录中..."
        }
        return "登录"
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            actionCard(
                icon: "questionmark.circle",
                title: "帮助",
                subtitle: "获取帮助"
            )

            actionCard(
                icon: "wallet.pass",
                title: "订阅",
                subtitle: "获取Pro"
            )
        }
        .padding(8)
        .background(Color(red: 0.03, green: 0.05, blue: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func actionCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 42, height: 42)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.white.opacity(0.92))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.62))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(Color(red: 0.01, green: 0.03, blue: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var settingsRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 42, height: 42)

                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.white)
            }

            Text("设置")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .frame(height: 76)
        .background(Color(red: 0.01, green: 0.03, blue: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
