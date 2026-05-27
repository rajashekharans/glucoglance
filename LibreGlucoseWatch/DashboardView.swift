import SwiftUI
import Charts
import Combine

struct DashboardView: View {
    @ObservedObject var store: GlucoseStore
    @State private var timeString = "Just now"

    // Timer to update elapsed time text (every 10s)
    let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    // Timer to auto-refresh glucose data while the view is visible (every 60s).
    // Apple Health / FreeStyle Libre sensors update every minute; we match that pace.
    let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Sleek Dark Background
                Color(red: 0.05, green: 0.06, blue: 0.09).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 28) {
                        
                        // 1. Current Reading HERO Area
                        if let current = store.currentReading {
                            currentGlucoseHero(current)
                        } else {
                            noDataHero
                        }
                        
                        // 2. Trend Metrics Cards
                        statsGridView
                        
                        // 3. 24-Hour Trend Chart
                        chartCardView
                        
                        // Status Bar
                        HStack {
                            Circle()
                                .fill(store.isLoading ? Color.green : Color.white.opacity(0.3))
                                .frame(width: 8, height: 8)
                            Text(store.syncMessage.isEmpty ? "Connected to LibreLinkUp" : store.syncMessage)
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.vertical, 8)
                    }
                    .padding()
                }
                .refreshable {
                    try? await store.refreshData()
                }
            }
            .navigationTitle("GlucoGlance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(store: store)) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        Task { try? await store.refreshData() }
                    }) {
                        if store.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
        }
        .accentColor(.green)
        .onReceive(timer) { _ in
            updateElapsedTime()
        }
        .onReceive(refreshTimer) { _ in
            // Skip if a fetch is already in flight to avoid stacking requests.
            guard !store.isLoading else { return }
            Task { try? await store.refreshData() }
        }
        .onAppear {
            updateElapsedTime()
            // Auto refresh
            Task { try? await store.refreshData() }
        }
    }
    
    // MARK: - Current Glucose Circle Hero
    private func currentGlucoseHero(_ current: GlucoseReading) -> some View {
        let themeColor = Color.glucoseColor(for: current.valueInMgDl)
        
        return VStack(spacing: 12) {
            ZStack {
                // Outer Glow ring
                Circle()
                    .stroke(themeColor.opacity(0.15), lineWidth: 16)
                    .frame(width: 200, height: 200)
                    .blur(radius: 2)
                
                // Ring showing target margins
                Circle()
                    .trim(from: 0.1, to: 0.9)
                    .stroke(
                        AngularGradient(
                            colors: [themeColor, themeColor.opacity(0.5), themeColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 180, height: 180)
                
                VStack(spacing: 4) {
                    Text(current.formattedValue)
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 6) {
                        Image(systemName: current.trend.symbol)
                            .font(.system(size: 20, weight: .bold))
                        Text(current.trend.label)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                    }
                    .foregroundColor(themeColor)
                }
            }
            .padding(.top, 10)
            
            VStack(spacing: 4) {
                Text(current.unitLabel)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.4))
                
                Text(timeString)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.02))
                .background(Color.glucoseColor(for: current.valueInMgDl).opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    private var noDataHero: some View {
        VStack(spacing: 16) {
            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No Glucose Data Found")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white)
            
            Text("Ensure your FreeStyle Libre sensor is active and connected, and swipe down to refresh.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Key stats (Average, TIR, Delta)
    private var statsGridView: some View {
        HStack(spacing: 14) {
            // Stats 1: Average
            statsCard(
                title: "AVERAGE",
                value: averageGlucoseString,
                subtitle: store.currentReading?.unitLabel ?? "mg/dL",
                icon: "waveform.path.ecg",
                color: .cyan
            )
            
            // Stats 2: TIR (Time in Range)
            statsCard(
                title: "TIME IN RANGE",
                value: tirString,
                subtitle: "70 - 180 mg/dL",
                icon: "checklist.checked",
                color: .green
            )
            
            // Stats 3: Delta
            statsCard(
                title: "DELTA (15M)",
                value: deltaString,
                subtitle: store.currentReading?.unitLabel ?? "",
                icon: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left",
                color: deltaColor
            )
        }
    }
    
    private func statsCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                Text(subtitle)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - 24H Chart Card
    private var chartCardView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Historical Glucose Log")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Last 24 hours")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Image(systemName: "chart.xyaxis.line")
                    .foregroundColor(.green.opacity(0.8))
            }
            
            if store.readings.isEmpty {
                HStack {
                    Spacer()
                    Text("No historical data to chart yet")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.vertical, 40)
                    Spacer()
                }
            } else {
                Chart {
                    // Target Normal Range Shading (70 - 180 mg/dL)
                    RectangleMark(
                        xStart: .value("Start", Date().addingTimeInterval(-86400)),
                        xEnd: .value("End", Date()),
                        yStart: .value("LowTarget", store.currentReading?.isMmolL ?? false ? 70.0.mgDlToMmolL : 70.0),
                        yEnd: .value("HighTarget", store.currentReading?.isMmolL ?? false ? 180.0.mgDlToMmolL : 180.0)
                    )
                    .foregroundStyle(Color.green.opacity(0.03))
                    
                    // Historical line
                    ForEach(store.readings) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Glucose", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        
                        AreaMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Glucose", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.green.opacity(0.12), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: chartYDomain)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.hour(), centered: true).foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel().foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Calculations for Stats
    
    private func updateElapsedTime() {
        guard let current = store.currentReading else { return }
        let diff = Date().timeIntervalSince(current.timestamp)
        let mins = Int(diff / 60)
        
        if mins < 1 {
            timeString = "Just now"
        } else {
            timeString = "\(mins)m ago"
        }
    }
    
    private var averageGlucoseString: String {
        guard !store.readings.isEmpty else { return "--" }
        let sum = store.readings.reduce(0.0) { $0 + $1.value }
        let avg = sum / Double(store.readings.count)
        
        if store.currentReading?.isMmolL ?? false {
            return String(format: "%.1f", avg)
        } else {
            return String(format: "%.0f", avg)
        }
    }
    
    private var tirString: String {
        guard !store.readings.isEmpty else { return "--" }
        let inRangeCount = store.readings.filter { reading in
            let val = reading.valueInMgDl
            return val >= 70.0 && val <= 180.0
        }.count
        
        let pct = (Double(inRangeCount) / Double(store.readings.count)) * 100.0
        return String(format: "%.0f%%", pct)
    }
    
    private var deltaString: String {
        guard store.readings.count >= 2 else { return "--" }
        let latest = store.readings[0]
        
        // Find reading roughly 15 minutes ago
        let targetTime = latest.timestamp.addingTimeInterval(-15 * 60)
        
        // Find closest reading to targetTime
        let closest = store.readings.min(by: {
            abs($0.timestamp.timeIntervalSince(targetTime)) < abs($1.timestamp.timeIntervalSince(targetTime))
        })
        
        guard let prev = closest, abs(prev.timestamp.timeIntervalSince(targetTime)) < 10 * 60 else {
            // Fallback to second element in list
            let diffVal = latest.value - store.readings[1].value
            return formatDelta(diffVal)
        }
        
        let diffVal = latest.value - prev.value
        return formatDelta(diffVal)
    }
    
    private func formatDelta(_ diffVal: Double) -> String {
        let prefix = diffVal >= 0 ? "+" : ""
        if store.currentReading?.isMmolL ?? false {
            return String(format: "%@%.1f", prefix, diffVal)
        } else {
            return String(format: "%@%.0f", prefix, diffVal)
        }
    }
    
    private var deltaColor: Color {
        guard store.readings.count >= 2 else { return .white }
        let latest = store.readings[0].valueInMgDl
        let prev = store.readings[1].valueInMgDl
        let diff = latest - prev
        
        if diff > 10.0 {
            return .orange // Rising quickly
        } else if diff < -10.0 {
            return .red // Falling quickly
        } else {
            return .cyan // Stable
        }
    }
    
    private var chartYDomain: ClosedRange<Double> {
        let isMmolL = store.currentReading?.isMmolL ?? false
        let readingsVals = store.readings.map { $0.value }
        let minVal = readingsVals.min() ?? (isMmolL ? 4.0 : 70.0)
        let maxVal = readingsVals.max() ?? (isMmolL ? 10.0 : 180.0)
        
        let padding = isMmolL ? 1.0 : 18.0
        return max(0.0, minVal - padding)...(maxVal + padding)
    }
}
