import Foundation

// MARK: - Date Helper
public struct LibreDateFormatter {
    private static let formatters: [DateFormatter] = {
        let f1 = DateFormatter()
        f1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f1.timeZone = TimeZone(secondsFromGMT: 0)
        
        let f2 = DateFormatter()
        f2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        f2.timeZone = TimeZone(secondsFromGMT: 0)
        
        let f3 = DateFormatter()
        f3.dateFormat = "M/d/yyyy h:mm:ss a"
        f3.timeZone = TimeZone(secondsFromGMT: 0)
        
        let f4 = DateFormatter()
        f4.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        return [f1, f2, f3, f4]
    }()
    
    public static func parse(_ dateString: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Login Models
public struct LibreLinkUpLoginResponse: Codable {
    public let status: Int
    public let data: LoginData?
    public let error: LLUError?
}

public struct LLUError: Codable {
    public let message: String?
}

public struct LoginData: Codable {
    public let redirect: Bool?
    public let region: String?
    public let authTicket: AuthTicket?
    public let user: UserInfo?
}

public struct AuthTicket: Codable {
    public let token: String
    public let duration: Int
    public let expires: Int
}

public struct UserInfo: Codable {
    public let id: String
    public let email: String
}

// MARK: - Connections Models
public struct LibreLinkUpConnectionResponse: Codable {
    public let status: Int
    public let data: [LLUConnection]?
}

public struct LLUConnection: Codable {
    public let id: String
    public let patientId: String
    public let firstName: String
    public let lastName: String
    public let targetLow: Double
    public let targetHigh: Double
    public let uom: Int // 0 = mg/dL, 1 = mmol/L (unreliable — use `country` instead)
    public let country: String? // e.g. "AU", "US", "GB" — used to pick display unit
    public let glucoseMeasurement: LLUMeasurement?
}

public struct LLUMeasurement: Codable {
    public let value: Double             // In user's region display unit (mmol/L for non-US)
    public let valueInMgPerDl: Double    // Always mg/dL
    public let timestamp: String
    public let rawTrendArrow: Int

    enum CodingKeys: String, CodingKey {
        case value = "Value"
        case valueInMgPerDl = "ValueInMgPerDl"
        case timestamp = "Timestamp"
        case rawTrendArrow = "TrendArrow"
    }

    public var date: Date? {
        return LibreDateFormatter.parse(timestamp)
    }

    public var trendArrowEnum: TrendArrow {
        return TrendArrow(rawValue: rawTrendArrow) ?? .unknown
    }
}

// MARK: - Graph Models
public struct LibreLinkUpGraphResponse: Codable {
    public let status: Int
    public let data: GraphDataPayload?
}

public struct GraphDataPayload: Codable {
    public let connection: LLUConnection
    public let graphData: [LLUGraphPoint]
}

public struct LLUGraphPoint: Codable {
    public let Value: Double            // In user's region display unit
    public let ValueInMgPerDl: Double   // Always mg/dL
    public let Timestamp: String

    public var date: Date? {
        return LibreDateFormatter.parse(Timestamp)
    }
}
