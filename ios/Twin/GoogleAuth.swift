import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

// Native Google Sign-In, shared by the sign-in screen (real accounts) and Account > Connect Google.

enum GoogleAuth {
    /// Calendar and Gmail are asked for up front so signing in also connects them.
    static let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/gmail.readonly"
    ]

    struct Credentials {
        let idToken: String
        /// Lets the server read Calendar and Gmail. Nil if Google left it out.
        let serverAuthCode: String?
    }

    static func signIn() async throws -> Credentials {
        #if canImport(GoogleSignIn)
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        let serverClientID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String ?? ""
        guard !clientID.isEmpty, !serverClientID.isEmpty else {
            throw APIError.notConfigured("Google sign-in isn't set up in this build. Add GOOGLE_IOS_CLIENT_ID, GOOGLE_WEB_CLIENT_ID, and GOOGLE_WEB_CLIENT_SECRET to server/.env (see README), run make google-check, then rebuild with make sim or make phone.")
        }
        guard let presenter = topViewController() else {
            throw APIError.notConfigured("Could not find a screen to show Google sign-in on.")
        }
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: scopes
        )
        guard let idToken = result.user.idToken?.tokenString else {
            throw APIError.notConfigured("Google did not return an ID token.")
        }
        let code = result.serverAuthCode.flatMap { $0.isEmpty ? nil : $0 }
        return Credentials(idToken: idToken, serverAuthCode: code)
        #else
        throw APIError.notConfigured("Add the GoogleSignIn package first: File > Add Package Dependencies > https://github.com/google/GoogleSignIn-iOS (product GoogleSignIn).")
        #endif
    }

    static func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
    }

    /// True when the person backed out of Google's sheet, which is not worth an error message.
    static func isCancel(_ error: Error) -> Bool {
        #if canImport(GoogleSignIn)
        let nsError = error as NSError
        return nsError.domain == kGIDSignInErrorDomain && nsError.code == GIDSignInError.canceled.rawValue
        #else
        return false
        #endif
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
