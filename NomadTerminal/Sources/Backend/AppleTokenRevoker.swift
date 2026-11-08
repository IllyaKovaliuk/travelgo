import Foundation
import Supabase

/// Client side of the `apple-revoke` edge function (see
/// `backend/supabase/functions/apple-revoke`). Sign in with Apple requires
/// the app to revoke the user's Apple token when their account is deleted
/// (App Review 5.1.1(v)). Both calls are best effort: a failure must never
/// block sign-in or, more importantly, account deletion.
enum AppleTokenRevoker {
    private struct Body: Encodable {
        let action: String
        var authorizationCode: String?
    }

    static func store(authorizationCode: String) async {
        _ = try? await supabase.functions.invoke(
            "apple-revoke",
            options: .init(body: Body(action: "store", authorizationCode: authorizationCode))
        )
    }

    static func revoke() async {
        _ = try? await supabase.functions.invoke(
            "apple-revoke",
            options: .init(body: Body(action: "revoke"))
        )
    }
}
