# Reels While GPT privacy

Policy version: October 8, 2026.

Reels While GPT is an independent local macOS utility. It is not affiliated with OpenAI or Meta. It shows Instagram Reels while ChatGPT prepares a response.

The utility does not collect or send passwords, ChatGPT messages, viewing history or cookies to its developer. It has no telemetry, analytics SDK or developer-operated cloud storage.

Preferences and window geometry are stored locally. The built-in viewer uses persistent WebKit website storage for cookies, website data and cache, allowing Instagram to remember sign-in. Session cookies/tokens are sensitive authentication data even though they are not passwords. The utility does not read password field values or export/import browser cookies. Passwords entered into Instagram are handled by Instagram's official HTTPS website. macOS password autofill/storage is governed by your system settings. The utility cannot guarantee how Instagram's own scripts store website data.

A retained feed is paused while hidden. Hidden sign-in pages are unloaded. Unloading a page does not remove its cookies. Use Watch → Remove saved Instagram sign-in to erase the built-in viewer's website data after confirmation. This closes the viewer and disables automatic viewing. Safari/Chrome sign-in stays unchanged. This does not delete your Instagram account or revoke other sessions.

When enabled, the detector checks response controls through Accessibility or permitted browser JavaScript. It does not request editable field values, message text or chat titles. A tab URL is used transiently for window matching; it is not saved to preferences or diagnostics. Diagnostics contain technical version/count/error information and are copied to the system clipboard only on your command.

WebKit/browser requests Instagram and the resources loaded by its website. Instagram's account, viewing, advertising and cookie practices are governed by [Meta's privacy policy](https://privacycenter.instagram.com/policy/), independently of this utility. Requests do not pass through a Reels While GPT developer server.

Publisher/author: [petrou13](https://github.com/petrou13). Support is via Issues in [reels-while-gpt](https://github.com/petrou13/reels-while-gpt/issues), once published. Follow SECURITY.md for private security reports; do not include sensitive data. The app does not send reports automatically.
