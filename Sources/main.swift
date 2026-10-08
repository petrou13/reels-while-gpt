import AppKit
import SwiftUI
import ApplicationServices

final class Model: ObservableObject {
    @Published var tab = 0
    @Published var viewerOpen = false
    @Published var nativeAccess: AccessState = .unchecked
    @Published var operationError = false
    var friendlyStatus: UserStatus {
        UserStatus.resolve(enabled:enabled,needsAX:source == .native || axOnly,trusted:axGranted,access:source == .native ? nativeAccess : .unchecked,validURL:validatedURL() != nil,failed:operationError,raw:status,viewerOpen:viewerOpen)
    }
    @Published var returnAfterResponse = UserDefaults.standard.bool(forKey:"returnAfterResponse")
    @Published var language = L10n.language
    @Published var keepLoaded = UserDefaults.standard.object(forKey:"keepLoaded") as? Bool ?? true
    @Published var miniTimeline = UserDefaults.standard.bool(forKey:"miniTimeline")
    @Published var muted = UserDefaults.standard.object(forKey:"muted") as? Bool ?? true
    func preferencesChanged() {
        UserDefaults.standard.set(language.rawValue,forKey:"language")
        UserDefaults.standard.set(keepLoaded,forKey:"keepLoaded")
        UserDefaults.standard.set(muted,forKey:"muted")
        UserDefaults.standard.set(miniTimeline,forKey:"miniTimeline")
        UserDefaults.standard.set(returnAfterResponse,forKey:"returnAfterResponse")
        NotificationCenter.default.post(name:Notification.Name("ReelsPreferencesChanged"),object:nil)
        changed?()
    }
    @Published var enabled = UserDefaults.standard.bool(forKey:"enabled")
    @Published var playback: PlaybackMode = PlaybackMode(rawValue:UserDefaults.standard.string(forKey:"playback") ?? "") ?? .floating
    @Published var axGranted = AXPermission.isGranted
    @Published var source: ChatSource = ChatSource(rawValue:UserDefaults.standard.string(forKey:"source") ?? "") ?? .native
    @Published var browser: Browser = Browser(rawValue: UserDefaults.standard.string(forKey: "browser") ?? "") ?? .chrome
    @Published var reelsURL = SecurityPolicy.savedReelsURL(UserDefaults.standard.string(forKey:"url") ?? "") ?? SecurityPolicy.defaultReelsURL
    @Published var clearingLogin = false
    @Published var nativeReport = "Нажмите «Проверить детектор» во время активного запроса ChatGPT"
    @Published var connectionTitle = ""
    @Published var connectionDetail = ""
    @Published var checking = false
    @Published var diagnosticExpanded = false
    @Published var checkResult = ""
    @Published var copyFeedback = ""
    private var checkNumber = 0
    private var diagnosticSelection = ""
    @Published var axOnly = UserDefaults.standard.bool(forKey: "axOnly")
    @Published var status = "Мониторинг выключен — включите переключатель выше"
    private let worker = DispatchQueue(label: "local.ReelsWhileGPT.browser")
    private let engine = Engine()
    private var working = false
    private var shuttingDown = false
    private var timer: Timer?
    private var monitoringActivity: NSObjectProtocol?
    private var focusObserver: NSObjectProtocol?
    var changed: (() -> Void)?
    init() {
        // Migrate older preferences immediately without retaining URL query/fragment data.
        UserDefaults.standard.set(reelsURL,forKey:"url")
        let t = Timer(timeInterval:0.8,repeats:true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t,forMode:.common); timer = t
        focusObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] _ in self?.poll() }
    }
    deinit {
        timer?.invalidate()
        if let monitoringActivity { ProcessInfo.processInfo.endActivity(monitoringActivity) }
        if let focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(focusObserver) }
    }
    func validatedURL() -> String? { SecurityPolicy.savedReelsURL(reelsURL) }
    func forgetInstagramLogin() {
        guard !clearingLogin else { return }
        let alert=NSAlert()
        alert.messageText=L("Удалить сохранённый вход в аккаунт?","Remove saved account sign-in?")
        alert.informativeText=L("Встроенное окно закроется, автоматический просмотр выключится. Будут удалены cookies, данные сайта и кэш этого приложения. Вход в Safari и Chrome сохранится.","The built-in viewer will close and automatic viewing will turn off. This app's cookies, website data and cache will be removed. Safari and Chrome sign-in stays unchanged.")
        alert.addButton(withTitle:L("Удалить вход","Remove sign-in")); alert.addButton(withTitle:L("Отмена","Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clearingLogin=true; enabled=false; save()
        worker.async {
            do { _ = try self.engine.finish(restore:false,disarmNative:true) }
            catch {
                DispatchQueue.main.async { self.clearingLogin=false; self.operationError=true; self.status=L("Не удалось закрыть просмотрщик. Повторите удаление входа.","Unable to close the viewer. Retry removing sign-in.") }
                return
            }
            self.engine.overlay.clearWebsiteData {
                self.enabled=false; self.save(); self.clearingLogin=false; self.viewerOpen=false
                self.status=L("Сохранённый вход удалён. При следующем открытии ленты потребуется войти заново.","Saved sign-in removed. You will need to sign in when reopening the feed.")
            }
        }
    }
    func save() {
        let selection = "\(source.rawValue)|\(browser.rawValue)|\(axOnly)"
        if selection != diagnosticSelection {
            diagnosticSelection=selection; connectionTitle=""; connectionDetail=""; checkResult=""
            nativeReport=L("Подключение изменено. Нажмите «Проверить детектор» для новой проверки.","Connection changed. Click Check detector to check the new selection.")
            diagnosticExpanded=false
        }
        UserDefaults.standard.set(enabled,forKey:"enabled")
        UserDefaults.standard.set(playback.rawValue,forKey:"playback")
        UserDefaults.standard.set(source.rawValue,forKey:"source")
        UserDefaults.standard.set(browser.rawValue,forKey:"browser")
        UserDefaults.standard.set(validatedURL() ?? SecurityPolicy.defaultReelsURL,forKey:"url")
        UserDefaults.standard.set(axOnly,forKey:"axOnly")
    }
    func poll() {
        guard !clearingLogin else { return }
        if enabled && !shuttingDown && monitoringActivity == nil {
            monitoringActivity = ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Monitor user-requested ChatGPT response completion")
        } else if (!enabled || shuttingDown), let activity = monitoringActivity {
            ProcessInfo.processInfo.endActivity(activity); monitoringActivity = nil
        }
        axGranted = AXPermission.isGranted
        guard !working && !shuttingDown && !clearingLogin else { return }
        let url = validatedURL() ?? "https://www.instagram.com/reels/"
        if validatedURL() == nil && enabled {
            enabled = false; save()
            status = "Неверный адрес ленты — укажите поддерживаемый HTTPS-адрес и включите мониторинг снова"
            changed?(); return
        }
        save(); working = true
        let on = enabled, b = browser, ax = axOnly, selectedSource = source, mode = playback, autoReturn = returnAfterResponse
        worker.async {
            let access = selectedSource == .native ? self.engine.native.permissionStatus() : AccessState.unchecked
            var failed = false
            let message: String
            do { message = try self.engine.tick(enabled: on,b: b,url: url,axOnly: ax,source: selectedSource,playback:mode,returnAfterResponse:autoReturn) }
            catch { message = (error as? AppFailure)?.message ?? L("Не удалось выполнить действие. Проверьте разрешения и повторите попытку.","Unable to complete this action. Check permissions and try again."); failed = true }
            let open = self.engine.floatingActive || self.engine.owned != nil
            DispatchQueue.main.async {
                self.viewerOpen = open
                self.working = false; self.nativeAccess = access; self.status = message
                if on { self.operationError = failed }
                self.changed?()
            }
        }
    }
    func command(test: Bool = false, quit: Bool = false, login: Bool = false, preview: Bool = false, manual: Bool = false) {
        guard !clearingLogin else { return }
        operationError = false
        if quit { save(); shuttingDown = true }
        else if !test { enabled = false; save() }
        guard !(test || login || manual) || validatedURL() != nil else { status = "Введите поддерживаемый HTTPS-адрес ленты"; return }
        let b = browser, mode = playback, url = validatedURL() ?? "https://www.instagram.com/reels/"
        worker.async {
            var failed = false
            let message: String
            do {
                if manual { message = try self.engine.manualOpen(b,url:url,playback:mode) }
                else if preview { message = try self.engine.preview() }
                else if login { message = try self.engine.login(url:url) }
                else if test { message = try self.engine.test(b,url:url,playback:mode) }
                else { message = try self.engine.finish(restore:!quit,disarmNative:true) }
            }
            catch { message = (error as? AppFailure)?.message ?? L("Не удалось выполнить действие. Проверьте разрешения и повторите попытку.","Unable to complete this action. Check permissions and try again."); failed = true }
            let open = self.engine.floatingActive || self.engine.owned != nil
            DispatchQueue.main.async {
                self.viewerOpen = open
                self.operationError = failed; self.status = message; self.changed?()
                if quit { NSApp.reply(toApplicationShouldTerminate: true) }
            }
        }
    }
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text,forType:.string)
        copyFeedback = "Скопировано"
    }
    func revealApp() { NSWorkspace.shared.selectFile(Bundle.main.bundlePath,inFileViewerRootedAtPath:"") }
    func diagnose() {
        guard !checking else { return }
        diagnosticSelection="\(source.rawValue)|\(browser.rawValue)|\(axOnly)"
        checking = true; diagnosticExpanded = false; checkNumber += 1
        let number = checkNumber
        checkResult = "Проверка #\(number): выполняется…"
        let identity = "Reels While GPT \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?")\nЗапущено из: \(URL(fileURLWithPath:Bundle.main.bundlePath).lastPathComponent)\nAXIsProcessTrusted=\(AXIsProcessTrusted())"
        let selectedSource = source, b = browser, ax = axOnly
        connectionTitle = L("Проверяем выбранное подключение…","Checking selected connection…")
        connectionDetail = ""
        worker.async {
            let result = self.engine.connectionDiagnosis(source:selectedSource,b:b,axOnly:ax)
            DispatchQueue.main.async {
                guard self.source == selectedSource && self.browser == b && self.axOnly == ax else {
                    self.checking=false; self.checkResult=L("Подключение изменено — повторите проверку","Connection changed — check again"); self.connectionTitle=""; self.connectionDetail=""; return
                }
                let time = DateFormatter.localizedString(from:Date(),dateStyle:.short,timeStyle:.medium)
                self.nativeAccess = result.access
                self.checking = false
                self.checkResult = "Проверка #\(number) завершена · \(time)"
                self.nativeReport = self.checkResult + "\n" + identity + "\n" + result.report
                self.connectionTitle = result.title; self.connectionDetail = result.detail
                self.copyFeedback = ""
            }
        }
    }
    func requestAX() {
        let alert = NSAlert()
        alert.messageText = L("Разрешить распознавание запросов?","Allow request detection?")
        alert.informativeText = L("Универсальный доступ позволяет находить кнопку остановки ответа в ChatGPT. Включите разрешение для Reels While GPT в настройках macOS. Текст сообщений и пароли не считываются.","Accessibility lets this app find ChatGPT’s stop button. Enable Reels While GPT in macOS settings. Message text and passwords are not read.")
        alert.addButton(withTitle:L("Перейти в настройки","Open Settings"))
        alert.addButton(withTitle:L("Не сейчас","Not Now"))
        let respond: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        if let window = NSApp.keyWindow { alert.beginSheetModal(for:window,completionHandler:respond) }
        else { respond(alert.runModal()) }
    }

}
struct SettingsIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing:10) {
            configuration.icon.frame(width:22,alignment:.center).accessibilityHidden(true)
            configuration.title
        }
    }
}
struct SettingsView: View {
    @ObservedObject var model: Model
    func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment:.leading,spacing:13) {
            Label(title,systemImage:icon).font(.headline)
            content()
        }.padding(21).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(nsColor:.controlBackgroundColor)).cornerRadius(13)
    }
    func helpRow(_ title: String, _ description: String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.subheadline.bold())
            Text(description).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    func navigation(_ index: Int, _ title: String, _ icon: String) -> some View {
        Button { model.tab = index } label: {
            Label(title,systemImage:icon).font(.body.weight(model.tab == index ? .semibold : .regular))
                .frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,11).padding(.horizontal,13)
                .background(model.tab == index ? Color.accentColor.opacity(0.16) : Color.clear).cornerRadius(8)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    var body: some View {
        HStack(alignment:.top,spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                if let icon = NSImage(named:"AppIcon") { Image(nsImage:icon).resizable().frame(width:55,height:55).accessibilityHidden(true).padding(.bottom,5) }
                Text("Reels\nWhile GPT").font(.title2.bold())
                Text(L("Ваш маленький перерыв, пока ChatGPT думает","Your little break while ChatGPT thinks")).font(.caption).foregroundStyle(.secondary).padding(.bottom,21)
                navigation(0,L("Просмотр","Watch"),"play.rectangle")
                navigation(1,L("Подключение","Connection"),"macwindow")
                navigation(2,L("Справка","Help"),"questionmark.circle")
                Spacer()
                Text("v1.18").font(.caption).foregroundStyle(.secondary)
            }.padding(21).frame(width:190).frame(maxHeight:.infinity).background(Color(nsColor:.controlBackgroundColor).opacity(0.6))
            VStack(alignment:.leading,spacing:13) {
                Text(model.tab == 0 ? L("Ваши Reels — в один клик","Your Reels, one click away") : model.tab == 1 ? L("Подключение и проверка","Connection and diagnostics") : L("Как пользоваться программой","How to use this app")).font(.title2.bold())
                ScrollView {
                    VStack(spacing:13) {
                        if model.tab == 0 {
                            card(model.friendlyStatus.title,icon:model.friendlyStatus.isProblem ? "exclamationmark.circle" : "checkmark.circle") {
                                Text(model.friendlyStatus.detail).font(.callout).foregroundStyle(.secondary)
                                if model.friendlyStatus == .accessDenied {
                                    Button(L("Разрешить распознавание запросов…","Allow request detection…")) { model.requestAX() }.help(L("Сначала предлагает перейти в настройки доступа. Настройки откроются только после вашего подтверждения.","Offer to open Accessibility settings. Settings only open when you choose to proceed."))
                                } else if model.friendlyStatus == .invalidAddress || model.friendlyStatus == .operationFailed {
                                    Button(L("Проверить настройки","Check settings")) { model.tab = 1 }
                                } else if model.friendlyStatus == .unrecognized { Button(L("Проверить подключение","Check connection")) { model.tab = 1 } }
                            }
                            card(L("Смотреть сейчас","Watch now"),icon:"play.fill") {
                                HStack(spacing:13) {
                                    Button(L("Открыть Reels","Open Reels")) { model.command(manual:true) }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut("r",modifiers:.command).help(L("Открывает ленту видео без запроса ChatGPT и выключает автоматический режим. Сочетание клавиш: Cmd+R.","Open the video feed without waiting for ChatGPT. Manual viewing turns automatic mode off. Cmd+R."))
                                    Button(L("Закрыть Reels","Close Reels")) { model.command() }.controlSize(.large).help(L("Закрывает свой просмотрщик и выключает автоматический режим. Если он открыт для ответа, возвращает к исходному диалогу.","Close the app’s viewer and turn automatic mode off. If opened for a response, return to that conversation."))
                                }
                                Text(L("Смотрите Reels без запроса ChatGPT и закройте окно, когда закончите. При ручном просмотре автоматический режим выключается.","Watch Reels without a ChatGPT request and close the window when finished. Manual viewing turns automatic mode off.")).font(.callout).foregroundStyle(.secondary)
                                Toggle(L("Открывать Reels, пока ChatGPT готовит ответ","Open Reels while ChatGPT prepares a response"),isOn:$model.enabled).disabled(model.clearingLogin).onChange(of:model.enabled) { _ in model.save(); model.poll() }.help(L("Автоматически открывает Reels при начале ответа ChatGPT и закрывает их после завершения. Для распознавания запросов нужно разрешение macOS.","Automatically open Reels when ChatGPT starts responding and close them after completion. Request detection permission is required."))
                            }
                            card(L("Где смотреть Reels","Where to watch Reels"),icon:"rectangle.portrait") {
                                Picker(L("Просмотр Reels","Reels viewer"),selection:$model.playback) { ForEach(PlaybackMode.allCases,id:\.self) { Text($0 == .floating ? L("Встроенное плавающее окно","Built-in floating window") : L("Картинка в картинке браузера","Browser picture-in-picture")).tag($0) } }.disabled(model.enabled).help(L("Встроенное окно поддерживает свайпы, перемотку видео и сохранение ленты. Браузерный режим использует картинку в картинке.","The built-in window supports swipes, video seeking and saved pages. Browser mode uses picture-in-picture."))
                                if model.playback == .browserPiP {
                                    Picker(L("Браузер для Reels","Reels browser"),selection:$model.browser) { ForEach(Browser.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.disabled(model.enabled).help(L("Выбранный браузер используется для Reels и для проверки запросов, если ChatGPT также открыт в браузере.","The selected browser is used for Reels and for request detection if you also use ChatGPT in a browser."))
                                }
                                if model.enabled { Text(L("Чтобы изменить место просмотра, выключите открытие Reels при запросах ChatGPT.","Turn off request-triggered Reels viewing to change the viewer.")).font(.caption).foregroundStyle(.secondary) }
                                Text(L("Встроенный просмотрщик поддерживает свайпы и быстрое повторное открытие. Режим браузера использует собственную сессию аккаунта.","The built-in viewer supports swipes and fast reopening. Browser mode uses the browser’s account session.")).font(.callout).foregroundStyle(.secondary)
                                if model.playback == .floating { Button(L("Войти в аккаунт","Sign in to your account")) { model.command(login:true) }.help(L("Открывает встроенное окно без ограничения времени, чтобы вы могли войти в аккаунт. Автоматический режим выключается.","Open the built-in viewer without a timer for account sign-in. Automatic mode turns off.")) }
                                Button(model.clearingLogin ? L("Удаляем вход…","Removing sign-in…") : L("Удалить сохранённый вход в аккаунт…","Remove saved account sign-in…")) { model.forgetInstagramLogin() }.disabled(model.clearingLogin).help(L("Удаляет данные сервиса только из встроенного окна после подтверждения. Вход в браузерах не затрагивается.","After confirmation, remove the service’s data only from the built-in viewer. Browser sign-in is unaffected."))
                                Text(L("Сервис сохраняет вход с помощью cookies в локальном хранилище WebKit. Приложение не считывает и не сохраняет пароль.","The service keeps sign-in through cookies in local WebKit storage. The app does not read or save your password.")).font(.caption).foregroundStyle(.secondary)
                            }
                            card(L("Запуск и воспроизведение","Opening and playback"),icon:"slider.horizontal.3") {
                                Toggle(L("Без звука","Mute videos"),isOn:$model.muted).onChange(of:model.muted) { _ in model.preferencesChanged() }.help(L("Включает или выключает звук во встроенном просмотрщике. Режим браузера использует собственные настройки звука.","Mute or unmute the built-in viewer. Browser mode has its own sound settings."))
                                Toggle(L("Сворачивать временную шкалу до наведения мыши","Minimize the timeline until hovered"),isOn:$model.miniTimeline).onChange(of:model.miniTimeline) { _ in model.preferencesChanged() }.help(L("Во встроенном окне оставляет тонкую полоску прогресса. Наведите на неё мышь, чтобы раскрыть перемотку. При перетаскивании ползунка шкала остаётся открытой. Размер видео не меняется.","The built-in window shows a thin progress line. Hover over it to reveal seeking controls. Controls stay open while dragging. Video size stays unchanged."))
                                Toggle(L("Сохранять загруженную ленту","Keep the feed loaded"),isOn:$model.keepLoaded).onChange(of:model.keepLoaded) { _ in model.preferencesChanged() }.help(L("При закрытии окна ставит видео на паузу и сохраняет страницу. Вы сможете продолжить с того же ролика до выхода из приложения.","Hide and pause instead of unloading the page. Reopening keeps the reel until you quit the app."))
                                Toggle(L("Переключиться на окно ChatGPT при получении ответа","Switch to the ChatGPT window when the response arrives"),isOn:$model.returnAfterResponse).onChange(of:model.returnAfterResponse) { _ in model.preferencesChanged() }.help(L("После завершения ответа и закрытия Reels переключает вас на окно ChatGPT. Выключите эту настройку, чтобы продолжить работу в текущем окне.","When the response is ready and Reels close, switch your working window to ChatGPT. Turn off to remain in your current window."))
                                Text(L("Если эта настройка выключена, Reels закроются, а вы останетесь в текущем окне.","With return disabled, Reels close without switching your working window.")).font(.caption).foregroundStyle(.secondary)
                                Picker(L("Язык","Language"),selection:$model.language) { ForEach(AppLanguage.allCases,id:\.self) { Text($0.title).tag($0) } }.onChange(of:model.language) { _ in model.preferencesChanged() }.help(L("Меняет язык приложения и справки сразу, без перезапуска. Язык сайта и ChatGPT не меняется.","Change the app and help language immediately. The website and ChatGPT keep their own language."))
                            }
                        } else if model.tab == 1 {
                            card(L("Подключение ChatGPT","ChatGPT connection"),icon:"macwindow") {
                                Picker(L("ChatGPT используется через","You use ChatGPT via"),selection:$model.source) { ForEach(ChatSource.allCases,id:\.self) { Text($0 == .native ? L("Приложение ChatGPT","The ChatGPT app") : L("Браузер","A browser")).tag($0) } }.disabled(model.enabled).help(L("Выберите, где вы отправляете запросы: в приложении ChatGPT или в браузере.","Choose where you send requests: the ChatGPT app or a browser."))
                                if model.source == .browser {
                                    Picker(L("Браузер для ChatGPT","ChatGPT browser"),selection:$model.browser) { ForEach(Browser.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.disabled(model.enabled).help(L("Этот браузер используется для запросов ChatGPT, а также для Reels, если выбран режим «Картинка в картинке браузера».","This browser is used for ChatGPT requests and for Reels when browser picture-in-picture is selected."))
                                }
                                if model.enabled { Text(L("Выключите автоматический просмотр, чтобы изменить способ подключения к ChatGPT.","Turn off automatic viewing to change how you connect to ChatGPT.")).font(.caption).foregroundStyle(.secondary) }
                            }
                            card(L("Доступ к ChatGPT","ChatGPT access"),icon:"checkmark.shield") {
                                if model.source == .native || model.axOnly {
                                    Label(model.axGranted && (model.source != .native || model.nativeAccess != .denied) ? L("Разрешение macOS получено","macOS permission granted") : L("Нужно разрешить распознавание запросов","Request detection permission needed"),systemImage:model.axGranted ? "checkmark.circle" : "exclamationmark.circle")
                                } else {
                                    Text(L("Основной способ проверки браузера — JavaScript через Автоматизацию macOS. Универсальный доступ нужен для резервного распознавания, если JavaScript недоступен.","Browser detection primarily uses JavaScript through macOS Automation. Accessibility is used as a fallback when JavaScript is unavailable.")).font(.callout).foregroundStyle(.secondary)
                                }
                                Button(L("Настроить Универсальный доступ…","Set up Accessibility…")) { model.requestAX() }.help(L("Добавьте именно эту копию Reels While GPT в Универсальный доступ macOS. Программа не считывает сообщения и пароли.","Add this exact Reels While GPT app copy to macOS Accessibility. Message text and passwords are not read."))
                            }
                            card(L("Проверить распознавание","Check detection"),icon:"stethoscope") {
                                Text(model.source == .browser ? L("Проверка выбранного браузера: автоматизация macOS, JavaScript и распознавание ответа. Откройте вкладку ChatGPT; для проверки генерации отправьте длинный запрос.","Check the selected browser: macOS automation, JavaScript and response detection. Open a ChatGPT tab; send a long request to test generation.") : L("Проверка приложения ChatGPT: Универсальный доступ и распознавание ответа. Проверяйте во время длинного ответа.","Check the ChatGPT app: Accessibility and response detection. Check during a long response.")).font(.callout).foregroundStyle(.secondary)
                                HStack {
                                    Button(model.checking ? L("Проверяем…","Checking…") : L("Проверить детектор","Check detector")) { model.diagnose() }.disabled(model.checking).help(L("Проверяйте во время ответа ChatGPT. Подробный отчёт предназначен для разбора ошибки.","Check while ChatGPT is responding. The detailed report is for troubleshooting."))
                                    Button(L("Копировать отчёт","Copy report")) { model.copy(L10n.text(model.nativeReport)) }.help(L("Копирует полный отчёт для разбора ошибки. В нём нет текстов диалогов и значений полей.","Copy the full troubleshooting report. It contains no conversation text or field values."))
                                }
                                if !model.connectionTitle.isEmpty {
                                    Text(model.connectionTitle).font(.headline).textSelection(.enabled)
                                    Text(model.connectionDetail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Text(L10n.text(model.checkResult)).font(.caption)
                                DisclosureGroup(L("Подробный отчёт","Detailed report"),isExpanded:$model.diagnosticExpanded) {
                                    Text(L10n.text(model.nativeReport)).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(.top,8)
                                }
                                Text(L10n.text(model.copyFeedback)).font(.caption).foregroundStyle(.secondary)
                            }
                            card(L("Дополнительные параметры","Advanced options"),icon:"gearshape") {
                                DisclosureGroup(L("Адрес ленты видео","Video feed address")) {
                                TextField(L("Адрес Reels","Reels address"),text:$model.reelsURL).textFieldStyle(.roundedBorder).disabled(model.enabled).help(L("Укажите поддерживаемый HTTPS-адрес ленты видео. Сохраняются только адреса Reels, без параметров и фрагментов.","Only a supported HTTPS video feed URL. Query parameters and fragments are removed before saving."))
                                }
                                if model.source == .browser { Toggle(L("Использовать только Универсальный доступ","Use Accessibility only"),isOn:$model.axOnly).disabled(model.enabled).help(L("Резервный способ проверки браузера без JavaScript. Может предоставлять меньше информации о состоянии ответа.","Browser detection fallback without JavaScript. It may provide less response-state information.")) }
                                HStack {
                                    Button(L("Тест · 8 с","Test · 8 s")) { model.command(test:true) }.help(L("Открывает Reels на 8 секунд, чтобы проверить просмотрщик.","Open Reels for 8 seconds to test the viewer."))
                                    Button(L("Макет окна","Window preview")) { model.command(preview:true) }.help(L("Показывает локальный макет без загрузки сайта. Закройте окно самостоятельно.","Show a local preview without loading the website. Close it manually."))
                                }
                                Button(L("Показать запущенную копию","Show running app copy")) { model.revealApp() }.help(L("Показывает запущенную копию приложения в Finder. Именно её нужно добавить в настройки доступа macOS.","Reveal the running app copy in Finder so you can grant it macOS permission."))
                                Button(L("Копировать текущий статус","Copy current status")) { model.copy(L10n.text(model.status)) }.help(L("Копирует подробное описание последнего действия или ошибки.","Copy the detailed description of the last action or error."))
                            }
                        } else {
                            card(L("Что делает Reels While GPT","What Reels While GPT does"),icon:"play.rectangle") {
                                Text(L("Мини-приложение показывает короткие вертикальные видео, пока ChatGPT отвечает. После подтверждённого завершения ответа оно закрывает своё окно Reels. Можно также смотреть вручную без запроса ChatGPT.","This small app shows short vertical videos while ChatGPT responds. After confirming completion, it closes its own Reels window. You can also watch manually without a ChatGPT request."))
                                Text(L("Сервис может потребовать вход. Программа не обходит авторизацию и не считывает ваши сообщения или пароли.","The service may require sign-in. The app does not bypass authentication or read your messages or passwords.")).font(.callout).foregroundStyle(.secondary)
                            }
                            card(L("Основные команды","Main controls"),icon:"cursorarrow") {
                                helpRow(L("Открыть Reels","Open Reels"),L("Открывает ленту без ограничения времени и выключает автоматический режим. Сочетание клавиш: Cmd+R.","Opens the feed with no time limit and turns automatic mode off. Shortcut: Cmd+R."))
                                helpRow(L("Закрыть Reels","Close Reels"),L("Закрывает свой просмотрщик и выключает автоматический режим. Если он был открыт для ответа, возвращает к этому диалогу.","Closes the app’s viewer and turns automatic mode off. If it was opened for a response, returns to that conversation."))
                                helpRow(L("Открывать Reels, пока ChatGPT готовит ответ","Open Reels while ChatGPT prepares a response"),L("Открывает Reels, когда ChatGPT начинает готовить ответ, и закрывает после его завершения. Эта настройка не запускает программу при входе в macOS.","Watches requests: opens Reels when a response begins and closes them after completion. This does not launch the app when you log in to macOS."))
                                helpRow(L("Переключиться на окно ChatGPT при получении ответа","Switch to the ChatGPT window when the response arrives"),L("После автоматического закрытия Reels переключает рабочее окно на ChatGPT. Выключите, чтобы остаться в текущем окне.","After Reels close automatically, switches your working window to ChatGPT. Turn it off to stay in your current window."))
                            }
                            card(L("Настройки просмотра и подключения","Viewing and connection"),icon:"gearshape") {
                                helpRow(L("Без звука","Mute videos"),L("Выключает звук встроенного просмотрщика. Сервис может попросить нажать кнопку воспроизведения, чтобы включить звук.","Mutes the built-in viewer. The service may require a playback click to allow sound."))
                                helpRow(L("Сохранять загруженную ленту","Keep the feed loaded"),L("При скрытии окна сохраняет страницу и текущий ролик до выхода из приложения. Повторное открытие не перезагружает страницу без необходимости.","Keeps the page and current reel while hidden, until the app quits. Reopening avoids unnecessary page reloads."))
                                helpRow(L("Подключение","Connection"),L("Выберите, через что вы используете ChatGPT, и настройте доступ. Чтобы изменить источник, сначала выключите автоматический режим. Место просмотра Reels выбирается на странице «Просмотр».","Choose how you use ChatGPT and set up permissions. Turn off automatic mode before changing the source. Select the Reels viewer on the Watch page."))
                                helpRow(L("Универсальный доступ","Accessibility"),L("Разрешение macOS для распознавания запросов. Если доступ запрещён, добавьте запущенную копию приложения в настройки Универсального доступа и включите разрешение.","macOS permission for detecting requests. If access fails, add the exact running app copy to Accessibility settings and enable it."))
                                helpRow(L("Свайпы","Swipes"),L("Во встроенном окне свайп вверх открывает следующий ролик, вниз — предыдущий. На странице входа и в комментариях используется обычная прокрутка.","In the built-in viewer, swipe up for the next reel, down for the previous one. Login pages and comments use normal scrolling."))
                            }
                            card(L("Технические команды","Technical controls"),icon:"wrench.and.screwdriver") {
                                helpRow(L("Проверить детектор","Check detector"),L("Проверяет выбранный способ подключения: браузер или приложение. В разделе «Подключение» покажет проблему и действия для её устранения. Для проверки генерации запустите длинный ответ.","Checks the selected browser or app connection. Connection shows the issue and how to fix it. Send a long request to check generation."))
                                helpRow(L("Тест · 8 с / Макет окна","Test · 8 s / Window preview"),L("Тест открывает ленту видео на 8 секунд. Макет показывает локальное окно без сети; закройте его самостоятельно.","Test opens the video feed for 8 seconds. Preview shows a local window without network access; close it manually."))
                                helpRow(L("Копировать отчёт / статус","Copy report / status"),L("Копирует диагностический текст для разбора ошибки. Значения полей и переписка в отчёт не входят.","Copies diagnostic text for troubleshooting. The report excludes field values and conversation text."))
                            }
                        }
                    }.padding(.vertical,2)
                }
            }.padding(21).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor)).labelStyle(SettingsIconLabelStyle())
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var item: NSStatusItem!
    var window: NSWindow?
    private var previewOverlay: OverlayBridge?
    func modelOverlayPreview() -> OverlayBridge {
        if previewOverlay == nil { previewOverlay = OverlayBridge() }; return previewOverlay!
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updateEditMenu()
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.title = "▶ GPT"
        model.changed = { [weak self] in self?.refreshMenu() }
        refreshMenu(); settings()
        if CommandLine.arguments.contains("--preview-overlay") {
            model.enabled = false
            (modelOverlayPreview()).preview()
        }
    }
    private var menuLanguage: AppLanguage?
    func updateEditMenu() {
        guard menuLanguage != L10n.language else { return }
        menuLanguage = L10n.language
        let main = NSMenu()
        let appItem = NSMenuItem(title:"Reels While GPT",action:nil,keyEquivalent:"")
        let appMenu = NSMenu(title:"Reels While GPT")
        let settingsItem = NSMenuItem(title:L("Настройки…","Settings…"),action:#selector(settings),keyEquivalent:",")
        settingsItem.target = self; appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let helpItem = NSMenuItem(title:L("Справка Reels While GPT","Reels While GPT Help"),action:#selector(showHelp),keyEquivalent:"?")
        helpItem.target = self; appMenu.addItem(helpItem)
        let quitItem = NSMenuItem(title:L("Выход","Quit"),action:#selector(quit),keyEquivalent:"q")
        quitItem.target = self; appMenu.addItem(quitItem)
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(title:L("Правка","Edit"),action:nil,keyEquivalent:"")
        let edit = NSMenu(title:L("Правка","Edit"))
        for (title, selector, key) in [(L("Вырезать","Cut"), "cut:", "x"),(L("Копировать","Copy"), "copy:", "c"),(L("Вставить","Paste"), "paste:", "v"),(L("Выбрать всё","Select All"), "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title:title,action:NSSelectorFromString(selector),keyEquivalent:key))
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }
    func refreshMenu() {
        updateEditMenu()
        let menu = NSMenu()
        let status = NSMenuItem(title:model.friendlyStatus.title,action:nil,keyEquivalent:""); status.isEnabled = false; menu.addItem(status)
        let toggle = NSMenuItem(title:model.enabled ? L("Выключить открытие при запросах","Disable request-triggered viewing") : L("Открывать Reels при запросах","Open Reels during requests"),action:#selector(toggle),keyEquivalent:""); toggle.target = self; toggle.isEnabled = !model.clearingLogin; menu.addItem(toggle)
        for (title, action) in [(L("Открыть Reels","Open Reels"),#selector(openReels)),(L("Настройки…","Settings…"),#selector(settings)),(L("Проверить просмотр · 8 с","Test viewer · 8 s"),#selector(test)),(L("Закрыть Reels","Close Reels"),#selector(stop)),(L("Выход","Quit"),#selector(quit))] {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:""); entry.target = self; menu.addItem(entry)
        }
        item.menu = menu
        item.button?.title = model.enabled ? "▶ GPT •" : "▶ GPT"
    }
    @objc func showHelp() { settings(); model.tab = 3 }
    @objc func toggle() { guard !model.clearingLogin else { return }; model.enabled.toggle(); model.save(); model.poll(); refreshMenu() }
    @objc func openReels() { model.command(manual:true) }
    @objc func test() { model.command(test:true) }
    @objc func stop() { model.command() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func settings() {
        model.tab = 0
        if window == nil {
            let w = NSWindow(contentRect:NSRect(x:0,y:0,width:840,height:520),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            w.contentMinSize = NSSize(width:700,height:460)
            w.setFrameAutosaveName("ReelsSettingsWindow")
            _ = w.setFrameUsingName("ReelsSettingsWindow")
            w.title = "Reels While GPT"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView:SettingsView(model:model)); w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !model.clearingLogin else { return .terminateCancel }
        model.command(quit:true); return .terminateLater
    }
}
let app = NSApplication.shared
// Check older releases as well; then use an atomic lock to cover simultaneous launches.
let existing = NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "local.ReelsWhileGPT").first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
if let existing {
    existing.activate(options:[.activateIgnoringOtherApps])
    let alert=NSAlert(); alert.messageText=L("Приложение уже запущено","The app is already running")
    alert.informativeText=L("Reels While GPT уже работает. Откройте его настройки через значок ▶ GPT в строке меню. Чтобы запустить новую версию, сначала завершите старую через пункт «Выход».","Reels While GPT is already running. Open settings from ▶ GPT in the menu bar. To launch a new version, quit the old one first.")
    alert.runModal(); exit(0)
}
let instanceLock = SingleInstanceLock(path:SingleInstanceLock.applicationPath)
if instanceLock == nil {
    let alert=NSAlert(); alert.messageText=L("Не удалось запустить приложение","Unable to start the app")
    alert.informativeText=L("Другая копия Reels While GPT уже запускается или работает, либо файл блокировки недоступен. Проверьте значок ▶ GPT в строке меню.","Another copy of Reels While GPT is starting or running, or its lock file is inaccessible. Check ▶ GPT in the menu bar.")
    alert.runModal(); exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
