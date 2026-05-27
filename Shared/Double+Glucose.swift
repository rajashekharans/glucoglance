import SwiftUI

extension Double {
    public var mgDlToMmolL: Double {
        return self / 18.0182
    }
    
    public var mmolLToMgDl: Double {
        return self * 18.0182
    }
}

extension Color {
    // Elegant color theme for glucose ranges
    public static func glucoseColor(for valueInMgDl: Double) -> Color {
        if valueInMgDl < 55.0 {
            // Urgent Low (Deep Red / Indigo alert)
            return Color(red: 0.75, green: 0.1, blue: 0.2)
        } else if valueInMgDl < 70.0 {
            // Low (Bright Coral Red)
            return Color(red: 0.9, green: 0.25, blue: 0.25)
        } else if valueInMgDl > 250.0 {
            // Very High (Deep Magenta / Purple)
            return Color(red: 0.65, green: 0.2, blue: 0.8)
        } else if valueInMgDl > 180.0 {
            // High (Vibrant Warm Amber / Orange)
            return Color(red: 0.95, green: 0.55, blue: 0.1)
        } else {
            // Perfect Normal (Beautiful Emerald Green)
            return Color(red: 0.15, green: 0.68, blue: 0.37)
        }
    }
    
    // Background gradient colors based on status (sleek, subtle glassmorphism colors)
    public static func glucoseGradient(for valueInMgDl: Double) -> Gradient {
        let mainColor = Color.glucoseColor(for: valueInMgDl)
        return Gradient(colors: [mainColor.opacity(0.25), mainColor.opacity(0.02)])
    }
}
