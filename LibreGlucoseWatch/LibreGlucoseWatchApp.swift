import SwiftUI

@main
struct LibreGlucoseWatchApp: App {
    @StateObject private var store = GlucoseStore.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
                if store.isSessionActive {
                    DashboardView(store: store)
                } else {
                    LoginView(store: store)
                }
            }
            .preferredColorScheme(.dark) // Lock to premium dark mode
        }
    }
}
