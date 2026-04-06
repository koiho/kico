//
//  RootScreen.swift
//  ios
//
//  Created by TAO DAI on 2025/6/28.
//

import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = RootViewModel()
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var toastCenter: ToastCenter

    var body: some View {
        NavigationStack {
            CameraView()
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            ToastHost()
        }
        .onChange(of: authManager.state) { _, newValue in
            if case .failed(let message) = newValue {
                toastCenter.showError(message, source: .auth, dedupeKey: "auth.failed")
            }
        }
    }
}
