import Foundation

enum SecurityPolicy {
    static let defaultReelsURL = "https://www.instagram.com/reels/"
    static func instagram(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, url.port == nil,
              let host=url.host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
    }
    static func chat(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil && url.port == nil &&
            ["chatgpt.com","chat.openai.com"].contains(url.host?.lowercased() ?? "")
    }
    static func savedReelsURL(_ text: String) -> String? {
        guard var parts=URLComponents(string:text.trimmingCharacters(in:.whitespacesAndNewlines)),
              let url=parts.url, instagram(url), ["instagram.com","www.instagram.com"].contains(url.host?.lowercased() ?? ""),
              parts.path == "/reels" || parts.path.hasPrefix("/reels/") || parts.path.hasPrefix("/reel/") else { return nil }
        // Login links, redirect parameters and URL fragments never enter preferences.
        parts.query=nil; parts.fragment=nil
        return parts.url?.absoluteString
    }
    static func metadataAllowed(role: String, pressable: Bool = false) -> Bool {
        role == "AXButton" || (pressable && ["AXGroup","AXImage","AXUnknown"].contains(role))
    }
    static func childContentAllowed(role: String) -> Bool {
        !["AXStaticText","AXLink","AXTextArea","AXTextField","AXTextEntryArea","AXSecureTextField"].contains(role)
    }
}
