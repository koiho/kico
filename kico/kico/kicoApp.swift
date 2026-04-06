//
//  kicoApp.swift
//  kico
//
//  Created by TAO DAI on 2026/3/26.
//

import SwiftUI
import SwiftData

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct kicoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var authManager = AuthManager()
    @StateObject private var toastCenter = ToastCenter()
    @StateObject private var referenceImageStore = ReferenceImageStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(themeManager)
                .environmentObject(authManager)
                .environmentObject(toastCenter)
                .environmentObject(referenceImageStore)
                .applyTheme(themeManager)
                .onOpenURL { url in
                    _ = authManager.handleOpenURL(url)
                }
                .task {
                    authManager.restoreFromKeychain()
                }
        }
    }
}
