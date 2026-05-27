import WidgetKit
import SwiftUI

public struct GlucoseEntry: TimelineEntry {
    public let date: Date
    public let reading: GlucoseReading?
    public let recentReadings: [GlucoseReading]
}

public struct GlucoseWidgetProvider: TimelineProvider {
    public typealias Entry = GlucoseEntry
    
    private let suiteName = "group.com.rajnaidu.LibreGlucoseWatch"
    private var defaults: UserDefaults {
        if let sharedDefaults = UserDefaults(suiteName: suiteName) {
            return sharedDefaults
        }
        return UserDefaults.standard
    }
    
    public init() {}
    
    private func getCachedData() -> (current: GlucoseReading?, history: [GlucoseReading]) {
        let currentReadingKey = "llu_current_reading"
        let readingsKey = "llu_readings"
        
        var current: GlucoseReading? = nil
        var history: [GlucoseReading] = []
        
        if let currentData = defaults.data(forKey: currentReadingKey),
           let reading = try? JSONDecoder().decode(GlucoseReading.self, from: currentData) {
            current = reading
        }
        
        if let readingsData = defaults.data(forKey: readingsKey),
           let loadedReadings = try? JSONDecoder().decode([GlucoseReading].self, from: readingsData) {
            history = loadedReadings
        }
        
        return (current, history)
    }
    
    public func placeholder(in context: Context) -> GlucoseEntry {
        // High-fidelity placeholder for immediate preview
        let mockReading = GlucoseReading(value: 120.0, timestamp: Date(), uom: 0, trend: .stable)
        return GlucoseEntry(date: Date(), reading: mockReading, recentReadings: [mockReading])
    }
    
    public func getSnapshot(in context: Context, completion: @escaping (GlucoseEntry) -> Void) {
        let (current, history) = getCachedData()
        let entry = GlucoseEntry(date: Date(), reading: current, recentReadings: history)
        completion(entry)
    }
    
    public func getTimeline(in context: Context, completion: @escaping (Timeline<GlucoseEntry>) -> Void) {
        let (current, history) = getCachedData()
        let currentDate = Date()
        
        let entry = GlucoseEntry(date: currentDate, reading: current, recentReadings: history)
        
        // Glucose is unpredictable, so we cannot pre-calculate future entries.
        // We create a single entry that remains active, and request a refresh in 15 minutes.
        // The iOS or watchOS app will also reload the timeline immediately when new data arrives.
        let refreshDate = currentDate.addingTimeInterval(15 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        
        completion(timeline)
    }
}
