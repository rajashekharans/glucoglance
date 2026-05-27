import Foundation
import WatchConnectivity
import Combine
import WidgetKit

#if os(iOS)
import HealthKit
#endif

@MainActor
public class GlucoseStore: NSObject, ObservableObject {
    public static let shared = GlucoseStore()
    
    // Published state
    @Published var currentReading: GlucoseReading? = nil
    @Published var readings: [GlucoseReading] = []
    @Published var isLoading = false
    @Published var lastUpdated: Date? = nil
    @Published var isSessionActive = false
    @Published var syncMessage: String = ""
    
    // LibreLinkUp client
    private let client = LibreLinkUpClient()
    
    #if os(iOS)
    private let healthKitManager = HealthKitManager()
    #endif
    
    // Storage keys
    private let suiteName = "group.com.rajnaidu.LibreGlucoseWatch"
    private var defaults: UserDefaults {
        if let sharedDefaults = UserDefaults(suiteName: suiteName) {
            return sharedDefaults
        }
        return UserDefaults.standard
    }
    
    // MARK: - Storage keys

    // UserDefaults — NON-sensitive data only
    private let readingsKey = "llu_readings"
    private let currentReadingKey = "llu_current_reading"
    private let useHealthKitKey = "llu_use_healthkit"
    private let cacheVersionKey = "llu_cache_version"
    private let emailKey = "llu_email"   // Shown in Settings; not a secret on its own
    private let regionKey = "llu_region" // Public LibreLinkUp regional endpoint URL

    // Sensitive items live in Keychain — keys defined in KeychainStore.Keys

    // Legacy UserDefaults keys, kept only for one-time migration to Keychain
    private let legacyCredentialsKey = "llu_credentials"
    private let legacySessionKey = "llu_session"

    private let keychain = KeychainStore.shared

    /// Bump this whenever the on-disk reading format / unit / timestamp interpretation
    /// changes. Old cached readings get wiped automatically when the user upgrades.
    /// v2: unit-flag rewrite (use country code, not connection.uom)
    /// v3: timestamp parsing switched from local Timestamp to UTC FactoryTimestamp
    /// v4: credentials + token migrated from UserDefaults to Keychain
    private let currentCacheVersion = 4

    override private init() {
        super.init()
        // Migrate / clear stale cache from older app versions where the `uom` flag
        // on stored readings could be inconsistent with the actual `value`.
        let storedVersion = defaults.integer(forKey: cacheVersionKey)
        if storedVersion < currentCacheVersion {
            defaults.removeObject(forKey: currentReadingKey)
            defaults.removeObject(forKey: readingsKey)
            migrateLegacyCredentialsToKeychain()
            defaults.set(currentCacheVersion, forKey: cacheVersionKey)
        }
        loadLocalData()
        setupWatchConnectivity()
    }

    /// One-time migration: copy LibreLinkUp password and bearer token out of
    /// plaintext UserDefaults and into Keychain, then wipe them from UserDefaults.
    /// Email and region URL stay in UserDefaults (neither is sensitive).
    private func migrateLegacyCredentialsToKeychain() {
        if let legacyCreds = defaults.dictionary(forKey: legacyCredentialsKey) as? [String: String] {
            if let email = legacyCreds["email"] {
                defaults.set(email, forKey: emailKey)
            }
            if let password = legacyCreds["password"], !password.isEmpty {
                keychain.setString(password, forKey: KeychainStore.Keys.password)
            }
            defaults.removeObject(forKey: legacyCredentialsKey)
        }
        if let legacySession = defaults.dictionary(forKey: legacySessionKey) {
            if let token = legacySession["token"] as? String, !token.isEmpty {
                keychain.setString(token, forKey: KeychainStore.Keys.token)
            }
            if let region = legacySession["region"] as? String {
                defaults.set(region, forKey: regionKey)
            }
            if let userId = legacySession["userId"] as? String, !userId.isEmpty {
                keychain.setString(userId, forKey: KeychainStore.Keys.userId)
            }
            defaults.removeObject(forKey: legacySessionKey)
        }
    }
    
    // MARK: - Local Data Management
    
    private func loadLocalData() {
        // Load current reading
        if let data = defaults.data(forKey: currentReadingKey),
           let reading = try? JSONDecoder().decode(GlucoseReading.self, from: data) {
            self.currentReading = reading
        }
        
        // Load readings log
        if let data = defaults.data(forKey: readingsKey),
           let loadedReadings = try? JSONDecoder().decode([GlucoseReading].self, from: data) {
            self.readings = loadedReadings
        }
        
        // Load session status — token + userId from Keychain, region from UserDefaults
        if let token = keychain.getString(forKey: KeychainStore.Keys.token),
           let userId = keychain.getString(forKey: KeychainStore.Keys.userId),
           let region = defaults.string(forKey: regionKey) {
            isSessionActive = true
            Task {
                await client.restoreSession(token: token, regionBaseURL: region, userId: userId)
            }
        }
        
        lastUpdated = defaults.object(forKey: "llu_last_updated") as? Date
    }
    
    private func saveLocalData() {
        // Save current reading
        if let currentReading = currentReading,
           let data = try? JSONEncoder().encode(currentReading) {
            defaults.set(data, forKey: currentReadingKey)
        } else {
            defaults.removeObject(forKey: currentReadingKey)
        }
        
        // Save readings history (limit to last 200 readings)
        let sortedReadings = readings.sorted(by: { $0.timestamp > $1.timestamp }).prefix(200)
        let readingsToSave = Array(sortedReadings)
        if let data = try? JSONEncoder().encode(readingsToSave) {
            defaults.set(data, forKey: readingsKey)
        }
        
        lastUpdated = Date()
        defaults.set(lastUpdated, forKey: "llu_last_updated")
        
        // Reload Widget Complications
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    // MARK: - Credentials & Auth

    /// Returns the email + password if both are available.
    /// Email comes from UserDefaults (not sensitive); password comes from Keychain.
    public var savedCredentials: [String: String]? {
        guard let email = defaults.string(forKey: emailKey),
              let password = keychain.getString(forKey: KeychainStore.Keys.password) else {
            return nil
        }
        return ["email": email, "password": password]
    }

    public func saveCredentials(email: String, password: String) {
        defaults.set(email, forKey: emailKey)
        keychain.setString(password, forKey: KeychainStore.Keys.password)
    }

    public func clearSession() {
        // Wipe sensitive items from Keychain
        keychain.deleteAll()

        // Wipe non-sensitive items from UserDefaults
        defaults.removeObject(forKey: emailKey)
        defaults.removeObject(forKey: regionKey)
        defaults.removeObject(forKey: currentReadingKey)
        defaults.removeObject(forKey: readingsKey)

        self.currentReading = nil
        self.readings = []
        self.isSessionActive = false
        self.lastUpdated = nil

        WidgetCenter.shared.reloadAllTimelines()
    }

    public func loginAndFetch(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let (token, regionURL, userId) = try await client.login(email: email, password: password)

            // Sensitive items → Keychain
            keychain.setString(token, forKey: KeychainStore.Keys.token)
            keychain.setString(userId, forKey: KeychainStore.Keys.userId)
            // Non-sensitive items → UserDefaults
            defaults.set(regionURL, forKey: regionKey)

            saveCredentials(email: email, password: password)
            isSessionActive = true

            // Initial data fetch
            try await refreshData()
        } catch {
            isSessionActive = false
            throw error
        }
    }
    
    // MARK: - Data Synchronization & Fetching
    
    public func refreshData() async throws {
        guard isSessionActive else {
            // Attempt to auto-login using saved credentials
            if let creds = savedCredentials,
               let email = creds["email"],
               let password = creds["password"] {
                try await loginAndFetch(email: email, password: password)
                return
            }
            throw LLUClientError.unauthenticated
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let connections = try await client.fetchConnections()
            guard let activeConnection = connections.first else {
                throw LLUClientError.requestFailed("No FreeStyle Libre patient connections found.")
            }

            // Fetch graph
            let graphPayload = try await client.fetchGlucoseGraph(patientId: activeConnection.patientId)

            // The API returns BOTH unit representations in every reading:
            //   - `Value` / `ValueInMgPerDl`
            // We pick which one to use based on the patient's country.
            // mg/dL is only used in the US; everywhere else is mmol/L.
            // No math conversion — both values come directly from the API.
            let useMgDl = (activeConnection.country?.uppercased() == "US")
            let uom = useMgDl ? 0 : 1

            // 1. Process recent historical points
            var newReadings: [GlucoseReading] = []
            for point in graphPayload.graphData {
                if let date = point.date {
                    let value = useMgDl ? point.ValueInMgPerDl : point.Value
                    let reading = GlucoseReading(value: value, timestamp: date, uom: uom, trend: .stable)
                    newReadings.append(reading)
                }
            }

            // 2. Process current measurement (has trend arrow)
            if let currentMeasure = graphPayload.connection.glucoseMeasurement, let date = currentMeasure.date {
                let value = useMgDl ? currentMeasure.valueInMgPerDl : currentMeasure.value
                let current = GlucoseReading(
                    value: value,
                    timestamp: date,
                    uom: uom,
                    trend: currentMeasure.trendArrowEnum
                )
                self.currentReading = current
                newReadings.append(current)
                
                #if os(iOS)
                // Write to HealthKit if enabled
                if useHealthKit {
                    writeToHealthKit(current)
                }
                #endif
            }
            
            // 3. Merge and deduplicate readings
            var allReadingsMap = [String: GlucoseReading]()
            // Map existing
            for reading in readings {
                let key = "\(reading.timestamp.timeIntervalSince1970)"
                allReadingsMap[key] = reading
            }
            // Map new
            for reading in newReadings {
                let key = "\(reading.timestamp.timeIntervalSince1970)"
                allReadingsMap[key] = reading
            }
            
            // Sort by descending timestamp
            self.readings = allReadingsMap.values.sorted(by: { $0.timestamp > $1.timestamp })
            
            saveLocalData()
            
            #if os(iOS)
            // Push data to Apple Watch
            syncToWatch()
            #endif
            
            syncMessage = "Last sync: \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
        } catch LLUClientError.unauthenticated {
            // Token expired. Try auto-relogin.
            if let creds = savedCredentials,
               let email = creds["email"],
               let password = creds["password"] {
                try await loginAndFetch(email: email, password: password)
            } else {
                clearSession()
                throw LLUClientError.unauthenticated
            }
        } catch {
            throw error
        }
    }
    
    // MARK: - Settings preferences
    
    public var useHealthKit: Bool {
        get { defaults.bool(forKey: useHealthKitKey) }
        set {
            defaults.set(newValue, forKey: useHealthKitKey)
            objectWillChange.send()
            #if os(iOS)
            if newValue {
                Task {
                    _ = try? await healthKitManager.requestAuthorization()
                }
            }
            #endif
        }
    }
    
    // MARK: - HealthKit Synchronization (iOS only)
    
    #if os(iOS)
    private func writeToHealthKit(_ reading: GlucoseReading) {
        Task {
            do {
                let isAuthorized = try await healthKitManager.requestAuthorization()
                if isAuthorized {
                    try await healthKitManager.writeGlucoseReading(
                        value: reading.value,
                        isMmolL: reading.isMmolL,
                        date: reading.timestamp
                    )
                }
            } catch {
                #if DEBUG
                print("Failed to save to HealthKit: \(error.localizedDescription)")
                #endif
            }
        }
    }
    #endif
    
    // MARK: - Watch Connectivity Setup & Management
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    #if os(iOS)
    public func syncToWatch() {
        guard WCSession.default.activationState == .activated else { return }
        
        var context: [String: Any] = [:]
        
        // 1. Send current reading
        if let current = currentReading,
           let data = try? JSONEncoder().encode(current) {
            context["currentReading"] = data
            
            // High-priority complication update
            if WCSession.default.isWatchAppInstalled {
                WCSession.default.transferCurrentComplicationUserInfo(["currentReading": data])
            }
        }
        
        // 2. Send last 20 readings history
        let recentReadings = Array(readings.prefix(20))
        if let data = try? JSONEncoder().encode(recentReadings) {
            context["recentReadings"] = data
        }
        
        // Credentials and the bearer token are NO LONGER sent over WCSession.
        // The watch reads them directly from the shared Keychain access group
        // (keychain-access-groups: $(AppIdentifierPrefix)com.rajnaidu.LibreGlucoseWatch.shared).
        // Removing them from the WC payload avoids plaintext PHI in the WC transport.

        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            #if DEBUG
            print("Failed to update Apple Watch application context: \(error.localizedDescription)")
            #endif
        }
    }
    #endif
}

// MARK: - WCSessionDelegate
extension GlucoseStore: WCSessionDelegate {
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        if activationState == .activated {
            Task { @MainActor in
                self.syncToWatch()
            }
        }
        #endif
    }
    
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate session
        WCSession.default.activate()
    }
    #endif
    
    // Handle foreground metadata / background context updates from WCSession
    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.processReceivedData(applicationContext)
        }
    }
    
    // Handle high-priority background complication updates
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.processReceivedData(userInfo)
        }
    }
    
    private func processReceivedData(_ data: [String: Any]) {
        var didChange = false
        
        // 1. Process current reading
        if let currentData = data["currentReading"] as? Data,
           let reading = try? JSONDecoder().decode(GlucoseReading.self, from: currentData) {
            self.currentReading = reading
            defaults.set(currentData, forKey: currentReadingKey)
            didChange = true
        }
        
        // 2. Process recent readings
        if let recentData = data["recentReadings"] as? Data,
           let loadedReadings = try? JSONDecoder().decode([GlucoseReading].self, from: recentData) {
            // Merge with local
            var merged = readings
            for newReading in loadedReadings {
                if !merged.contains(where: { $0.timestamp == newReading.timestamp }) {
                    merged.append(newReading)
                }
            }
            self.readings = merged.sorted(by: { $0.timestamp > $1.timestamp }).prefix(200).map { $0 }
            
            if let savedData = try? JSONEncoder().encode(self.readings) {
                defaults.set(savedData, forKey: readingsKey)
            }
            didChange = true
        }
        
        // Credentials and the session token are NOT received via WCSession anymore.
        // The watch reads them directly from the shared Keychain access group.
        // If a fresh session was just established on iPhone, the watch picks it
        // up on its next launch via loadLocalData().
        #if os(watchOS)
        if !isSessionActive,
           let token = keychain.getString(forKey: KeychainStore.Keys.token),
           let userId = keychain.getString(forKey: KeychainStore.Keys.userId),
           let region = defaults.string(forKey: regionKey) {
            isSessionActive = true
            Task {
                await client.restoreSession(token: token, regionBaseURL: region, userId: userId)
            }
        }
        #endif

        if didChange {
            lastUpdated = Date()
            defaults.set(lastUpdated, forKey: "llu_last_updated")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
