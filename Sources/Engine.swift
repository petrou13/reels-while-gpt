import Foundation

struct ConnectionDiagnosis {
    let report: String
    let title: String
    let detail: String
    let access: AccessState
}

// Confined to the serial worker queue. No network requests or message contents.
final class Engine {
    let overlay: OverlayService
    var floatingActive = false, setupOpen = false, pipRestored = false
    var sessionPlayback: PlaybackMode = .browserPiP
    var pipState = "loading"
    let native: NativeService
    var nativeOrigin: NativeRef?
    let bridge: BrowserService
    init(bridge: BrowserService = BrowserBridge(), native: NativeService = NativeChat(), overlay: OverlayService = OverlayBridge()) { self.bridge = bridge; self.native = native; self.overlay = overlay }
    var origin: TabRef?
    var browser: Browser?
    var owned: OwnedWindow?
    var since = Date()
    var idleSamples = 0
    var testUntil: Date?
    var idleSince: Date?
    func connectionDiagnosis(source: ChatSource, b: Browser, axOnly: Bool) -> ConnectionDiagnosis {
        if source == .browser {
            let result = bridge.diagnose(b,axOnly:axOnly,target:browser == b ? origin : nil)
            return ConnectionDiagnosis(report:result.report,title:result.title,detail:result.detail(b,axOnly:axOnly),access:.unchecked)
        }
        let report = native.diagnostics(), access = native.permissionStatus()
        return ConnectionDiagnosis(report:report,
            title:access == .allowed ? L("Доступ к приложению ChatGPT получен","ChatGPT app access granted") : L("Нужно проверить доступ к приложению ChatGPT","Check ChatGPT app access"),
            detail:access == .allowed ? L("Подробный отчёт ниже показывает, распознано ли состояние ответа. Проверяйте во время длинного ответа.","The detailed report below shows whether the response state was detected. Check during a long response.") : L("Откройте приложение ChatGPT и разрешите Универсальный доступ этой копии Reels While GPT.","Open the ChatGPT app and grant Accessibility to this copy of Reels While GPT."),access:access)
    }
    func finish(restore: Bool, disarmNative: Bool = false) throws -> String {
        if disarmNative { native.stopMonitoring() }
        var diagnostic: String?
        if floatingActive { overlay.hide(); floatingActive = false }
        setupOpen = false
        if let owned { diagnostic = try bridge.close(owned); self.owned = nil }
        if restore, diagnostic == nil {
            if let nativeOrigin { native.restore(nativeOrigin) }
            else if let origin, let browser { try? bridge.restore(browser,origin) }
        }
        origin = nil; nativeOrigin = nil; browser = nil; testUntil = nil; idleSamples = 0; idleSince = nil
        return diagnostic ?? "Готово — ChatGPT вернулся"
    }
    func openViewer(_ b: Browser, url: String, playback: PlaybackMode) throws {
        sessionPlayback = playback; pipRestored = false; pipState = "loading"
        if playback == .floating { try overlay.show(url:url); floatingActive = true }
        else { owned = try bridge.open(b,url:url) }
    }
    func manualOpen(_ b: Browser, url: String, playback: PlaybackMode) throws -> String {
        _ = try finish(restore:false,disarmNative:true)
        try openViewer(b,url:url,playback:playback)
        setupOpen = true
        return "Ручной просмотр · закройте окно, когда закончите"
    }
    func preview() throws -> String {
        _ = try finish(restore:false)
        overlay.preview(); floatingActive = true; setupOpen = true
        return "Preview 9:16 · без загрузки сайта"
    }
    func login(url: String) throws -> String {
        _ = try finish(restore:false)
        try overlay.show(url:url); floatingActive = true; setupOpen = true
        return "Войдите в аккаунт в плавающем окне, затем включите мониторинг"
    }
    var viewerStatus: String {
        if sessionPlayback == .floating { return overlay.status }
        switch pipState {
        case "active": return "Picture-in-Picture активен"
        case "gesture": return "Нажмите «Смотреть поверх ChatGPT» в своём окне с видео"
        case "permission": return "Для PiP включите JavaScript from Apple Events в браузере"
        case "login": return "Сервис просит вход в выбранном браузере"
        case "unsupported": return "Браузер не предоставил PiP; выберите встроенное плавающее окно"
        case "gone", "changed", "wrong-page": return "Окно Reels закрыто или изменено пользователем"
        default: return "Ожидание видео / запуска Picture-in-Picture"
        }
    }
    func test(_ b: Browser, url: String, playback: PlaybackMode = .browserPiP) throws -> String {
        guard owned == nil && origin == nil && nativeOrigin == nil && !floatingActive else { return "Уже есть активный сеанс" }
        try openViewer(b,url:url,playback:playback); testUntil = Date().addingTimeInterval(8)
        return "Test: своё окно закроется через 8 секунд"
    }
    func tick(enabled: Bool, b: Browser, url: String, axOnly: Bool, source: ChatSource = .browser, playback: PlaybackMode = .browserPiP, returnAfterResponse: Bool = true) throws -> String {
        if setupOpen {
            if enabled { overlay.hide(); floatingActive = false; setupOpen = false }
        }
        if let owned, enabled || testUntil != nil || setupOpen {
            bridge.prepareReels(owned)
            pipState = bridge.preparePiP(owned)
            if pipState == "active" && !pipRestored {
                if let nativeOrigin { native.restore(nativeOrigin) }
                else if let origin, let browser { try? bridge.restore(browser,origin) }
                bridge.tuckAway(owned)
                pipRestored = true
            }
        }
        if setupOpen && !enabled { return viewerStatus }
        if let until = testUntil { return Date() >= until ? try finish(restore:false) : "Test: " + viewerStatus }
        if !enabled {
            native.stopMonitoring()
            return owned != nil || origin != nil || nativeOrigin != nil || floatingActive ? try finish(restore:false) : "Мониторинг выключен — включите переключатель выше"
        }
        if origin != nil || nativeOrigin != nil {
            if Date().timeIntervalSince(since) > 1800 { return try finish(restore: returnAfterResponse) + " (лимит 30 минут)" }
            let result = nativeOrigin.map { native.observe($0) } ?? bridge.observe(browser!,origin!,axOnly: axOnly)
            if result.signal == .idle {
                idleSamples += 1
                if idleSince == nil { idleSince = Date() }
                if idleSamples >= 3 && Date().timeIntervalSince(idleSince!) >= 2 && Date().timeIntervalSince(since) >= 3 { return try finish(restore: returnAfterResponse) }
            } else { idleSamples = 0; idleSince = nil }
            let state = result.signal == .unknown ? "Состояние недоступно (\(result.method)); ожидаем или нажмите Return" : "ChatGPT: \(result.signal == .busy ? "генерация" : "подтверждаем завершение") · \(result.method)"
            return state + " · " + viewerStatus
        }
        if source == .native {
            guard let ref = native.capture() else { return native.availability }
            let result = native.observe(ref)
            if result.signal == .busy {
                nativeOrigin = ref; since = Date(); idleSamples = 0; idleSince = nil
                try openViewer(b,url:url,playback:playback)
                return "ChatGPT app: генерация · " + viewerStatus
            }
            return result.signal == .unknown ? "ChatGPT app: сигнал не распознан · \(result.method) · нажмите «Проверить детектор»" : "Готов к запросу в приложении ChatGPT"
        }
        guard let tab = try bridge.front(b) else { return "Ожидание: откройте вкладку ChatGPT в \(b.rawValue)" }
        let result = bridge.observe(b,tab,axOnly: axOnly)
        if result.signal == .busy {
            // Set latch before opening: a failed open must not create repeated windows.
            origin = axOnly ? tab : bridge.mark(b,tab); browser = b; since = Date(); idleSamples = 0; idleSince = nil
            _ = bridge.accessibility(b,tab) // Capture original AXWebArea before changing focus.
            try openViewer(b,url:url,playback:playback)
            return "Генерация обнаружена · \(result.method) · " + viewerStatus
        }
        return result.signal == .unknown ? "Нет сигнала: \(result.method). Проверьте подключение" : "Готов к следующему запросу · \(result.method)"
    }
}
