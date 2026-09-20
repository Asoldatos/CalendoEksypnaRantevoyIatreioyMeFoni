import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct GoogleCalendar: Identifiable, Codable, Hashable {
    let id: String
    let summary: String
    let primary: Bool
}

struct AIAppointmentResult: Decodable {
    let patientName: String
    let dateISO: String
    let time: String
    let durationMinutes: Int
    let confidence: Double
}

enum GoogleServiceError: LocalizedError {
    case notConnected, noPresentationAnchor, invalidCallback, tokenExchange, requestFailed, authorizationExpired

    var errorDescription: String? {
        switch self {
        case .notConnected: "Συνδεθείτε πρώτα με τον Google λογαριασμό σας."
        case .noPresentationAnchor: "Δεν βρέθηκε παράθυρο για τη σύνδεση Google."
        case .invalidCallback: "Η σύνδεση Google δεν ολοκληρώθηκε."
        case .tokenExchange: "Δεν ήταν δυνατή η επιβεβαίωση σύνδεσης Google."
        case .requestFailed: "Η υπηρεσία Google δεν απάντησε."
        case .authorizationExpired: "Η σύνδεση Google έληξε. Συνδεθείτε ξανά."
        }
    }
}

@MainActor
final class GoogleSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let clientID = "718756612878-vgbmspg71o536u77bg42k3rkolm4gfnb.apps.googleusercontent.com"
    static let redirectScheme = "com.googleusercontent.apps.718756612878-vgbmspg71o536u77bg42k3rkolm4gfnb"
    private enum Key { static let access = "calendo.google.accessToken"; static let refresh = "calendo.google.refreshToken"; static let expiresAt = "calendo.google.expiresAt" }
    private var session: ASWebAuthenticationSession?

    var accessToken: String? { KeychainStore.string(for: Key.access) }
    var isConnected: Bool { accessToken != nil }

    func signIn() async throws {
        let verifier = Self.randomURLSafeString()
        let state = Self.randomURLSafeString()
        let challenge = Self.challenge(for: verifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.calendarlist.readonly"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent select_account")
        ]
        guard let url = components.url else { throw GoogleServiceError.invalidCallback }
        let callback = try await authorize(url: url)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw GoogleServiceError.invalidCallback }
        let result = try await exchangeToken(parameters: [
            "client_id": Self.clientID, "code": code, "code_verifier": verifier,
            "grant_type": "authorization_code", "redirect_uri": Self.redirectURI
        ])
        try save(result)
    }

    func validAccessToken() async throws -> String {
        if let expiresAt = UserDefaults.standard.object(forKey: Key.expiresAt) as? Date, expiresAt <= .now.addingTimeInterval(60) {
            guard try await refreshAccessToken() else { throw GoogleServiceError.authorizationExpired }
        }
        return try token()
    }

    func calendars() async throws -> [GoogleCalendar] {
        let data = try await authorizedData(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)
        let response = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        return response.items.map { GoogleCalendar(id: $0.id, summary: $0.summary ?? "Ημερολόγιο", primary: $0.primary ?? false) }
    }

    func createEvent(_ draft: AppointmentDraft, calendarID: String) async throws {
        guard let safeCalendarID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(safeCalendarID)/events") else { throw GoogleServiceError.requestFailed }
        let payload: [String: Any] = [
            "summary": draft.calendarTitle,
            "start": ["dateTime": CalendarEventDateFormatter.string(from: draft.startDate), "timeZone": "Europe/Athens"],
            "end": ["dateTime": CalendarEventDateFormatter.string(from: draft.endDate), "timeZone": "Europe/Athens"]
        ]
        _ = try await authorizedData(url: url, method: "POST", body: try JSONSerialization.data(withJSONObject: payload), expectedStatus: 200)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    private func authorizedData(url: URL, method: String = "GET", body: Data? = nil, expectedStatus: Int = 200) async throws -> Data {
        var didRefresh = false
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == expectedStatus { return data }
            if status == 401, !didRefresh, try await refreshAccessToken() {
                didRefresh = true
                continue
            }
            if status == 401 { throw GoogleServiceError.authorizationExpired }
            throw GoogleServiceError.requestFailed
        }
    }

    private func refreshAccessToken() async throws -> Bool {
        guard let refresh = KeychainStore.string(for: Key.refresh) else { return false }
        let result = try await exchangeToken(parameters: ["client_id": Self.clientID, "refresh_token": refresh, "grant_type": "refresh_token"])
        try save(result, preservingRefreshToken: refresh)
        return true
    }

    private func exchangeToken(parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.map { "\($0.key)=\($0.value.urlFormEncoded)" }.sorted().joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(TokenResponse.self, from: data) else { throw GoogleServiceError.tokenExchange }
        return result
    }

    private func save(_ response: TokenResponse, preservingRefreshToken: String? = nil) throws {
        try KeychainStore.save(response.accessToken, for: Key.access)
        UserDefaults.standard.set(Date.now.addingTimeInterval(TimeInterval(response.expiresIn ?? 3_000)), forKey: Key.expiresAt)
        if let refresh = response.refreshToken ?? preservingRefreshToken { try KeychainStore.save(refresh, for: Key.refresh) }
    }

    private func authorize(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let newSession = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.redirectScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? GoogleServiceError.invalidCallback) }
            }
            newSession.presentationContextProvider = self
            newSession.prefersEphemeralWebBrowserSession = false
            session = newSession
            newSession.start()
        }
    }

    private func token() throws -> String { guard let accessToken else { throw GoogleServiceError.notConnected }; return accessToken }
    private static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }
    private static func randomURLSafeString() -> String { Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString().base64URLSafe }
    private static func challenge(for verifier: String) -> String { Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().base64URLSafe }
}

struct GeminiAppointmentService {
    func analyze(audioURL: URL, token: String) async throws -> AIAppointmentResult {
        let audio = try Data(contentsOf: audioURL)
        let mime = audioURL.pathExtension.lowercased() == "m4a" ? "audio/mp4" : "audio/m4a"
        var request = URLRequest(url: URL(string: "https://cbmjymirgxevmyzyedqr.supabase.co/functions/v1/process-appointment-audio")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "audioBase64": audio.base64EncodedString(), "mimeType": mime,
            "referenceDate": AthensDateFormatter.dateString(from: .now)
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw GoogleServiceError.requestFailed }
        return try JSONDecoder().decode(AIAppointmentResult.self, from: data)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case refreshToken = "refresh_token"; case expiresIn = "expires_in" }
}
private struct CalendarListResponse: Decodable { let items: [CalendarItem] }
private struct CalendarItem: Decodable { let id: String; let summary: String?; let primary: Bool? }

private enum AthensDateFormatter {
    static func dateString(from date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Europe/Athens"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
private enum CalendarEventDateFormatter {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Europe/Athens"); formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return formatter.string(from: date)
    }
}
private extension String {
    var base64URLSafe: String { replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    var urlFormEncoded: String { addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self }
}

enum KeychainStore {
    static func string(for key: String) -> String? {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key, kSecReturnData: true] as CFDictionary
        var result: AnyObject?; guard SecItemCopyMatching(query, &result) == errSecSuccess, let data = result as? Data else { return nil }; return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8); SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary)
        let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key, kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary, nil)
        guard status == errSecSuccess else { throw GoogleServiceError.tokenExchange }
    }
}
