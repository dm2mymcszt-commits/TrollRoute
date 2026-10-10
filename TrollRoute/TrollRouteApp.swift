//
//  TrollRouteApp.swift
//  TrollRoute
//
//  Developed by son3ra1n.
//

import SwiftUI
@main
@MainActor enum TrollRouteEntry {
    static func main() {
        if KeeperRuntime.handleCommandLine() { return }
        TrollRouteApp.main()
    }
}

struct TrollRouteApp: App {
    var body: some Scene { WindowGroup { MigrationLaunchView() } }
}

struct ReadyAppView: View {
    @StateObject private var appSettings = AppSettings()
    var body: some View {
            ContentView()
                .onAppear {
                    KeeperClient.shared.resumeIfCurrentBoot()
                    if checkSandbox(), !appSettings.tsBypass, !appSettings.isFirstRun {
                        UIApplication.shared.alert(title:"TrollRoute wasn't installed with TrollStore", body:"Unable to create test file. The app cannot work without the correct entitlements. Please use TrollStore to install it.", withButton:true)
                    }
                }
                .sheet(isPresented: $appSettings.isFirstRun) {
                    if #available(iOS 16.0, *) {
                        NavigationStack {
                            WelcomeView()
                        }
                    } else {
                        NavigationView {
                            WelcomeView()
                        }
                    }
                }
    }
}

class AppSettings: ObservableObject {
    @AppStorage("TSBypass", store: SharedPreferences.defaults) var tsBypass = false
    @AppStorage("isFirstRun", store: SharedPreferences.defaults) var isFirstRun = true
}
