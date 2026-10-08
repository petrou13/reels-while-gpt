import AppKit
import WebKit

enum PlaybackMode: String, CaseIterable {
    case floating = "Плавающее окно поверх Full Screen"
    case browserPiP = "Picture-in-Picture браузера"
}
protocol OverlayService: AnyObject {
    func show(url: String) throws
    func hide()
    func preview()
    func clearWebsiteData(completion: @escaping () -> Void)
    var status: String { get }
}
extension OverlayService { func preview() {}; func clearWebsiteData(completion: @escaping () -> Void) { completion() } }
enum ViewerReusePolicy {
    static func shouldLoad(requested: String, loaded: String?, hasPage: Bool) -> Bool { loaded != requested || !hasPage }
}
struct OverlayLayout {
    static let timelineHeight: CGFloat = 28
    static let miniTimelineHeight: CGFloat = 10
    static func timeline(autoMini: Bool, hovering: Bool, dragging: Bool) -> CGFloat {
        autoMini && !hovering && !dragging ? miniTimelineHeight : timelineHeight
    }
    static func contentSize(width: CGFloat, timeline: CGFloat = timelineHeight) -> CGSize {
        CGSize(width:width,height:width*16/9+timeline)
    }
    static func size(available: CGSize, timeline: CGFloat = timelineHeight) -> CGSize {
        let videoHeight = max(180,min(640,available.height-90-timeline,(available.width-40)*16/9))
        return contentSize(width:videoHeight*9/16,timeline:timeline)
    }
    static func resized(current: CGSize, proposed: CGSize, timeline: CGFloat = timelineHeight) -> CGSize {
        // Determine the dragged dimension; the timeline has a fixed height at every scale.
        let widthDriven = abs(proposed.width-current.width) >= abs(proposed.height-current.height)*9/16
        let width = widthDriven ? proposed.width : (proposed.height-timeline)*9/16
        return contentSize(width:max(240,min(480,width)),timeline:timeline)
    }
}
final class ReelsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class PagingHandler: NSObject, WKScriptMessageHandler {
    weak var player: FloatingPlayer?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, FloatingPlayer.allowed(url), let state = message.body as? [String:Any] else { return }
        if state["kind"] as? String == "seek" { player?.seekState(state) }
        else { player?.pagingState(state) }
    }
}
final class TimelineBar: NSView {
    var hoverChanged: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let tracking=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(tracking); area=tracking
    }
    override func mouseEntered(with event: NSEvent) { hoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged?(false) }
}
final class MiniTimeline: NSView {
    var fraction: Double = 0 { didSet { needsDisplay=true } }
    override func draw(_ dirtyRect: NSRect) {
        let track=NSRect(x:10,y:(bounds.height-2)/2,width:max(0,bounds.width-20),height:2)
        NSColor.separatorColor.setFill(); NSBezierPath(roundedRect:track,xRadius:1,yRadius:1).fill()
        var progress=track; progress.size.width *= max(0,min(1,fraction))
        NSColor.controlAccentColor.setFill(); NSBezierPath(roundedRect:progress,xRadius:1,yRadius:1).fill()
    }
}
final class SeekSlider: NSSlider {
    var trackingEnded: (() -> Void)?
    var videoToken: Int?
    private(set) var trackingToken: Int?
    private(set) var trackingSeek = false
    override func mouseDown(with event: NSEvent) {
        trackingToken=videoToken; trackingSeek=true
        super.mouseDown(with:event)
        trackingSeek=false; trackingToken=nil; trackingEnded?()
    }
}
final class FloatingPlayer: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private(set) var panel: ReelsPanel!
    private let controlWorld = WKContentWorld.world(name:"ReelsWhileGPTControls")
    private var web: WKWebView!
    private let seekSlider = SeekSlider(value:0,minValue:0,maxValue:1,target:nil,action:nil)
    private let seekTime = NSTextField(labelWithString:"—:—")
    private let seekDuration = NSTextField(labelWithString:"—:—")
    private let timelineBar = TimelineBar()
    private let miniTimeline = MiniTimeline()
    private var timelineConstraint: NSLayoutConstraint!
    private var timelineHover = false
    private var collapseTask: DispatchWorkItem?
    private var timelineHeight: CGFloat = OverlayLayout.timelineHeight
    private var seekToken: Int?
    private func updateTimeline() {
        guard timelineConstraint != nil else { return }
        let height=OverlayLayout.timeline(autoMini:UserDefaults.standard.bool(forKey:"miniTimeline"),hovering:timelineHover,dragging:seekSlider.trackingSeek)
        let mini=height == OverlayLayout.miniTimelineHeight
        for view in [seekSlider,seekTime,seekDuration] { view.isHidden=mini }
        miniTimeline.isHidden = !mini
        guard height != timelineHeight else { return }
        let frame=panel.frame
        let width=panel.contentRect(forFrameRect:frame).width
        timelineHeight=height; timelineConstraint.constant=height
        panel.contentMinSize=OverlayLayout.contentSize(width:240,timeline:height)
        panel.contentMaxSize=OverlayLayout.contentSize(width:480,timeline:height)
        var target=panel.frameRect(forContentRect:NSRect(origin:.zero,size:OverlayLayout.contentSize(width:width,timeline:height)))
        target.origin=NSPoint(x:frame.minX,y:frame.maxY-target.height)
        panel.setFrame(target,display:true)
        panel.contentView?.layoutSubtreeIfNeeded()
    }
    private func timelineHoverChanged(_ hovering: Bool) {
        timelineHover=hovering; collapseTask?.cancel()
        if hovering { updateTimeline() }
        else {
            let task=DispatchWorkItem { [weak self] in self?.updateTimeline() }
            collapseTask=task; DispatchQueue.main.asyncAfter(deadline:.now()+0.25,execute:task)
        }
    }
    private static func timeText(_ time: Double) -> String { String(format:"%d:%02d",Int(time)/60,Int(time)%60) }
    func seekState(_ state: [String:Any]) {
        guard state["ready"] as? Bool == true, let token = state["token"] as? Int,
              let time = state["time"] as? Double, let duration = state["duration"] as? Double,
              time.isFinite, duration.isFinite, duration > 0, duration < 86400, token > 0, time >= 0, time <= duration else {
            seekToken=nil; seekSlider.videoToken=nil; seekSlider.isEnabled=false; seekTime.stringValue="—:—"; seekDuration.stringValue="—:—"; miniTimeline.fraction=0; return
        }
        seekToken=token; seekSlider.videoToken=token; seekSlider.isEnabled=true; seekSlider.maxValue=duration
        if !seekSlider.trackingSeek { seekSlider.doubleValue=time }
        seekTime.stringValue=Self.timeText(seekSlider.doubleValue); seekDuration.stringValue=Self.timeText(duration)
        miniTimeline.fraction=time/duration
    }
    private func evaluatePlayerScript(_ script: String, completionHandler: ((Any?,Error?) -> Void)? = nil) {
        web.evaluateJavaScript(script,in:nil,in:controlWorld) { result in
            switch result {
            case .success(let value): completionHandler?(value,nil)
            case .failure(let error): completionHandler?(nil,error)
            }
        }
    }
    func unloadForDataRemoval() {
        web.stopLoading(); web.loadHTMLString("",baseURL:nil)
        currentURL=nil; panel.orderOut(nil); seekState(["ready":false])
    }
    @objc private func seekVideo() {
        guard let token = seekSlider.trackingSeek ? seekSlider.trackingToken : seekToken else { return }
        let time=seekSlider.doubleValue
        seekTime.stringValue=Self.timeText(time)
        evaluatePlayerScript("window.__rwgSeekTo && window.__rwgSeekTo(\(token),\(time));",completionHandler:nil)
    }
    private var preferenceObserver: NSObjectProtocol?
    private var monitor: Any?
    private var gate = ReelSwipeGate()
    private var videoRect: CGRect?
    private let paging = PagingHandler()
    func pagingState(_ state: [String:Any]) {
        guard state["ready"] as? Bool == true,
              let x = state["x"] as? Double, let y = state["y"] as? Double,
              let width = state["width"] as? Double, let height = state["height"] as? Double,
              [x,y,width,height].allSatisfy({ $0.isFinite }), width > 100, height > 150 else {
            videoRect = nil; gate.reset(); return
        }
        let viewportWidth = state["viewportWidth"] as? Double ?? Double(web.bounds.width)
        let viewportHeight = state["viewportHeight"] as? Double ?? Double(web.bounds.height)
        guard viewportWidth.isFinite, viewportHeight.isFinite, viewportWidth > 0, viewportHeight > 0 else { videoRect = nil; return }
        let sx = Double(web.bounds.width)/viewportWidth, sy = Double(web.bounds.height)/viewportHeight
        videoRect = CGRect(x:x*sx,y:y*sy,width:width*sx,height:height*sy)
    }
    deinit { collapseTask?.cancel(); if let monitor { NSEvent.removeMonitor(monitor) }; if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) } }
    private var placed = false
    private var currentURL: String?
    private(set) var message = "Плавающее окно готово"
    init(previewOnly: Bool = false) {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = previewOnly ? .nonPersistent() : .default() // Persistent app-owned login; never imports browser cookies.
        config.mediaTypesRequiringUserActionForPlayback = []
        if let path = Bundle.main.url(forResource:"reels",withExtension:"js"), let js = try? String(contentsOf:path,encoding:.utf8) {
            config.userContentController.addUserScript(WKUserScript(source:js,injectionTime:.atDocumentEnd,forMainFrameOnly:true,in:controlWorld))
        }
        if let path = Bundle.main.url(forResource:"seek",withExtension:"js"), let js = try? String(contentsOf:path,encoding:.utf8) {
            config.userContentController.addUserScript(WKUserScript(source:js,injectionTime:.atDocumentEnd,forMainFrameOnly:true,in:controlWorld))
        }
        paging.player = self
        config.userContentController.add(paging,contentWorld:controlWorld,name:"reelPaging")
        if let path = Bundle.main.url(forResource:"swipe",withExtension:"js"), let js = try? String(contentsOf:path,encoding:.utf8) {
            config.userContentController.addUserScript(WKUserScript(source:js,injectionTime:.atDocumentEnd,forMainFrameOnly:true,in:controlWorld))
        }
        web = WKWebView(frame:.zero,configuration:config)
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        web.navigationDelegate = self; web.uiDelegate = self
        panel = ReelsPanel(contentRect:NSRect(x:0,y:0,width:360,height:640),styleMask:[.titled,.closable,.resizable,.nonactivatingPanel,.utilityWindow],backing:.buffered,defer:false)
        panel.title = L10n.text("Reels · плавающее окно")
        if !previewOnly { placed = panel.setFrameUsingName("ReelsPlayer"); panel.setFrameAutosaveName("ReelsPlayer") }
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.canJoinAllApplications,.ignoresCycle]
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false; panel.worksWhenModal = true
        panel.isReleasedWhenClosed = false; panel.delegate = self
        let content = NSView()
        let bar = timelineBar
        timelineConstraint=bar.heightAnchor.constraint(equalToConstant:timelineHeight)
        for view in [web!,bar,seekSlider,seekTime,seekDuration,miniTimeline] { view.translatesAutoresizingMaskIntoConstraints=false }
        content.addSubview(web); content.addSubview(bar)
        for view in [seekTime,seekSlider,seekDuration] { bar.addSubview(view) }
        bar.addSubview(miniTimeline); miniTimeline.isHidden=true
        bar.hoverChanged = { [weak self] hovering in self?.timelineHoverChanged(hovering) }
        seekSlider.trackingEnded = { [weak self] in self?.updateTimeline() }
        seekSlider.controlSize = .small
        seekSlider.target=self; seekSlider.action=#selector(seekVideo); seekSlider.isContinuous=true; seekSlider.isEnabled=false
        seekSlider.setAccessibilityLabel(L("Перемотка видео","Seek video"))
        seekSlider.toolTip=L("Перетащите ползунок, чтобы перейти к нужному моменту","Drag to jump to a moment in the video")
        for label in [seekTime,seekDuration] { label.font=NSFont.monospacedDigitSystemFont(ofSize:10,weight:.regular); label.alignment = .center }
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo:content.topAnchor), web.leadingAnchor.constraint(equalTo:content.leadingAnchor), web.trailingAnchor.constraint(equalTo:content.trailingAnchor),
            web.bottomAnchor.constraint(equalTo:bar.topAnchor), bar.bottomAnchor.constraint(equalTo:content.bottomAnchor), bar.leadingAnchor.constraint(equalTo:content.leadingAnchor), bar.trailingAnchor.constraint(equalTo:content.trailingAnchor), timelineConstraint!,
            seekTime.leadingAnchor.constraint(equalTo:bar.leadingAnchor,constant:8), seekTime.widthAnchor.constraint(equalToConstant:42), seekTime.centerYAnchor.constraint(equalTo:bar.centerYAnchor),
            seekSlider.leadingAnchor.constraint(equalTo:seekTime.trailingAnchor,constant:6), seekSlider.trailingAnchor.constraint(equalTo:seekDuration.leadingAnchor,constant:-6), seekSlider.centerYAnchor.constraint(equalTo:bar.centerYAnchor),
            seekDuration.trailingAnchor.constraint(equalTo:bar.trailingAnchor,constant:-8), seekDuration.widthAnchor.constraint(equalToConstant:42), seekDuration.centerYAnchor.constraint(equalTo:bar.centerYAnchor),
            miniTimeline.leadingAnchor.constraint(equalTo:bar.leadingAnchor),miniTimeline.trailingAnchor.constraint(equalTo:bar.trailingAnchor),miniTimeline.topAnchor.constraint(equalTo:bar.topAnchor),miniTimeline.bottomAnchor.constraint(equalTo:bar.bottomAnchor)
        ])
        panel.contentView = content
        panel.contentMinSize = OverlayLayout.contentSize(width:240)
        panel.contentMaxSize = OverlayLayout.contentSize(width:480)
        // A fixed aspect ratio on the whole window would subtract the timeline from the video.
        // Restore older saved frames using their width, while preserving the top edge.
        let oldFrame=panel.frame
        let corrected=OverlayLayout.contentSize(width:max(240,min(480,panel.contentRect(forFrameRect:oldFrame).width)))
        var restored=panel.frameRect(forContentRect:NSRect(origin:.zero,size:corrected))
        restored.origin=NSPoint(x:oldFrame.minX,y:oldFrame.maxY-restored.height)
        panel.setFrame(restored,display:false)
        updateTimeline()
        preferenceObserver = NotificationCenter.default.addObserver(forName:Notification.Name("ReelsPreferencesChanged"),object:nil,queue:.main) { [weak self] _ in
            guard let self else { return }
            self.updateTimeline()
            self.panel.title = L10n.text("Reels · плавающее окно")
            self.seekSlider.setAccessibilityLabel(L("Перемотка видео","Seek video"))
            self.seekSlider.toolTip=L("Перетащите ползунок, чтобы перейти к нужному моменту","Drag to jump to a moment in the video")
            if self.panel.isVisible {
                self.evaluatePlayerScript("window.__rwgSeekLanguage = '\(L("ru","en"))'; window.__rwgSeekUpdate && window.__rwgSeekUpdate(); window.__rwgMuted = \(UserDefaults.standard.object(forKey:"muted") as? Bool ?? true); window.__rwgResume && window.__rwgResume();",completionHandler:nil)
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.isVisible,
                  let rect = self.videoRect, !event.modifierFlags.contains(.command) else { return event }
            let point = self.web.convert(event.locationInWindow,from:nil)
            let cssPoint = CGPoint(x:point.x,y:self.web.isFlipped ? point.y : self.web.bounds.height-point.y)
            guard self.web.bounds.contains(point), rect.contains(cssPoint), abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else { return event }
            if let direction = self.gate.step(delta:Double(event.scrollingDeltaY),began:event.phase.contains(.began),
                 ended:event.phase.contains(.ended) || event.phase.contains(.cancelled),
                 momentum:!event.momentumPhase.isEmpty,phased:!event.phase.isEmpty,time:event.timestamp) {
                self.evaluatePlayerScript("window.__rwgStepReel && window.__rwgStepReel(\(direction));") { [weak self] result, _ in
                    guard let self, result as? Bool != true else { return }
                    self.evaluatePlayerScript("window.__rwgScrollReel && window.__rwgScrollReel(\(direction));",completionHandler:nil)
                }
            }
            return nil
        }
    }
    func place() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = OverlayLayout.size(available:frame.size,timeline:timelineHeight)
        panel.setContentSize(size)
        let windowSize = panel.frame.size
        panel.setFrameOrigin(NSPoint(x:frame.maxX-windowSize.width-20,y:frame.maxY-windowSize.height-20))
    }
    func show(url: String) {
        collapseTask?.cancel()
        timelineHover=false; updateTimeline()
        if !placed { place(); placed = true }
        if ViewerReusePolicy.shouldLoad(requested:url,loaded:currentURL,hasPage:web.url != nil) {
            currentURL = url; message = "Instagram загружается в плавающем окне"
            web.load(URLRequest(url:URL(string:url)!))
        } else {
            message = "Плавающее окно готово · сохранённая лента"
            evaluatePlayerScript("window.__rwgSuspended = false; window.__rwgSeekLanguage = '\(L("ru","en"))'; window.__rwgSeekUpdate && window.__rwgSeekUpdate(); window.__rwgMuted = \(UserDefaults.standard.object(forKey:"muted") as? Bool ?? true); window.__rwgAlignReel && window.__rwgAlignReel(); window.__rwgResume && window.__rwgResume();",completionHandler:nil)
        }
        // Do not activate our application: keep the current fullscreen Space and ChatGPT focus.
        panel.orderFrontRegardless()
    }
    func hide() {
        collapseTask?.cancel(); timelineHover=false; updateTimeline()
        gate.reset(); videoRect = nil; seekState(["ready":false])
        evaluatePlayerScript("window.__rwgSuspended = true; document.querySelectorAll('video').forEach(v => v.pause());",completionHandler:nil)
        if web.url?.path.contains("/accounts/") == true || !(UserDefaults.standard.object(forKey:"keepLoaded") as? Bool ?? true) { currentURL = nil; web.loadHTMLString("",baseURL:nil) }
        panel.orderOut(nil); message = "Плавающее окно скрыто"
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let current=sender.contentRect(forFrameRect:sender.frame).size
        let proposed=sender.contentRect(forFrameRect:NSRect(origin:.zero,size:frameSize)).size
        let content=OverlayLayout.resized(current:current,proposed:proposed,timeline:timelineHeight)
        return sender.frameRect(forContentRect:NSRect(origin:.zero,size:content)).size
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        gate.reset()
        evaluatePlayerScript("window.__rwgAlignReel && window.__rwgAlignReel();",completionHandler:nil)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { currentURL = nil; videoRect = nil; seekState(["ready":false]) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func preview() {
        currentURL = nil
        web.loadHTMLString(L10n.text("<meta name='viewport' content='width=device-width,initial-scale=1'><body style='margin:0;background:#15151c;color:white;font-family:system-ui;display:grid;place-items:center;height:100vh'><div style='text-align:center'><div style='font-size:64px'>▶</div><h2>Плавающее окно 9:16</h2><p>Поверх полноэкранных приложений</p><p>Можно перемещать и менять размер</p></div></body>"),baseURL:nil)
        place(); panel.orderFrontRegardless(); message = "Локальный preview · без Instagram"
    }
    static func allowed(_ url: URL) -> Bool { SecurityPolicy.instagram(url) }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !action.shouldPerformDownload, let url = action.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" || Self.allowed(url) { decisionHandler(.allow) }
        else if action.targetFrame?.isMainFrame == false && url.scheme == "https" && url.user == nil && url.password == nil { decisionHandler(.allow) }
        else {
            message = "Внешняя страница заблокирована; вход выполняйте непосредственно в Instagram"
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny) // Viewing Reels needs neither camera nor microphone capture.
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, Self.allowed(url) { webView.load(action.request) }
        return nil
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { videoRect = nil; gate.reset(); seekState(["ready":false]) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if currentURL == nil { message = "Локальный preview · без Instagram"; return }
        message = webView.url?.path.contains("/accounts/") == true
            ? "Войдите один раз в Instagram в плавающем окне; вход сохранится"
            : "Плавающее окно готово · Instagram может требовать вход / Play"
        evaluatePlayerScript("window.__rwgSeekLanguage = '\(L("ru","en"))'; window.__rwgSeekUpdate && window.__rwgSeekUpdate(); window.__rwgMuted = \(UserDefaults.standard.object(forKey:"muted") as? Bool ?? true); window.__rwgResume && window.__rwgResume();",completionHandler:nil)
        if !panel.isVisible { hide() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        message = "Не удалось загрузить Instagram; проверьте подключение и повторите открытие"
    }
}
final class OverlayBridge: OverlayService {
    private var player: FloatingPlayer?
    private var previewPlayer: FloatingPlayer?
    private func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute:body)
    }
    func show(url: String) throws {
        guard let parsed = URL(string:url), FloatingPlayer.allowed(parsed) else { throw AppFailure(message:"Недопустимый URL Instagram") }
        onMain { if player == nil { player = FloatingPlayer() }; player!.show(url:url) }
    }
    func hide() { onMain { player?.hide(); previewPlayer?.hide() } }
    func clearWebsiteData(completion: @escaping () -> Void) {
        onMain {
            player?.unloadForDataRemoval(); player=nil
            previewPlayer?.unloadForDataRemoval(); previewPlayer=nil
            WKWebsiteDataStore.default().removeData(ofTypes:WKWebsiteDataStore.allWebsiteDataTypes(),modifiedSince:Date.distantPast) {
                DispatchQueue.main.async(execute:completion)
            }
        }
    }
    var status: String { onMain { player?.message ?? "Плавающее окно готово" } }
    func preview() { onMain { if previewPlayer == nil { previewPlayer = FloatingPlayer(previewOnly:true) }; previewPlayer!.preview() } }
}
