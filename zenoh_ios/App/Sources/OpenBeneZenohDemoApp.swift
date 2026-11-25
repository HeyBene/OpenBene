import SwiftUI

@main
struct OpenBeneZenohDemoApp: App {
    @StateObject private var link = ZenohLink()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(link)
        }
    }
}
