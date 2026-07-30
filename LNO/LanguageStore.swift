import SwiftUI

/// Owns the app's current display language. Mirrors `AuthStore`'s pattern: a
/// small `ObservableObject` injected once at the app root. Resolution order on
/// first launch matches the web dashboard's `detectBrowserLang()` fallback chain
/// (main.tsx): signed-in user's server-side choice > locally persisted choice >
/// device locale > English.
@MainActor
final class LanguageStore: ObservableObject {
    @Published private(set) var lang: Lang

    init() {
        #if DEBUG
        // Test hook, same shape as -LNODemo / -LNOTab:
        //   xcrun simctl launch <device> company.lno.controlcenter -LNOLang fr
        // Writes through LanguagePersistence so the App Group copy is set too — which is what
        // the widget extension and the Live Activity actually read. Setting the preference
        // from outside the app (defaults write) does NOT reach that container.
        if let raw = UserDefaults.standard.string(forKey: "LNOLang"), let forced = Lang(rawValue: raw) {
            LanguagePersistence.save(forced)
            lang = forced
            return
        }
        #endif
        lang = LanguagePersistence.load() ?? Lang.detectDeviceLanguage()
    }

    /// Call once `AuthStore.user` becomes non-nil (or changes). Mirrors main.tsx's
    /// `useEffect` at ~line 272: once logged in, if the server has an explicit
    /// language set and it disagrees with what we're showing locally, the server
    /// value wins — so a choice made on the web dashboard shows up here too.
    func syncFromServer(_ user: User?) {
        guard let raw = user?.language, let serverLang = Lang(rawValue: raw), serverLang != lang else { return }
        apply(serverLang)
    }

    /// User picked a language in Settings. Applies immediately (no relaunch),
    /// persists locally so it survives offline/relaunch, and — if signed into a
    /// real (non-demo) account — pushes it to the server so it becomes the
    /// shared default other clients (the web dashboard) pick up too.
    func setLang(_ new: Lang, auth: AuthStore) {
        guard new != lang else { return }
        apply(new)
        guard auth.phase == .signedIn, !auth.isDemo else { return }
        Task {
            do {
                let updated = try await auth.client.updateLanguage(new.rawValue)
                auth.user = updated
            } catch {
                // Best-effort: the local choice already applied; the next
                // successful session/profile round-trip will retry the sync.
            }
        }
    }

    private func apply(_ new: Lang) {
        lang = new
        LanguagePersistence.save(new)
    }
}
