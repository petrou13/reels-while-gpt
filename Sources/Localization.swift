import Foundation

enum AppLanguage: String, CaseIterable { case ru, en
    var title: String { self == .ru ? "Русский" : "English" }
}
enum L10n {
    static var language: AppLanguage { AppLanguage(rawValue:UserDefaults.standard.string(forKey:"language") ?? "ru") ?? .ru }
    static func choose(_ ru: String, _ en: String) -> String { language == .ru ? ru : en }
    static func text(_ value: String, language: AppLanguage = language) -> String {
        var result = value
        if language == .en {
            for (ru,en) in phrases.sorted(by: { $0.key.count > $1.key.count }) { result = result.replacingOccurrences(of:ru,with:en) }
        } else {
            for (a,b) in [("Плавающее окно поверх Full Screen","Плавающее окно поверх полноэкранных приложений"),("Preview 9:16","Макет 9:16"),("Локальный preview","Локальный макет"),("Test:","Проверка:"),("Return","Вернуться"),("ChatGPT app","Приложение ChatGPT"),("Picture-in-Picture","Картинка в картинке"),("Full Screen","полный экран"),("credentials","учётных данных"),("standalone","отдельное приложение"),("timeout или нет ответа","истекло время ожидания или нет ответа"),("Play","запуск видео"),("Stop / Esc","Остановка / Esc"),("Interrupt / Прервать","Прервать"),("Stop response / generation / turn","Остановить ответ")] { result = result.replacingOccurrences(of:a,with:b) }
        }
        return result
    }
    static let phrases: [String:String] = [
        "Ручной просмотр · закройте окно, когда закончите":"Manual viewing · close the window when finished",
        "Плавающее окно поверх Full Screen":"Floating window over full screen", "Picture-in-Picture браузера":"Browser picture-in-picture",
        "ChatGPT в браузере":"ChatGPT in a browser", "Приложение ChatGPT":"ChatGPT desktop app",
        "Плавающее окно 9:16":"9:16 floating window", "Поверх полноэкранных приложений":"Over full-screen apps", "Можно перемещать и менять размер":"Move and resize this window", "Плавающее окно готово":"Floating window ready", "Плавающее окно скрыто":"Floating window hidden", "Reels · плавающее окно":"Reels · floating window",
        "Instagram загружается в плавающем окне":"Loading Instagram in the floating window",
        "Войдите один раз в Instagram в плавающем окне; вход сохранится":"Sign in to Instagram once; your session will be saved",
        "Instagram может требовать вход / Play":"Instagram may require sign-in or playback",
        "Внешняя страница заблокирована; вход выполняйте непосредственно в Instagram":"External page blocked; sign in directly in Instagram",
        "Не удалось загрузить Instagram:":"Could not load Instagram:", "Недопустимый URL Instagram":"Invalid Instagram URL",
        "Локальный preview · без Instagram":"Local preview · no Instagram", "Preview 9:16 · без загрузки Instagram":"9:16 preview · no Instagram loading",
        "Готово — ChatGPT вернулся":"Done — returned to ChatGPT", "Войдите в Instagram в плавающем окне, затем включите мониторинг":"Sign in to Instagram in the floating window, then enable monitoring",
        "Picture-in-Picture активен":"Picture-in-picture is active", "Нажмите «Смотреть поверх ChatGPT» в своём окне Instagram":"Click “Watch over ChatGPT” in your Instagram window",
        "Для PiP включите JavaScript from Apple Events в браузере":"For PiP, enable JavaScript from Apple Events in your browser",
        "Instagram просит вход в выбранном браузере":"Instagram requires sign-in in the selected browser",
        "Браузер не предоставил PiP; выберите встроенное плавающее окно":"Browser PiP unavailable; select the built-in floating window",
        "Окно Reels закрыто или изменено пользователем":"Reels window was closed or changed by the user",
        "Ожидание видео / запуска Picture-in-Picture":"Waiting for video / picture-in-picture",
        "Уже есть активный сеанс":"A session is already active", "Test: своё окно закроется через 8 секунд":"Test: this window closes in 8 seconds",
        "Мониторинг выключен — включите переключатель выше":"Monitoring is off — turn on the switch above",
        "лимит 30 минут":"30-minute limit", "Состояние недоступно":"State unavailable", "ожидаем или нажмите Return":"waiting, or click Return",
        "подтверждаем завершение":"confirming completion", "генерация":"generating", "сигнал не распознан":"signal not recognized",
        "нажмите «Проверить детектор»":"click “Check detector”", "Готов к запросу в приложении ChatGPT":"Ready for a request in the ChatGPT app",
        "Ожидание: откройте вкладку ChatGPT в":"Waiting: open a ChatGPT tab in", "Генерация обнаружена":"Generation detected",
        "Нет сигнала: проверьте JavaScript / Accessibility":"No signal: check JavaScript / Accessibility", "Готов к следующему запросу":"Ready for the next request",
        "Нет ScriptRunner":"ScriptRunner is missing", "Не удалось прочитать ScriptRunner":"Could not read ScriptRunner output", "timeout или нет ответа":"timeout or no response", "Нет detector.js":"detector.js is missing",
        "Установите":"Install", "или выберите другой браузер для Reels":"or select another browser for Reels", "Не удалось запустить":"Could not launch",
        "Браузер не вернул идентификатор окна":"Browser did not return a window identifier", "Браузер перезапущен; старое окно не трогаем":"Browser restarted; the previous window is left untouched",
        "окно изменено пользователем; оставлено открытым":"window changed by the user; left open",
        "Нет доступа AX: добавьте именно эту сборку Reels While GPT в Универсальный доступ":"AX access denied: add this exact build of Reels While GPT to Accessibility",
        "Приложение ChatGPT не найдено (проверены standalone и новая дистрибуция)":"ChatGPT app not found (classic and modern distributions checked)",
        "Доступ к окнам ChatGPT запрещён macOS (-25211). Общий AX-флаг не подтверждает доступ к этому приложению. Закройте все старые копии Reels While GPT, удалите его запись из Универсального доступа, добавьте запущенную .app заново и перезапустите её.":"macOS denied access to ChatGPT windows (-25211). Global AX trust does not confirm access to this app. Quit older copies, remove the old Accessibility entry, add the running .app and restart it.",
        "Нет доступных окон ChatGPT: откройте окно диалога и повторите проверку.":"No ChatGPT windows available: open a conversation window and check again.", "Нет доступных окон":"No accessible windows",
        "окно/процесс недоступны":"window/process unavailable", "Детектор ещё не проверял приложение ChatGPT":"The detector has not checked the ChatGPT app yet",
        "Диагностика не содержит текстов диалогов, заголовков чатов, значений полей или credentials.":"Diagnostics contain no conversation text, chat titles, field values or credentials.",
        "Нажмите «Проверить детектор» во время активного запроса ChatGPT":"Click “Check detector” while ChatGPT is generating a response",
        "Неверный URL Reels — введите HTTPS-адрес instagram.com и включите мониторинг снова":"Invalid Reels URL — enter an HTTPS instagram.com address and enable monitoring again", "Введите HTTPS URL Instagram":"Enter an HTTPS Instagram URL",
        "Проверка #":"Check #", "завершена":"completed", "выполняется…":"running…", "Запущено из:":"Running from:", "сохранённая лента":"saved feed", "Скопировано":"Copied", "ChatGPT app":"ChatGPT app", "Interrupt / Прервать":"Interrupt", "Остановить / прекратить ответ":"Stop response", "ChatGPT app · AX":"ChatGPT app · AX"
    ]
}
func L(_ ru: String, _ en: String) -> String { L10n.choose(ru,en) }
