import Foundation

/// Manages GitHub authentication via Personal Access Token (PAT) or OAuth Device Flow.
///
/// Both methods store the resulting token in Keychain under "github_pat"
/// so GitSyncManager and LocalGitService work without changes.
@MainActor
final class GitHubAuthService: ObservableObject {
    static let shared = GitHubAuthService()

    // MARK: - Types

    enum AuthMethod: String {
        case none, pat, oauth
    }

    enum AuthState: Equatable {
        case signedOut
        case authenticating
        case deviceFlow(userCode: String, verificationURL: String)
        case authenticated
        case error(String)
    }

    // MARK: - Published State

    @Published var state: AuthState = .signedOut
    @Published var method: AuthMethod = .none
    @Published var username: String = ""
    @Published var avatarURL: String?

    // MARK: - Config

    /// GitHub OAuth App Client ID.
    /// Default is the LocalCoder OAuth App. Override via Settings or `setClientID(_:)`.
    private static let defaultClientID = "Ov23li66H2KVThVW5rsZ"

    private var clientID: String {
        let custom = UserDefaults.standard.string(forKey: "github_oauth_client_id") ?? ""
        return custom.isEmpty ? Self.defaultClientID : custom
    }

    var hasOAuthConfigured: Bool { !clientID.isEmpty }

    // MARK: - Internal

    private var deviceCode: String?
    private var userCode: String?
    private var verificationURL: String?
    private var pollingInterval: TimeInterval = 5
    private var pollingTask: Task<Void, Never>?
    private var networkRetries = 0
    private static let maxNetworkRetries = 30 // retry for ~2.5 min

    var isAuthenticated: Bool {
        if case .authenticated = state { return true }
        return false
    }

    /// The active token (PAT or OAuth) — used by GitSyncManager.
    var token: String {
        KeychainService.load(key: "github_pat") ?? ""
    }

    // MARK: - Init

    private init() {
        restoreSession()
    }

    // MARK: - Configuration

    func setClientID(_ id: String) {
        UserDefaults.standard.set(id, forKey: "github_oauth_client_id")
    }

    // MARK: - PAT Authentication

    func signInWithPAT(_ pat: String) async {
        state = .authenticating

        do {
            let user = try await fetchUser(token: pat)

            KeychainService.save(key: "github_pat", value: pat)
            UserDefaults.standard.set("pat", forKey: "github_auth_method")
            UserDefaults.standard.set(user.login, forKey: "github_username")
            if let avatar = user.avatarURL {
                UserDefaults.standard.set(avatar, forKey: "github_avatar_url")
            }

            username = user.login
            avatarURL = user.avatarURL
            method = .pat
            state = .authenticated
        } catch {
            state = .error("Invalid token: \(error.localizedDescription)")
        }
    }

    // MARK: - GitHub Device Flow OAuth

    func startDeviceFlow() async {
        guard hasOAuthConfigured else {
            state = .error("No OAuth Client ID configured. Set one in Settings → GitHub OAuth.")
            return
        }

        state = .authenticating

        do {
            let deviceAuth = try await requestDeviceCode()
            deviceCode = deviceAuth.deviceCode
            userCode = deviceAuth.userCode
            verificationURL = deviceAuth.verificationURI
            pollingInterval = TimeInterval(deviceAuth.interval)
            networkRetries = 0

            state = .deviceFlow(
                userCode: deviceAuth.userCode,
                verificationURL: deviceAuth.verificationURI
            )

            startPolling()
        } catch {
            state = .error("Failed to start sign-in: \(error.localizedDescription)")
        }
    }

    func cancelDeviceFlow() {
        pollingTask?.cancel()
        pollingTask = nil
        deviceCode = nil
        state = .signedOut
    }

    // MARK: - Sign Out

    func signOut() {
        pollingTask?.cancel()
        pollingTask = nil

        KeychainService.delete(key: "github_pat")
        UserDefaults.standard.removeObject(forKey: "github_auth_method")
        UserDefaults.standard.removeObject(forKey: "github_username")
        UserDefaults.standard.removeObject(forKey: "github_avatar_url")

        username = ""
        avatarURL = nil
        method = .none
        state = .signedOut
    }

    // MARK: - Session Restore

    private func restoreSession() {
        // Check for existing token in keychain
        guard !token.isEmpty else {
            state = .signedOut
            return
        }

        if let methodStr = UserDefaults.standard.string(forKey: "github_auth_method"),
           let stored = AuthMethod(rawValue: methodStr) {
            method = stored
        } else {
            // Legacy: token exists but no method recorded → assume PAT
            method = .pat
            UserDefaults.standard.set("pat", forKey: "github_auth_method")
        }

        username = UserDefaults.standard.string(forKey: "github_username") ?? ""
        avatarURL = UserDefaults.standard.string(forKey: "github_avatar_url")
        state = .authenticated
    }

    // MARK: - Device Flow API

    private struct DeviceCodeResponse {
        let deviceCode: String
        let userCode: String
        let verificationURI: String
        let expiresIn: Int
        let interval: Int
    }

    private struct GitHubUser {
        let login: String
        let avatarURL: String?
    }

    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "client_id=\(clientID)&scope=repo".data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let verificationURI = json["verification_uri"] as? String,
              let expiresIn = json["expires_in"] as? Int,
              let interval = json["interval"] as? Int else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error_description"] as? String {
                throw NSError(domain: "GitHubAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: error])
            }
            throw URLError(.badServerResponse)
        }

        return DeviceCodeResponse(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: verificationURI,
            expiresIn: expiresIn,
            interval: interval
        )
    }

    private func pollForToken() async throws -> String? {
        guard let deviceCode else { return nil }

        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }

        if let token = json["access_token"] as? String {
            return token
        }

        if let error = json["error"] as? String {
            switch error {
            case "authorization_pending":
                return nil
            case "slow_down":
                pollingInterval += 5
                return nil
            case "expired_token":
                throw NSError(domain: "GitHubAuth", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Authorization expired. Please try again."])
            case "access_denied":
                throw NSError(domain: "GitHubAuth", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Authorization denied."])
            default:
                let desc = json["error_description"] as? String ?? error
                throw NSError(domain: "GitHubAuth", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: desc])
            }
        }

        return nil
    }

    /// Resume polling when the app returns to foreground (e.g. after Safari auth).
    func resumePollingIfNeeded() {
        guard deviceCode != nil,
              let code = userCode,
              let url = verificationURL else { return }
        // Don't resume if already authenticated
        if case .authenticated = state { return }
        // Restore the device flow UI and restart polling
        state = .deviceFlow(userCode: code, verificationURL: url)
        networkRetries = 0
        startPolling()
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while true {
                guard let self else { return }

                // Sleep between polls — if cancelled (app backgrounded), just stop quietly
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
                } catch {
                    // CancellationError or similar — stop silently, keep deviceCode for resume
                    return
                }

                // Check cancellation again after sleep
                if Task.isCancelled { return }

                do {
                    if let accessToken = try await self.pollForToken() {
                        let user = try await self.fetchUser(token: accessToken)

                        KeychainService.save(key: "github_pat", value: accessToken)
                        UserDefaults.standard.set("oauth", forKey: "github_auth_method")
                        UserDefaults.standard.set(user.login, forKey: "github_username")
                        if let avatar = user.avatarURL {
                            UserDefaults.standard.set(avatar, forKey: "github_avatar_url")
                        }

                        self.username = user.login
                        self.avatarURL = user.avatarURL
                        self.method = .oauth
                        self.state = .authenticated
                        self.deviceCode = nil
                        self.userCode = nil
                        self.verificationURL = nil
                        self.networkRetries = 0
                        return
                    }
                    // Successful poll (pending) — reset network retry counter
                    self.networkRetries = 0
                } catch is CancellationError {
                    // App backgrounded during network call — stop quietly, keep state for resume
                    return
                } catch let error as URLError where error.code == .networkConnectionLost
                            || error.code == .notConnectedToInternet
                            || error.code == .timedOut
                            || error.code == .cannotConnectToHost
                            || error.code == .cancelled {
                    // Network error — retry silently
                    self.networkRetries += 1
                    if self.networkRetries >= Self.maxNetworkRetries {
                        self.state = .error("Network unavailable. Tap Sign In to retry.")
                        self.deviceCode = nil
                        return
                    }
                    continue
                } catch {
                    // Non-network error (expired, denied, etc.) — fail
                    self.state = .error(error.localizedDescription)
                    self.deviceCode = nil
                    return
                }
            }
        }
    }

    // MARK: - Fetch User Repos

    struct GitHubRepo: Identifiable, Hashable {
        let id: Int
        let fullName: String   // "owner/repo"
        let name: String       // "repo"
        let isPrivate: Bool
        let description: String?
        let updatedAt: String?
    }

    /// Fetches all repositories accessible to the authenticated user, paginated.
    func fetchUserRepos() async throws -> [GitHubRepo] {
        guard isAuthenticated, !token.isEmpty else { return [] }

        var allRepos: [GitHubRepo] = []
        var page = 1
        let perPage = 100

        while true {
            var request = URLRequest(url: URL(string: "https://api.github.com/user/repos?per_page=\(perPage)&page=\(page)&sort=updated&direction=desc&affiliation=owner,collaborator,organization_member")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw NSError(domain: "GitHubAuth", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to fetch repositories."])
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                break
            }

            if json.isEmpty { break }

            for repo in json {
                guard let id = repo["id"] as? Int,
                      let fullName = repo["full_name"] as? String,
                      let name = repo["name"] as? String else { continue }
                allRepos.append(GitHubRepo(
                    id: id,
                    fullName: fullName,
                    name: name,
                    isPrivate: repo["private"] as? Bool ?? false,
                    description: repo["description"] as? String,
                    updatedAt: repo["updated_at"] as? String
                ))
            }

            if json.count < perPage { break }
            page += 1
        }

        return allRepos
    }

    // MARK: - Create New Repository

    struct CreateRepoResult {
        let fullName: String   // "owner/repo"
        let cloneURL: String   // "https://github.com/owner/repo.git"
        let htmlURL: String    // "https://github.com/owner/repo"
    }

    /// Creates a new repository on GitHub for the authenticated user.
    func createRepo(name: String, description: String = "", isPrivate: Bool = true) async throws -> CreateRepoResult {
        guard isAuthenticated, !token.isEmpty else {
            throw NSError(domain: "GitHubAuth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated. Please sign in first."])
        }

        var request = URLRequest(url: URL(string: "https://api.github.com/user/repos")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": name,
            "description": description,
            "private": isPrivate,
            "auto_init": false  // We'll push our own initial commit
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 201 {
            // Success
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fullName = json["full_name"] as? String,
                  let cloneURL = json["clone_url"] as? String,
                  let htmlURL = json["html_url"] as? String else {
                throw URLError(.badServerResponse)
            }
            return CreateRepoResult(fullName: fullName, cloneURL: cloneURL, htmlURL: htmlURL)
        } else if http.statusCode == 422 {
            // Validation error (e.g., repo already exists)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let message = firstError["message"] as? String {
                throw NSError(domain: "GitHubAuth", code: 422,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "GitHubAuth", code: 422,
                          userInfo: [NSLocalizedDescriptionKey: "Repository name already exists or is invalid."])
        } else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                throw NSError(domain: "GitHubAuth", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "GitHubAuth", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create repository."])
        }
    }

    private func fetchUser(token: String) async throws -> GitHubUser {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "GitHubAuth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Authentication failed. Check your token."])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String else {
            throw URLError(.badServerResponse)
        }

        return GitHubUser(login: login, avatarURL: json["avatar_url"] as? String)
    }
}
