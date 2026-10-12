import SwiftUI

@main
struct OpenBotAnchorNavApp: App {
    @StateObject private var demo = DemoSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(demo)
                .onAppear { demo.load() }
        }
    }
}
