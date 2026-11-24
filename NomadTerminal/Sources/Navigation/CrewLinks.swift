import Foundation

/// Shareable crew invite: `https://nomad-legal.vercel.app/crew/<code>`.
/// Same universal-link host as `RouteLinks`; the code is the invite code
/// minted by `create_crew_invite`.
enum CrewLinks {
    static func url(forInviteCode code: String) -> URL {
        URL(string: "https://\(RouteLinks.host)/crew/\(code)")!
    }
}
