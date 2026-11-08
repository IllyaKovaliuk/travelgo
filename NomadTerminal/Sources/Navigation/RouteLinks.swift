import Foundation

/// Shareable link to a route: `https://nomad-legal.vercel.app/route/<id>`.
/// It's a universal link (`applinks:` entitlement + the site's
/// `.well-known/apple-app-site-association`): tapping it in Messages etc.
/// opens the app on that route when installed, otherwise a web page with the
/// route's name. The `io.nomadterminal.app://route/<id>` custom scheme (what
/// that page's "Open in Nomad" button uses) is accepted too.
enum RouteLinks {
    static let host = "nomad-legal.vercel.app"

    static func url(forRouteID id: String) -> URL {
        URL(string: "https://\(host)/route/\(id)")!
    }

    /// The route id in a shared link, or nil for any other URL (e.g. a GPX
    /// file handed over by Files, which `.onOpenURL` also receives).
    static func routeID(from url: URL) -> String? {
        let parts: [String]
        if url.scheme == "https", url.host == host {
            parts = url.pathComponents.filter { $0 != "/" }
        } else if url.scheme == "io.nomadterminal.app", url.host == "route" {
            parts = ["route"] + url.pathComponents.filter { $0 != "/" }
        } else {
            return nil
        }
        guard parts.count == 2, parts[0] == "route", UUID(uuidString: parts[1]) != nil else { return nil }
        return parts[1]
    }
}
