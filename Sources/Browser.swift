import AppKit
import ApplicationServices

enum Browser: String, CaseIterable, Codable {
    case chrome = "Google Chrome", safari = "Safari"
    var bundleID: String { self == .chrome ? "com.google.Chrome" : "com.apple.Safari" }
}
struct TabRef { let window: Int; let tab: Int; let url: String; let title: String; var token: String? = nil }
struct OwnedWindow { let browser: Browser; let window: Int; let tab: Int; let pid: pid_t; let launch: Date? }
enum Signal: String { case busy, idle, unknown }
struct Observation { let signal: Signal; let method: String }
struct AppFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

protocol BrowserService: AnyObject {
    func front(_ b: Browser) throws -> TabRef?
    func observe(_ b: Browser, _ t: TabRef, axOnly: Bool) -> Observation
    func mark(_ b: Browser, _ t: TabRef) -> TabRef
    func open(_ b: Browser, url: String) throws -> OwnedWindow
    func close(_ owned: OwnedWindow) throws -> String?
    func prepareReels(_ owned: OwnedWindow)
    func preparePiP(_ owned: OwnedWindow) -> String
    func tuckAway(_ owned: OwnedWindow)
    func restore(_ b: Browser, _ t: TabRef) throws
    func accessibility(_ b: Browser, _ t: TabRef) -> Signal
}
extension BrowserService { func prepareReels(_ owned: OwnedWindow) {}; func preparePiP(_ owned: OwnedWindow) -> String { "loading" }; func tuckAway(_ owned: OwnedWindow) {} }
final class BrowserBridge: BrowserService {
    private var axAreas: [String: AXUIElement] = [:]
    private var autoplayUnavailable: Set<String> = []
    // No shell interpolation: all user strings are AppleScript string literals.
    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
    func run(_ browser: Browser, _ body: String) throws -> NSAppleEventDescriptor {
        let source = "with timeout of 5 seconds\ntell application \(Self.quote(browser.rawValue))\n\(body)\nend tell\nend timeout"
        guard let executable = Bundle.main.url(forAuxiliaryExecutable:"ScriptRunner") else { throw AppFailure(message:"Нет ScriptRunner") }
        let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = executable
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        try process.run()
        // Prompt/compilation may outlast an AppleScript event timeout. Bound the whole helper.
        DispatchQueue.global().asyncAfter(deadline:.now()+12) {
            if process.isRunning { process.terminate() }
        }
        try input.fileHandleForWriting.write(contentsOf:Data(source.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let object = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw AppFailure(message:"Не удалось прочитать ScriptRunner") }
        if object["error"] != nil { throw AppFailure(message:"AppleScript: ошибка управления браузером, код \(object["code"] as? Int ?? -1)") }
        guard let result = object["result"] as? [String:Any] else { throw AppFailure(message:"ScriptRunner: timeout или нет ответа") }
        return Self.decode(result)
    }
    static func decode(_ object: [String:Any]) -> NSAppleEventDescriptor {
        switch object["kind"] as? String {
        case "list":
            let list = NSAppleEventDescriptor.list()
            for (i,value) in ((object["value"] as? [[String:Any]]) ?? []).enumerated() { list.insert(decode(value),at:i+1) }
            return list
        case "integer": return NSAppleEventDescriptor(int32:Int32((object["value"] as? Int) ?? 0))
        default: return NSAppleEventDescriptor(string:(object["value"] as? String) ?? "")
        }
    }
    func app(_ browser: Browser) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first
    }
    static func isChat(_ text: String) -> Bool {
        guard let u=URL(string:text) else { return false }
        return SecurityPolicy.chat(u)
    }
    func front(_ b: Browser) throws -> TabRef? {
        guard app(b) != nil else { return nil }
        let body = b == .chrome ? """
        if (count windows) is 0 then return {}
        set w to front window
        set t to active tab of w
        return {id of w, id of t, URL of t}
        """ : """
        if (count windows) is 0 then return {}
        set w to front window
        set t to current tab of w
        return {id of w, index of t, URL of t}
        """
        let r = try run(b, body)
        guard r.numberOfItems == 3, let url = r.atIndex(3)?.stringValue, Self.isChat(url) else { return nil }
        return TabRef(window: Int(r.atIndex(1)!.int32Value), tab: Int(r.atIndex(2)!.int32Value), url: url, title:"")
    }
    func targetScript(_ b: Browser, _ t: TabRef) -> String {
        if b == .chrome { return "set w to window id \(t.window)\nset t to first tab of w whose id is \(t.tab)" }
        // Safari has no stable tab ID. Require the original index AND original URL;
        // reordering/navigation causes unknown instead of accidentally reading another tab.
        return "set w to window id \(t.window)\nset t to tab \(t.tab) of w"
    }
    func observe(_ b: Browser, _ t: TabRef, axOnly: Bool) -> Observation {
        if !axOnly {
            do {
                guard let jsURL = Bundle.main.url(forResource: "detector", withExtension: "js") else { throw AppFailure(message: "Нет detector.js") }
                var js = try String(contentsOf: jsURL, encoding: .utf8)
                if let token = t.token {
                    js = "window.__reelsWhileGPTToken === " + Self.quote(token) + " ? (" + js.trimmingCharacters(in: .whitespacesAndNewlines) + ") : 'unknown'"
                }
                let command = b == .chrome ? "execute t javascript \(Self.quote(js))" : "do JavaScript \(Self.quote(js)) in t"
                let guardURL = t.token == nil && b == .safari ? "if URL of t is not \(Self.quote(t.url)) then return \"unknown\"\n" : ""
                let r = try run(b, "\(targetScript(b,t))\n\(guardURL)return \(command)")
                if let s = r.stringValue, let signal = Signal(rawValue: s), signal != .unknown {
                    return Observation(signal: signal, method: "DOM")
                }
            } catch { /* Missing JavaScript permission: use public Accessibility API. */ }
        }
        return Observation(signal: accessibility(b,t), method: "Accessibility")
    }
    func mark(_ b: Browser, _ tab: TabRef) -> TabRef {
        var result = tab
        let token = UUID().uuidString
        let js = "window.__reelsWhileGPTToken = " + Self.quote(token) + "; 'marked'"
        let command = b == .chrome ? "execute t javascript \(Self.quote(js))" : "do JavaScript \(Self.quote(js)) in t"
        if (try? run(b,"\(targetScript(b,tab))\nreturn \(command)").stringValue) == "marked" { result.token = token }
        return result
    }
    func open(_ b: Browser, url: String) throws -> OwnedWindow {
        if app(b) == nil {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier:b.bundleID) != nil else { throw AppFailure(message:"Установите \(b.rawValue) или выберите другой браузер для Reels") }
            _ = try run(b,"launch")
            for _ in 0..<20 {
                if app(b) != nil { break }
                Thread.sleep(forTimeInterval:0.1)
            }
        }
        guard let process = app(b) else { throw AppFailure(message:"Не удалось запустить \(b.rawValue)") }
        let screen = CGDisplayBounds(CGMainDisplayID())
        let width = Int(min(430,screen.width-40)), height = Int(min(860,screen.height-100))
        let x = Int(screen.maxX)-width-24, y = Int(screen.minY)+60
        let bounds = "{\(x), \(y), \(x+width), \(y+height)}"
        let body = b == .chrome ? """
        set w to make new window
        set URL of active tab of w to \(Self.quote(url))
        try
            set bounds of w to \(bounds)
        end try
        set resultIDs to {id of w, id of active tab of w}
        activate
        return resultIDs
        """ : """
        set previousIDs to id of every window
        make new document with properties {URL:\(Self.quote(url))}
        set w to front window
        if (id of w) is in previousIDs then error "Safari did not create a dedicated window; check tab preferences"
        if (count tabs of w) is not 1 then error "Safari new window has unexpected tabs"
        try
            set bounds of w to \(bounds)
        end try
        set resultIDs to {id of w, index of current tab of w}
        activate
        return resultIDs
        """
        let r = try run(b, body)
        guard r.numberOfItems == 2 else { throw AppFailure(message: "Браузер не вернул идентификатор окна") }
        return OwnedWindow(browser: b, window: Int(r.atIndex(1)!.int32Value), tab: Int(r.atIndex(2)!.int32Value), pid: process.processIdentifier, launch: process.launchDate)
    }
    func prepareReels(_ owned: OwnedWindow) {
        guard let process = app(owned.browser), process.processIdentifier == owned.pid, process.launchDate == owned.launch,
              let resource = Bundle.main.url(forResource:"reels",withExtension:"js"),
              let js = try? String(contentsOf:resource,encoding:.utf8) else { return }
        let b = owned.browser
        let key = "\(owned.pid):\(owned.window):\(owned.tab)"
        guard !autoplayUnavailable.contains(key) else { return }
        let target = b == .chrome
            ? "set w to window id \(owned.window)\nset t to first tab of w whose id is \(owned.tab)"
            : "set w to window id \(owned.window)\nif (count tabs of w) is not 1 then return\nset t to current tab of w"
        let command = b == .chrome ? "execute t javascript \(Self.quote(js))" : "do JavaScript \(Self.quote(js)) in t"
        // Optional: Instagram/browser can still require a click or login. No credentials are touched.
        do { _ = try run(b,"\(target)\nreturn \(command)") }
        catch { autoplayUnavailable.insert(key) }
    }
    func preparePiP(_ owned: OwnedWindow) -> String {
        guard let process = app(owned.browser), process.processIdentifier == owned.pid, process.launchDate == owned.launch else { return "gone" }
        guard let path = Bundle.main.url(forResource:"pip",withExtension:"js"), let source = try? String(contentsOf:path,encoding:.utf8) else { return "unsupported" }
        let js = "window.__rwgLanguage = \(Self.quote(L10n.language.rawValue));" + source
        let b = owned.browser
        let target = b == .chrome
            ? "set w to window id \(owned.window)\nset t to first tab of w whose id is \(owned.tab)"
            : "set w to window id \(owned.window)\nif (count tabs of w) is not 1 then return \"changed\"\nset t to current tab of w"
        let command = b == .chrome ? "execute t javascript \(Self.quote(js))" : "do JavaScript \(Self.quote(js)) in t"
        do { return try run(b,"\(target)\nreturn \(command)").stringValue ?? "loading" }
        catch { return "permission" }
    }
    func tuckAway(_ owned: OwnedWindow) {
        guard let process = app(owned.browser), process.processIdentifier == owned.pid, process.launchDate == owned.launch else { return }
        _ = try? run(owned.browser,"if not (exists window id \(owned.window)) then return\nset w to window id \(owned.window)\nif (count tabs of w) is not 1 then return\nset miniaturized of w to true")
    }
    // Return a diagnostic when ownership cannot be established. Never close by URL.
    func close(_ owned: OwnedWindow) throws -> String? {
        guard let process = app(owned.browser), process.processIdentifier == owned.pid, process.launchDate == owned.launch else {
            return "Браузер перезапущен; старое окно не трогаем"
        }
        let body = owned.browser == .chrome ? """
        if not (exists window id \(owned.window)) then return "gone"
        set w to window id \(owned.window)
        if not (exists (first tab of w whose id is \(owned.tab))) then return "gone"
        close (first tab of w whose id is \(owned.tab))
        return "closed"
        """ : """
        if not (exists window id \(owned.window)) then return "gone"
        set w to window id \(owned.window)
        if (count tabs of w) is not 1 then return "unsafe"
        set u to URL of current tab of w
        if u does not start with "https://www.instagram.com/" and u does not start with "https://instagram.com/" then return "unsafe"
        close w
        return "closed"
        """
        let result = try run(owned.browser, body).stringValue
        return result == "unsafe" ? "Safari: окно изменено пользователем; оставлено открытым" : nil
    }
    func restore(_ b: Browser, _ t: TabRef) throws {
        let select = b == .chrome ? "set active tab index of w to index of t" : "set current tab of w to t"
        var guardScript = "if URL of t is not \(Self.quote(t.url)) then return"
        if let token = t.token {
            let js = "window.__reelsWhileGPTToken === " + Self.quote(token) + " && ['chatgpt.com','chat.openai.com'].includes(location.hostname) ? 'yes' : 'no'"
            let command = b == .chrome ? "execute t javascript \(Self.quote(js))" : "do JavaScript \(Self.quote(js)) in t"
            guardScript = "if (\(command)) is not \"yes\" then return"
        }
        _ = try run(b, "\(targetScript(b,t))\n\(guardScript)\n\(select)\nset index of w to 1\nactivate")
    }
    func attribute(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, key as CFString, &result) == .success ? result : nil
    }
    func accessibility(_ b: Browser, _ tab: TabRef) -> Signal {
        guard AXPermission.isGranted, let process = app(b) else { return .unknown }
        let root = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        guard let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] else { return .unknown }
        let cacheKey = "\(process.processIdentifier):\(tab.window):\(tab.tab)"
        var area = axAreas[cacheKey]
        if area == nil {
            // Match web areas by the exact ChatGPT URL, without reading any window/chat titles.
            var matches: [AXUIElement] = []
            var search = windows, i = 0
            let deadline = Date().addingTimeInterval(1.5)
            while i < search.count && i < 1500 && Date() < deadline {
                let e = search[i]; i += 1
                let role = attribute(e,kAXRoleAttribute) as? String ?? ""
                if role == "AXWebArea" {
                    let value=attribute(e,"AXURL")
                    let url=(value as? URL)?.absoluteString ?? (value as? String ?? "")
                    if url == tab.url { matches.append(e) }
                    continue
                }
                if SecurityPolicy.childContentAllowed(role:role), let children=attribute(e,kAXChildrenAttribute) as? [AXUIElement] { search.append(contentsOf:children) }
            }
            guard i == search.count, matches.count == 1 else { return .unknown }
            area=matches[0]
            if axAreas.count >= 32 { axAreas.removeAll() }
            if let area { axAreas[cacheKey] = area }
        }
        guard let area else { return .unknown }
        let value = attribute(area,"AXURL")
        let currentURL = (value as? URL)?.absoluteString ?? (value as? String ?? "")
        guard Self.isChat(currentURL) else { axAreas.removeValue(forKey:cacheKey); return .unknown }
        var queue = [area], offset = 0, composer = false, ready = false
        let deadline = Date().addingTimeInterval(1.5)
        while offset < queue.count && offset < 1800 && Date() < deadline {
            let e = queue[offset]; offset += 1
            let role = attribute(e, kAXRoleAttribute) as? String ?? ""
            if SecurityPolicy.metadataAllowed(role:role) {
                let label = [kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute,"AXIdentifier"]
                    .compactMap { attribute(e,$0) as? String }.joined(separator:" ").lowercased()
                if Self.stopLabel(label) { return .busy }
                if label.contains("send") || label.contains("отправить") || label.contains("voice") || label.contains("голос") || label.contains("dictate") || label.contains("диктов") { ready = true }
            }
            if ["AXTextArea", "AXTextField"].contains(role) { composer = true }
            if SecurityPolicy.childContentAllowed(role:role), let children = attribute(e,kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf: children) }
        }
        guard offset == queue.count else { return .unknown }
        return composer && ready ? .idle : .unknown
    }
    static func stopLabel(_ s: String) -> Bool {
        s.contains("stop generating") || s.contains("stop generation") || s.contains("stop streaming") || s.contains("остановить генерацию") || s.contains("прекратить генерацию") || s.contains("остановить ответ") || s.contains("stop-button")
    }
}
