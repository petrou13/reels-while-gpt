import Foundation

enum AccessState { case unchecked, allowed, denied }
enum UserStatus: Equatable {
    case accessDenied, invalidAddress, operationFailed, openChat, unrecognized, viewing, answering, ready, manualReady
    var title: String {
        switch self {
        case .accessDenied: return L("Автоматический просмотр пока недоступен","Automatic viewing is unavailable")
        case .invalidAddress: return L("Нужно исправить адрес Reels","Fix the Reels address")
        case .operationFailed: return L("Не удалось выполнить действие","Could not complete this action")
        case .openChat: return L("Откройте ChatGPT","Open ChatGPT")
        case .unrecognized: return L("Не удаётся определить, закончен ли ответ","Cannot tell whether the response is finished")
        case .viewing: return L("Reels открыты","Reels are open")
        case .answering: return L("Всё работает — ChatGPT отвечает","Working — ChatGPT is responding")
        case .ready: return L("Всё готово к работе","Ready to go")
        case .manualReady: return L("Можно смотреть Reels","Ready to watch Reels")
        }
    }
    var detail: String {
        switch self {
        case .accessDenied: return L("macOS не разрешает распознавать запросы. Добавьте эту копию Reels While GPT в Универсальный доступ и включите разрешение. Reels можно открыть вручную.","macOS has blocked request detection. Add this copy of Reels While GPT to Accessibility and enable it. You can still open Reels manually.")
        case .invalidAddress: return L("Откройте раздел «Технические» и укажите HTTPS-адрес Instagram.","In Advanced, enter an HTTPS Instagram address.")
        case .operationFailed: return L("Повторите действие. Если ошибка осталась, откройте «Технические» и скопируйте отчёт или статус для разбора.","Try again. If the error persists, open Advanced and copy the report or status for troubleshooting.")
        case .openChat: return L("Откройте основное окно переписки в выбранном приложении или браузере, затем отправьте сообщение.","Open a regular conversation in the selected app or browser, then send a message.")
        case .unrecognized: return L("Откройте основное окно переписки и проверьте доступ в разделе «Подключение». При необходимости закройте Reels вручную.","Open the main conversation window and check permissions in Connection. Close Reels manually if needed.")
        case .viewing: return L("Закройте окно, когда закончите. Если Instagram попросит войти, сделайте это в окне Reels.","Close the window when finished. If Instagram requests sign-in, complete it in the Reels window.")
        case .answering: return L("Reels закроются, когда приложение подтвердит завершение ответа.","Reels will close when the app confirms the response has finished.")
        case .ready: return L("Отправьте сообщение в ChatGPT — Reels откроются на время ответа и затем закроются.","Send a message in ChatGPT — Reels will open during the response and close afterward.")
        case .manualReady: return L("Нажмите «Открыть Reels». Чтобы Reels открывались во время ответов ChatGPT, включите соответствующую настройку на этой странице.","Click Open Reels. To open Reels while ChatGPT responds, enable the corresponding setting on this page.")
        }
    }
    var isProblem: Bool { [.accessDenied,.invalidAddress,.operationFailed,.openChat,.unrecognized].contains(self) }
    static func resolve(enabled: Bool, needsAX: Bool, trusted: Bool, access: AccessState, validURL: Bool, failed: Bool, raw: String, viewerOpen: Bool = false) -> UserStatus {
        if needsAX && (!trusted || access == .denied || raw.contains("AXWindows error=-25211") || raw.hasPrefix("Нет доступа AX")) { return .accessDenied }
        if !validURL { return .invalidAddress }
        if failed { return .operationFailed }
        if raw.contains("Ручной просмотр") || raw.contains("Instagram просит вход") || raw.contains("Войдите") || raw.hasPrefix("Test:") { return .viewing }
        if !enabled { return viewerOpen ? .viewing : .manualReady }
        if raw.contains("не найдено") || raw.contains("Нет доступных окон") || raw.contains("откройте вкладку") { return .openChat }
        if raw.contains("не распознан") || raw.contains("Состояние недоступно") || raw.contains("Нет сигнала") { return .unrecognized }
        if raw.contains("генерация") || raw.contains("Генерация обнаружена") || raw.contains("подтверждаем завершение") { return .answering }
        return .ready
    }
}
