import Foundation

/// Shareable crew invite: `https://nomad-legal.vercel.app/crew/<code>`.
/// Same universal-link host as `RouteLinks` (the `applinks:` entitlement and
/// the site's `apple-app-site-association` cover `/crew/*`); the code is the
/// invite code minted by `create_crew_invite`. The `io.nomadterminal.app://crew/<code>`
/// custom scheme (what the web page's "Open in Nomad" button uses) works too.
enum CrewLinks {
    static func url(forInviteCode code: String) -> URL {
        URL(string: "https://\(RouteLinks.host)/crew/\(code)")!
    }

    /// Letters and digits only — what `create_crew_invite` produces — so a
    /// pasted or linked value can never smuggle anything else into an RPC.
    static func isValidCode(_ s: String) -> Bool {
        (6...64).contains(s.count) && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// The invite code in a link, or nil for any other URL.
    static func inviteCode(from url: URL) -> String? {
        let parts: [String]
        if url.scheme == "https", url.host == RouteLinks.host {
            parts = url.pathComponents.filter { $0 != "/" }
        } else if url.scheme == "io.nomadterminal.app", url.host == "crew" {
            parts = ["crew"] + url.pathComponents.filter { $0 != "/" }
        } else {
            return nil
        }
        guard parts.count == 2, parts[0] == "crew", isValidCode(parts[1]) else { return nil }
        return parts[1]
    }

    /// For the "Join with a code" field: accepts either the bare code or the
    /// whole invite link pasted from a message.
    static func inviteCode(fromText text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: t), let code = inviteCode(from: url) { return code }
        return isValidCode(t) ? t : nil
    }
}
