import SwiftUI

@main
struct IpeleLinkApp: App {
    @StateObject private var pump = PumpClient()

    var body: some Scene {
        WindowGroup {
            ContentView(pump: pump)
        }
    }
}
