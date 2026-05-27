import SwiftUI
import Charts
import Combine

struct WatchDashboardView: View {
    @ObservedObject var store = GlucoseStore.shared
    @State private var timeString = "Just now"

    // Timer to update elapsed time text (every 10s)
    let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    // Timer to auto-refresh glucose data while the watch app is visible (every 60s).
    // Foreground only — battery is fine since the watch face is actively being looked at.
    let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Group {
            if store.isSessionActive {
                authenticatedView
            } else {
                unauthenticatedView
            }
        }
        .preferredColorScheme(.dark)
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
    
    // MARK: - Authenticated Dashboard
    private var authenticatedView: some View {
        ScrollView {
            VStack(spacing: 8) {
                // 1. Core Glucose display
                if let current = store.currentReading {
                    glucoseIndicator(current)
                } else {
                    ProgressView()
                        .frame(height: 70)
                }
                
                // 2. Refresh / Timestamp
                HStack(spacing: 4) {
                    Text(timeString)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Spacer()
                    
                    Button(action: {
                        Task { try? await store.refreshData() }
                    }) {
                        if store.isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
                }
                .padding(.horizontal, 4)
                
                Divider().opacity(0.15)
                
                // 3. Mini 3-Hour Sparkline Chart
                sparklineChartView
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func glucoseIndicator(_ current: GlucoseReading) -> some View {
        let themeColor = Color.glucoseColor(for: current.valueInMgDl)
        
        return HStack(spacing: 12) {
            // Circle with Glucose value
            ZStack {
                Circle()
                    .stroke(themeColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 68, height: 68)
                
                Circle()
                    .trim(from: 0, to: 0.8)
                    .stroke(themeColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 68, height: 68)
                
                Text(current.formattedValue)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Trend Arrow and Unit
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: current.trend.symbol)
                        .font(.system(size: 16, weight: .bold))
                    Text(current.trend.label)
                        .font(.system(.caption2, design: .rounded))
                }
                .foregroundColor(themeColor)
                
                Text(current.unitLabel)
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .background(themeColor.opacity(0.02))
        )
    }
    
    // MARK: - Mini Sparkline Chart
    private var sparklineChartView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("3h Trend")
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
            
            // Limit to last 3 hours (3 hours * 60 mins = 180 mins)
            let threeHoursAgo = Date().addingTimeInterval(-3 * 60 * 60)
            let recentReadings = store.readings.filter { $0.timestamp >= threeHoursAgo }
            
            if recentReadings.isEmpty {
                HStack {
                    Spacer()
                    Text("No trend data")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                Chart(recentReadings) {
                    LineMark(
                        x: .value("Time", $0.timestamp),
                        y: .value("Glucose", $0.value)
                    )
                    .foregroundStyle(Color.green)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    
                    AreaMark(
                        x: .value("Time", $0.timestamp),
                        y: .value("Glucose", $0.value)
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
                .chartYScale(domain: chartYDomain(recentReadings))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 44)
            }
        }
    }
    
    // MARK: - Unauthenticated Setup Notice
    private var unauthenticatedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundColor(.green)
            
            Text("LibreGlucoseWatch")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
            
            Text("Please launch and log in on the iOS companion app on your iPhone.")
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(10)
    }
    
    // MARK: - Helper calculations
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
    
    private func chartYDomain(_ filtered: [GlucoseReading]) -> ClosedRange<Double> {
        let isMmolL = store.currentReading?.isMmolL ?? false
        let values = filtered.map { $0.value }
        let minVal = values.min() ?? (isMmolL ? 4.0 : 70.0)
        let maxVal = values.max() ?? (isMmolL ? 10.0 : 180.0)
        let padding = isMmolL ? 0.5 : 9.0
        return max(0.0, minVal - padding)...(maxVal + padding)
    }
}
