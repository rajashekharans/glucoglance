import WidgetKit
import SwiftUI

@main
struct GlucoseWidget: Widget {
    let kind: String = "LibreGlucoseWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlucoseWidgetProvider()) { entry in
            GlucoseWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Blood Glucose")
        .description("Displays your real-time FreeStyle Libre blood sugar and trend.")
        #if os(watchOS)
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
            
        ])
        #else
        .supportedFamilies([
            .accessoryCircular,
            .accessoryInline,
            .accessoryRectangular
        ])
        #endif
    }
}
