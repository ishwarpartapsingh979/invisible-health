import Foundation
import SwiftUI
import AuthenticationServices

/// Sign in with Apple + the single source of the per-user `user_id` for the app.
///
/// Multi-user (2026-07): every read/write is keyed by a stable `user_id`. The
/// hosted voice agent derives that id from the LiveKit participant identity the
/// app joins with — it strips a `-ios` suffix, so `"<user>-ios"` → `<user>`
/// (see `voice_agent.py:_user_id_from_identity`) — and the data tabs pass
/// `?user_id=` to the token server. This manager owns that id on the client:
///   - Sign in with Apple gives a STABLE, app-scoped `user` string (identical
///     across launches + reinstalls for the same Apple ID). We persist it and
///     use it as the `user_id`.
///   - `VoiceConfig.devUserIdOverride` wins if set — e.g. Ishwar keeps `"ishwar"`
///     (and his existing history) by setting it, without signing in.
///
/// NOTE for whoever builds this in Xcode: enable the **Sign in with Apple**
/// capability (Signing & Capabilities) so the provisioning profile carries the
/// `com.apple.developer.applesignin` entitlement (already added to the
/// `.entitlements` files). Without the capability the button errors at runtime.
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    /// The resolved per-user id. `nil` when nobody is signed in and no override
    /// is set → the app shows the sign-in gate. Persisted across launches.
    @Published private(set) var userId: String?
    /// Friendly name from the first Apple sign-in (Apple sends it only once).
    @Published private(set) var displayName: String?

    private let userIdKey = "auth.appleUserId"
    private let nameKey = "auth.displayName"

    private init() {
        // A configured dev override wins (continuity / single-user builds).
        if let override = VoiceConfig.devUserIdOverride, !override.isEmpty {
            userId = override
        } else {
            userId = UserDefaults.standard.string(forKey: userIdKey)
        }
        displayName = UserDefaults.standard.string(forKey: nameKey)
    }

    /// True once we have a usable `user_id` (signed in, or an override is set).
    var isSignedIn: Bool { userId != nil }

    /// Persist a successful Sign in with Apple credential and adopt its id.
    func completeSignIn(_ credential: ASAuthorizationAppleIDCredential) {
        // Apple's `user` is stable + app-scoped — the right thing to key on.
        let appleId = credential.user
        UserDefaults.standard.set(appleId, forKey: userIdKey)
        if let components = credential.fullName {
            let name = PersonNameComponentsFormatter().string(from: components)
            if !name.isEmpty {
                UserDefaults.standard.set(name, forKey: nameKey)
                displayName = name
            }
        }
        // A dev override still wins if configured; otherwise use the Apple id.
        if let override = VoiceConfig.devUserIdOverride, !override.isEmpty {
            userId = override
        } else {
            userId = appleId
        }
    }

    /// Re-check the stored Apple credential on launch; sign out if it was
    /// revoked in Settings. No-ops when running on an override.
    func refreshCredentialState() {
        guard VoiceConfig.devUserIdOverride == nil,
              let appleId = UserDefaults.standard.string(forKey: userIdKey) else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleId) { [weak self] state, _ in
            guard state == .revoked || state == .notFound else { return }
            DispatchQueue.main.async { self?.signOut() }
        }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        displayName = nil
        // Fall back to an override if one is set, else the sign-in gate.
        userId = (VoiceConfig.devUserIdOverride?.isEmpty == false) ? VoiceConfig.devUserIdOverride : nil
    }
}

/// The sign-in gate shown until there's a `user_id` (see `Invisible_HealthApp`).
/// Voice-first product, so this stays minimal — one button, then straight in.
struct SignInView: View {
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Text("Invisible Health")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text("Sign in so your coach knows it's you — your plans, history and rules stay yours.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                Spacer()
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    if case let .success(authorization) = result,
                       let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                        AuthManager.shared.completeSignIn(credential)
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .padding(.horizontal, 36)
                .padding(.bottom, 44)
            }
        }
    }
}
