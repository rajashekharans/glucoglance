import Foundation
import CryptoKit

public enum LLUClientError: Error, LocalizedError {
    case invalidURL
    case loginFailed(String)
    case unauthenticated
    case requestFailed(String)
    case invalidResponse
    case serializationError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The API URL was invalid."
        case .loginFailed(let msg):
            return "Login failed: \(msg)"
        case .unauthenticated:
            return "Not logged in or session expired."
        case .requestFailed(let msg):
            return "Network request failed: \(msg)"
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .serializationError(let err):
            return "Failed to parse data: \(err.localizedDescription)"
        }
    }
}

public actor LibreLinkUpClient {
    private let globalBaseURL = "https://api.libreview.io"
    private var activeBaseURL: String = "https://api.libreview.io"
    
    private var token: String? = nil
    private var userId: String? = nil
    private var accountIdHash: String? = nil
    
    private let productHeader = "llu.ios"
    private let versionHeader = "4.16.0"
    
        private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    public init() {}
    
    // Calculates SHA256 of the User ID as required for the Account-Id header in 4.11+ APIs
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // Helper to perform HTTP Requests
    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String,
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
        guard let url = URL(string: "\(activeBaseURL)\(endpoint)") else {
            throw LLUClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        
        // Default Headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(productHeader, forHTTPHeaderField: "product")
        request.setValue(versionHeader, forHTTPHeaderField: "version")
        
        // Authorization & Custom Headers
        if let token = self.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let accountId = self.accountIdHash {
            request.setValue(accountId, forHTTPHeaderField: "Account-Id")
        }
        
        // Additional Custom Headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await self.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLUClientError.invalidResponse
        }

        // Parse HTTP Status code
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw LLUClientError.unauthenticated
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Status code \(httpResponse.statusCode)"
            throw LLUClientError.requestFailed(errorMsg)
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            throw LLUClientError.serializationError(error)
        }
    }
    
    /// Authenticates with LibreLinkUp. Handles regional redirects automatically.
    public func login(email: String, password: String) async throws -> (token: String, regionBaseURL: String, userId: String) {
        // Reset base URL to global for initial login attempt
        self.activeBaseURL = globalBaseURL
        self.token = nil
        self.userId = nil
        self.accountIdHash = nil
        
        let bodyDict = ["email": email, "password": password]
        let bodyData = try? JSONSerialization.data(withJSONObject: bodyDict)
        
        // 1. Initial login attempt (Global Endpoint)
        let loginResponse: LibreLinkUpLoginResponse = try await performRequest(
            endpoint: "/llu/auth/login",
            method: "POST",
            body: bodyData
        )
        
        guard loginResponse.status == 0 else {
            throw LLUClientError.loginFailed(loginResponse.error?.message ?? "Unknown error code \(loginResponse.status)")
        }
        
        // 2. Check for regional redirect
        if let redirect = loginResponse.data?.redirect, redirect, let region = loginResponse.data?.region {
            // Update base URL to the regional subdomain
            self.activeBaseURL = "https://api-\(region).libreview.io"
            
            // Retry login against the regional endpoint
            let regionalResponse: LibreLinkUpLoginResponse = try await performRequest(
                endpoint: "/llu/auth/login",
                method: "POST",
                body: bodyData
            )
            
            guard regionalResponse.status == 0 else {
                throw LLUClientError.loginFailed(regionalResponse.error?.message ?? "Regional login failed.")
            }
            
            return try processLoginPayload(regionalResponse)
        } else {
            return try processLoginPayload(loginResponse)
        }
    }
    
        private func extractRegion(from jwt: String) -> String? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count > 1 else { return nil }
        let payloadPart = parts[1]
        
        // Convert base64url to base64
        var base64 = payloadPart
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding
        let paddingLength = 4 - (base64.count % 4)
        if paddingLength < 4 {
            base64.append(String(repeating: "=", count: paddingLength))
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let region = json["region"] as? String else {
            return nil
        }
        
        return region.lowercased()
    }
    
    private func processLoginPayload(_ response: LibreLinkUpLoginResponse) throws -> (token: String, regionBaseURL: String, userId: String) {
        // No diagnostic logging here — the previous version printed the JWT token
        // prefix, user id, and detected region, all of which are sensitive PHI/PII
        // when surfaced via sysdiagnose or Console.app.

        guard let data = response.data,
              let ticket = data.authTicket,
              let user = data.user else {
            throw LLUClientError.invalidResponse
        }

        self.token = ticket.token
        self.userId = user.id
        self.accountIdHash = sha256(user.id)

        // Dynamically detect region from the JWT token and update activeBaseURL
        if let detectedRegion = extractRegion(from: ticket.token) {
            let regionalURL = "https://api-\(detectedRegion).libreview.io"
            if self.activeBaseURL != regionalURL {
                self.activeBaseURL = regionalURL
            }
        }

        return (ticket.token, self.activeBaseURL, user.id)
    }
    
    /// Restores a previously saved authenticated session
    public func restoreSession(token: String, regionBaseURL: String, userId: String) {
        self.token = token
        self.activeBaseURL = regionBaseURL
        self.userId = userId
        self.accountIdHash = sha256(userId)
    }
    
    /// Fetches all active caregiver-sharing connections
    public func fetchConnections() async throws -> [LLUConnection] {
        guard token != nil else { throw LLUClientError.unauthenticated }
        
        let response: LibreLinkUpConnectionResponse = try await performRequest(
            endpoint: "/llu/connections",
            method: "GET"
        )
        
        guard response.status == 0, let connections = response.data else {
            throw LLUClientError.requestFailed("Failed to fetch connections. Status \(response.status)")
        }
        
        return connections
    }
    
    /// Fetches detailed glucose readings (graph and current) for a specific patient ID
    public func fetchGlucoseGraph(patientId: String) async throws -> GraphDataPayload {
        guard token != nil else { throw LLUClientError.unauthenticated }
        
        let response: LibreLinkUpGraphResponse = try await performRequest(
            endpoint: "/llu/connections/\(patientId)/graph",
            method: "GET"
        )
        
        guard response.status == 0, let payload = response.data else {
            throw LLUClientError.requestFailed("Failed to fetch graph data. Status \(response.status)")
        }
        
        return payload
    }
}
