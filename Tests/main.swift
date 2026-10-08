import Foundation
import ApplicationServices

final class Fake: BrowserService {
    var signal: Signal = .busy
    var opened = 0, closed = 0, restored = 0, marked = 0
    var failOpen = false, failClose = false
    var pip = "loading", tucked = 0
    func preparePiP(_ owned: OwnedWindow) -> String { pip }
    func tuckAway(_ owned: OwnedWindow) { tucked += 1 }
    let tab = TabRef(window:1,tab:2,url:"https://chatgpt.com/c/test",title:"Test")
    func front(_ b: Browser) throws -> TabRef? { tab }
    func observe(_ b: Browser, _ t: TabRef, axOnly: Bool) -> Observation { Observation(signal:signal,method:"Fixture") }
    func mark(_ b: Browser, _ t: TabRef) -> TabRef { marked += 1; return t }
    func open(_ b: Browser, url: String) throws -> OwnedWindow {
        opened += 1
        if failOpen { throw AppFailure(message:"fixture open failure") }
        return OwnedWindow(browser:b,window:10,tab:20,pid:123,launch:nil)
    }
    func close(_ owned: OwnedWindow) throws -> String? {
        if failClose { throw AppFailure(message:"fixture close failure") }
        closed += 1; return nil
    }
    func restore(_ b: Browser, _ t: TabRef) throws { restored += 1 }
    func accessibility(_ b: Browser, _ t: TabRef) -> Signal { signal }
}
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(),message); checks += 1
}
let f = Fake(), e = Engine(bridge:f)
func tick(_ on: Bool = true, ax: Bool = false) throws {
    _ = try e.tick(enabled:on,b:.chrome,url:"https://www.instagram.com/reels/",axOnly:ax)
}
try tick(); check(f.opened == 1,"opens on busy")
try tick(); check(f.opened == 1,"no duplicate window on repeated busy")
f.signal = .unknown; try tick(); check(f.closed == 0,"unknown never completes")
f.signal = .idle; try tick(); try tick(); check(f.closed == 0,"idle transient is debounced")
f.signal = .unknown; try tick(); check(e.idleSamples == 0,"unknown resets completion counter")
f.signal = .idle; e.since = Date().addingTimeInterval(-10)
try tick(); e.idleSince = Date().addingTimeInterval(-3); try tick(); try tick()
check(f.closed == 1 && f.restored == 1 && e.origin == nil,"confirmed idle closes owned and returns ChatGPT")
f.signal = .busy; try tick(ax:true); check(f.marked == 1,"AX-only does not execute JS marker")
try tick(false); check(f.closed == 2 && f.restored == 1,"disable cleans up without focusing ChatGPT")
f.failOpen = true
try? tick(); try tick(); check(f.opened == 3,"open error latch prevents window spam")
_ = try e.finish(restore:false); f.failOpen = false
try tick(); f.failClose = true
_ = try? e.finish(restore:true); check(e.owned != nil,"failed close retains ownership for retry")
f.failClose = false; _ = try e.finish(restore:true)
check(e.owned == nil,"retry closes same owned window")
_ = try e.test(.safari,url:"https://www.instagram.com/reels/")
let opened = f.opened
_ = try e.test(.safari,url:"https://www.instagram.com/reels/")
check(f.opened == opened,"test also prevents duplicate windows")
e.testUntil = Date().addingTimeInterval(-1); try tick(false)
check(e.owned == nil,"test timer closes while disabled")
try tick(); e.since = Date().addingTimeInterval(-1801); try tick()
check(e.owned == nil,"30-minute fail-safe cleanup")
check(BrowserBridge.isChat("https://chatgpt.com/c/abc"),"allow exact ChatGPT host")
check(!BrowserBridge.isChat("https://chatgpt.com.evil.test/c/abc"),"reject lookalike host")
check(!BrowserBridge.isChat("http://chatgpt.com/"),"require HTTPS")
check(BrowserBridge.quote("a\"b\\c") == "\"a\\\"b\\\\c\"","safe AppleScript literal")


final class FakeNative: NativeService {
    var signal: Signal = .busy, available = true, restored = 0, observed = 0
    var availability: String { "Fixture unavailable" }
    func capture() -> NativeRef? { available ? NativeRef(pid:321,launch:nil,window:nil) : nil }
    func observe(_ ref: NativeRef) -> Observation { observed += 1; return Observation(signal:signal,method:"Native fixture") }
    func restore(_ ref: NativeRef) { restored += 1 }
}
let nf = FakeNative(), bf = Fake(), ne = Engine(bridge:bf,native:nf)
func nativeTick(_ on: Bool = true, source: ChatSource = .native) throws {
    _ = try ne.tick(enabled:on,b:.safari,url:"https://www.instagram.com/reels/",axOnly:false,source:source)
}
try nativeTick(); check(bf.opened == 1 && ne.nativeOrigin != nil && ne.origin == nil,"native busy starts own Reels window")
try nativeTick(); check(bf.opened == 1,"native repeated busy does not duplicate")
nf.available = false; try nativeTick(); check(nf.observed == 3,"native tracked ref persists when app loses focus")
nf.signal = .unknown; try nativeTick(); check(bf.closed == 0,"native unknown does not complete")
nf.signal = .idle; ne.since = Date().addingTimeInterval(-10)
try nativeTick(); ne.idleSince = Date().addingTimeInterval(-3); try nativeTick(); try nativeTick()
check(bf.closed == 1 && nf.restored == 1 && bf.restored == 0,"native completion restores native app only")
nf.available = true; nf.signal = .busy; try nativeTick()
try nativeTick(false); check(bf.closed == 2 && nf.restored == 1,"native Disable closes owned without activation")
nf.available = false; let total = bf.opened; try nativeTick()
check(bf.opened == total,"unavailable native app does not open Reels")
nf.available = true; try nativeTick(); nf.signal = .idle
ne.since = Date().addingTimeInterval(-10); try nativeTick(); ne.idleSince = Date().addingTimeInterval(-3)
try nativeTick(source:.browser); try nativeTick(source:.browser)
check(nf.restored == 2 && bf.restored == 0,"active session retains its source despite setting change")
var controls = NativeControls()
controls.add(role:"AXButton",label:"Stop",enabled:true)
check(controls.signal(complete:false) == .busy,"native exact Stop is a positive signal")
controls = NativeControls(); controls.add(role:"AXTextArea",label:"",enabled:true)
controls.add(role:"AXButton",label:"Отправить",enabled:false)
check(controls.signal(complete:true) == .idle,"empty composer with disabled Send confirms idle")
check(controls.signal(complete:false) == .unknown,"incomplete native tree is unknown")
controls = NativeControls(); controls.add(role:"AXButton",label:"Start voice",enabled:true)
check(controls.signal(complete:true) == .unknown,"ready button without composer is unknown")


final class FakeOverlay: OverlayService {
    var shown = 0, hidden = 0
    var status: String { "Fixture floating overlay" }
    func show(url:String) throws { shown += 1 }
    func hide() { hidden += 1 }
}
let of = FakeOverlay(), ob = Fake(), on = FakeNative(), oe = Engine(bridge:ob,native:on,overlay:of)
func overlayTick(_ enabled:Bool = true) throws {
    _ = try oe.tick(enabled:enabled,b:.safari,url:"https://www.instagram.com/reels/",axOnly:false,source:.native,playback:.floating)
}
try overlayTick()
check(of.shown == 1 && ob.opened == 0 && oe.floatingActive,"floating opens owned panel, no browser window")
try overlayTick(); check(of.shown == 1,"floating does not duplicate on repeated busy")
on.signal = .unknown; try overlayTick(); check(of.hidden == 0,"unknown retains floating player")
on.signal = .idle; oe.since = Date().addingTimeInterval(-10)
try overlayTick(); oe.idleSince = Date().addingTimeInterval(-3); try overlayTick(); try overlayTick()
check(of.hidden == 1 && ob.closed == 0 && on.restored == 1,"completion hides own panel and restores ChatGPT")
on.signal = .busy; try overlayTick(); try overlayTick(false)
check(of.hidden == 2 && on.restored == 1,"disable hides overlay without stealing focus")
_ = try oe.login(url:"https://www.instagram.com/reels/"); try overlayTick(false)
check(oe.setupOpen && of.hidden == 2,"login setup remains visible while monitoring is off")
try overlayTick(); check(!oe.setupOpen && of.hidden == 3 && oe.nativeOrigin != nil,"enabling after setup hides setup before monitoring")
_ = try oe.finish(restore:false)
_ = try oe.test(.chrome,url:"https://www.instagram.com/reels/",playback:.floating)
oe.testUntil = Date().addingTimeInterval(-1); try overlayTick(false)
check(!oe.floatingActive && ob.opened == 0,"floating Test expires without browser operations")
let pb = Fake(), pn = FakeNative(), pe = Engine(bridge:pb,native:pn,overlay:FakeOverlay())
func pipTick() throws {
    _ = try pe.tick(enabled:true,b:.chrome,url:"https://www.instagram.com/reels/",axOnly:false,source:.native,playback:.browserPiP)
}
try pipTick(); pb.pip = "gesture"; try pipTick()
check(pn.restored == 0 && pb.tucked == 0,"no premature return before PiP succeeds")
pb.pip = "active"; try pipTick(); try pipTick()
check(pn.restored == 1 && pb.tucked == 1,"PiP returns source and tucks own staging window once")
check(pe.owned != nil,"PiP ownership retained until generation completes")
let size = OverlayLayout.size(available:CGSize(width:1440,height:900))
check(size.width == 360 && size.height == 668,"default overlay adds the timeline below a 360x640 video")
let small = OverlayLayout.size(available:CGSize(width:800,height:600))
check(small.height <= 510 && abs(small.width/(small.height-OverlayLayout.timelineHeight)-9.0/16.0) < 0.001,"overlay fits small display and preserves portrait")
let wider = OverlayLayout.resized(current:size,proposed:CGSize(width:400,height:668))
check(abs((wider.height-28)/wider.width-16.0/9) < 0.000001,"width resize preserves the video's aspect ratio")
let taller = OverlayLayout.resized(current:size,proposed:CGSize(width:360,height:804))
check(abs(taller.width-436.5) < 0.000001 && taller.height == 804,"height resize excludes timeline before calculating width")
check(OverlayLayout.resized(current:size,proposed:CGSize(width:100,height:100)).width == 240,"minimum size includes the timeline")
check(OverlayLayout.resized(current:size,proposed:CGSize(width:1000,height:2000)).width == 480,"maximum size preserves video geometry")
check(OverlayLayout.timeline(autoMini:false,hovering:false,dragging:false) == 28,"timeline is smaller by default")
check(OverlayLayout.timeline(autoMini:true,hovering:false,dragging:false) == 10,"mini preference collapses idle timeline")
check(OverlayLayout.timeline(autoMini:true,hovering:true,dragging:false) == 28,"hover expands timeline")
check(OverlayLayout.timeline(autoMini:true,hovering:false,dragging:true) == 28,"dragging keeps timeline expanded outside its bounds")
let miniSize=OverlayLayout.contentSize(width:360,timeline:10)
check(miniSize.height == 650 && miniSize.height-10 == size.height-28,"collapse preserves the exact video size")
let miniResize=OverlayLayout.resized(current:miniSize,proposed:CGSize(width:360,height:810),timeline:10)
check(miniResize.width == 450 && miniResize.height == 810,"resize uses the current compact timeline height")
check(AXPermission.evaluate(trusted:true,probe:.success,hasValue:true),"actual Accessibility granted")
check(AXPermission.evaluate(trusted:false,probe:.success,hasValue:true),"successful AX access handles stale trust flag")
check(!AXPermission.evaluate(trusted:true,probe:.apiDisabled,hasValue:false),"disabled AX API overrides stale granted flag")
check(AXPermission.evaluate(trusted:true,probe:.cannotComplete,hasValue:false),"temporary focus error does not revoke granted permission")
check(!AXPermission.evaluate(trusted:false,probe:.cannotComplete,hasValue:false),"missing permission remains separate from enabled state")


let variants = ["Interrupt", "Interrupt response", "Stop response", "Stop turn", "Stop (Esc)", "Stop generating response", "stop_turn_button", "Прервать", "Остановить ответ", "Остановить (Esc)"]
for label in variants {
    var c = NativeControls(); c.add(role:"AXButton",label:label,enabled:true)
    check(c.signal(complete:false) == .busy,"native response marker: " + label)
}
var c = NativeControls(); c.add(role:"AXGroup",label:"Interrupt",enabled:true,pressable:true)
check(c.signal(complete:true) == .busy,"custom clickable AXGroup interrupt is detected")
c = NativeControls(); c.add(role:"AXButton",label:"Stop recording",enabled:true)
check(c.signal(complete:true) == .unknown,"recording controls are not response generation")
c = NativeControls(); c.add(role:"AXButton",label:"Stop",enabled:false)
check(c.signal(complete:true) == .unknown,"disabled stale Stop is not busy")
check(NativeChat.chooseWindow(signals:[.idle,.busy],focused:0) == 1,"busy background chat is detected while another window is focused")
check(NativeChat.chooseWindow(signals:[.unknown,.busy],focused:nil) == 1,"generation detected with no AXFocusedWindow")
check(NativeChat.chooseWindow(signals:[.busy,.busy],focused:1) == 1,"focused busy window wins when multiple chats generate")
check(NativeChat.chooseWindow(signals:[],focused:nil) == nil,"missing AXWindows does not invent a request")
check(NativeChat.brandedChatGPT(name:"Codex",displayName:"ChatGPT",bundleName:nil,path:nil),"display branding identifies modern ChatGPT")
check(!NativeChat.brandedChatGPT(name:"Codex",displayName:"Codex",bundleName:"Codex",path:"/Applications/Codex.app"),"unrelated Codex is not selected automatically")
check(NativeChat.brandedChatGPT(name:nil,displayName:nil,bundleName:nil,path:"/Applications/ChatGPT.app"),"app bundle path is a safe branding fallback")
var scan = NativeScan(); scan.controls.add(role:"AXButton",label:"Interrupt",enabled:true); scan.complete = false
check(scan.signal == .busy,"positive stop works despite partial AX traversal")
scan = NativeScan(); scan.controls.add(role:"AXTextArea",label:"",enabled:true); scan.controls.add(role:"AXButton",label:"Send",enabled:false); scan.complete=false
check(scan.signal == .unknown,"partial tree cannot falsely complete a response")
check(!scan.summary.contains("AXValue"),"native diagnostics do not contain editor values")
var swipe = ReelSwipeGate()
check(swipe.step(delta:-20,began:true,ended:false,momentum:false,phased:true,time:0) == nil,"small motion does not turn a reel")
check(swipe.step(delta:-20,began:false,ended:false,momentum:false,phased:true,time:0.01) == 1,"upward natural scroll advances one reel")
check(swipe.step(delta:-100,began:false,ended:true,momentum:false,phased:true,time:0.02) == nil,"same gesture cannot skip more reels")
check(swipe.step(delta:-100,began:false,ended:false,momentum:true,phased:false,time:1) == nil,"inertial tail never turns another reel")
check(swipe.step(delta:40,began:true,ended:false,momentum:false,phased:true,time:2) == -1,"new reverse gesture goes back")
swipe.reset()
check(swipe.step(delta:-40,began:false,ended:false,momentum:false,phased:false,time:3) == 1,"wheel burst turns one reel")
check(swipe.step(delta:-80,began:false,ended:false,momentum:false,phased:false,time:3.1) == nil,"same wheel burst is grouped")
check(swipe.step(delta:-40,began:false,ended:false,momentum:false,phased:false,time:4) == 1,"later wheel burst can advance")
check(!ViewerReusePolicy.shouldLoad(requested:"https://www.instagram.com/reels/",loaded:"https://www.instagram.com/reels/",hasPage:true),"same feed reuses live page after hiding and SPA redirects")
check(ViewerReusePolicy.shouldLoad(requested:"https://www.instagram.com/reels/new",loaded:"https://www.instagram.com/reels/",hasPage:true),"changed URL loads a new page")
check(ViewerReusePolicy.shouldLoad(requested:"https://www.instagram.com/reels/",loaded:nil,hasPage:true),"terminated content process reloads")
check(ViewerReusePolicy.shouldLoad(requested:"https://www.instagram.com/reels/",loaded:"https://www.instagram.com/reels/",hasPage:false),"missing page reloads")
check(L10n.text("Генерация обнаружена · Плавающее окно готово",language:.en) == "Generation detected · Floating window ready","compound status translates fully")
check(L10n.text("ChatGPT app: генерация · Return",language:.ru) == "Приложение ChatGPT: генерация · Вернуться","Russian status removes mixed English labels")
check(L10n.text("Проверка #2 завершена · Запущено из:",language:.en) == "Check #2 completed · Running from:","diagnostic headings translate")
check(L10n.text("Preview 9:16",language:.ru) == "Макет 9:16","preview label is Russian")
let backgroundNative = FakeNative(), backgroundBrowser = Fake(), backgroundOverlay = FakeOverlay()
let backgroundEngine = Engine(bridge:backgroundBrowser,native:backgroundNative,overlay:backgroundOverlay)
func backgroundTick() throws { _ = try backgroundEngine.tick(enabled:true,b:.chrome,url:"https://www.instagram.com/reels/",axOnly:false,source:.native,playback:.floating,returnAfterResponse:false) }
try backgroundTick(); backgroundNative.available = false; backgroundNative.signal = .idle
backgroundEngine.since = Date().addingTimeInterval(-10)
try backgroundTick(); backgroundEngine.idleSince = Date().addingTimeInterval(-3); try backgroundTick(); try backgroundTick()
check(backgroundOverlay.hidden == 1,"completion closes Reels when app capture is unavailable in background")
check(backgroundNative.restored == 0,"background completion preserves user's current window when auto return is off")
check(backgroundEngine.nativeOrigin == nil && !backgroundEngine.floatingActive,"background completion clears tracked session")
let manualOverlay = FakeOverlay(), manualNative = FakeNative(), manualBrowser = Fake()
let manualEngine = Engine(bridge:manualBrowser,native:manualNative,overlay:manualOverlay)
_ = try manualEngine.manualOpen(.chrome,url:"https://www.instagram.com/reels/",playback:.floating)
_ = try manualEngine.tick(enabled:false,b:.chrome,url:"https://www.instagram.com/reels/",axOnly:false,source:.native,playback:.floating)
check(manualOverlay.shown == 1 && manualOverlay.hidden == 0,"manual Reels stays open with monitoring disabled")
check(manualNative.observed == 0 && manualEngine.testUntil == nil,"manual Reels needs no request and no 8-second timeout")
_ = try manualEngine.finish(restore:false)
check(manualOverlay.hidden == 1,"manual close hides the app-owned viewer")
_ = try manualEngine.manualOpen(.chrome,url:"https://www.instagram.com/reels/",playback:.browserPiP)
let manualMessage = try manualEngine.tick(enabled:false,b:.chrome,url:"https://www.instagram.com/reels/",axOnly:false,source:.native,playback:.browserPiP)
check(manualBrowser.opened == 1 && manualBrowser.closed == 0 && manualMessage != manualOverlay.status,"manual browser mode reports browser playback, not embedded viewer status")
_ = try manualEngine.finish(restore:false)
check(manualBrowser.closed == 1,"manual browser close closes only the owned window")
func userState(_ trusted: Bool = true, _ access: AccessState = .allowed, _ raw: String = "Готов к запросу в приложении ChatGPT", _ on: Bool = true, _ failed: Bool = false, _ valid: Bool = true, _ open: Bool = false, _ required: Bool = true) -> UserStatus {
    UserStatus.resolve(enabled:on,needsAX:required,trusted:trusted,access:access,validURL:valid,failed:failed,raw:raw,viewerOpen:open)
}
check(userState(false) == .accessDenied,"missing global Accessibility permission shows corrective guidance")
check(userState(true,.denied) == .accessDenied,"target permission denied is visible even when global trust is true")
check(userState(true,.allowed,"bundle=x; AXWindows error=-25211") == .accessDenied,"fresh target denial is not hidden by a previous successful probe")
check(userState(true,.allowed,"AXManualAccessibility=-25205; AXEnhancedUserInterface=-25208") == .ready,"unsupported optional flags do not become user-facing access errors")
check(userState(true,.allowed,"Детектор: bundle=x, nodes=328",false) == .manualReady,"technical diagnostics are reduced to a friendly manual-ready state")
check(userState(true,.allowed,"Ручной просмотр · закройте окно, когда закончите",false) == .viewing,"manual viewer has a clear open status")
check(userState(true,.allowed,"Плавающее окно готово",false,false,true,true) == .viewing,"retained manual window remains identified as open after polling")
check(userState(true,.allowed,"Приложение ChatGPT не найдено",true) == .openChat,"missing app tells user to open ChatGPT")
check(userState(true,.allowed,"ChatGPT app: сигнал не распознан",true) == .unrecognized,"unknown detection does not claim everything works")
check(userState(true,.allowed,"ChatGPT app: генерация · nodes=100",true) == .answering,"active response gets a nontechnical status")
check(userState(true,.allowed,"arbitrary exception with PID",false,true) == .operationFailed,"exceptions stay out of the overview")
check(userState(true,.allowed,"",false,false,false) == .invalidAddress,"invalid URL has an actionable status")
check(userState(false,.unchecked,"Готов к следующему запросу",true,false,true,false,false) == .ready,"DOM-only browser does not require optional AX access")
let lockTestPath = NSTemporaryDirectory()+"Reels-lock-test-"+UUID().uuidString
var firstLock = SingleInstanceLock(path:lockTestPath)
check(firstLock != nil,"first instance obtains process lock")
check(SingleInstanceLock(path:lockTestPath) == nil,"second instance cannot obtain held lock")
firstLock=nil
check(SingleInstanceLock(path:lockTestPath) != nil,"lock is released when owner exits")
try? FileManager.default.removeItem(atPath:lockTestPath)
check(SecurityPolicy.savedReelsURL("https://www.instagram.com/reels/?session=dummy-secret#token") == "https://www.instagram.com/reels/","query/fragment secrets never enter saved preferences")
check(SecurityPolicy.savedReelsURL("https://www.instagram.com/reel/ABC123/?utm_source=test") == "https://www.instagram.com/reel/ABC123/","a public reel address is retained without tracking parameters")
for invalid in ["http://www.instagram.com/reels/","https://instagram.com.evil.test/reels/","https://user:dummy@instagram.com/reels/","https://instagram.com:443/reels/","file:///reels/","javascript:alert(1)","https://www.instagram.com/accounts/login/?password=dummy"] {
    check(SecurityPolicy.savedReelsURL(invalid) == nil,"unsafe or login address cannot be saved")
}
check(SecurityPolicy.instagram(URL(string:"https://www.instagram.com/accounts/login/")!),"official Instagram login navigation still works")
check(!SecurityPolicy.instagram(URL(string:"https://dummy@www.instagram.com/")!),"embedded credentials are rejected in navigation")
check(!SecurityPolicy.chat(URL(string:"https://chatgpt.com.evil.test/")!),"lookalike ChatGPT host is rejected")
check(!SecurityPolicy.chat(URL(string:"https://user:dummy@chatgpt.com/")!),"ChatGPT URL credentials rejected")
for role in ["AXStaticText","AXLink","AXTextArea","AXTextField","AXTextEntryArea","AXSecureTextField"] {
    check(!SecurityPolicy.metadataAllowed(role:role,pressable:true),"text/input metadata is excluded even for pressable elements")
    check(!SecurityPolicy.childContentAllowed(role:role),"private text/input children are excluded")
}
check(SecurityPolicy.metadataAllowed(role:"AXButton"),"detector still reads real button labels")
print("PASS: \(checks) lifecycle, overlay, PiP, native marker and permission checks")
