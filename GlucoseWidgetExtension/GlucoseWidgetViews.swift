import WidgetKit
import SwiftUI
import Charts

struct GlucoseWidgetView: View {
    let entry: GlucoseWidgetProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        if let reading = entry.reading {
            switch family {
            case .accessoryCircular:
                circularLayout(reading)
            case .accessoryCorner:
                cornerLayout(reading)
            case .accessoryInline:
                inlineLayout(reading)
            case .accessoryRectangular:
                rectangularLayout(reading)
            #if os(watchOS)
            case .accessoryBezel:
                bezelLayout(reading)
            #endif
            default:
                inlineLayout(reading)
            }
        } else {
            emptyLayout
        }
    }
    
    // MARK: - Layouts
    
    // Circular: Progress ring + centered value + tiny arrow
    private func circularLayout(_ reading: GlucoseReading) -> some View {
        let themeColor = Color.glucoseColor(for: reading.valueInMgDl)
        // Normalize value for a progress circle (min 40, max 250)
        let normalized = min(1.0, max(0.0, (reading.valueInMgDl - 40) / 210.0))
        
        return ZStack {
            AccessoryWidgetBackground()
            
            // Progress ring
            Circle()
                .trim(from: 0.0, to: CGFloat(normalized))
                .stroke(themeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            VStack(spacing: -2) {
                Text(reading.formattedValue)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                
                Image(systemName: reading.trend.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(themeColor)
            }
        }
    }
    
    // Corner: Outer label + styled value
    private func cornerLayout(_ reading: GlucoseReading) -> some View {
        let themeColor = Color.glucoseColor(for: reading.valueInMgDl)
        
        return ZStack {
            AccessoryWidgetBackground()
            Image(systemName: reading.trend.symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(themeColor)
                .widgetLabel {
                    Text("\(reading.formattedValue) \(reading.unitLabel)")
                        .foregroundColor(themeColor)
                }
        }
    }
    
    // Inline: 120 ↗
    private func inlineLayout(_ reading: GlucoseReading) -> some View {
        let themeColor = Color.glucoseColor(for: reading.valueInMgDl)
        return HStack(spacing: 3) {
            Text(reading.formattedValue)
                .fontWeight(.bold)
            Image(systemName: reading.trend.symbol)
                .foregroundColor(themeColor)
        }
    }
    
    // Rectangular: Card with mini chart, big text, trend description
    private func rectangularLayout(_ reading: GlucoseReading) -> some View {
        let themeColor = Color.glucoseColor(for: reading.valueInMgDl)
        let elapsed = Int(Date().timeIntervalSince(reading.timestamp) / 60)
        let timeText = elapsed < 1 ? "now" : "\(elapsed)m"
        
        // Filter last 3 hours of readings for complication chart
        let threeHoursAgo = Date().addingTimeInterval(-3 * 60 * 60)
        let recentReadings = entry.recentReadings.filter { $0.timestamp >= threeHoursAgo }
        
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(reading.formattedValue)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                
                Image(systemName: reading.trend.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(themeColor)
                
                Text(reading.unitLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                
                Spacer()
                
                Text(timeText)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            if recentReadings.count >= 2 {
                Chart(recentReadings) {
                    LineMark(
                        x: .value("Time", $0.timestamp),
                        y: .value("Glucose", $0.value)
                    )
                    .foregroundStyle(Color.green)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 20)
                .padding(.top, 2)
            } else {
                Text("Libre Link Up Active")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                Text(reading.trend.label)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(themeColor)
            }
        }
    }
    
    // Bezel: Gauge wrapping bezel with value detail label
    #if os(watchOS)
    private func bezelLayout(_ reading: GlucoseReading) -> some View {
        let themeColor = Color.glucoseColor(for: reading.valueInMgDl)
        
        return circularLayout(reading)
            .widgetLabel {
                Text("\(reading.formattedValue) \(reading.unitLabel) • \(reading.trend.label)")
                    .foregroundColor(themeColor)
            }
    }
    #endif
    
    // MARK: - Fallback Empty State
    private var emptyLayout: some View {
        switch family {
        case .accessoryInline:
            return AnyView(Text("Libre --"))
        case .accessoryRectangular:
            return AnyView(
                VStack(alignment: .leading, spacing: 2) {
                    Text("LibreGlucose")
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("No Sensor Data")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            )
        default:
            return AnyView(
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .foregroundColor(.white.opacity(0.4))
                }
            )
        }
    }
}
