// ControlWidget is iOS-only (Control Center). Disabled for the watchOS-only target.
#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

struct GlucoseWidgetControl: ControlWidget {
    static let kind: String = "com.rajnaidu.LibreGlucoseWatch.GlucoseWidgetControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenAppIntent()) {
                Label("Glucose", systemImage: "drop.fill")
            }
        }
        .displayName("Glucose")
        .description("Open LibreGlucoseWatch.")
    }
}

struct OpenAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Glucose"
    static let openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult { .result() }
}
#endif
