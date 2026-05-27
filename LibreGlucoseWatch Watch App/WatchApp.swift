import SwiftUI
import WatchKit

@main
struct WatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
        }
    }
}

class WatchAppDelegate: NSObject, WKApplicationDelegate {
    
    func applicationDidFinishLaunching() {
        scheduleNextBackgroundRefresh()
    }
    
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                // Perform a background pull from LibreLinkUp
                Task {
                    do {
                        try await GlucoseStore.shared.refreshData()
                    } catch {
                        print("WatchOS background refresh failed: \(error.localizedDescription)")
                    }
                    
                    // Schedule next check
                    scheduleNextBackgroundRefresh()
                    
                    // Finished
                    refreshTask.setTaskCompletedWithSnapshot(true)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
    
    private func scheduleNextBackgroundRefresh() {
        // Run background pull every 5 minutes — CGM data needs freshness.
        // watchOS may stretch this on tight budget but won't run more often.
        let nextRefreshDate = Date().addingTimeInterval(5 * 60)
        
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: nextRefreshDate,
            userInfo: nil
        ) { error in
            if let error = error {
                print("Failed to schedule watchOS background refresh: \(error.localizedDescription)")
            } else {
                print("watchOS background refresh scheduled successfully for \(nextRefreshDate).")
            }
        }
    }
}
