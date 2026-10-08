import AppKit
import ApplicationServices

enum ChatSource: String, CaseIterable {
    case browser = "ChatGPT в браузере"
    case native = "Приложение ChatGPT"
}
struct NativeRef {
    let pid: pid_t
    let launch: Date?
    let window: AXUIElement?
    var identifier: String? = nil
}
protocol NativeService: AnyObject {
    func capture() -> NativeRef?
    func observe(_ ref: NativeRef) -> Observation
    func restore(_ ref: NativeRef)
    func stopMonitoring()
    func diagnostics() -> String
    var availability: String { get }
    func permissionStatus() -> AccessState
}
extension NativeService {
    func permissionStatus() -> AccessState { .unchecked }
    func stopMonitoring() {}
    func diagnostics() -> String { availability }
}
struct NativeControls {
    var composer = false, ready = false, stop = false
    var matched: Set<String> = []
    static func stopMarker(_ value: String) -> String? {
        let label = value.lowercased().replacingOccurrences(of:"_",with:" ").replacingOccurrences(of:"-",with:" ")
            .trimmingCharacters(in:.whitespacesAndNewlines)
        if label.contains("stop recording") || label.contains("stop dictat") || label.contains("остановить запись") || label.contains("остановить диктов") { return nil }
        if label.contains("interrupt") || label.contains("прервать") { return "Interrupt / Прервать" }
        if label.contains("stop generating") || label.contains("stop generation") || label.contains("stop streaming") || label.contains("stop response") || label.contains("stop turn") || label.contains("stop button") || label.contains("cancel response") || label.contains("cancel generation") { return "Stop response / generation / turn" }
        if label.contains("остановить") || label.contains("прекратить генерацию") || label.contains("прекратить ответ") { return "Остановить / прекратить ответ" }
        if label == "stop" || label.hasPrefix("stop (") || label.hasPrefix("stop [") || label == "stop esc" || label == "прекратить" { return "Stop / Esc" }
        return nil
    }
    mutating func add(role: String, label: String, enabled: Bool, pressable: Bool = false) {
        let label = label.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
        if ["AXTextArea","AXTextField","AXTextEntryArea"].contains(role) { composer = true }
        if role == kAXButtonRole || pressable {
            if enabled, let marker = Self.stopMarker(label) { stop = true; matched.insert(marker) }
            if label.contains("send") || label.contains("отправить") || label.contains("voice") || label.contains("голос") || label.contains("dictat") || label.contains("диктов") { ready = true }
        }
    }
    func signal(complete: Bool) -> Signal {
        if stop { return .busy }
        return complete && composer && ready ? .idle : .unknown
    }
}
struct NativeScan {
    var controls = NativeControls()
    var nodes = 0, buttons = 0, customControls = 0, textInputs = 0
    var complete = true
    var errors: Set<Int32> = []
    var signal: Signal { controls.signal(complete:complete) }
    var summary: String {
        "state=\(signal.rawValue), nodes=\(nodes), buttons=\(buttons), custom=\(customControls), inputs=\(textInputs), composer=\(controls.composer), ready=\(controls.ready), complete=\(complete), markers=\(controls.matched.sorted().joined(separator:",")), AXErrors=\(errors.sorted())"
    }
}
final class NativeChat: NativeService {
    static let bundleID = "com.openai.chat"
    private struct ChangedFlag { let root: AXUIElement; let key: String; let original: Bool; let pid: pid_t; let launch: Date? }
    private var changedFlags: [ChangedFlag] = []
    private var prepared: [pid_t: Date] = [:]
    private var prepareReport: [pid_t: String] = [:]
    private var cached: (ref: NativeRef, scan: NativeScan, time: Date)?
    private var report = "Детектор ещё не проверял приложение ChatGPT"
    static func brandedChatGPT(name: String?, displayName: String?, bundleName: String?, path: String?) -> Bool {
        [name,displayName,bundleName].compactMap { $0 }.contains { $0.caseInsensitiveCompare("ChatGPT") == .orderedSame }
            || path?.lowercased().hasSuffix("/chatgpt.app") == true
    }
    func app() -> NSRunningApplication? {
        let classic = NSRunningApplication.runningApplications(withBundleIdentifier:Self.bundleID)
        let modern = NSRunningApplication.runningApplications(withBundleIdentifier:"com.openai.codex").filter { app in
            let bundle = app.bundleURL.flatMap(Bundle.init(url:))
            return Self.brandedChatGPT(name:app.localizedName,displayName:bundle?.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String,bundleName:bundle?.object(forInfoDictionaryKey:"CFBundleName") as? String,path:app.bundleURL?.path)
        }
        return (classic+modern).first(where:{$0.isActive}) ?? (classic+modern).first
    }
    var availability: String { report }
    func permissionStatus() -> AccessState {
        guard AXPermission.isGranted else { return .denied }
        guard let app = app() else { return .unchecked }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root,0.12)
        let error = read(root,kAXWindowsAttribute).1
        if error == .apiDisabled { return .denied }
        return error == .success ? .allowed : .unchecked
    }
    func read(_ element: AXUIElement, _ key: String) -> (CFTypeRef?,AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element,key as CFString,&value)
        return (value,error)
    }
    func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? { read(element,key).0 }
    func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value,to:AXUIElement.self)
    }
    func enableFlag(_ element: AXUIElement, _ key: String, app: NSRunningApplication) -> AXError {
        let original = attr(element,key) as? Bool ?? false
        let error = AXUIElementSetAttributeValue(element,key as CFString,kCFBooleanTrue)
        if error == .success && !original {
            changedFlags.append(ChangedFlag(root:element,key:key,original:original,pid:app.processIdentifier,launch:app.launchDate))
        }
        return error
    }
    func prepare(_ root: AXUIElement, app: NSRunningApplication) {
        AXUIElementSetMessagingTimeout(root,0.12)
        if let date = prepared[app.processIdentifier], Date().timeIntervalSince(date) < 10 { return }
        prepared[app.processIdentifier] = Date()
        // Electron documents AXManualAccessibility for third-party assistive clients.
        // Unsupported flags are harmless; no launch flags, web debugging or private ChatGPT APIs.
        let manual = enableFlag(root,"AXManualAccessibility",app:app)
        let enhanced = enableFlag(root,"AXEnhancedUserInterface",app:app)
        prepareReport[app.processIdentifier] = "AXManualAccessibility=\(manual.rawValue), AXEnhancedUserInterface=\(enhanced.rawValue) (0=success, -25205=unsupported)"
    }
    static func chooseWindow(signals: [Signal], focused: Int?) -> Int? {
        if let focused, signals.indices.contains(focused), signals[focused] == .busy { return focused }
        if let busy = signals.firstIndex(of:.busy) { return busy }
        if let focused, signals.indices.contains(focused) { return focused }
        return signals.firstIndex(of:.idle) ?? signals.indices.first
    }
    func capture() -> NativeRef? {
        guard AXPermission.isGranted else { report = "Нет доступа AX: добавьте именно эту сборку Reels While GPT в Универсальный доступ"; return nil }
        guard let app = app() else { report = "Приложение ChatGPT не найдено (проверены standalone и новая дистрибуция)"; return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        prepare(root,app:app)
        var windows = (attr(root,kAXWindowsAttribute) as? [AXUIElement]) ?? []
        let focused = element(attr(root,kAXFocusedWindowAttribute)) ?? element(attr(root,kAXMainWindowAttribute))
        if let focused, !windows.contains(where:{CFEqual($0,focused)}) { windows.insert(focused,at:0) }
        // Fullscreen windows may omit AXFocusedWindow; AXWindows/AXMainWindow are valid fallbacks.
        var focusedIndex = focused.flatMap { f in windows.firstIndex(where:{CFEqual($0,f)}) }
        let version = app.bundleURL.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "?"
        let meta = "bundle=\(app.bundleIdentifier ?? "?"), version=\(version), pid=\(app.processIdentifier), active=\(app.isActive), windows=\(windows.count)"
        guard !windows.isEmpty else {
            let windowsError = read(root,kAXWindowsAttribute).1.rawValue
            let explanation = windowsError == AXError.apiDisabled.rawValue
                ? "Доступ к окнам ChatGPT запрещён macOS (-25211). Общий AX-флаг не подтверждает доступ к этому приложению. Закройте все старые копии Reels While GPT, удалите его запись из Универсального доступа, добавьте запущенную .app заново и перезапустите её."
                : "Нет доступных окон ChatGPT: откройте окно диалога и повторите проверку."
            report = "\(explanation)\n\(meta)\nНет доступных окон; AXWindows error=\(windowsError)\n\(prepareReport[app.processIdentifier] ?? "")"
            return nil
        }
        if let index = focusedIndex, index != 0 { windows.swapAt(0,index); focusedIndex = 0 }
        var scans: [NativeScan] = []
        let deadline = Date().addingTimeInterval(3)
        for window in windows.prefix(4) {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            let result = (attr(window,kAXMinimizedAttribute) as? Bool) == true ? NativeScan(complete:false) : scan(window,budget:min(2,remaining))
            scans.append(result)
            if result.signal == .busy { break } // Open promptly; don't scan unrelated windows first.
        }
        guard let index = Self.chooseWindow(signals:scans.map(\.signal),focused:focusedIndex) else { return nil }
        let ref = NativeRef(pid:app.processIdentifier,launch:app.launchDate,window:windows[index],identifier:attr(windows[index],"AXIdentifier") as? String)
        cached = (ref,scans[index],Date())
        report = "\(meta)\n\(prepareReport[app.processIdentifier] ?? "")\n" + scans.enumerated().map { "window[\($0.offset)]: \($0.element.summary)" }.joined(separator:"\n")
        return ref
    }
    func scan(_ window: AXUIElement, budget: TimeInterval = 2) -> NativeScan {
        AXUIElementSetMessagingTimeout(window,0.12)
        var result = NativeScan(), queue = [window], i = 0
        let deadline = Date().addingTimeInterval(budget)
        while i < queue.count && i < 5000 && Date() < deadline {
            let node = queue[i]; i += 1
            let (roleValue,roleError) = read(node,kAXRoleAttribute)
            guard let role = roleValue as? String else {
                result.complete = false; result.errors.insert(roleError.rawValue); continue
            }
            result.nodes += 1
            if ["AXStaticText","AXLink","AXSecureTextField"].contains(role) { continue } // Never read text or secure field content.
            var actions: CFArray?
            var pressable = false
            if ["AXGroup","AXImage","AXUnknown"].contains(role) {
                if AXUIElementCopyActionNames(node,&actions) == .success {
                    pressable = (actions as? [String])?.contains(kAXPressAction) == true
                }
            }
            let isInput = ["AXTextArea","AXTextField","AXTextEntryArea"].contains(role)
            if isInput {
                result.textInputs += 1
                result.controls.add(role:role,label:"",enabled:true)
                continue // No title/help/value or children of editable fields.
            }
            if SecurityPolicy.metadataAllowed(role:role,pressable:pressable) {
                if role == kAXButtonRole { result.buttons += 1 }
                if pressable { result.customControls += 1 }
                if isInput { result.textInputs += 1 }
                // Batch control metadata into one AX message. Never request AXValue.
                let keys = [kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute,"AXIdentifier",kAXEnabledAttribute,"AXHidden"]
                var values: CFArray?
                let metadataError = AXUIElementCopyMultipleAttributeValues(node,keys as CFArray,[],&values)
                let metadata = values as? [Any] ?? []
                if metadata.count > 5, (metadata[5] as? Bool) == true { continue }
                let enabled = metadata.count > 4 ? (metadata[4] as? Bool ?? true) : true
                let labels = metadata.prefix(4).compactMap { $0 as? String }
                if metadataError != .success { result.complete = false; result.errors.insert(metadataError.rawValue) }
                for label in labels.isEmpty ? [""] : labels {
                    result.controls.add(role:role,label:label,enabled:enabled,pressable:pressable)
                }
                if result.controls.stop { result.complete = false; return result }
            }
            let (childValue,childError) = read(node,kAXChildrenAttribute)
            var children = childValue as? [AXUIElement] ?? []
            if children.isEmpty { children = (attr(node,kAXVisibleChildrenAttribute) as? [AXUIElement]) ?? [] }
            if children.isEmpty && role == "AXWebArea" { children = (attr(node,"AXContents") as? [AXUIElement]) ?? [] }
            queue.append(contentsOf:children.reversed())
            if ![AXError.success,.attributeUnsupported,.noValue].contains(childError) {
                result.complete = false; result.errors.insert(childError.rawValue)
            }
        }
        if i < queue.count { result.complete = false }
        return result
    }
    func observe(_ ref: NativeRef) -> Observation {
        guard AXPermission.isGranted, let app = NSRunningApplication(processIdentifier:ref.pid), app.launchDate == ref.launch,
              let window = ref.window else { return Observation(signal:.unknown,method:"Native AX: окно/процесс недоступны") }
        let result: NativeScan
        if let cached, cached.ref.pid == ref.pid, let cachedWindow = cached.ref.window, CFEqual(cachedWindow,window), Date().timeIntervalSince(cached.time) < 0.35 {
            result = cached.scan; self.cached = nil
        } else {
            // Re-read the application's window list instead of relying solely on a retained AX tree.
            // Never select a different window just because it became focused.
            let root = AXUIElementCreateApplication(ref.pid)
            AXUIElementSetMessagingTimeout(root,0.12)
            prepare(root,app:app)
            let windows = (attr(root,kAXWindowsAttribute) as? [AXUIElement]) ?? []
            let same = windows.first(where:{ CFEqual($0,window) })
            let byID = ref.identifier.flatMap { id -> AXUIElement? in
                let matches = windows.filter { (attr($0,"AXIdentifier") as? String) == id }
                return matches.count == 1 ? matches[0] : nil
            }
            result = scan(same ?? byID ?? window)
        }
        let detail = result.signal == .unknown ? " · nodes=\(result.nodes), buttons=\(result.buttons), inputs=\(result.textInputs), complete=\(result.complete)" : ""
        report = "bundle=\(app.bundleIdentifier ?? "?"), pid=\(ref.pid), active=\(app.isActive)\n\(prepareReport[ref.pid] ?? "")\n\(result.summary)"
        return Observation(signal:result.signal,method:"ChatGPT app · AX\(detail)")
    }
    func diagnostics() -> String {
        _ = capture()
        return report + "\nДиагностика не содержит текстов диалогов, заголовков чатов, значений полей или credentials."
    }
    func restore(_ ref: NativeRef) {
        guard let app = NSRunningApplication(processIdentifier:ref.pid), app.launchDate == ref.launch else { return }
        if let window = ref.window { AXUIElementPerformAction(window,kAXRaiseAction as CFString) }
        DispatchQueue.main.async { app.activate(options:[]) }
    }
    func stopMonitoring() {
        for flag in changedFlags {
            if let app = NSRunningApplication(processIdentifier:flag.pid), app.launchDate == flag.launch {
                AXUIElementSetAttributeValue(flag.root,flag.key as CFString,flag.original ? kCFBooleanTrue : kCFBooleanFalse)
            }
        }
        changedFlags.removeAll(); prepared.removeAll(); cached = nil
    }
}
