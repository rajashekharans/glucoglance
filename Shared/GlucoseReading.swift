import Foundation

public enum TrendArrow: Int, Codable, CaseIterable {
    case unknown = 0
    case risingQuickly = 1
    case rising = 2
    case stable = 3
    case falling = 4
    case fallingQuickly = 5
    
    public var symbol: String {
        switch self {
        case .risingQuickly: return "arrow.up"
        case .rising: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .falling: return "arrow.down.right"
        case .fallingQuickly: return "arrow.down"
        case .unknown: return "minus"
        }
    }
    
    public var label: String {
        switch self {
        case .risingQuickly: return "Rising Quickly"
        case .rising: return "Rising"
        case .stable: return "Stable"
        case .falling: return "Falling"
        case .fallingQuickly: return "Falling Quickly"
        case .unknown: return "Stable"
        }
    }
}

public struct GlucoseReading: Codable, Identifiable, Equatable {
    public var id: String {
        return "\(timestamp.timeIntervalSince1970)-\(value)"
    }
    
    public let value: Double
    public let timestamp: Date
    public let uom: Int // 0 = mg/dL, 1 = mmol/L
    public let trend: TrendArrow
    
    public var isMmolL: Bool {
        return uom == 1
    }
    
    public var formattedValue: String {
        if isMmolL {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.0f", value)
        }
    }
    
    public var unitLabel: String {
        return isMmolL ? "mmol/L" : "mg/dL"
    }
    
    // Returns value converted to mg/dL
    public var valueInMgDl: Double {
        if isMmolL {
            return value * 18.0182
        } else {
            return value
        }
    }
    
    // Returns value converted to mmol/L
    public var valueInMmolL: Double {
        if isMmolL {
            return value
        } else {
            return value / 18.0182
        }
    }
    
    public var isHigh: Bool {
        // High is > 180 mg/dL (10.0 mmol/L)
        return valueInMgDl > 180.0
    }
    
    public var isLow: Bool {
        // Low is < 70 mg/dL (3.9 mmol/L)
        return valueInMgDl < 70.0
    }
    
    public var isUrgentLow: Bool {
        // Urgent Low is < 55 mg/dL (3.0 mmol/L)
        return valueInMgDl < 55.0
    }
    
    public init(value: Double, timestamp: Date, uom: Int, trend: TrendArrow) {
        self.value = value
        self.timestamp = timestamp
        self.uom = uom
        self.trend = trend
    }
}
