import Foundation

/// The Google account that signed in last on this device.
///
/// The sign-in screen uses it to offer "Sign in as <name>" instead of a bare
/// "Sign in with Google", mirroring the personalised button the web dashboard gets
/// from Google Identity Services. It is deliberately NOT the Google session: a
/// native app cannot see that. It is only what this app itself saw at the last
/// successful Google sign-in, so it survives signing out (as Google's own button
/// does) and is cleared explicitly via "Use another account".
struct RememberedGoogleUser: Codable, Equatable {
    var firstName: String
    var lastName: String
    var email: String
    var avatar: String?

    var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? email : full
    }

    init(firstName: String, lastName: String, email: String, avatar: String?) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.avatar = avatar
    }

    /// Only Google accounts qualify — an emailed-code shareholder must not be offered
    /// a Google button that would send them down a path their account can't take.
    init?(user: User) {
        guard user.authProvider == "google" else { return nil }
        self.init(firstName: user.firstName, lastName: user.lastName,
                  email: user.email, avatar: user.avatar)
    }

    static func load() -> RememberedGoogleUser? {
        guard let raw = Keychain.load(account: Keychain.lastGoogleUserAccount),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RememberedGoogleUser.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self),
              let raw = String(data: data, encoding: .utf8) else { return }
        Keychain.save(raw, account: Keychain.lastGoogleUserAccount)
    }

    static func forget() { Keychain.clear(account: Keychain.lastGoogleUserAccount) }
}
