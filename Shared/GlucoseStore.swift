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

    /// Human-readable message describing the most recent sync failure, or nil
    /// when the last sync succeeded. The dashboard surfaces this in red so the
    /// user never silently looks at stale glucose data assuming it's current.
    @Published var lastSyncError: String? = nil
    
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
    private let tokenExpiresKey = "llu_token_expires" // Unix epoch seconds — token metadata, not secret

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
        defaults.removeObject(forKey: tokenExpiresKey)
        defaults.removeObject(forKey: currentReadingKey)
        defaults.removeObject(forKey: readingsKey)

        self.currentReading = nil
        self.readings = []
        self.isSessionActive = false
        self.lastUpdated = nil
        self.lastSyncError = nil
        self.syncMessage = ""

        WidgetCenter.shared.reloadAllTimelines()
    }

    public func loginAndFetch(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let (token, regionURL, userId, expires) = try await client.login(email: email, password: password)

            // Sensitive items → Keychain
            keychain.setString(token, forKey: KeychainStore.Keys.token)
            keychain.setString(userId, forKey: KeychainStore.Keys.userId)
            // Non-sensitive items → UserDefaults
            defaults.set(regionURL, forKey: regionKey)
            defaults.set(expires, forKey: tokenExpiresKey)

            saveCredentials(email: email, password: password)
            isSessionActive = true

            // Initial data fetch
            try await refreshData()
        } catch {
            isSessionActive = false
            throw error
        }
    }

    /// Returns true if the stored bearer token expires within the next 60 seconds
    /// (or has already expired). Used to trigger a proactive re-login before
    /// hitting the API with a soon-to-be-invalid token.
    /// Returns false if no expiry is stored — the caller will fall back to the
    /// reactive 401 handling.
    private var tokenIsExpiringSoon: Bool {
        let expires = defaults.integer(forKey: tokenExpiresKey)
        guard expires > 0 else { return false }
        let now = Int(Date().timeIntervalSince1970)
        return expires - now < 60
    }
    
    // MARK: - Data Synchronization & Fetching
    
    public func refreshData() async throws {
        guard isSessionActive else {
            // Attempt to auto-login using saved credentials
            if let creds = savedCredentials,
               let email = creds["email"],
               let password = creds["password"] {
                do {
                    try await loginAndFetch(email: email, password: password)
                    return
                } catch {
                    lastSyncError = "Login failed: \(error.localizedDescription)"
                    throw error
                }
            }
            lastSyncError = "Not signed in"
            throw LLUClientError.unauthenticated
        }

        // Proactive token refresh: if the bearer token is expiring soon (or has
        // already expired), re-login BEFORE making the request. Avoids the
        // 401 round-trip and ensures we never display stale data because of an
        // expired token.
        if tokenIsExpiringSoon,
           let creds = savedCredentials,
           let email = creds["email"],
           let password = creds["password"] {
            do {
                try await loginAndFetch(email: email, password: password)
                return  // loginAndFetch already refreshed glucose data
            } catch {
                lastSyncError = "Session expired and re-login failed: \(error.localizedDescription)"
                throw error
            }
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
            // Clear any prior error — this sync succeeded.
            lastSyncError = nil
        } catch LLUClientError.unauthenticated {
            // Token expired or server rejected it. Try auto-relogin.
            if let creds = savedCredentials,
               let email = creds["email"],
               let password = creds["password"] {
                do {
                    try await loginAndFetch(email: email, password: password)
                } catch {
                    lastSyncError = "Session expired and re-login failed: \(error.localizedDescription)"
                    throw error
                }
            } else {
                lastSyncError = "Session expired — please sign in again"
                clearSession()
                throw LLUClientError.unauthenticated
            }
        } catch {
            lastSyncError = "Sync failed: \(error.localizedDescription)"
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
        
        // Send session metadata so the Watch can restore its own authenticated session.
        // WCSession is encrypted between the paired devices. We include non-sensitive
        // fields (email, region) and the bearer token + userId so the watch app can
        // perform API calls directly without requiring the iPhone to be present.
        if let email = defaults.string(forKey: emailKey) {
            context["email"] = email
        }
        if let region = defaults.string(forKey: regionKey) {
            context["region"] = region
        }
        if let token = keychain.getString(forKey: KeychainStore.Keys.token) {
            context["token"] = token
        }
        if let userId = keychain.getString(forKey: KeychainStore.Keys.userId) {
            context["userId"] = userId
        }
        let expires = defaults.integer(forKey: tokenExpiresKey)
        if expires > 0 {
            context["tokenExpires"] = expires
        }

        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            #if DEBUG
            print("Failed to update Apple Watch application context: \(error.localizedDescription)")
            #endif
        }
        // Also try immediate delivery if the session is reachable; otherwise enqueue background transfer.
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(context, replyHandler: nil) { error in
                #if DEBUG
                print("sendMessage to Watch failed: \(error.localizedDescription)")
                #endif
            }
        } else {
            WCSession.default.transferUserInfo(context)
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
        #elseif os(watchOS)
        if activationState == .activated {
            // Apply any pre-existing context immediately
            let ctx = session.receivedApplicationContext
            if !ctx.isEmpty {
                self.processReceivedData(ctx)
            }
            // If we still don't have an authenticated session, ask the phone to sync now.
            if !self.isSessionActive && session.isReachable {
                session.sendMessage(["request": "sync"], replyHandler: nil, errorHandler: nil)
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
    
    #if os(iOS)
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        if let request = message["request"] as? String, request == "sync" {
            self.syncToWatch()
            replyHandler(["status": "ok"])
        } else {
            replyHandler(["status": "ignored"])
        }
    }
    #endif
    
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
        
        #if os(watchOS)
        // Mirror non-sensitive metadata
        if let email = data["email"] as? String {
            defaults.set(email, forKey: emailKey)
        }
        if let region = data["region"] as? String {
            defaults.set(region, forKey: regionKey)
        }
        // Persist sensitive session fields on the Watch's own Keychain
        if let token = data["token"] as? String, !token.isEmpty {
            keychain.setString(token, forKey: KeychainStore.Keys.token)
        }
        if let userId = data["userId"] as? String, !userId.isEmpty {
            keychain.setString(userId, forKey: KeychainStore.Keys.userId)
        }
        if let expires = data["tokenExpires"] as? Int {
            defaults.set(expires, forKey: tokenExpiresKey)
        }
        // Try to restore session if we now have everything needed.
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
