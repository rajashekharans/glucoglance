import WidgetKit
import SwiftUI
import Charts

// MARK: - Timeline Entry

struct GlucoseEntry: TimelineEntry {
    let date: Date
    let reading: GlucoseReading?
    let recentReadings: [GlucoseReading]
}

// MARK: - Timeline Provider

struct GlucoseWidgetProvider: TimelineProvider {
    typealias Entry = GlucoseEntry

    private let suiteName = "group.com.rajnaidu.LibreGlucoseWatch"
    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private func loadCachedData() -> (current: GlucoseReading?, history: [GlucoseReading]) {
        var current: GlucoseReading? = nil
        var history: [GlucoseReading] = []

        if let data = defaults.data(forKey: "llu_current_reading"),
           let reading = try? JSONDecoder().decode(GlucoseReading.self, from: data) {
            current = reading
        }

        if let data = defaults.data(forKey: "llu_readings"),
           let loaded = try? JSONDecoder().decode([GlucoseReading].self, from: data) {
            history = loaded
        }

        return (current, history)
    }

    func placeholder(in context: Context) -> GlucoseEntry {
        let mock = GlucoseReading(value: 120.0, timestamp: Date(), uom: 0, trend: .stable)
        return GlucoseEntry(date: Date(), reading: mock, recentReadings: [mock])
    }

    func getSnapshot(in context: Context, completion: @escaping (GlucoseEntry) -> Void) {
        let (current, history) = loadCachedData()
        completion(GlucoseEntry(date: Date(), reading: current, recentReadings: history))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlucoseEntry>) -> Void) {
        let (current, history) = loadCachedData()
        let entry = GlucoseEntry(date: Date(), reading: current, recentReadings: history)
        // Glucose can't be predicted ahead — single entry, refresh in 5 min.
        // The main app calls WidgetCenter.shared.reloadAllTimelines() when new data arrives.
        let refreshDate = Date().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

// MARK: - Widget

struct GlucoseWidget: Widget {
    let kind: String = "GlucoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlucoseWidgetProvider()) { entry in
            GlucoseWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Blood Glucose")
        .description("Live FreeStyle Libre blood sugar and trend.")
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
            .accessoryRectangular,
        ])
        #endif
    }
}

// MARK: - View

struct GlucoseWidgetView: View {
    let entry: GlucoseEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let reading = entry.reading {
            switch family {
            case .accessoryCircular:    circularLayout(reading)
            case .accessoryCorner:      cornerLayout(reading)
            case .accessoryInline:      inlineLayout(reading)
            case .accessoryRectangular: rectangularLayout(reading)
            default:                    inlineLayout(reading)
            }
        } else {
            emptyLayout
        }
    }

    private func circularLayout(_ reading: GlucoseReading) -> some View {
        let themeColor = Color.glucoseColor(for: reading.valueInMgDl)
        let normalized = min(1.0, max(0.0, (reading.valueInMgDl - 40) / 210.0))

        return ZStack {
            AccessoryWidgetBackground()
            Circle()
                .trim(from: 0.0, to: CGFloat(normalized))
                .stroke(themeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text(reading.formattedValue)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Image(systemName: reading.trend.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(themeColor)
            }
        }
    }

    private func cornerLayout(_ reading: GlucoseReading) -> some View {
        let themeColor = Color.glucoseColor(for: reading.valueInMgDl)
        return Image(systemName: reading.trend.symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(themeColor)
            .widgetLabel {
                Text("\(reading.formattedValue) \(reading.unitLabel)")
            }
    }

    private func inlineLayout(_ reading: GlucoseReading) -> some View {
        HStack(spacing: 3) {
            Text(reading.formattedValue).fontWeight(.bold)
            Image(systemName: reading.trend.symbol)
        }
    }

    private func rectangularLayout(_ reading: GlucoseReading) -> some View {
        let themeColor = Color.glucoseColor(for: reading.valueInMgDl)
        let elapsed = Int(Date().timeIntervalSince(reading.timestamp) / 60)
        let timeText = elapsed < 1 ? "now" : "\(elapsed)m"
        let threeHoursAgo = Date().addingTimeInterval(-3 * 60 * 60)
        let recent = entry.recentReadings.filter { $0.timestamp >= threeHoursAgo }

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(reading.formattedValue)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                Image(systemName: reading.trend.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(themeColor)
                Text(reading.unitLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text(timeText)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.secondary)
            }

            if recent.count >= 2 {
                Chart(recent, id: \.id) {
                    LineMark(
                        x: .value("Time", $0.timestamp),
                        y: .value("Glucose", $0.value)
                    )
                    .foregroundStyle(themeColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 20)
            } else {
                Text(reading.trend.label)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(themeColor)
            }
        }
    }

    @ViewBuilder
    private var emptyLayout: some View {
        switch family {
        case .accessoryInline:
            Text("Libre --")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("LibreGlucose")
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.bold)
                Text("No Sensor Data")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.secondary)
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Rectangular", as: .accessoryRectangular) {
    GlucoseWidget()
} timeline: {
    GlucoseEntry(
        date: .now,
        reading: GlucoseReading(value: 120, timestamp: .now, uom: 0, trend: .stable),
        recentReadings: []
    )
}

#Preview("Circular", as: .accessoryCircular) {
    GlucoseWidget()
} timeline: {
    GlucoseEntry(
        date: .now,
        reading: GlucoseReading(value: 145, timestamp: .now, uom: 0, trend: .rising),
        recentReadings: []
    )
}
